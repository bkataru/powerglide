//! MCP (Model Context Protocol) Server
//! Exposes powerglide tools to other MCP clients

const std = @import("std");
const json = std.json;
const mem = std.mem;
const Registry = @import("../tools/registry.zig").Registry;
const ToolInput = @import("../tools/tool.zig").ToolInput;

pub const McpServer = struct {
    allocator: std.mem.Allocator,
    registry: *Registry,

    pub fn init(allocator: std.mem.Allocator, registry: *Registry) McpServer {
        return .{
            .allocator = allocator,
            .registry = registry,
        };
    }

    const MAX_LINE_BYTES = 8 * 1024 * 1024; // 8 MiB — matches client-side guard

    pub fn run(self: *McpServer) !void {
        const stdin_fd = std.fs.File.stdin().handle;
        const stdout = std.fs.File.stdout().deprecatedWriter();

        var buf = std.ArrayList(u8){};
        defer buf.deinit(self.allocator);

        var byte_buf: [1]u8 = undefined;
        while (true) {
            const n = std.posix.read(stdin_fd, &byte_buf) catch break;
            if (n == 0) break;
            if (byte_buf[0] == '\n') {
                if (buf.items.len > 0) {
                    const response = try self.handleRequest(buf.items);
                    defer self.allocator.free(response);
                    try stdout.writeAll(response);
                    try stdout.writeAll("\n");
                    buf.clearRetainingCapacity();
                }
            } else {
                if (buf.items.len >= MAX_LINE_BYTES) return error.RequestTooLarge;
                try buf.append(self.allocator, byte_buf[0]);
            }
        }
    }

    fn handleRequest(self: *McpServer, line: []const u8) ![]const u8 {
        const parsed = json.parseFromSlice(json.Value, self.allocator, line, .{}) catch {
            return try self.makeError(null, -32700, "Parse error");
        };
        defer parsed.deinit();

        if (parsed.value != .object) {
            return try self.makeError(null, -32600, "Invalid Request");
        }

        const obj = parsed.value.object;
        const method = obj.get("method") orelse return try self.makeError(null, -32600, "Missing method");
        if (method != .string) return try self.makeError(null, -32600, "Method must be a string");

        const id = obj.get("id");

        if (mem.eql(u8, method.string, "initialize")) {
            return try self.handleInitialize(id);
        } else if (mem.eql(u8, method.string, "tools/list")) {
            return try self.handleToolsList(id);
        } else if (mem.eql(u8, method.string, "tools/call")) {
            const params = obj.get("params") orelse return try self.makeError(id, -32602, "Missing params");
            return try self.handleToolsCall(id, params);
        } else {
            return try self.makeError(id, -32601, "Method not found");
        }
    }

    fn handleInitialize(self: *McpServer, id: ?json.Value) ![]const u8 {
        var result_obj = json.ObjectMap.init(self.allocator);
        defer result_obj.deinit();

        try result_obj.put("protocolVersion", .{ .string = "2024-11-05" });
        
        var capabilities = json.ObjectMap.init(self.allocator);
        defer capabilities.deinit();
        
        var tools_cap = json.ObjectMap.init(self.allocator);
        defer tools_cap.deinit();
        try tools_cap.put("listChanged", .{ .bool = false });
        try capabilities.put("tools", .{ .object = tools_cap });
        
        try result_obj.put("capabilities", .{ .object = capabilities });

        var server_info = json.ObjectMap.init(self.allocator);
        defer server_info.deinit();
        try server_info.put("name", .{ .string = "powerglide" });
        try server_info.put("version", .{ .string = "0.1.1" });
        try result_obj.put("serverInfo", .{ .object = server_info });

        return try self.makeResponse(id, .{ .object = result_obj });
    }

    fn handleToolsList(self: *McpServer, id: ?json.Value) ![]const u8 {
        var result_obj = json.ObjectMap.init(self.allocator);
        defer result_obj.deinit();

        var tools_list = json.Array.init(self.allocator);
        defer tools_list.deinit();

        var it = self.registry.tools.iterator();
        while (it.next()) |entry| {
            const tool = entry.value_ptr.*;
            var tool_obj = json.ObjectMap.init(self.allocator);
            errdefer tool_obj.deinit();

            try tool_obj.put("name", .{ .string = tool.name });
            try tool_obj.put("description", .{ .string = tool.description });
            
            const schema_parsed = try json.parseFromSlice(json.Value, self.allocator, tool.input_schema, .{});
            defer schema_parsed.deinit();
            try tool_obj.put("inputSchema", try deepCloneValue(self.allocator, schema_parsed.value));

            try tools_list.append(.{ .object = tool_obj });
        }

        try result_obj.put("tools", .{ .array = tools_list });
        return try self.makeResponse(id, .{ .object = result_obj });
    }

    fn handleToolsCall(self: *McpServer, id: ?json.Value, params: json.Value) ![]const u8 {
        if (params != .object) return try self.makeError(id, -32602, "Params must be an object");
        const name_val = params.object.get("name") orelse return try self.makeError(id, -32602, "Missing tool name");
        if (name_val != .string) return try self.makeError(id, -32602, "Tool name must be a string");
        const arguments = params.object.get("arguments") orelse return try self.makeError(id, -32602, "Missing arguments");

        const input = ToolInput{
            .name = name_val.string,
            .arguments = arguments,
        };

        const output = self.registry.execute(self.allocator, input) catch |err| {
            return try self.makeError(id, -32000, try std.fmt.allocPrint(self.allocator, "Execution error: {}", .{err}));
        };
        defer self.allocator.free(output.content);

        var result_obj = json.ObjectMap.init(self.allocator);
        defer result_obj.deinit();

        var content_list = json.Array.init(self.allocator);
        defer content_list.deinit();

        var text_obj = json.ObjectMap.init(self.allocator);
        defer text_obj.deinit();
        try text_obj.put("type", .{ .string = "text" });
        try text_obj.put("text", .{ .string = try self.allocator.dupe(u8, output.content) });
        try content_list.append(.{ .object = text_obj });

        try result_obj.put("content", .{ .array = content_list });
        if (output.is_error) {
            try result_obj.put("isError", .{ .bool = true });
        }

        return try self.makeResponse(id, .{ .object = result_obj });
    }

    fn makeResponse(self: *McpServer, id: ?json.Value, result: json.Value) ![]const u8 {
        var resp_obj = json.ObjectMap.init(self.allocator);
        defer resp_obj.deinit();

        try resp_obj.put("jsonrpc", .{ .string = "2.0" });
        if (id) |i| try resp_obj.put("id", i);
        try resp_obj.put("result", result);

        var buf = std.ArrayList(u8){};
        defer buf.deinit(self.allocator);
        try buf.writer(self.allocator).print("{f}", .{json.fmt(std.json.Value{ .object = resp_obj }, .{})});
        return try buf.toOwnedSlice(self.allocator);
    }

    fn makeError(self: *McpServer, id: ?json.Value, code: i64, message: []const u8) ![]const u8 {
        var resp_obj = json.ObjectMap.init(self.allocator);
        defer resp_obj.deinit();

        try resp_obj.put("jsonrpc", .{ .string = "2.0" });
        if (id) |i| try resp_obj.put("id", i);
        
        var err_obj = json.ObjectMap.init(self.allocator);
        defer err_obj.deinit();
        try err_obj.put("code", .{ .integer = code });
        try err_obj.put("message", .{ .string = message });
        try resp_obj.put("error", .{ .object = err_obj });

        var buf = std.ArrayList(u8){};
        defer buf.deinit(self.allocator);
        try buf.writer(self.allocator).print("{f}", .{json.fmt(std.json.Value{ .object = resp_obj }, .{})});
        return try buf.toOwnedSlice(self.allocator);
    }
};

