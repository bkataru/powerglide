const std = @import("std");

pub const TerminalSession = struct {
    id: []const u8,
    pty: ?*anyopaque = null,
    exit_code: u8 = 0,
    active: bool = false,

    pub fn create(id: []const u8) TerminalSession {
        return .{ .id = id };
    }

    pub fn destroy(self: *TerminalSession) void {
        _ = self;
    }
};

pub const TerminalSessionStore = struct {
    sessions: std.StringHashMap(TerminalSession),

    pub fn init(allocator: std.mem.Allocator) TerminalSessionStore {
        return .{ .sessions = std.StringHashMap(TerminalSession).init(allocator) };
    }

    pub fn deinit(self: *TerminalSessionStore) void {
        self.sessions.deinit();
    }
};

test "placeholder" {
    try std.testing.expect(true);
}
