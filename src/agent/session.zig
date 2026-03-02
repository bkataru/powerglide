const std = @import("std");

pub const Session = struct {
    id: []const u8,
    created_at: i64,
    status: SessionStatus = .pending,

    pub const SessionStatus = enum {
        pending,
        active,
        paused,
        completed,
        failed,
    };
};

pub const SessionManager = struct {
    sessions: std.ArrayList(Session),

    pub fn init(allocator: std.mem.Allocator) SessionManager {
        return .{ .sessions = std.ArrayList(Session).init(allocator) };
    }

    pub fn deinit(self: *SessionManager) void {
        self.sessions.deinit();
    }
};

test "placeholder" {
    try std.testing.expect(true);
}
