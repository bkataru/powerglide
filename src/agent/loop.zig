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
    velocity_ms: u64 = 500,
    heartbeat_interval_ms: u64 = 30_000,
    think_budget_ms: u64 = 120_000,
    model: []const u8 = "claude-opus-4-6",
    session_file: []const u8 = ".powerglide/session.json",
};

/// Result of a single loop step
pub const StepResult = union(enum) {
    /// Continue to the next state
    continue_loop: LoopState,
    /// Loop completed successfully
    done: void,
    /// Loop failed with an error message
    failed: []const u8,
};

/// Main Ralph loop state machine
pub const Loop = struct {
    allocator: std.mem.Allocator,
    config: LoopConfig,
    state: LoopState,
    step_count: u32,
    last_heartbeat_ms: i64,

    /// Initialize the loop with configuration
    pub fn init(allocator: std.mem.Allocator, config: LoopConfig) Loop {
        return .{
            .allocator = allocator,
            .config = config,
            .state = .idle,
            .step_count = 0,
            .last_heartbeat_ms = time.milliTimestamp(),
        };
    }

    /// Clean up resources
    pub fn deinit(self: *Loop) void {
        _ = self;
    }

    /// Main ralph loop - runs until completion or failure
    pub fn run(self: *Loop) !void {
        std.debug.print("Starting Ralph loop (max_steps={}, velocity_ms={})\n", .{
            self.config.max_steps,
            self.config.velocity_ms,
        });

        while (true) {
            // Check rogue guard before each step
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
                    // Velocity control - delay between steps
                    if (self.config.velocity_ms > 0) {
                        time.sleep(self.config.velocity_ms * 1_000_000); // Convert ms to ns
                    }
                    self.step_count += 1;
                },
            }
        }
    }

    /// Execute a single step of the loop
    pub fn step(self: *Loop) !StepResult {
        switch (self.state) {
            .idle => {
                return .{ .continue_loop = .load_tasks };
            },
            .load_tasks => {
                // Load session state from disk
                try self.loadState();
                return .{ .continue_loop = .pick_task };
            },
            .pick_task => {
                // Select next task from queue - would interact with Session
                // For now, transition to thinking
                return .{ .continue_loop = .thinking };
            },
            .thinking => {
                // LLM is generating - waiting for response
                // This would be where we call the LLM
                // For now, transition to tool_call (simulating LLM response)
                return .{ .continue_loop = .tool_call };
            },
            .tool_call => {
                // Model requested a tool execution
                // Would parse tool call from LLM response
                return .{ .continue_loop = .executing };
            },
            .executing => {
                // Tool is running - would execute the tool
                return .{ .continue_loop = .observing };
            },
            .observing => {
                // Processing tool result, updating state
                return .{ .continue_loop = .verify };
            },
            .verify => {
                // Running quality checks (zig build, tests)
                return .{ .continue_loop = .commit };
            },
            .commit => {
                // Saving progress to disk
                try self.saveState();
                return .{ .continue_loop = .done };
            },
            .done => {
                return .{ .done = {} };
            },
            .failed => {
                return .{ .failed = "Loop already in failed state" };
            },
        }
    }

    /// Rogue guard - prevents runaway agents
    pub fn checkRogueGuard(self: *Loop) !void {
        // Check step limit
        if (self.step_count >= self.config.max_steps) {
            return error.StepLimitExceeded;
        }

        // Check heartbeat timeout
        const now = time.milliTimestamp();
        if (now - self.last_heartbeat_ms > @as(i64, @intCast(self.config.heartbeat_interval_ms))) {
            return error.HeartbeatTimeout;
        }

        // Update heartbeat
        self.last_heartbeat_ms = now;
    }

    /// Save current state to disk
    pub fn saveState(self: *Loop) !void {
        const dir_path = self.config.session_file[0 .. mem.lastIndexOf(u8, self.config.session_file, "/") orelse 0];
        if (dir_path.len > 0) {
            try std.fs.cwd().makePath(dir_path);
        }

        const file = try std.fs.cwd().createFile(self.config.session_file, .{});
        defer file.close();

        // Write minimal state - step count and current state
        var buf: [256]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&buf);
        try fbs.writer().print("{{\"step_count\":{},\"state\":\"{s}\"}}", .{
            self.step_count,
            @tagName(self.state),
        });

        try file.writeAll(fbs.getWritten());
    }

    /// Load state from disk
    pub fn loadState(self: *Loop) !void {
        const file = std.fs.cwd().openFile(self.config.session_file, .{}) catch |err| {
            if (err == error.FileNotFound) {
                // No existing state - start fresh
                return;
            }
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
    const config = LoopConfig{
        .max_steps = 10,
        .velocity_ms = 0,
    };
    var loop = Loop.init(allocator, config);
    defer loop.deinit();

    try std.testing.expect(loop.state == .idle);
    try std.testing.expect(loop.step_count == 0);

    // First step should transition to load_tasks
    const result = try loop.step();
    try std.testing.expect(result == .continue_loop);
    try std.testing.expect(loop.state == .load_tasks);
}

test "Loop step count increments" {
    const allocator = std.testing.allocator;
    const config = LoopConfig{
        .max_steps = 10,
        .velocity_ms = 0,
    };
    var loop = Loop.init(allocator, config);
    defer loop.deinit();

    // Run through a few steps
    var i: u32 = 0;
    while (i < 5) : (i += 1) {
        _ = try loop.step();
    }

    try std.testing.expect(loop.step_count == 5);
}

test "Rogue guard step limit" {
    const allocator = std.testing.allocator;
    const config = LoopConfig{
        .max_steps = 2,
        .velocity_ms = 0,
    };
    var loop = Loop.init(allocator, config);
    defer loop.deinit();

    // Run steps up to the limit
    _ = try loop.step();
    _ = try loop.step();

    // Next step should fail due to step limit
    try std.testing.expectError(error.StepLimitExceeded, loop.checkRogueGuard());
}
