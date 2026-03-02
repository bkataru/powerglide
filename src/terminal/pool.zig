const std = @import("std");

pub const TerminalPool = struct {
    max_size: usize = 4,
    active_count: usize = 0,
    sessions: std.ArrayList(?*anyopaque),

    pub fn init(allocator: std.mem.Allocator, max_size: usize) TerminalPool {
        return .{
            .max_size = max_size,
            .sessions = std.ArrayList(?*anyopaque).init(allocator),
        };
    }

    pub fn deinit(self: *TerminalPool) void {
        self.sessions.deinit();
    }

    pub fn acquire(self: *TerminalPool) ?*anyopaque {
        if (self.active_count >= self.max_size) {
            return null;
        }
        self.active_count += 1;
        return @as(?*anyopaque, @ptrFromInt(@intFromBool(true)));
    }

    pub fn release(self: *TerminalPool, _session: *anyopaque) void {
        _ = _session;
        if (self.active_count > 0) {
            self.active_count -= 1;
        }
    }
};

test "placeholder" {
    try std.testing.expect(true);
}
