//! Reliable exit code capture for subprocesses
//! This is powerglide's KEY DIFFERENTIATOR - reliable exit code capture

const std = @import("std");
const posix = std.posix;

/// Waitpid flags for non-blocking wait
pub const WNOHANG: u32 = 1;
pub const WUNTRACED: u32 = 2;
pub const WCONTINUED: u32 = 8;

/// Exit status representation
pub const ExitStatus = union(enum) {
    /// Normal exit with code (0-255)
    exited: u8,
    /// Process was killed by a signal
    signaled: u32,
    /// Process was stopped by a signal (for job control)
    stopped: u32,
    /// Unknown state (process doesn't exist or error)
    unknown: void,
};

/// Wait status macros for interpreting waitpid result
fn WIFEXITED(status: u32) bool {
    return (status & 0x7f) == 0;
}

fn WEXITSTATUS(status: u32) u8 {
    return @intCast((status >> 8) & 0xff);
}

fn WIFSIGNALED(status: u32) bool {
    return (status & 0x7f) != 0 and (status & 0x7f) != 0x7f;
}

fn WTERMSIG(status: u32) u32 {
    return status & 0x7f;
}

fn WIFSTOPPED(status: u32) bool {
    return (status & 0xff) == 0x7f;
}

fn WSTOPSIG(status: u32) u32 {
    return (status >> 8) & 0xff;
}

/// Reliable exit code capture for a subprocess
pub const ExitCodeCapture = struct {
    pid: posix.pid_t,
    exited: bool = false,
    exit_status: ExitStatus = .unknown,

    /// Initialize an exit code capture for a given process PID
    pub fn init(pid: posix.pid_t) ExitCodeCapture {
        return .{
            .pid = pid,
        };
    }

    /// Block until process exits, return its exit status
    pub fn wait(self: *ExitCodeCapture) !ExitStatus {
        const result = while (true) {
            const wait_result = posix.waitpid(self.pid, 0);
            if (wait_result.pid == -1) {
                continue;
            }
            break wait_result;
        };

        self.exit_status = parseStatus(result.status);
        self.exited = true;
        return self.exit_status;
    }

    /// Non-blocking check - returns null if still running
    pub fn poll(self: *ExitCodeCapture) !?ExitStatus {
        const result = posix.waitpid(self.pid, WNOHANG);

        if (result.pid == 0) {
            return null;
        }

        self.exit_status = parseStatus(result.status);
        self.exited = true;
        return self.exit_status;
    }

    /// Send SIGTERM, wait up to timeout_ms, then SIGKILL
    pub fn kill(self: *ExitCodeCapture, timeout_ms: u64) !void {
        _ = posix.kill(self.pid, posix.SIG.TERM);

        const start = std.time.milliTimestamp();
        while (true) {
            const result = posix.waitpid(self.pid, WNOHANG);
            if (result.pid != 0) {
                return;
            }

            const elapsed = @as(u64, @intCast(std.time.milliTimestamp() - start));
            if (elapsed >= timeout_ms) {
                _ = posix.kill(self.pid, posix.SIG.KILL);
                _ = posix.waitpid(self.pid, 0);
                return;
            }

            std.time.sleep(10 * std.time.ns_per_ms);
        }
    }

    /// Check if process is still alive
    pub fn isAlive(self: *const ExitCodeCapture) bool {
        // use kill with signal 0 to check for existence without reaping
        posix.kill(self.pid, 0) catch |err| {
            if (err == error.ProcessNotFound) return false;
            return true; // other errors might mean it exists but we can't kill it
        };
        return true;
    }
};

/// Parse waitpid status into ExitStatus union
fn parseStatus(status: u32) ExitStatus {
    if (WIFEXITED(status)) {
        return .{ .exited = WEXITSTATUS(status) };
    } else if (WIFSIGNALED(status)) {
        return .{ .signaled = WTERMSIG(status) };
    } else if (WIFSTOPPED(status)) {
        return .{ .stopped = WSTOPSIG(status) };
    }
    return .unknown;
}

/// Convert ExitStatus to a simple exit code
pub fn exitStatusToCode(status: ExitStatus) u8 {
    switch (status) {
        .exited => |code| return code,
        .signaled => |_| return 255,
        .stopped => return 255,
        .unknown => return 255,
    }
}

test "ExitCodeCapture basic" {
    const capture = ExitCodeCapture.init(1);
    try std.testing.expect(capture.pid == 1);
    try std.testing.expect(!capture.exited);
}

test "ExitStatus parsing" {
    const status = 0 << 8;
    try std.testing.expect(WIFEXITED(status));
    try std.testing.expect(WEXITSTATUS(status) == 0);

    const status2 = 42 << 8;
    try std.testing.expect(WIFEXITED(status2));
    try std.testing.expect(WEXITSTATUS(status2) == 42);
}

test "exitStatusToCode" {
    try std.testing.expect(exitStatusToCode(.{ .exited = 0 }) == 0);
    try std.testing.expect(exitStatusToCode(.{ .exited = 42 }) == 42);
    try std.testing.expect(exitStatusToCode(.{ .signaled = 9 }) == 255);
    try std.testing.expect(exitStatusToCode(.unknown) == 255);
}
