const std = @import("std");
const json = std.json;
const mem = std.mem;
const Tool = @import("tool.zig").Tool;
const ToolInput = @import("tool.zig").ToolInput;
const ToolOutput = @import("tool.zig").ToolOutput;
const BuiltinTools = @import("tool.zig").BuiltinTools;
const mcp = @import("../mcp/client.zig");
const tool_bridge = @import("../mcp/tool_bridge.zig");

/// Tool registry - manages available tools and their execution
pub const Registry = struct {
    allocator: std.mem.Allocator,
    tools: std.StringHashMap(Tool),
    mcp_clients: std.ArrayList(*mcp.McpClient),

    /// Initialize the registry with built-in tools
    pub fn init(allocator: std.mem.Allocator) Registry {
        var reg = Registry{
            .allocator = allocator,
            .tools = std.StringHashMap(Tool).init(allocator),
            .mcp_clients = std.ArrayList(*mcp.McpClient){},
        };

        // Register all built-in tools
        for (BuiltinTools.all()) |tool| {
            reg.register(tool) catch {};
        }

        return reg;
    }

    /// Clean up registry resources
    pub fn deinit(self: *Registry) void {
        var iter = self.tools.iterator();
        while (iter.next()) |entry| {
            const tool = entry.value_ptr.*;
            self.allocator.free(tool.name);
            self.allocator.free(tool.description);
            self.allocator.free(tool.input_schema);
            
            // If it's an MCP tool, clean up its context
            if (tool.ctx) |ctx| {
                const mcp_ctx: *tool_bridge.McpToolContext = @ptrCast(@alignCast(ctx));
                mcp_ctx.deinit(self.allocator);
            }
        }
        self.tools.deinit();

        for (self.mcp_clients.items) |client| {
            client.deinit();
            self.allocator.destroy(client);
        }
        self.mcp_clients.deinit(self.allocator);
    }

    /// Register a new tool
    pub fn register(self: *Registry, tool: Tool) !void {
        const name = try self.allocator.dupe(u8, tool.name);
        errdefer self.allocator.free(name);
        const desc = try self.allocator.dupe(u8, tool.description);
        errdefer self.allocator.free(desc);
        const schema = try self.allocator.dupe(u8, tool.input_schema);
        errdefer self.allocator.free(schema);

        try self.tools.put(name, .{
            .name = name,
            .description = desc,
            .input_schema = schema,
            .handler = tool.handler,
            .ctx = tool.ctx,
        });
    }

    /// Register all tools from an MCP server
    pub fn registerMcpServer(self: *Registry, server_name: []const u8, command: []const []const u8) !void {
        const client = try self.allocator.create(mcp.McpClient);
        client.* = try mcp.McpClient.init(self.allocator, command);
        errdefer {
            client.deinit();
            self.allocator.destroy(client);
        }

        try client.initialize();
        const mcp_tools = try client.listTools();
        defer {
            for (mcp_tools) |*t| {
                t.deinit(self.allocator);
            }
            self.allocator.free(mcp_tools);
        }

        for (mcp_tools) |m_tool| {
            const tool = try tool_bridge.mcpToolToTool(self.allocator, client, m_tool, server_name);
            try self.register(tool);
            // register() dupes everything, so we must clean up 'tool'
            self.allocator.free(tool.name);
            self.allocator.free(tool.description);
            self.allocator.free(tool.input_schema);
            // Note: tool.ctx is managed by Registry.deinit
        }

        try self.mcp_clients.append(self.allocator, client);
    }

    /// Get a tool by name
    pub fn get(self: *const Registry, name: []const u8) ?Tool {
        return self.tools.get(name);
    }

    /// Check if a tool exists
    pub fn has(self: *const Registry, name: []const u8) bool {
        return self.tools.contains(name);
    }

    /// Execute a tool by name with the given arguments
    pub fn execute(self: *const Registry, allocator: std.mem.Allocator, input: ToolInput) !ToolOutput {
        const tool = self.tools.get(input.name) orelse {
            return ToolOutput.failure(std.fmt.allocPrint(allocator, "Unknown tool: {s}", .{input.name}) catch "Unknown tool");
        };

        // Validate input against schema (basic check)
        if (input.arguments == .null) {
            return ToolOutput.failure("Invalid arguments: expected object");
        }

        // Execute the tool
        return tool.handler(allocator, tool.ctx, input) catch |err| {
            return ToolOutput.failure(std.fmt.allocPrint(allocator, "Tool execution failed: {}", .{err}) catch "Tool execution failed");
        };
    }

    /// List all registered tools
    pub fn list(self: *const Registry) []const Tool {
        var tool_count: usize = 0;
        var it = self.tools.iterator();
        while (it.next()) |_| {
            tool_count += 1;
        }

        var tool_list = std.ArrayList(Tool){};
        defer tool_list.deinit();

        it = self.tools.iterator();
        while (it.next()) |entry| {
            try tool_list.append(self.allocator, entry.value_ptr.*);
        }

        return tool_list.toOwnedSlice(self.allocator);
    }

    /// List all tools as JSON string
    pub fn listAsJson(self: *const Registry, allocator: std.mem.Allocator) ![]const u8 {
        var buf = try std.ArrayList(u8).initCapacity(allocator, 1024);
        defer buf.deinit(allocator);

        try buf.appendSlice(allocator, "[");

        var it = self.tools.iterator();
        var first = true;
        while (it.next()) |entry| {
            if (!first) try buf.appendSlice(allocator, ",");
            first = false;

            const tool = entry.value_ptr.*;
            try buf.appendSlice(allocator, "{\"name\":\"");
            try buf.appendSlice(allocator, tool.name);
            try buf.appendSlice(allocator, "\",\"description\":\"");
            try buf.appendSlice(allocator, tool.description);
            try buf.appendSlice(allocator, "\",\"input_schema\":");
            try buf.appendSlice(allocator, tool.input_schema);
            try buf.appendSlice(allocator, "}");
        }

        try buf.appendSlice(allocator, "]");
        return buf.toOwnedSlice(allocator);
    }

    /// Remove a tool from the registry
    pub fn unregister(self: *Registry, name: []const u8) void {
        if (self.tools.fetchRemove(name)) |entry| {
            self.allocator.free(entry.value.name);
            self.allocator.free(entry.value.description);
            self.allocator.free(entry.value.input_schema);
        }
    }

    /// Get the count of registered tools
    pub fn count(self: *const Registry) usize {
        return self.tools.count();
    }
};

