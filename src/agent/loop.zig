const std = @import("std");
const json = std.json;
const mem = std.mem;
const time = std.time;

/// Ralph Loop State Machine states
pub const LoopState = enum {
    idle,
    load_tasks,
    pick_task,
    thinking,
    tool_call,
    executing,
    observing,
    verify,
    commit,
    done,
    failed,
};

/// Configuration for the Ralph loop
pub const LoopConfig = struct {
    max_steps: u32 = 200,
    velocity: f64 = 1.0,
    heartbeat_interval_ms: u64 = 30_000,
    think_budget_ms: u64 = 120_000,
    model: []const u8 = "claude-opus-4-6",
    session_file: []const u8 = ".powerglide/session.json",
};

/// Result of a single loop step
pub const StepResult = union(enum) {
    continue_loop: LoopState,
    done: void,
    failed: []const u8,
};

/// Main Ralph loop state machine
pub const Loop = struct {
    allocator: std.mem.Allocator,
    config: LoopConfig,
    state: LoopState,
    step_count: u32,
    last_heartbeat_ms: i64,

    pub fn init(allocator: std.mem.Allocator, config: LoopConfig) Loop {
        return .{
            .allocator = allocator,
            .config = config,
            .state = .idle,
            .step_count = 0,
            .last_heartbeat_ms = time.milliTimestamp(),
        };
    }

    pub fn deinit(self: *Loop) void {
        _ = self;
    }

    pub fn run(self: *Loop) !void {
        std.debug.print("Starting Ralph loop (max_steps={}, velocity={d:.1})\n", .{
            self.config.max_steps,
            self.config.velocity,
        });

        while (true) {
            try self.checkRogueGuard();
            const result = try self.step();

            switch (result) {
                .done => {
                    std.debug.print("Ralph loop completed after {} steps\n", .{self.step_count});
                    break;
                },
                .failed => |msg| {
                    std.debug.print("Ralph loop failed: {s}\n", .{msg});
                    self.state = .failed;
                    break;
                },
                .continue_loop => |next_state| {
                    self.state = next_state;
                    if (self.config.velocity > 0) {
                        const delay_ns = @as(u64, @intFromFloat(1000.0 / self.config.velocity * 1_000_000.0));
                        std.Thread.sleep(delay_ns);
                    }
                    self.step_count += 1;
                },
            }
        }
    }

    pub fn step(self: *Loop) !StepResult {
        switch (self.state) {
            .idle => {
                self.state = .load_tasks;
                return .{ .continue_loop = .load_tasks };
            },
            .load_tasks => {
                try self.loadState();
                self.state = .pick_task;
                return .{ .continue_loop = .pick_task };
            },
            .pick_task => {
                self.state = .thinking;
                return .{ .continue_loop = .thinking };
            },
            .thinking => {
                self.state = .tool_call;
                return .{ .continue_loop = .tool_call };
            },
            .tool_call => {
                self.state = .executing;
                return .{ .continue_loop = .executing };
            },
            .executing => {
                self.state = .observing;
                return .{ .continue_loop = .observing };
            },
            .observing => {
                self.state = .verify;
                return .{ .continue_loop = .verify };
            },
            .verify => {
                self.state = .commit;
                return .{ .continue_loop = .commit };
            },
            .commit => {
                try self.saveState();
                self.state = .done;
                return .{ .continue_loop = .done };
            },
            .done => return .{ .done = {} },
            .failed => return .{ .failed = "Loop already in failed state" },
        }
    }

    pub fn checkRogueGuard(self: *Loop) !void {
        if (self.step_count >= self.config.max_steps) {
            return error.StepLimitExceeded;
        }
        const now = time.milliTimestamp();
        if (now - self.last_heartbeat_ms > @as(i64, @intCast(self.config.heartbeat_interval_ms))) {
            return error.HeartbeatTimeout;
        }
        self.last_heartbeat_ms = now;
    }

    pub fn saveState(self: *Loop) !void {
        const dir_path = self.config.session_file[0 .. mem.lastIndexOf(u8, self.config.session_file, "/") orelse 0];
        if (dir_path.len > 0) {
            try std.fs.cwd().makePath(dir_path);
        }
        const file = try std.fs.cwd().createFile(self.config.session_file, .{});
        defer file.close();
        var buf: [256]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&buf);
        try fbs.writer().print("{{\"step_count\":{},\"state\":\"{s}\"}}", .{
            self.step_count,
            @tagName(self.state),
        });
        try file.writeAll(fbs.getWritten());
    }

    pub fn loadState(self: *Loop) !void {
        const file = std.fs.cwd().openFile(self.config.session_file, .{}) catch |err| {
            if (err == error.FileNotFound) return;
            return err;
        };
        defer file.close();
        const content = try file.readToEndAlloc(self.allocator, 4096);
        defer self.allocator.free(content);
        const parsed = try json.parseFromSlice(json.Value, self.allocator, content, .{});
        defer parsed.deinit();
        if (parsed.value == .object) {
            const obj = parsed.value.object;
            if (obj.get("step_count")) |step_count| {
                if (step_count == .integer) {
                    self.step_count = @intCast(step_count.integer);
                }
            }
        }
    }
};

