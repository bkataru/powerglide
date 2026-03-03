const std = @import("std");
const Worker = @import("worker.zig").Worker;

pub const MonitorEvent = union(enum) {
    worker_done: u32, // worker id
    worker_stale: u32, // worker id (heartbeat timeout)
    worker_failed: u32, // worker id (process died)
    all_done: void,
};

pub const Monitor = struct {
    allocator: std.mem.Allocator,
    workers: std.AutoHashMap(u32, *Worker),
    heartbeat_timeout_ms: u64,
    poll_interval_ms: u64,

    pub fn init(allocator: std.mem.Allocator, heartbeat_timeout_ms: u64) Monitor {
        return Monitor{
            .allocator = allocator,
            .workers = std.AutoHashMap(u32, *Worker).init(allocator),
            .heartbeat_timeout_ms = heartbeat_timeout_ms,
            .poll_interval_ms = 5000,
        };
    }

    pub fn deinit(self: *Monitor) void {
        self.workers.deinit();
    }

    pub fn addWorker(self: *Monitor, worker: *Worker) !void {
        try self.workers.put(worker.config.id, worker);
    }

    pub fn removeWorker(self: *Monitor, id: u32) void {
        self.workers.remove(id);
    }

    /// Single poll cycle: check each worker status
    /// Returns list of events that occurred
    pub fn poll(self: *Monitor, allocator: std.mem.Allocator) ![]MonitorEvent {
        var events = std.ArrayList(MonitorEvent){};
        errdefer events.deinit(allocator);
        try events.ensureTotalCapacity(allocator, 16);

        var iterator = self.workers.iterator();
        while (iterator.next()) |entry| {
            const id = entry.key_ptr.*;
            const worker = entry.value_ptr.*;

            if (worker.status == .idle) {
                continue;
            }

            // Check if heartbeat is stale
            if (worker.isStale(self.heartbeat_timeout_ms)) {
                try events.append(allocator, .{ .worker_stale = id });
                continue;
            }

            // Check if worker is still running
            if (worker.status == .running) {
                if (worker.pid) |pid| {
                    var status: std.posix.wait_status = undefined;
                    const wait_result = std.posix.waitpid(pid, &status, std.posix.WNOHANG);

                    if (wait_result > 0) {
                        // Process has exited
                        if (status.Exited) {
                            if (status.code == 0) {
                                worker.status = .done;
                                try events.append(allocator, .{ .worker_done = id });
                            } else {
                                worker.status = .failed;
                                try events.append(allocator, .{ .worker_failed = id });
                            }
                        } else if (status.Signaled) {
                            worker.status = .failed;
                            try events.append(allocator, .{ .worker_failed = id });
                        }
                    } else if (wait_result == -1) {
                        // Error - process might have died
                        worker.status = .failed;
                        try events.append(allocator, .{ .worker_failed = id });
                    }
                }
            }

            // Check for completion via output file
            if (worker.status == .running) {
                const done = worker.checkDone() catch false;
                if (done) {
                    try events.append(allocator, .{ .worker_done = id });
                }
            }
        }

        // Check if all workers are done
        if (self.allDone()) {
            try events.append(allocator, .all_done);
        }

        return events.toOwnedSlice();
    }

    /// Kill all stale workers (heartbeat timed out)
    pub fn killStale(self: *Monitor) void {
        var iterator = self.workers.iterator();
        while (iterator.next()) |entry| {
            const worker = entry.value_ptr.*;
            if (worker.isStale(self.heartbeat_timeout_ms)) {
                worker.kill();
            }
        }
    }

    pub fn activeCount(self: *const Monitor) usize {
        var count: usize = 0;
        var iterator = self.workers.iterator();
        while (iterator.next()) |entry| {
            const worker = entry.value_ptr.*;
            if (worker.status == .running) {
                count += 1;
            }
        }
        return count;
    }

    pub fn allDone(self: *const Monitor) bool {
        if (self.workers.count() == 0) {
            return true;
        }

        var iterator = self.workers.iterator();
        while (iterator.next()) |entry| {
            const worker = entry.value_ptr.*;
            if (worker.status == .running or worker.status == .idle) {
                return false;
            }
        }
        return true;
    }

    /// Get worker by ID
    pub fn getWorker(self: *const Monitor, id: u32) ?*Worker {
        return self.workers.get(id);
    }
};

test "Monitor.init creates monitor with default config" {
    const allocator = std.testing.allocator;
    var monitor = Monitor.init(allocator, 60_000);
    defer monitor.deinit();

    try std.testing.expectEqual(@as(u64, 60_000), monitor.heartbeat_timeout_ms);
    try std.testing.expectEqual(@as(u64, 5000), monitor.poll_interval_ms);
    try std.testing.expectEqual(@as(usize, 0), monitor.workers.count());
}

test "Monitor.activeCount returns zero for empty monitor" {
    const allocator = std.testing.allocator;
    var monitor = Monitor.init(allocator, 60_000);
    defer monitor.deinit();

    try std.testing.expectEqual(@as(usize, 0), monitor.activeCount());
}

test "Monitor.allDone returns true for empty monitor" {
    const allocator = std.testing.allocator;
    var monitor = Monitor.init(allocator, 60_000);
    defer monitor.deinit();

    try std.testing.expect(monitor.allDone());
}

test "Monitor.getWorker returns null for nonexistent worker" {
    const allocator = std.testing.allocator;
    var monitor = Monitor.init(allocator, 60_000);
    defer monitor.deinit();

    const worker = monitor.getWorker(999);
    try std.testing.expect(worker == null);
}

