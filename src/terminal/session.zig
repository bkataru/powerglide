//! Terminal session management
const std = @import("std");
const posix = std.posix;

const PlainProcess = @import("pty.zig").PlainProcess;
const ExitStatus = @import("exit_code.zig").ExitStatus;
const exitStatusToCode = @import("exit_code.zig").exitStatusToCode;

pub const SessionId = u32;

pub const CommandResult = struct {
    output: []u8, // caller owns
    exit_code: u8,
    timed_out: bool,
};

pub const TerminalSession = struct {
    id: SessionId,
    allocator: std.mem.Allocator,
    process: ?PlainProcess = null,

    pub fn init(allocator: std.mem.Allocator, id: SessionId) TerminalSession {
        return .{
            .id = id,
            .allocator = allocator,
            .process = null,
        };
    }

    pub fn deinit(self: *TerminalSession) void {
        if (self.process) |*proc| {
            proc.deinit();
        }
    }

    /// Run a command, wait for completion (with timeout)
    pub fn runCommand(self: *TerminalSession, allocator: std.mem.Allocator, cmd: []const u8, timeout_ms: u64) !CommandResult {
        // Close any existing process
        if (self.process) |*proc| {
            proc.deinit();
            self.process = null;
        }

        // Spawn the command using /bin/sh -c
        const shell_cmd = ["/bin/sh", "-c"];
        self.process = try PlainProcess.spawn(allocator, &shell_cmd);

        // Write the command to stdin if needed, then close stdin
        if (self.process) |*proc| {
            if (proc.stdin_pipe[1] >= 0) {
                _ = posix.write(proc.stdin_pipe[1], cmd) catch {};
                posix.close(proc.stdin_pipe[1]);
                proc.stdin_pipe[1] = -1;
            }
        }

        // Wait with timeout using poll loop
        var timed_out = false;
        var exit_code: u8 = 0;
        const start = std.time.milliTimestamp();

        while (true) {
            if (self.process) |*proc| {
                const status = proc.exit_capture.poll() catch null;
                if (status) |s| {
                    // Process has exited
                    exit_code = exitStatusToCode(s);
                    break;
                }
            }

            const elapsed = @as(u64, @intCast(std.time.milliTimestamp() - start));
            if (elapsed >= timeout_ms) {
                // Timeout - kill the process
                if (self.process) |*proc| {
                    proc.exit_capture.kill(1000) catch {};
                    exit_code = 255;
                }
                timed_out = true;
                break;
            }

            // Sleep a bit before checking again
            std.time.sleep(10 * std.time.ns_per_ms);
        }

        // Read output
        var output: []u8 = &[_]u8{};
        if (self.process) |*proc| {
            output = proc.readStdout(allocator) catch &[_]u8{};
            // Also read stderr and append
            const stderr = proc.readStderr(allocator) catch &[_]u8{};
            if (stderr.len > 0) {
                // Append stderr to output
                var combined = std.ArrayList(u8){};
                combined.appendSlice(output) catch {};
                combined.appendSlice(stderr) catch {};
                output = combined.toOwnedSlice();
            }
        }

        return .{
            .output = output,
            .exit_code = exit_code,
            .timed_out = timed_out,
        };
    }

    pub fn isAlive(self: *const TerminalSession) bool {
        if (self.process) |*proc| {
            return proc.isAlive();
        }
        return false;
    }
};

test "TerminalSession.init creates session with correct id" {
    const allocator = std.testing.allocator;
    const session = TerminalSession.init(allocator, 42);

    try std.testing.expectEqual(@as(SessionId, 42), session.id);
    try std.testing.expectEqual(allocator, session.allocator);
    try std.testing.expect(session.process == null);

    session.deinit();
}

test "TerminalSession.isAlive returns false for uninitialized session" {
    const allocator = std.testing.allocator;
    const session = TerminalSession.init(allocator, 1);
    defer session.deinit();

    const alive = session.isAlive();
    try std.testing.expect(!alive);
}

test "CommandResult struct fields are accessible" {
    const allocator = std.testing.allocator;
    const result = CommandResult{
        .output = try allocator.alloc(u8, 0),
        .exit_code = 0,
        .timed_out = false,
    };
    allocator.free(result.output);

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(!result.timed_out);
}
    try std.testing.expect(true);
}