/// Create a default registry with all built-in tools
pub fn createDefaultRegistry(allocator: std.mem.Allocator) Registry {
    return Registry.init(allocator);
}

// Alias for backward compatibility
pub const ToolRegistry = Registry;

test "Registry initialization" {
    const allocator = std.testing.allocator;
    var registry = Registry.init(allocator);
    defer registry.deinit();

    // Should have built-in tools
    try std.testing.expect(registry.count() > 0);
    try std.testing.expect(registry.has("bash"));
    try std.testing.expect(registry.has("read"));
    try std.testing.expect(registry.has("write"));
}

test "Registry get tool" {
    const allocator = std.testing.allocator;
    var registry = Registry.init(allocator);
    defer registry.deinit();

    const bash_tool = registry.get("bash");
    try std.testing.expect(bash_tool != null);
    try std.testing.expect(mem.eql(u8, bash_tool.?.name, "bash"));
}

test "Registry execute" {
    const allocator = std.testing.allocator;
    var registry = Registry.init(allocator);
    defer registry.deinit();

    // Execute a simple command
    var args_map = std.json.ObjectMap.init(allocator);
    defer args_map.deinit();
    try args_map.put("command", json.Value{ .string = "echo hello" });
    const args = json.Value{ .object = args_map };

    const input = ToolInput{
        .name = "bash",
        .arguments = args,
    };

    const result = try registry.execute(allocator, input);
    defer allocator.free(result.content);
    try std.testing.expect(!result.is_error);
    try std.testing.expect(mem.eql(u8, result.content, "hello\n"));
}

test "Registry list as JSON" {
    const allocator = std.testing.allocator;
    var registry = Registry.init(allocator);
    defer registry.deinit();

    const json_str = try registry.listAsJson(allocator);
    defer allocator.free(json_str);

    // Should be a valid JSON array
    try std.testing.expect(json_str[0] == '[');
    try std.testing.expect(json_str[json_str.len - 1] == ']');
}

test "Registry unregister" {
    const allocator = std.testing.allocator;
    var registry = Registry.init(allocator);
    defer registry.deinit();

    try std.testing.expect(registry.has("bash"));
    registry.unregister("bash");
    try std.testing.expect(!registry.has("bash"));
}