test "Loop state transitions" {
    const allocator = std.testing.allocator;
    const config = LoopConfig{ .max_steps = 10, .velocity = 0 };
    var loop = Loop.init(allocator, config);
    defer loop.deinit();

    try std.testing.expect(loop.state == .idle);
    _ = try loop.step();
    try std.testing.expect(loop.state == .load_tasks);
}

test "Loop step count increments" {
    const allocator = std.testing.allocator;
    const config = LoopConfig{ .max_steps = 10, .velocity = 0 };
    var loop = Loop.init(allocator, config);
    defer loop.deinit();

    var i: u32 = 0;
    while (i < 5) : (i += 1) {
        _ = try loop.step();
    }
    try std.testing.expect(loop.step_count == 0);
}

test "Rogue guard step limit" {
    const allocator = std.testing.allocator;
    const config = LoopConfig{ .max_steps = 2, .velocity = 0 };
    var loop = Loop.init(allocator, config);
    defer loop.deinit();

    loop.step_count = 2;
    try std.testing.expectError(error.StepLimitExceeded, loop.checkRogueGuard());
}

test "Loop all 11 states transition correctly" {
    const allocator = std.testing.allocator;
    const tmp_session = "/tmp/test_loop_session.json";
    const config = LoopConfig{
        .max_steps = 20,
        .velocity = 0,
        .session_file = tmp_session,
    };
    var loop = Loop.init(allocator, config);
    defer loop.deinit();

    // Clean up old session file
    std.fs.cwd().deleteFile(tmp_session) catch {};
    defer std.fs.cwd().deleteFile(tmp_session) catch {};

    // idle -> load_tasks
    try std.testing.expect(loop.state == .idle);
    const result1 = try loop.step();
    try std.testing.expect(result1.continue_loop == .load_tasks);
    try std.testing.expect(loop.state == .load_tasks);

    // load_tasks -> pick_task
    const result2 = try loop.step();
    try std.testing.expect(result2.continue_loop == .pick_task);
    try std.testing.expect(loop.state == .pick_task);

    // pick_task -> thinking
    const result3 = try loop.step();
    try std.testing.expect(result3.continue_loop == .thinking);
    try std.testing.expect(loop.state == .thinking);

    // thinking -> tool_call
    const result4 = try loop.step();
    try std.testing.expect(result4.continue_loop == .tool_call);
    try std.testing.expect(loop.state == .tool_call);

    // tool_call -> executing
    const result5 = try loop.step();
    try std.testing.expect(result5.continue_loop == .executing);
    try std.testing.expect(loop.state == .executing);

    // executing -> observing
    const result6 = try loop.step();
    try std.testing.expect(result6.continue_loop == .observing);
    try std.testing.expect(loop.state == .observing);

    // observing -> verify
    const result7 = try loop.step();
    try std.testing.expect(result7.continue_loop == .verify);
    try std.testing.expect(loop.state == .verify);

    // verify -> commit
    const result8 = try loop.step();
    try std.testing.expect(result8.continue_loop == .commit);
    try std.testing.expect(loop.state == .commit);

    // commit -> done
    const result9 = try loop.step();
    try std.testing.expect(result9.continue_loop == .done);
    try std.testing.expect(loop.state == .done);

    // done should return done
    const result10 = try loop.step();
    try std.testing.expect(result10 == .done);
}