// ==================== Tests ====================

test "McpServer init" {
    const allocator = std.testing.allocator;
    var registry = @import("../tools/registry.zig").Registry.init(allocator);
    defer registry.deinit();
    const server = McpServer.init(allocator, &registry);
    try std.testing.expect(server.registry == &registry);
}

test "McpServer handleRequest parse error" {
    const allocator = std.testing.allocator;
    var registry = @import("../tools/registry.zig").Registry.init(allocator);
    defer registry.deinit();
    var server = McpServer.init(allocator, &registry);
    const resp = try server.handleRequest("not json");
    defer allocator.free(resp);
    try std.testing.expect(mem.indexOf(u8, resp, "Parse error") != null);
    try std.testing.expect(mem.indexOf(u8, resp, "-32700") != null);
}

test "McpServer handleRequest invalid request - not object" {
    const allocator = std.testing.allocator;
    var registry = @import("../tools/registry.zig").Registry.init(allocator);
    defer registry.deinit();
    var server = McpServer.init(allocator, &registry);
    const resp = try server.handleRequest("[1,2,3]");
    defer allocator.free(resp);
    try std.testing.expect(mem.indexOf(u8, resp, "Invalid Request") != null);
    try std.testing.expect(mem.indexOf(u8, resp, "-32600") != null);
}

