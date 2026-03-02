//! PTY (Pseudo-Terminal) allocation and process spawning

const std = @import("std");
const posix = std.posix;
const ExitCodeCapture = @import("exit_code.zig").ExitCodeCapture;
const ExitStatus = @import("exit_code.zig").ExitStatus;

/// PTY-related errors
pub const PtyError = error{
    OpenPtmxFailed,
    GrantptFailed,
    UnlockptFailed,
    PtsnameError,
    ForkFailed,
    ExecFailed,
    InvalidFd,
    ReadError,
    WriteError,
};

/// A process running in a PTY
pub const PtyProcess = struct {
    master_fd: posix.fd_t = -1,
    slave_fd: posix.fd_t = -1,
    child_pid: posix.pid_t = 0,
    exit_capture: ExitCodeCapture,

    /// Spawn a command in a new PTY
    pub fn spawn(_: std.mem.Allocator, cmd: []const []const u8) !PtyProcess {
        var self = try allocatePty();
        errdefer self.deinit();

        try self.spawnChild(cmd);
        return self;
    }

    fn allocatePty() !PtyProcess {
        const master_fd = posix.open("/dev/ptmx", posix.O.RDWR | posix.O.NOCTTY) catch {
            return PtyError.OpenPtmxFailed;
        };
        errdefer posix.close(master_fd);

        if (posix.grantpt(master_fd) != 0) {
            return PtyError.GrantptFailed;
        }

        if (posix.unlockpt(master_fd) != 0) {
            return PtyError.UnlockptFailed;
        }

        const slave_name = posix.ptsname(master_fd) catch {
            return PtyError.PtsnameError;
        };

        const slave_fd = posix.open(slave_name, posix.O.RDWR | posix.O.NOCTTY) catch {
            return PtyError.PtsnameError;
        };

        return .{
            .master_fd = master_fd,
            .slave_fd = slave_fd,
            .child_pid = 0,
            .exit_capture = undefined,
        };
    }

    fn spawnChild(self: *PtyProcess, cmd: []const []const u8) !void {
        const pid = posix.fork() catch {
            return PtyError.ForkFailed;
        };

        if (pid == 0) {
            self.childFork(cmd);
            posix._exit(1);
        } else {
            self.child_pid = pid;
            self.exit_capture = ExitCodeCapture.init(pid);
        }
    }

    fn childFork(self: *PtyProcess, cmd: []const []const u8) void {
        posix.close(self.master_fd);
        _ = posix.setsid();

        posix.dup2(self.slave_fd, posix.STDIN_FILENO) catch {};
        posix.dup2(self.slave_fd, posix.STDOUT_FILENO) catch {};
        posix.dup2(self.slave_fd, posix.STDERR_FILENO) catch {};

        if (self.slave_fd > posix.STDERR_FILENO) {
            posix.close(self.slave_fd);
        }

        if (cmd.len > 0) {
            const argv = allocArgv(cmd) catch {
                posix._exit(1);
            };
            defer freeArgv(cmd, argv);

            const result = posix.execvpeZ(cmd[0], argv, &[_][:0]u8{});
            _ = result;
        }

        posix._exit(1);
    }

    fn allocArgv(cmd: []const []const u8) ![*]?[*:0]u8 {
        const argv = try std.heap.c_allocator.alloc([*:0]u8, cmd.len + 1);
        for (cmd, 0..) |arg, i| {
            argv[i] = try std.heap.c_allocator.dupeZ(u8, arg);
        }
        argv[cmd.len] = null;
        return argv.ptr;
    }

    fn freeArgv(cmd: []const []const u8, argv: [*]?[*:0]u8) void {
        for (cmd) |arg| {
            std.heap.c_allocator.free(arg);
        }
        std.heap.c_allocator.free(argv[0..cmd.len]);
    }

    /// Read from PTY
    pub fn read(self: *PtyProcess, buffer: []u8) !usize {
        if (self.master_fd < 0) {
            return PtyError.InvalidFd;
        }

        const flags = posix.fcntl(self.master_fd, posix.F.GETFL, 0) catch {
            return PtyError.ReadError;
        };
        _ = posix.fcntl(self.master_fd, posix.F.SETFL, flags | posix.O.NONBLOCK) catch {};

        const n = posix.read(self.master_fd, buffer) catch |e| {
            _ = posix.fcntl(self.master_fd, posix.F.SETFL, flags) catch {};
            if (e == error.WouldBlock) {
                return 0;
            }
            return PtyError.ReadError;
        };

        _ = posix.fcntl(self.master_fd, posix.F.SETFL, flags) catch {};
        return n;
    }

    /// Write to PTY
    pub fn write(self: *PtyProcess, data: []const u8) !void {
        if (self.master_fd < 0) {
            return PtyError.InvalidFd;
        }

        const n = posix.write(self.master_fd, data) catch {
            return PtyError.WriteError;
        };

        if (n != data.len) {
            return PtyError.WriteError;
        }
    }

    /// Close and wait for child
    pub fn close(self: *PtyProcess) !ExitStatus {
        if (self.master_fd >= 0) {
            posix.close(self.master_fd);
            self.master_fd = -1;
        }

        if (self.slave_fd >= 0) {
            posix.close(self.slave_fd);
            self.slave_fd = -1;
        }

        return self.exit_capture.wait();
    }

    /// Non-blocking read of all available output
    pub fn readAll(self: *PtyProcess, allocator: std.mem.Allocator) ![]u8 {
        var output = std.ArrayList(u8).init(allocator);
        errdefer output.deinit();

        var buffer: [4096]u8 = undefined;
        while (true) {
            const n = self.read(&buffer) catch |e| {
                if (e == error.WouldBlock or e == PtyError.ReadError) {
                    break;
                }
                return e;
            };

            if (n == 0) {
                break;
            }

            try output.appendSlice(buffer[0..n]);
        }

        return output.toOwnedSlice();
    }

    /// Check if process is alive
    pub fn isAlive(self: *const PtyProcess) bool {
        return self.exit_capture.isAlive();
    }

    /// Get child PID
    pub fn getPid(self: *const PtyProcess) posix.pid_t {
        return self.child_pid;
    }

    /// Clean up resources
    pub fn deinit(self: *PtyProcess) void {
        if (self.master_fd >= 0) {
            posix.close(self.master_fd);
            self.master_fd = -1;
        }
        if (self.slave_fd >= 0) {
            posix.close(self.slave_fd);
            self.slave_fd = -1;
        }
    }
};

