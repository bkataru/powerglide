const std = @import("std");

pub const ExitCodeCapture = struct {
    exit_code: u8 = 0,
    signal: ?u8 = null,
    timed_out: bool = false,

    pub fn fromProcess(pid: i32) ExitCodeCapture {
        _ = pid;
        return .{};
    }

    pub fn fromStatus(status: i32) ExitCodeCapture {
        _ = status;
        return .{};
    }
};

test "placeholder" {
    const capture = ExitCodeCapture.fromProcess(0);
    try std.testing.expect(capture.exit_code == 0);
}
