const std = @import("std");
const tool = @import("tool.zig");

pub const ToolRegistry = struct {
    allocator: std.mem.Allocator,
    tools: std.StringHashMap(tool.Tool),

    pub fn init(allocator: std.mem.Allocator) ToolRegistry {
        return .{
            .allocator = allocator,
            .tools = std.StringHashMap(tool.Tool).init(allocator),
        };
    }

    pub fn deinit(self: *ToolRegistry) void {
        self.tools.deinit();
    }

    pub fn register(self: *ToolRegistry, t: tool.Tool) !void {
        try self.tools.put(t.name, t);
    }

    pub fn get(self: *ToolRegistry, name: []const u8) ?tool.Tool {
        return self.tools.get(name);
    }

    pub fn list(self: *ToolRegistry) []const tool.Tool {
        return self.tools.values();
    }
};

test "placeholder" {
    try std.testing.expect(true);
}