/// Plain process (without PTY)
pub const PlainProcess = struct {
    stdin_pipe: [2]posix.fd_t = .{ -1, -1 },
    stdout_pipe: [2]posix.fd_t = .{ -1, -1 },
    stderr_pipe: [2]posix.fd_t = .{ -1, -1 },
    child_pid: posix.pid_t = 0,
    exit_capture: ExitCodeCapture,

    /// Spawn a command without PTY
    pub fn spawn(_: std.mem.Allocator, cmd: []const []const u8) !PlainProcess {
        var self: PlainProcess = .{};

        self.stdin_pipe = try posix.pipe();
        self.stdout_pipe = try posix.pipe();
        self.stderr_pipe = try posix.pipe();

        const pid = posix.fork() catch {
            self.deinit();
            return PtyError.ForkFailed;
        };

        if (pid == 0) {
            self.childFork(cmd);
            posix._exit(1);
        } else {
            self.child_pid = pid;
            self.exit_capture = ExitCodeCapture.init(pid);

            posix.close(self.stdin_pipe[0]);
            posix.close(self.stdout_pipe[1]);
            posix.close(self.stderr_pipe[1]);

            self.stdin_pipe[0] = -1;
            self.stdout_pipe[1] = -1;
            self.stderr_pipe[1] = -1;
        }

        return self;
    }

    fn childFork(self: *PlainProcess, cmd: []const []const u8) void {
        posix.close(self.stdin_pipe[1]);
        posix.close(self.stdout_pipe[0]);
        posix.close(self.stderr_pipe[0]);

        posix.dup2(self.stdin_pipe[0], posix.STDIN_FILENO) catch {};
        posix.dup2(self.stdout_pipe[1], posix.STDOUT_FILENO) catch {};
        posix.dup2(self.stderr_pipe[1], posix.STDERR_FILENO) catch {};

        if (self.stdin_pipe[0] > posix.STDERR_FILENO) posix.close(self.stdin_pipe[0]);
        if (self.stdout_pipe[1] > posix.STDERR_FILENO) posix.close(self.stdout_pipe[1]);
        if (self.stderr_pipe[1] > posix.STDERR_FILENO) posix.close(self.stderr_pipe[1]);

        if (cmd.len > 0) {
            const argv = allocArgv(cmd) catch {
                posix._exit(1);
            };
            defer freeArgv(cmd, argv);

            const result = posix.execvpeZ(cmd[0], argv, &[_][:0]u8{});
            _ = result;
        }

        posix._exit(1);
    }

    fn allocArgv(cmd: []const []const u8) ![*]?[*:0]u8 {
        const argv = try std.heap.c_allocator.alloc([*:0]u8, cmd.len + 1);
        for (cmd, 0..) |arg, i| {
            argv[i] = try std.heap.c_allocator.dupeZ(u8, arg);
        }
        argv[cmd.len] = null;
        return argv.ptr;
    }

    fn freeArgv(cmd: []const []const u8, argv: [*]?[*:0]u8) void {
        for (cmd) |arg| {
            std.heap.c_allocator.free(arg);
        }
        std.heap.c_allocator.free(argv[0..cmd.len]);
    }

    /// Read stdout
    pub fn readStdout(self: *PlainProcess, allocator: std.mem.Allocator) ![]u8 {
        if (self.stdout_pipe[0] < 0) {
            return &[0]u8{};
        }

        var buffer = std.ArrayList(u8).init(allocator);
        errdefer buffer.deinit();

        var buf: [4096]u8 = undefined;
        while (true) {
            const n = posix.read(self.stdout_pipe[0], &buf) catch |e| {
                if (e == error.WouldBlock) {
                    break;
                }
                return e;
            };
            if (n == 0) {
                break;
            }
            try buffer.appendSlice(buf[0..n]);
        }

        return buffer.toOwnedSlice();
    }

    /// Read stderr
    pub fn readStderr(self: *PlainProcess, allocator: std.mem.Allocator) ![]u8 {
        if (self.stderr_pipe[0] < 0) {
            return &[0]u8{};
        }

        var buffer = std.ArrayList(u8).init(allocator);
        errdefer buffer.deinit();

        var buf: [4096]u8 = undefined;
        while (true) {
            const n = posix.read(self.stderr_pipe[0], &buf) catch |e| {
                if (e == error.WouldBlock) {
                    break;
                }
                return e;
            };
            if (n == 0) {
                break;
            }
            try buffer.appendSlice(buf[0..n]);
        }

        return buffer.toOwnedSlice();
    }

    /// Wait for process to exit
    pub fn wait(self: *PlainProcess) !ExitStatus {
        if (self.stdin_pipe[1] >= 0) posix.close(self.stdin_pipe[1]);
        if (self.stdout_pipe[0] >= 0) posix.close(self.stdout_pipe[0]);
        if (self.stderr_pipe[0] >= 0) posix.close(self.stderr_pipe[0]);

        return self.exit_capture.wait();
    }

    /// Check if alive
    pub fn isAlive(self: *const PlainProcess) bool {
        return self.exit_capture.isAlive();
    }

    /// Clean up
    pub fn deinit(self: *PlainProcess) void {
        if (self.stdin_pipe[0] >= 0) posix.close(self.stdin_pipe[0]);
        if (self.stdin_pipe[1] >= 0) posix.close(self.stdin_pipe[1]);
        if (self.stdout_pipe[0] >= 0) posix.close(self.stdout_pipe[0]);
        if (self.stdout_pipe[1] >= 0) posix.close(self.stdout_pipe[1]);
        if (self.stderr_pipe[0] >= 0) posix.close(self.stderr_pipe[0]);
        if (self.stderr_pipe[1] >= 0) posix.close(self.stderr_pipe[1]);
    }
};

test "PtyProcess placeholder" {
    try std.testing.expect(true);
}

test "PlainProcess placeholder" {
    try std.testing.expect(true);
}
