const std = @import("std");
const WorkerConfig = @import("worker.zig").WorkerConfig;
const Worker = @import("worker.zig").Worker;
const Monitor = @import("monitor.zig").Monitor;

pub const SwarmConfig = struct {
    max_workers: u32 = 8,
    working_dir: []const u8,
    heartbeat_timeout_ms: u64 = 60_000,
    poll_interval_ms: u64 = 5_000,
    default_agent: []const u8 = "hephaestus",
};

pub const TaskAssignment = struct {
    task_id: []const u8,
    description: []const u8,
    priority: u8 = 5,
    assigned_worker: ?u32 = null,
    done: bool = false,
};

pub const Swarm = struct {
    allocator: std.mem.Allocator,
    config: SwarmConfig,
    workers: std.ArrayList(Worker),
    tasks: std.ArrayList(TaskAssignment),
    monitor: Monitor,
    next_worker_id: u32,

    pub fn init(allocator: std.mem.Allocator, config: SwarmConfig) Swarm {
        return Swarm{
            .allocator = allocator,
            .config = config,
            .workers = std.ArrayList(Worker).init(allocator),
            .tasks = std.ArrayList(TaskAssignment).init(allocator),
            .monitor = Monitor.init(allocator, config.heartbeat_timeout_ms),
            .next_worker_id = 0,
        };
    }

    pub fn deinit(self: *Swarm) void {
        // Kill all workers
        for (self.workers.items) |*worker| {
            worker.deinit();
        }
        self.workers.deinit();
        self.tasks.deinit();
        self.monitor.deinit();
    }

    /// Add a task to the swarm queue
    pub fn addTask(self: *Swarm, task_id: []const u8, description: []const u8, priority: u8) !void {
        const task = TaskAssignment{
            .task_id = task_id,
            .description = description,
            .priority = priority,
            .assigned_worker = null,
            .done = false,
        };
        try self.tasks.append(task);
    }

    /// Dispatch next pending task to a new worker (up to max_workers)
    pub fn dispatch(self: *Swarm) !?u32 {
        // Check if we can spawn more workers
        const active_count = self.activeWorkerCount();
        if (active_count >= self.config.max_workers) {
            return null;
        }

        // Find the highest priority pending task
        var best_task_idx: ?usize = null;
        var best_priority: u8 = 0;

        for (self.tasks.items, 0..) |task, idx| {
            if (!task.done and task.assigned_worker == null) {
                if (best_task_idx == null or task.priority > best_priority) {
                    best_task_idx = idx;
                    best_priority = task.priority;
                }
            }
        }

        if (best_task_idx == null) {
            return null;
        }

        const task_idx = best_task_idx.?;
        const task = &self.tasks.items[task_idx];

        // Create worker config
        const worker_id = self.next_worker_id;
        self.next_worker_id += 1;

        const worker_config = WorkerConfig{
            .id = worker_id,
            .task_description = task.description,
            .working_dir = self.config.working_dir,
            .agent_name = self.config.default_agent,
            .timeout_ms = self.config.heartbeat_timeout_ms * 10, // 10x heartbeat timeout
        };

        // Create and init worker
        var worker = try Worker.init(self.allocator, worker_config);
        errdefer worker.deinit();

        // Spawn the worker
        try worker.spawn();

        // Add to workers list
        try self.workers.append(worker);

        // Add to monitor
        const worker_ptr = &self.workers.items[self.workers.items.len - 1];
        try self.monitor.addWorker(worker_ptr);

        // Mark task as assigned
        task.assigned_worker = worker_id;

        return worker_id;
    }

    /// Run the swarm until all tasks complete or timeout
    pub fn run(self: *Swarm) !void {
        const start_time = std.time.milliTimestamp();
        const timeout_ms = self.config.heartbeat_timeout_ms * 10; // Total timeout
 while (!self.allDone()) {
 // Check for timeout
 const elapsed: u64 = @intCast(std.time.milliTimestamp() - start_time);
 if (elapsed > timeout_ms) {
                return error.SwarmTimeout;
            }

            // Single poll cycle
            try self.tick();

            // Sleep for poll interval
            std.time.sleep(self.config.poll_interval_ms * 1_000_000); // Convert ms to ns
        }
    }

    /// Single poll: dispatch new tasks, check completions, kill stale workers
    pub fn tick(self: *Swarm) !void {
        // Dispatch pending tasks if we have capacity
        while (self.activeWorkerCount() < self.config.max_workers) {
            const dispatched = try self.dispatch();
            if (dispatched == null) {
                break;
            }
        }

        // Poll the monitor for events
        const events = try self.monitor.poll(self.allocator);
        defer self.allocator.free(events);

        // Process events
        for (events) |event| {
            switch (event) {
                .worker_done => |worker_id| {
                    // Mark the task as done
                    for (self.tasks.items) |*task| {
                        if (task.assigned_worker == worker_id) {
                            task.done = true;
                            break;
                        }
                    }
                },
                .worker_stale => |worker_id| {
                    // Kill the stale worker
                    if (self.monitor.getWorker(worker_id)) |worker| {
                        worker.kill();
                    }
                    // Mark task as not done (will need retry or fail)
                    for (self.tasks.items) |*task| {
                        if (task.assigned_worker == worker_id) {
                            task.assigned_worker = null; // Allow retry
                            break;
                        }
                    }
                },
                .worker_failed => |worker_id| {
                    // Mark task as not done (will need retry or fail)
                    for (self.tasks.items) |*task| {
                        if (task.assigned_worker == worker_id) {
                            task.assigned_worker = null; // Allow retry
                            break;
                        }
                    }
                },
                .all_done => {
                    // All workers completed
                },
            }
        }

        // Kill any stale workers
        self.monitor.killStale();
    }

    pub fn pendingCount(self: *const Swarm) usize {
        var count: usize = 0;
        for (self.tasks.items) |task| {
            if (!task.done and task.assigned_worker == null) {
                count += 1;
            }
        }
        return count;
    }

    pub fn activeWorkerCount(self: *const Swarm) usize {
        return self.monitor.activeCount();
    }

    pub fn allDone(self: *const Swarm) bool {
        // All tasks done AND all workers done
        const all_tasks_done = for (self.tasks.items) |task| {
            if (!task.done) break false;
        } else true;

        return all_tasks_done and self.monitor.allDone();
    }

    /// Get task by ID
    pub fn getTask(self: *const Swarm, task_id: []const u8) ?*TaskAssignment {
        for (self.tasks.items) |*task| {
            if (std.mem.eql(u8, task.task_id, task_id)) {
                return task;
            }
        }
        return null;
    }

    /// Get worker by ID
    pub fn getWorker(self: *const Swarm, id: u32) ?*Worker {
        for (self.workers.items) |*worker| {
            if (worker.config.id == id) {
                return worker;
            }
        }
        return null;
    }
};

