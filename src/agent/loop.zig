const std = @import("std");

pub const LoopState = enum {
    idle,
    thinking,
    acting,
    observing,
    finished,
    failed,
};

pub const Loop = struct {
    state: LoopState = .idle,
    max_iterations: u32 = 100,
    current_iteration: u32 = 0,
    velocity_ms: u32 = 100,

    pub fn init() Loop {
        return .{};
    }

    pub fn reset(self: *Loop) void {
        self.state = .idle;
        self.current_iteration = 0;
    }

    pub fn next(self: *Loop) ?LoopState {
        if (self.current_iteration >= self.max_iterations) {
            self.state = .finished;
            return null;
        }
        self.current_iteration += 1;
        return self.state;
    }
};

test "placeholder" {
    const loop = Loop.init();
    try std.testing.expect(loop.state == .idle);
}
