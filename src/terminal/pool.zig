//! Multi-Terminal Pool - manages multiple terminal sessions

const std = @import("std");

const TerminalSession = @import("session.zig").TerminalSession;
const SessionId = @import("session.zig").SessionId;
const CommandResult = @import("session.zig").CommandResult;

/// Pool for managing multiple terminal sessions
pub const Pool = struct {
    allocator: std.mem.Allocator,
    sessions: std.AutoHashMap(SessionId, TerminalSession),
    next_id: SessionId,
    max_sessions: usize,

    /// Initialize a new terminal pool
    pub fn init(allocator: std.mem.Allocator, max_sessions: usize) Pool {
        return .{
            .allocator = allocator,
            .sessions = std.AutoHashMap(SessionId, TerminalSession).init(allocator),
            .next_id = 1,
            .max_sessions = max_sessions,
        };
    }

    /// Clean up all sessions and pool resources
    pub fn deinit(self: *Pool) void {
        var iter = self.sessions.valueIterator();
        while (iter.next()) |session| {
            session.deinit();
        }
        self.sessions.deinit();
    }

    /// Create a new terminal session
    pub fn create(self: *Pool) !SessionId {
        if (self.sessions.size >= self.max_sessions) {
            return error.PoolFull;
        }

        const id = self.next_id;
        self.next_id += 1;

        const session = TerminalSession.init(self.allocator, id);
        try self.sessions.put(id, session);

        return id;
    }

    /// Get session by ID
    pub fn get(self: *Pool, id: SessionId) ?*TerminalSession {
        return self.sessions.getPtr(id);
    }

    /// Run a command in a session and wait for result
    pub fn run(self: *Pool, id: SessionId, allocator: std.mem.Allocator, cmd: []const u8, timeout_ms: u64) !CommandResult {
        const session = self.sessions.getPtr(id) orelse return error.SessionNotFound;
        return session.runCommand(allocator, cmd, timeout_ms);
    }

    /// Close a session by ID
    pub fn close(self: *Pool, id: SessionId) void {
        if (self.sessions.getPtr(id)) |session| {
            session.deinit();
        }
        _ = self.sessions.remove(id);
    }

    /// Count active sessions (sessions with alive processes)
    pub fn activeCount(self: *const Pool) usize {
        var count: usize = 0;
        var iter = self.sessions.valueIterator();
        while (iter.next()) |session| {
            if (session.isAlive()) {
                count += 1;
            }
        }
        return count;
    }
};

/// Pool-specific errors
pub const PoolError = error{
    PoolFull,
    SessionNotFound,
};

test "Pool.init creates pool with default config" {
    const allocator = std.testing.allocator;
    const pool = Pool.init(allocator, 10);

    try std.testing.expectEqual(@as(usize, 10), pool.max_sessions);
    try std.testing.expectEqual(@as(SessionId, 1), pool.next_id);
    try std.testing.expectEqual(@as(usize, 0), pool.sessions.size);

    pool.deinit();
}

test "Pool.create adds new session" {
    const allocator = std.testing.allocator;
    var pool = Pool.init(allocator, 10);
    defer pool.deinit();

    const id = try pool.create();
    try std.testing.expectEqual(@as(SessionId, 1), id);
    try std.testing.expectEqual(@as(usize, 1), pool.sessions.size);
}

test "Pool.get retrieves session by id" {
    const allocator = std.testing.allocator;
    var pool = Pool.init(allocator, 10);
    defer pool.deinit();

    const id = try pool.create();
    const session = pool.get(id);
    try std.testing.expect(session != null);
    try std.testing.expectEqual(id, session.?.id);

    const not_found = pool.get(999);
    try std.testing.expect(not_found == null);
}

test "Pool.activeCount returns zero for empty pool" {
    const allocator = std.testing.allocator;
    const pool = Pool.init(allocator, 10);
    defer pool.deinit();

    try std.testing.expectEqual(@as(usize, 0), pool.activeCount());
}
    try std.testing.expect(true);
}
