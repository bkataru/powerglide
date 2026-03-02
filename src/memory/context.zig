const std = @import("std");

pub const Context = struct {
    allocator: std.mem.Allocator,
    history: std.ArrayList(ContextEntry),
    max_tokens: usize = 100000,

    pub const ContextEntry = struct {
        role: []const u8,
        content: []const u8,
        timestamp: i64,
    };

    pub fn init(allocator: std.mem.Allocator) Context {
        return .{
            .allocator = allocator,
            .history = std.ArrayList(ContextEntry).init(allocator),
        };
    }

    pub fn deinit(self: *Context) void {
        self.history.deinit();
    }

    pub fn addMessage(self: *Context, role: []const u8, content: []const u8) !void {
        const entry = ContextEntry{
            .role = role,
            .content = content,
            .timestamp = std.time.timestamp(),
        };
        try self.history.append(entry);
    }

    pub fn getMessages(self: *Context) []const ContextEntry {
        return self.history.items;
    }
};

test "placeholder" {
    try std.testing.expect(true);
}
