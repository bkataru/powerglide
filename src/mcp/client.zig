//! MCP (Model Context Protocol) Client
//! Implements JSON-RPC 2.0 message exchange over process stdin/stdout pipes

const std = @import("std");
const json = std.json;
const mem = std.mem;
const pty = @import("../terminal/pty.zig");

// ==================== JSON-RPC 2.0 Structures ====================

/// JSON-RPC 2.0 Request
const JsonRpcRequest = struct {
    jsonrpc: []const u8 = "2.0",
    method: []const u8,
    params: ?json.Value = null,
    id: ?json.Value = null,
};

// ==================== MCP Protocol Structures ====================

/// MCP Tool Definition
pub const McpTool = struct {
    name: []const u8,
    description: []const u8,
    inputSchema: json.Value,

    pub fn deinit(self: *McpTool, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.description);
        deepFreeValue(allocator, self.inputSchema);
    }
};

fn deepFreeValue(allocator: std.mem.Allocator, val: json.Value) void {
    switch (val) {
        .string => allocator.free(val.string),
        .array => {
            for (val.array.items) |item| {
                deepFreeValue(allocator, item);
            }
            // Managed Array has its own deinit but we need the allocator
            var mut_array = val.array;
            mut_array.deinit();
        },
        .object => {
            var it = val.object.iterator();
            while (it.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                deepFreeValue(allocator, entry.value_ptr.*);
            }
            var mut_obj = val.object;
            mut_obj.deinit();
        },
        else => {},
    }
}

/// MCP Tool Call Result
pub const ToolCallResult = struct {
    content: []const u8,
    isError: bool = false,
};

// ==================== MCP Client ====================

pub const McpClient = struct {
    allocator: std.mem.Allocator,
    process: pty.PlainProcess,
    request_id: i64 = 0,

    /// Initialize an MCP client with a command
    pub fn init(allocator: std.mem.Allocator, command: []const []const u8) !McpClient {
        const process = try pty.PlainProcess.spawn(allocator, command);
        return .{
            .allocator = allocator,
            .process = process,
        };
    }

    /// Clean up resources
    pub fn deinit(self: *McpClient) void {
        self.process.deinit();
    }

    /// Send a JSON-RPC request and get the response
    fn sendRequest(self: *McpClient, method: []const u8, params: ?json.Value) !json.Value {
        self.request_id += 1;

        const request = JsonRpcRequest{
            .method = method,
            .params = params,
            .id = json.Value{ .integer = self.request_id },
        };

        var buf = std.ArrayList(u8){};
        defer buf.deinit(self.allocator);
        try buf.writer(self.allocator).print("{f}", .{json.fmt(request, .{})});

        try self.writeLine(buf.items);

        const response_json = try self.readLine();
        defer self.allocator.free(response_json);

        const parsed = try json.parseFromSlice(json.Value, self.allocator, response_json, .{});
        defer parsed.deinit();

        if (parsed.value != .object) return error.InvalidResponse;
        const obj = parsed.value.object;

        if (obj.get("error")) |err_val| {
            std.debug.print("MCP Error: {any}\n", .{err_val});
            return error.McpError;
        }

        const result = obj.get("result") orelse return error.MissingResult;
        // We need to return a cloned value because 'parsed' will be deinitialized
        // Actually, returning a json.Value that is managed by the caller's allocator is better.
        // But for simplicity, we'll return a stringified version or a deeply cloned Value.
        // Let's use a stringified version for now, as it's easier to handle in the bridge.
        var result_buf = std.ArrayList(u8){};
        try result_buf.writer(self.allocator).print("{f}", .{json.fmt(result, .{})});
        return json.Value{ .string = try result_buf.toOwnedSlice(self.allocator) };
    }

    fn writeLine(self: *McpClient, line: []const u8) !void {
        const data = try std.fmt.allocPrint(self.allocator, "{s}\n", .{line});
        defer self.allocator.free(data);
        _ = try std.posix.write(self.process.stdin_pipe[1], data);
    }

    fn readLine(self: *McpClient) ![]u8 {
        var buffer = std.ArrayList(u8){};
        errdefer buffer.deinit(self.allocator);

        var byte_buf: [1]u8 = undefined;
        while (true) {
            const n = try std.posix.read(self.process.stdout_pipe[0], &byte_buf);
            if (n == 0) break;
            const byte = byte_buf[0];
            if (byte == '\n') break;
            try buffer.append(self.allocator, byte);
        }
        const line = try buffer.toOwnedSlice(self.allocator);
        std.debug.print("MCP RAW: {s}\n", .{line});
        return line;
    }

    pub fn initialize(self: *McpClient) !void {
        var params_obj = json.ObjectMap.init(self.allocator);
        defer params_obj.deinit();
        try params_obj.put("protocolVersion", .{ .string = "2024-11-05" });
        
        var client_info = json.ObjectMap.init(self.allocator);
        defer client_info.deinit();
        try client_info.put("name", .{ .string = "powerglide" });
        try client_info.put("version", .{ .string = "0.1.0" });
        try params_obj.put("clientInfo", .{ .object = client_info });

        var capabilities = json.ObjectMap.init(self.allocator);
        defer capabilities.deinit();
        try params_obj.put("capabilities", .{ .object = capabilities });

        const result = try self.sendRequest("initialize", .{ .object = params_obj });
        self.allocator.free(result.string);

        // Send initialized notification
        const notification = JsonRpcRequest{
            .method = "notifications/initialized",
            .params = null,
            .id = null,
        };
        var buf = std.ArrayList(u8){};
        defer buf.deinit(self.allocator);
        try buf.writer(self.allocator).print("{f}", .{json.fmt(notification, .{})});
        try self.writeLine(buf.items);
    }

    pub fn listTools(self: *McpClient) ![]McpTool {
        const result_val = try self.sendRequest("tools/list", null);
        defer self.allocator.free(result_val.string);

        const parsed = try json.parseFromSlice(json.Value, self.allocator, result_val.string, .{});
        defer parsed.deinit();

        const obj = parsed.value.object;
        const tools_array = obj.get("tools").?.array;
        var tools = try self.allocator.alloc(McpTool, tools_array.items.len);

        for (tools_array.items, 0..) |tool_val, i| {
            const tool_obj = tool_val.object;
            tools[i] = .{
                .name = try self.allocator.dupe(u8, tool_obj.get("name").?.string),
                .description = try self.allocator.dupe(u8, tool_obj.get("description").?.string),
                .inputSchema = try deepCloneValue(self.allocator, tool_obj.get("inputSchema").?),
            };
        }
        return tools;
    }

    pub fn callTool(self: *McpClient, name: []const u8, arguments: json.Value) !ToolCallResult {
        var params_obj = json.ObjectMap.init(self.allocator);
        defer params_obj.deinit();
        try params_obj.put("name", .{ .string = name });
        try params_obj.put("arguments", arguments);

        const result_val = try self.sendRequest("tools/call", .{ .object = params_obj });
        defer self.allocator.free(result_val.string);

        const parsed = try json.parseFromSlice(json.Value, self.allocator, result_val.string, .{});
        defer parsed.deinit();

        const obj = parsed.value.object;
        const content_array = obj.get("content").?.array;
        
        // Combine all text content
        var output = std.ArrayList(u8){};
        errdefer output.deinit(self.allocator);

        for (content_array.items) |item| {
            if (item == .object) {
                if (item.object.get("type")) |t| {
                    if (mem.eql(u8, t.string, "text")) {
                        try output.appendSlice(self.allocator, item.object.get("text").?.string);
                    }
                }
            }
        }

        return ToolCallResult{
            .content = try output.toOwnedSlice(self.allocator),
            .isError = if (obj.get("isError")) |e| e.bool else false,
        };
    }
};

