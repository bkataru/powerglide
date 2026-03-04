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
        const name = params.object.get("name") orelse return try self.makeError(id, -32602, "Missing tool name");
        const arguments = params.object.get("arguments") orelse return try self.makeError(id, -32602, "Missing arguments");

        const input = ToolInput{
            .name = name.string,
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