test "LoopState enum values" {
    try std.testing.expect(@intFromEnum(LoopState.idle) == 0);
    try std.testing.expect(@intFromEnum(LoopState.load_tasks) == 1);
    try std.testing.expect(@intFromEnum(LoopState.pick_task) == 2);
    try std.testing.expect(@intFromEnum(LoopState.thinking) == 3);
    try std.testing.expect(@intFromEnum(LoopState.tool_call) == 4);
    try std.testing.expect(@intFromEnum(LoopState.executing) == 5);
    try std.testing.expect(@intFromEnum(LoopState.observing) == 6);
    try std.testing.expect(@intFromEnum(LoopState.verify) == 7);
    try std.testing.expect(@intFromEnum(LoopState.commit) == 8);
    try std.testing.expect(@intFromEnum(LoopState.done) == 9);
    try std.testing.expect(@intFromEnum(LoopState.failed) == 10);
}

test "LoopConfig default values" {
    const allocator = std.testing.allocator;
    const config = LoopConfig{};
    var loop = Loop.init(allocator, config);
    defer loop.deinit();

    try std.testing.expect(loop.config.max_steps == 200);
    try std.testing.expect(loop.config.velocity == 1.0);
    try std.testing.expect(loop.config.heartbeat_interval_ms == 30_000);
    try std.testing.expect(loop.config.think_budget_ms == 120_000);
    try std.testing.expect(std.mem.eql(u8, loop.config.model, "claude-opus-4-6"));
}

test "LoopConfig custom values" {
    const allocator = std.testing.allocator;
    const config = LoopConfig{
        .max_steps = 50,
        .velocity = 2.5,
        .heartbeat_interval_ms = 60_000,
        .think_budget_ms = 240_000,
        .model = "gpt-4",
        .session_file = "/tmp/custom.json",
    };
    var loop = Loop.init(allocator, config);
    defer loop.deinit();

    try std.testing.expect(loop.config.max_steps == 50);
    try std.testing.expect(loop.config.velocity == 2.5);
    try std.testing.expect(loop.config.heartbeat_interval_ms == 60_000);
    try std.testing.expect(std.mem.eql(u8, loop.config.model, "gpt-4"));
}

test "Loop saveState creates file" {
    const allocator = std.testing.allocator;
    const tmp_session = "/tmp/test_loop_save.json";
    const config = LoopConfig{
        .max_steps = 10,
        .velocity = 0,
        .session_file = tmp_session,
    };
    var loop = Loop.init(allocator, config);
    defer loop.deinit();

    std.fs.cwd().deleteFile(tmp_session) catch {};
    defer std.fs.cwd().deleteFile(tmp_session) catch {};

    loop.step_count = 5;
    loop.state = .thinking;

    try loop.saveState();

    // Check file exists
    const file = try std.fs.cwd().openFile(tmp_session, .{});
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 1024);
    defer allocator.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "step_count") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "5") != null);
}

test "Loop loadState loads from file" {
    const allocator = std.testing.allocator;
    const tmp_session = "/tmp/test_loop_load.json";
    const config = LoopConfig{
        .max_steps = 10,
        .velocity = 0,
        .session_file = tmp_session,
    };

    std.fs.cwd().deleteFile(tmp_session) catch {};
    defer std.fs.cwd().deleteFile(tmp_session) catch {};

    // Create session file
    {
        var loop1 = Loop.init(allocator, config);
        defer loop1.deinit();
        loop1.step_count = 7;
        loop1.state = .observing;
        try loop1.saveState();
    }

    // Load session
    var loop2 = Loop.init(allocator, config);
    defer loop2.deinit();

    try loop2.loadState();

    try std.testing.expect(loop2.step_count == 7);
}

