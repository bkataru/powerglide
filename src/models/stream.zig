const std = @import("std");

pub const StreamEvent = union(enum) {
    content: []const u8,
    done,
    error: []const u8,
};

pub const SSEStream = struct {
    allocator: std.mem.Allocator,
    buffer: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator) SSEStream {
        return .{
            .allocator = allocator,
            .buffer = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *SSEStream) void {
        self.buffer.deinit();
    }

    pub fn parseEvent(self: *SSEStream, data: []const u8) !?StreamEvent {
        _ = self;
        _ = data;
        return null;
    }
};

test "placeholder" {
    try std.testing.expect(true);
}