test "Swarm.init creates swarm with default config" {
    const allocator = std.testing.allocator;
    const config = SwarmConfig{
        .working_dir = "/tmp",
    };
    const swarm = Swarm.init(allocator, config);

    try std.testing.expectEqual(@as(u32, 8), swarm.config.max_workers);
    try std.testing.expectEqual(@as(u64, 60_000), swarm.config.heartbeat_timeout_ms);
    try std.testing.expectEqual(@as(u32, 0), swarm.next_worker_id);
    try std.testing.expectEqual(@as(usize, 0), swarm.workers.items.len);
    try std.testing.expectEqual(@as(usize, 0), swarm.tasks.items.len);

    swarm.deinit();
}

test "Swarm.addTask adds task to queue" {
    const allocator = std.testing.allocator;
    const config = SwarmConfig{
        .working_dir = "/tmp",
    };
    var swarm = Swarm.init(allocator, config);
    defer swarm.deinit();

    try swarm.addTask("task-1", "First task", 5);
    try swarm.addTask("task-2", "Second task", 10);

    try std.testing.expectEqual(@as(usize, 2), swarm.tasks.items.len);
    try std.testing.expectEqualStrings("task-1", swarm.tasks.items[0].task_id);
    try std.testing.expectEqualStrings("task-2", swarm.tasks.items[1].task_id);
    try std.testing.expectEqual(@as(u8, 10), swarm.tasks.items[1].priority); // Higher priority
}

test "Swarm.pendingCount returns correct count" {
    const allocator = std.testing.allocator;
    const config = SwarmConfig{
        .working_dir = "/tmp",
    };
    var swarm = Swarm.init(allocator, config);
    defer swarm.deinit();

    try swarm.addTask("task-1", "First task", 5);
    try swarm.addTask("task-2", "Second task", 3);

    try std.testing.expectEqual(@as(usize, 2), swarm.pendingCount());

    // Mark first task as done
    swarm.tasks.items[0].done = true;
    try std.testing.expectEqual(@as(usize, 1), swarm.pendingCount());

    // Assign second task to a worker
    swarm.tasks.items[1].assigned_worker = 1;
    try std.testing.expectEqual(@as(usize, 0), swarm.pendingCount());
}

test "Swarm.getTask finds task by ID" {
    const allocator = std.testing.allocator;
    const config = SwarmConfig{
        .working_dir = "/tmp",
    };
    var swarm = Swarm.init(allocator, config);
    defer swarm.deinit();

    try swarm.addTask("task-1", "First task", 5);
    try swarm.addTask("task-2", "Second task", 3);

    const found = swarm.getTask("task-1");
    try std.testing.expect(found != null);
    try std.testing.expectEqualStrings("First task", found.?.description);

    const not_found = swarm.getTask("nonexistent");
    try std.testing.expect(not_found == null);
}
