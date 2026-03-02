const std = @import("std");

pub const WorkerId = u32;

pub const WorkerStatus = enum {
    idle,
    running,
    done,
    failed,
    killed,
};

pub const WorkerConfig = struct {
    id: WorkerId,
    task_description: []const u8,
    working_dir: []const u8 = "/tmp",
    max_steps: u32 = 100,
    velocity_ms: u64 = 500,
    timeout_ms: u64 = 600_000, // 10 min default
    agent_name: []const u8 = "hephaestus",
};

pub const Worker = struct {
    allocator: std.mem.Allocator,
    config: WorkerConfig,
    status: WorkerStatus,
    pid: ?std.posix.pid_t,
    output_file: []const u8,
    started_at_ms: i64,
    last_heartbeat_ms: i64,

    pub fn init(allocator: std.mem.Allocator, config: WorkerConfig) !Worker {
        const now = std.time.milliTimestamp();

        // Create unique output file path
        const output_file = try std.fmt.allocPrint(
            allocator,
            "/tmp/worker_{d}_{d}.log",
            .{ config.id, now },
        );

        return Worker{
            .allocator = allocator,
            .config = config,
            .status = .idle,
            .pid = null,
            .output_file = output_file,
            .started_at_ms = now,
            .last_heartbeat_ms = now,
        };
    }

    pub fn deinit(self: *Worker) void {
        // Kill the process if still running
        if (self.status == .running) {
            self.kill();
        }
        self.allocator.free(self.output_file);
    }

    /// Spawn the worker (launches oh-my-opencode run in background)
    /// Command: npx oh-my-opencode run --agent {config.agent_name} --directory {config.working_dir} "{task}" > {output_file} 2>&1
    pub fn spawn(self: *Worker) !void {
        if (self.status != .idle and self.status != .done and self.status != .failed and self.status != .killed) {
            return error.WorkerAlreadyRunning;
        }

        const task_arg = self.config.task_description;
        const agent_name = self.config.agent_name;
        const working_dir = self.config.working_dir;
        const output_file = self.output_file;

        // Build shell command that runs in background and captures PID
        const pid_shell_cmd = try std.fmt.allocPrint(
            self.allocator,
            "npx oh-my-opencode run --agent {s} --directory {s} \"{s}\" > {s} 2>&1 &\necho $!",
            .{ agent_name, working_dir, task_arg, output_file },
        );
        defer self.allocator.free(pid_shell_cmd);

        // Execute the command and capture the background PID
        const pid_result = try std.process.Child.exec(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{ "/bin/sh", "-c", pid_shell_cmd },
            .cwd = working_dir,
        });

        const pid_str = std.mem.trim(u8, pid_result.stdout, &[_]u8{ '\n', '\r', ' ' });
        if (pid_str.len > 0) {
            self.pid = std.fmt.parseInt(std.posix.pid_t, pid_str, 10) catch null;
        }

        self.status = .running;
        self.started_at_ms = std.time.milliTimestamp();
        self.last_heartbeat_ms = self.started_at_ms;
    }

    /// Check worker output file for completion signal or DONE marker
    pub fn checkDone(self: *Worker) !bool {
        if (self.status != .running) {
            return self.status == .done;
        }

        // Check if process is still running
        if (self.pid) |pid| {
            const result = std.posix.kill(pid, 0);
            if (result == .success) {
                // Process still running, check output for completion markers
            } else if (result == .perm) {
                // Permission denied - process exists
            } else if (result == .fail) {
                // Process doesn't exist, check if it completed successfully
                self.status = .done;
                return true;
            }
        }

        // Read the output file and look for completion markers
        const output = self.tailOutput(self.allocator, 8192) catch return false;
        defer self.allocator.free(output);

        // Look for completion patterns
        const completion_markers = [_][]const u8{
            "PHASE",
            "COMPLETE",
            "All tasks completed",
            "DONE",
            "finished successfully",
            "Worker completed",
        };

        for (completion_markers) |marker| {
            if (std.mem.indexOf(u8, output, marker) != null) {
                self.status = .done;
                return true;
            }
        }

        // Check if the process has exited
        if (self.pid) |pid| {
            var status: std.posix.wait_status = undefined;
            const wait_result = std.posix.waitpid(pid, &status, std.posix.WNOHANG);
            if (wait_result > 0) {
                // Process has exited
                if (status.Exited) {
                    if (status.code == 0) {
                        self.status = .done;
                        return true;
                    } else {
                        self.status = .failed;
                        return true;
                    }
                } else if (status.Signaled) {
                    self.status = .failed;
                    return true;
                }
            }
        }

        return false;
    }

    /// Kill the worker process
    pub fn kill(self: *Worker) void {
        if (self.pid) |pid| {
            _ = std.posix.kill(pid, std.posix.SIGTERM) catch {};
            // Give it a moment to terminate gracefully
            std.time.sleep(100_000_000); // 100ms

            // Force kill if still alive
            _ = std.posix.kill(pid, std.posix.SIGKILL) catch {};
            self.pid = null;
        }
        self.status = .killed;
    }

    /// Read current output from log file (last N bytes)
    pub fn tailOutput(self: *Worker, allocator: std.mem.Allocator, bytes: usize) ![]u8 {
        const file = std.fs.openFileAbsolute(self.output_file, .{
            .mode = .read_only,
        }) catch {
            // File might not exist yet
            return try allocator.alloc(u8, 0);
        };
        defer file.close();

        const stat = try file.stat();
        const file_size: usize = @intCast(stat.size);

        if (file_size == 0) {
            return try allocator.alloc(u8, 0);
        }

        const read_start = if (file_size > bytes) file_size - bytes else 0;
        const read_size = file_size - read_start;

        try file.seekTo(read_start);

        const buffer = try allocator.alloc(u8, read_size);
        const bytes_read = try file.read(buffer);
        // Trim if we read less than expected
        if (bytes_read < buffer.len) {
            return buffer[0..bytes_read];
        }

        return buffer;
    }

    /// Update heartbeat timestamp
    pub fn heartbeat(self: *Worker) void {
        self.last_heartbeat_ms = std.time.milliTimestamp();
    }

    /// Check if heartbeat timed out
    pub fn isStale(self: *const Worker, timeout_ms: u64) bool {
        const now = std.time.milliTimestamp();
        const elapsed: u64 = @intCast(now - self.last_heartbeat_ms);
        return elapsed > timeout_ms;
    }
};

test "placeholder" {
    try std.testing.expect(true);
}