test "McpServer handleRequest missing method" {
    const allocator = std.testing.allocator;
    var registry = @import("../tools/registry.zig").Registry.init(allocator);
    defer registry.deinit();
    var server = McpServer.init(allocator, &registry);
    const resp = try server.handleRequest("{\"jsonrpc\":\"2.0\",\"id\":1}");
    defer allocator.free(resp);
    try std.testing.expect(mem.indexOf(u8, resp, "Missing method") != null);
}

test "McpServer handleRequest unknown method" {
    const allocator = std.testing.allocator;
    var registry = @import("../tools/registry.zig").Registry.init(allocator);
    defer registry.deinit();
    var server = McpServer.init(allocator, &registry);
    const resp = try server.handleRequest("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"unknown/method\"}");
    defer allocator.free(resp);
    try std.testing.expect(mem.indexOf(u8, resp, "Method not found") != null);
    try std.testing.expect(mem.indexOf(u8, resp, "-32601") != null);
}

test "McpServer initialize response" {
    const allocator = std.testing.allocator;
    var registry = @import("../tools/registry.zig").Registry.init(allocator);
    defer registry.deinit();
    var server = McpServer.init(allocator, &registry);
    const resp = try server.handleRequest("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}");
    defer allocator.free(resp);
    try std.testing.expect(mem.indexOf(u8, resp, "2024-11-05") != null);
    try std.testing.expect(mem.indexOf(u8, resp, "powerglide") != null);
    try std.testing.expect(mem.indexOf(u8, resp, "capabilities") != null);
}

test "McpServer tools/list response" {
    // Use arena because handleToolsList deep-clones JSON schemas into response objects
    // that are freed together at arena teardown
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var registry = @import("../tools/registry.zig").Registry.init(allocator);
    // registry.deinit() handled by arena
    var server = McpServer.init(allocator, &registry);
    const resp = try server.handleRequest("{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/list\"}");
    try std.testing.expect(mem.indexOf(u8, resp, "tools") != null);
    try std.testing.expect(mem.indexOf(u8, resp, "bash") != null);
}

test "McpServer tools/call missing params" {
    const allocator = std.testing.allocator;
    var registry = @import("../tools/registry.zig").Registry.init(allocator);
    defer registry.deinit();
    var server = McpServer.init(allocator, &registry);
    const resp = try server.handleRequest("{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\"}");
    defer allocator.free(resp);
    try std.testing.expect(mem.indexOf(u8, resp, "Missing params") != null);
}

test "McpServer tools/call unknown tool" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var registry = @import("../tools/registry.zig").Registry.init(allocator);
    var server = McpServer.init(allocator, &registry);
    const resp = try server.handleRequest("{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"no_such_tool\",\"arguments\":{}}}");
    try std.testing.expect(resp.len > 0);
}