fn deepCloneValue(allocator: mem.Allocator, val: json.Value) !json.Value {
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

// ==================== Tests ====================

test "McpTool deinit frees fields" {
    const allocator = std.testing.allocator;
    var schema_obj = json.ObjectMap.init(allocator);
    try schema_obj.put(try allocator.dupe(u8, "type"), .{ .string = try allocator.dupe(u8, "object") });

    var tool = McpTool{
        .name = try allocator.dupe(u8, "test_tool"),
        .description = try allocator.dupe(u8, "A test tool"),
        .inputSchema = .{ .object = schema_obj },
    };
    tool.deinit(allocator);
    // No leak = pass
}

test "deepCloneValue null passthrough" {
    const allocator = std.testing.allocator;
    const result = try deepCloneValue(allocator, .null);
    try std.testing.expect(result == .null);
}

test "deepCloneValue bool passthrough" {
    const allocator = std.testing.allocator;
    const t = try deepCloneValue(allocator, .{ .bool = true });
    const f = try deepCloneValue(allocator, .{ .bool = false });
    try std.testing.expect(t.bool == true);
    try std.testing.expect(f.bool == false);
}

test "deepCloneValue integer passthrough" {
    const allocator = std.testing.allocator;
    const result = try deepCloneValue(allocator, .{ .integer = 99 });
    try std.testing.expect(result.integer == 99);
}

test "deepCloneValue float passthrough" {
    const allocator = std.testing.allocator;
    const result = try deepCloneValue(allocator, .{ .float = 3.14 });
    try std.testing.expect(result.float == 3.14);
}

test "deepCloneValue string is duped" {
    const allocator = std.testing.allocator;
    const result = try deepCloneValue(allocator, .{ .string = "original" });
    defer allocator.free(result.string);
    try std.testing.expect(mem.eql(u8, result.string, "original"));
}

test "deepCloneValue array is deep copied" {
    const allocator = std.testing.allocator;
    var arr = json.Array.init(allocator);
    defer arr.deinit();
    try arr.append(.{ .string = "item" });
    try arr.append(.{ .integer = 7 });

    const result = try deepCloneValue(allocator, .{ .array = arr });
    defer {
        allocator.free(result.array.items[0].string);
        var ra = result.array;
        ra.deinit();
    }
    try std.testing.expect(mem.eql(u8, result.array.items[0].string, "item"));
    try std.testing.expect(result.array.items[1].integer == 7);
}

test "deepCloneValue object is deep copied" {
    const allocator = std.testing.allocator;
    var obj = json.ObjectMap.init(allocator);
    defer obj.deinit();
    try obj.put("name", .{ .string = "value" });

    const result = try deepCloneValue(allocator, .{ .object = obj });
    defer {
        if (result.object.get("name")) |v| allocator.free(v.string);
        const keys = result.object.keys();
        for (keys) |k| allocator.free(k);
        var ro = result.object;
        ro.deinit();
    }
    try std.testing.expect(result.object.get("name") != null);
    try std.testing.expect(mem.eql(u8, result.object.get("name").?.string, "value"));
}

test "ToolCallResult success" {
    const result = ToolCallResult{
        .content = "output",
        .isError = false,
    };
    try std.testing.expect(!result.isError);
    try std.testing.expect(mem.eql(u8, result.content, "output"));
}

test "ToolCallResult error" {
    const result = ToolCallResult{
        .content = "error message",
        .isError = true,
    };
    try std.testing.expect(result.isError);
}
