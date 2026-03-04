const std = @import("std");
const json = std.json;
const mem = std.mem;
const Tool = @import("tool.zig").Tool;
const ToolInput = @import("tool.zig").ToolInput;
const ToolOutput = @import("tool.zig").ToolOutput;
const BuiltinTools = @import("tool.zig").BuiltinTools;

/// Tool registry - manages available tools and their execution
pub const Registry = struct {
    allocator: std.mem.Allocator,
    tools: std.StringHashMap(Tool),

    /// Initialize the registry with built-in tools
    pub fn init(allocator: std.mem.Allocator) Registry {
        var reg = Registry{
            .allocator = allocator,
            .tools = std.StringHashMap(Tool).init(allocator),
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
            self.allocator.free(entry.value_ptr.name);
            self.allocator.free(entry.value_ptr.description);
            self.allocator.free(entry.value_ptr.input_schema);
        }
        self.tools.deinit();
    }

    /// Register a new tool
    pub fn register(self: *Registry, tool: Tool) !void {
        const name = try self.allocator.dupe(u8, tool.name);
        const desc = try self.allocator.dupe(u8, tool.description);
        const schema = try self.allocator.dupe(u8, tool.input_schema);

        try self.tools.put(name, .{
            .name = name,
            .description = desc,
            .input_schema = schema,
            .handler = tool.handler,
        });
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
        return tool.handler(allocator, input) catch |err| {
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

        var tool_list = std.ArrayList(Tool).init(self.allocator);
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