test "McpServer tools/call bash echo" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var registry = @import("../tools/registry.zig").Registry.init(allocator);
    var server = McpServer.init(allocator, &registry);
    const resp = try server.handleRequest("{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"tools/call\",\"params\":{\"name\":\"bash\",\"arguments\":{\"command\":\"echo mcp_test\"}}}");
    try std.testing.expect(mem.indexOf(u8, resp, "mcp_test") != null);
}

test "McpServer response contains jsonrpc 2.0" {
    const allocator = std.testing.allocator;
    var registry = @import("../tools/registry.zig").Registry.init(allocator);
    defer registry.deinit();
    var server = McpServer.init(allocator, &registry);
    const resp = try server.handleRequest("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}");
    defer allocator.free(resp);
    try std.testing.expect(mem.indexOf(u8, resp, "2.0") != null);
}

test "McpServer response id echoed" {
    const allocator = std.testing.allocator;
    var registry = @import("../tools/registry.zig").Registry.init(allocator);
    defer registry.deinit();
    var server = McpServer.init(allocator, &registry);
    const resp = try server.handleRequest("{\"jsonrpc\":\"2.0\",\"id\":42,\"method\":\"initialize\",\"params\":{}}");
    defer allocator.free(resp);
    try std.testing.expect(mem.indexOf(u8, resp, "42") != null);
}

test "deepCloneValue null" {
    const allocator = std.testing.allocator;
    const cloned = try deepCloneValue(allocator, .null);
    try std.testing.expect(cloned == .null);
}

test "deepCloneValue bool" {
    const allocator = std.testing.allocator;
    const cloned = try deepCloneValue(allocator, .{ .bool = true });
    try std.testing.expect(cloned.bool == true);
}

test "deepCloneValue integer" {
    const allocator = std.testing.allocator;
    const cloned = try deepCloneValue(allocator, .{ .integer = 42 });
    try std.testing.expect(cloned.integer == 42);
}

test "deepCloneValue string" {
    const allocator = std.testing.allocator;
    const cloned = try deepCloneValue(allocator, .{ .string = "hello" });
    defer allocator.free(cloned.string);
    try std.testing.expect(mem.eql(u8, cloned.string, "hello"));
}

test "deepCloneValue array" {
    const allocator = std.testing.allocator;
    var arr = json.Array.init(allocator);
    defer arr.deinit();
    try arr.append(.{ .integer = 1 });
    try arr.append(.{ .string = "x" });
    const cloned = try deepCloneValue(allocator, .{ .array = arr });
    defer {
        allocator.free(cloned.array.items[1].string);
        var ca = cloned.array;
        ca.deinit();
    }
    try std.testing.expect(cloned.array.items[0].integer == 1);
    try std.testing.expect(mem.eql(u8, cloned.array.items[1].string, "x"));
}

test "deepCloneValue object" {
    const allocator = std.testing.allocator;
    var obj = json.ObjectMap.init(allocator);
    defer obj.deinit();
    try obj.put("key", .{ .string = "val" });
    const cloned = try deepCloneValue(allocator, .{ .object = obj });
    defer {
        const v = cloned.object.get("key").?;
        allocator.free(v.string);
        const k = cloned.object.keys()[0];
        allocator.free(k);
        var co = cloned.object;
        co.deinit();
    }
    try std.testing.expect(cloned.object.get("key") != null);
}

fn deepCloneValue(allocator: std.mem.Allocator, val: json.Value) !json.Value {
    switch (val) {
        .null, .bool, .integer, .float, .number_string => return val,
        .string => return .{ .string = try allocator.dupe(u8, val.string) },
        .array => {
            var new_list = json.Array.init(allocator);
            try new_list.ensureTotalCapacity(val.array.items.len);
            for (val.array.items) |item| {
                try new_list.append(try deepCloneValue(allocator, item));
            }
            return .{ .array = new_list };
        },
        .object => {
            var new_obj = json.ObjectMap.init(allocator);
            var it = val.object.iterator();
            while (it.next()) |entry| {
                try new_obj.put(try allocator.dupe(u8, entry.key_ptr.*), try deepCloneValue(allocator, entry.value_ptr.*));
            }
            return .{ .object = new_obj };
        },
    }
}
