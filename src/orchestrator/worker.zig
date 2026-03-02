const std = @import("std");

pub const Worker = struct {
    id: []const u8,
    status: WorkerStatus = .idle,
    current_task: ?[]const u8 = null,

    pub const WorkerStatus = enum {
        idle,
        busy,
        waiting,
        done,
        error,
    };
};

pub const WorkerPool = struct {
    allocator: std.mem.Allocator,
    workers: std.ArrayList(Worker),

    pub fn init(allocator: std.mem.Allocator, size: usize) WorkerPool {
        return .{
            .allocator = allocator,
            .workers = std.ArrayList(Worker).init(allocator),
        };
    }

    pub fn deinit(self: *WorkerPool) void {
        self.workers.deinit();
    }

    pub fn assignTask(self: *WorkerPool, worker_id: []const u8, task: []const u8) !void {
        _ = self;
        _ = worker_id;
        _ = task;
    }
};

test "placeholder" {
    try std.testing.expect(true);
}