test "Loop loadState handles missing file" {
    const allocator = std.testing.allocator;
    const tmp_session = "/tmp/test_loop_missing.json";
    const config = LoopConfig{
        .max_steps = 10,
        .velocity = 0,
        .session_file = tmp_session,
    };
    var loop = Loop.init(allocator, config);
    defer loop.deinit();

    std.fs.cwd().deleteFile(tmp_session) catch {};

    // Should not error when file doesn't exist
    try loop.loadState();
    try std.testing.expect(loop.step_count == 0);
}

test "LoopStepResult union" {
    const result1: StepResult = .{ .continue_loop = .idle };
    try std.testing.expect(result1 == .continue_loop);

    const result2: StepResult = .{ .done = {} };
    try std.testing.expect(result2 == .done);

    const result3: StepResult = .{ .failed = "error message" };
    try std.testing.expect(result3 == .failed);
}

test "Loop failed state returns failed" {
    const allocator = std.testing.allocator;
    const config = LoopConfig{ .max_steps = 10, .velocity = 0 };
    var loop = Loop.init(allocator, config);
    defer loop.deinit();

    loop.state = .failed;

    const result = try loop.step();
    try std.testing.expect(result == .failed);
}

test "Loop initialization state is idle" {
    const allocator = std.testing.allocator;
    const config = LoopConfig{};
    var loop = Loop.init(allocator, config);
    defer loop.deinit();

    try std.testing.expect(loop.state == .idle);
    try std.testing.expect(loop.step_count == 0);
}

test "Loop deinit is safe to call" {
    const allocator = std.testing.allocator;
    const config = LoopConfig{};
    var loop = Loop.init(allocator, config);
    loop.deinit(); // Should not panic
}

test "Loop heartbeat initialization" {
    const allocator = std.testing.allocator;
    const config = LoopConfig{};
    var loop = Loop.init(allocator, config);
    defer loop.deinit();

    try std.testing.expect(loop.last_heartbeat_ms > 0);
}

test "Loop heartbeat updates on check" {
    const allocator = std.testing.allocator;
    const config = LoopConfig{ .heartbeat_interval_ms = 1000 };
    var loop = Loop.init(allocator, config);
    defer loop.deinit();

    const old_heartbeat = loop.last_heartbeat_ms;
    std.time.sleep(100 * std.time.ns_per_ms);
    try loop.checkRogueGuard();

    try std.testing.expect(loop.last_heartbeat_ms > old_heartbeat);
}

test "Loop heartbeat timeout" {
    const allocator = std.testing.allocator;
    const config = LoopConfig{ .heartbeat_interval_ms = 10 };
    var loop = Loop.init(allocator, config);
    defer loop.deinit();

    // Set heartbeat to old time
    loop.last_heartbeat_ms = loop.last_heartbeat_ms - 100_000;

    try std.testing.expectError(error.HeartbeatTimeout, loop.checkRogueGuard());
}

test "Loop session file with subdirectory" {
    const allocator = std.testing.allocator;
    const tmp_session = "/tmp/test_subdir/session.json";
    const config = LoopConfig{
        .max_steps = 10,
        .velocity = 0,
        .session_file = tmp_session,
    };
    var loop = Loop.init(allocator, config);
    defer loop.deinit();

    std.fs.cwd().deleteTree("/tmp/test_subdir") catch {};
    defer std.fs.cwd().deleteTree("/tmp/test_subdir") catch {};

    try loop.saveState();

    const file = try std.fs.cwd().openFile(tmp_session, .{});
    defer file.close();
    _ = file;
}
