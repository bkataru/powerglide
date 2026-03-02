const std = @import("std");
const json = std.json;
const mem = std.mem;
const time = std.time;

/// A single task in the session
pub const Task = struct {
    id: []const u8,
    description: []const u8,
    passes: bool = false,
    priority: u8 = 5,

    pub fn jsonParse(allocator: std.mem.Allocator, source: []const u8) !Task {
        const parsed = try json.parseFromSlice(json.Value, allocator, source, .{});
        defer parsed.deinit();

        if (parsed.value != .object) {
            return error.InvalidJson;
        }

        const obj = parsed.value.object;
        return .{
            .id = try parseStringField(obj, "id", allocator),
            .description = try parseStringField(obj, "description", allocator),
            .passes = parseBoolField(obj, "passes", false),
            .priority = parseIntField(u8, obj, "priority", 5),
        };
    }

    pub fn jsonStringify(self: *const Task, allocator: std.mem.Allocator) ![]const u8 {
        var buf = std.ArrayList(u8).init(allocator);
        try json.stringify(self.*, .{}, buf.writer());
        return buf.toOwnedSlice();
    }
};

/// A message in the conversation history
pub const Message = struct {
    role: []const u8, // "user", "assistant", "tool"
    content: []const u8,
    tool_name: ?[]const u8 = null,
    tool_result: ?[]const u8 = null,

    pub fn jsonParse(allocator: std.mem.Allocator, source: []const u8) !Message {
        const parsed = try json.parseFromSlice(json.Value, allocator, source, .{});
        defer parsed.deinit();

        if (parsed.value != .object) {
            return error.InvalidJson;
        }

        const obj = parsed.value.object;
        return .{
            .role = try parseStringField(obj, "role", allocator),
            .content = try parseStringField(obj, "content", allocator),
            .tool_name = if (obj.get("tool_name")) |v| if (v == .string) try allocator.dupe(u8, v.string) else null else null,
            .tool_result = if (obj.get("tool_result")) |v| if (v == .string) try allocator.dupe(u8, v.string) else null else null,
        };
    }

    pub fn jsonStringify(self: *const Message, allocator: std.mem.Allocator) ![]const u8 {
        var buf = std.ArrayList(u8).init(allocator);
        try json.stringify(self.*, .{}, buf.writer());
        return buf.toOwnedSlice();
    }
};

/// Session status
pub const SessionStatus = enum {
    pending,
    active,
    paused,
    completed,
    failed,
};

/// Full session with tasks and messages
pub const Session = struct {
    id: []const u8,
    created_at: i64,
    updated_at: i64,
    tasks: std.ArrayList(Task),
    messages: std.ArrayList(Message),
    step_count: u32,
    velocity_ms: u64,
    status: SessionStatus = .pending,

    /// Initialize a new session
    pub fn init(allocator: std.mem.Allocator, id: []const u8) !Session {
        const now = time.milliTimestamp();
        return .{
            .id = try allocator.dupe(u8, id),
            .created_at = now,
            .updated_at = now,
            .tasks = std.ArrayList(Task).init(allocator),
            .messages = std.ArrayList(Message).init(allocator),
            .step_count = 0,
            .velocity_ms = 500,
        };
    }

    /// Clean up session resources
    pub fn deinit(self: *Session, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        for (self.tasks.items) |task| {
            allocator.free(task.id);
            allocator.free(task.description);
        }
        self.tasks.deinit();

        for (self.messages.items) |msg| {
            allocator.free(msg.role);
            allocator.free(msg.content);
            if (msg.tool_name) |name| allocator.free(name);
            if (msg.tool_result) |result| allocator.free(result);
        }
        self.messages.deinit();
    }

    /// Add a task to the session
    pub fn addTask(self: *Session, task: Task) !void {
        try self.tasks.append(task);
        self.updated_at = time.milliTimestamp();
    }

    /// Add a message to the session
    pub fn addMessage(self: *Session, msg: Message) !void {
        try self.messages.append(msg);
        self.updated_at = time.milliTimestamp();
    }

    /// Get the next incomplete task (highest priority first)
    pub fn nextTask(self: *const Session) ?*const Task {
        var best_task: ?*const Task = null;
        var best_priority: u8 = 255;

        for (self.tasks.items) |*task| {
            if (!task.passes and task.priority < best_priority) {
                best_priority = task.priority;
                best_task = task;
            }
        }

        return best_task;
    }

    /// Check if all tasks are done
    pub fn allTasksDone(self: *const Session) bool {
        for (self.tasks.items) |task| {
            if (!task.passes) return false;
        }
        return self.tasks.items.len > 0;
    }

    /// Mark a task as complete
    pub fn completeTask(self: *Session, task_id: []const u8) void {
        for (self.tasks.items) |*task| {
            if (mem.eql(u8, task.id, task_id)) {
                task.passes = true;
                self.updated_at = time.milliTimestamp();
                return;
            }
        }
    }

    /// Save session to JSON file
    pub fn save(self: *const Session, allocator: std.mem.Allocator, path: []const u8) !void {
        // Ensure directory exists
        if (mem.lastIndexOf(u8, path, "/")) |idx| {
            const dir_path = path[0..idx];
            if (dir_path.len > 0) {
                try std.fs.cwd().makePath(dir_path);
            }
        }

        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();

        var buf = std.ArrayList(u8).init(allocator);
        defer buf.deinit();

        // Build JSON manually for more control
        try buf.appendSlice("{");

        // id
        try buf.appendSlice("\"id\":\"");
        try buf.appendSlice(self.id);
        try buf.appendSlice("\",");

        // created_at
        try buf.appendSlice("\"created_at\":");
        try buf.writer().print("{d},", .{self.created_at});

        // updated_at
        try buf.appendSlice("\"updated_at\":");
        try buf.writer().print("{d},", .{self.updated_at});

        // status
        try buf.appendSlice("\"status\":\"");
        try buf.appendSlice(@tagName(self.status));
        try buf.appendSlice("\",");

        // step_count
        try buf.appendSlice("\"step_count\":");
        try buf.writer().print("{u},", .{self.step_count});

        // velocity_ms
        try buf.appendSlice("\"velocity_ms\":");
        try buf.writer().print("{u},", .{self.velocity_ms});

        // tasks array
        try buf.appendSlice("\"tasks\":[");
        for (self.tasks.items, 0..) |task, i| {
            if (i > 0) try buf.appendSlice(",");
            try buf.appendSlice("{");
            try buf.appendSlice("\"id\":\"");
            try buf.appendSlice(task.id);
            try buf.appendSlice("\",");
            try buf.appendSlice("\"description\":\"");
            try buf.appendSlice(task.description);
            try buf.appendSlice("\",");
            try buf.appendSlice("\"passes\":");
            try buf.writer().print("{}", .{task.passes});
            try buf.appendSlice(",");
            try buf.appendSlice("\"priority\":");
            try buf.writer().print("{u}", .{task.priority});
            try buf.appendSlice("}");
        }
        try buf.appendSlice("],");

        // messages array
        try buf.appendSlice("\"messages\":[");
        for (self.messages.items, 0..) |msg, i| {
            if (i > 0) try buf.appendSlice(",");
            try buf.appendSlice("{");
            try buf.appendSlice("\"role\":\"");
            try buf.appendSlice(msg.role);
            try buf.appendSlice("\",");
            try buf.appendSlice("\"content\":\"");
            try escapeJsonString(msg.content, &buf);
            try buf.appendSlice("\"");
            if (msg.tool_name) |name| {
                try buf.appendSlice(",\"tool_name\":\"");
                try buf.appendSlice(name);
                try buf.appendSlice("\"");
            }
            if (msg.tool_result) |result| {
                try buf.appendSlice(",\"tool_result\":\"");
                try escapeJsonString(result, &buf);
                try buf.appendSlice("\"");
            }
            try buf.appendSlice("}");
        }
        try buf.appendSlice("]");

        try buf.appendSlice("}");

        try file.writeAll(buf.items);
    }

    /// Load session from JSON file
    pub fn load(allocator: std.mem.Allocator, path: []const u8) !Session {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const content = try file.readToEndAlloc(allocator, 1024 * 1024);
        defer allocator.free(content);

        return try parseSession(allocator, content);
    }
};

/// Parse session from JSON content
fn parseSession(allocator: std.mem.Allocator, content: []const u8) !Session {
    const parsed = try json.parseFromSlice(json.Value, allocator, content, .{});
    defer parsed.deinit();

    if (parsed.value != .object) {
        return error.InvalidJson;
    }

    const obj = parsed.value.object;

    const id = try parseStringField(obj, "id", allocator);
    const created_at = parseIntField(i64, obj, "created_at", 0);
    const updated_at = parseIntField(i64, obj, "updated_at", 0);
    const step_count = parseIntField(u32, obj, "step_count", 0);
    const velocity_ms = parseIntField(u64, obj, "velocity_ms", 500);

    var session = try Session.init(allocator, id);
    session.created_at = created_at;
    session.updated_at = updated_at;
    session.step_count = step_count;
    session.velocity_ms = velocity_ms;

    // Parse status
    if (obj.get("status")) |status_val| {
        if (status_val == .string) {
            const status_str = status_val.string;
            if (mem.eql(u8, status_str, "pending")) session.status = .pending else if (mem.eql(u8, status_str, "active")) session.status = .active else if (mem.eql(u8, status_str, "paused")) session.status = .paused else if (mem.eql(u8, status_str, "completed")) session.status = .completed else if (mem.eql(u8, status_str, "failed")) session.status = .failed;
        }
    }

    // Parse tasks
    if (obj.get("tasks")) |tasks_val| {
        if (tasks_val == .array) {
            for (tasks_val.array) |task_val| {
                if (task_val == .object) {
                    const task_obj = task_val.object;
                    const task = Task{
                        .id = try parseStringField(task_obj, "id", allocator),
                        .description = try parseStringField(task_obj, "description", allocator),
                        .passes = parseBoolField(task_obj, "passes", false),
                        .priority = parseIntField(u8, task_obj, "priority", 5),
                    };
                    try session.tasks.append(task);
                }
            }
        }
    }

    // Parse messages
    if (obj.get("messages")) |msgs_val| {
        if (msgs_val == .array) {
            for (msgs_val.array) |msg_val| {
                if (msg_val == .object) {
                    const msg_obj = msg_val.object;
                    const msg = Message{
                        .role = try parseStringField(msg_obj, "role", allocator),
                        .content = try parseStringField(msg_obj, "content", allocator),
                        .tool_name = if (msg_obj.get("tool_name")) |v|
                            if (v == .string) try allocator.dupe(u8, v.string) else null
                        else
                            null,
                        .tool_result = if (msg_obj.get("tool_result")) |v|
                            if (v == .string) try allocator.dupe(u8, v.string) else null
                        else
                            null,
                    };
                    try session.messages.append(msg);
                }
            }
        }
    }

    return session;
}

/// Helper function to parse a string field from JSON object
fn parseStringField(obj: std.json.ObjectMap, field: []const u8, allocator: std.mem.Allocator) ![]const u8 {
    if (obj.get(field)) |val| {
        if (val == .string) {
            return try allocator.dupe(u8, val.string);
        }
    }
    return error.MissingField;
}

/// Helper function to parse an integer field with default
fn parseIntField(comptime T: type, obj: std.json.ObjectMap, field: []const u8, default_val: T) T {
    if (obj.get(field)) |val| {
        if (val == .integer) {
            return @intCast(val.integer);
        }
    }
    return default_val;
}

/// Helper function to parse a boolean field with default
fn parseBoolField(obj: std.json.ObjectMap, field: []const u8, default_val: bool) bool {
    if (obj.get(field)) |val| {
        if (val == .bool) {
            return val.bool;
        }
    }
    return default_val;
}

/// Escape special characters in JSON string
fn escapeJsonString(src: []const u8, buf: *std.ArrayList(u8)) !void {
    for (src) |c| {
        switch (c) {
            '"' => try buf.appendSlice("\\\""),
            '\\' => try buf.appendSlice("\\\\"),
            '\n' => try buf.appendSlice("\\n"),
            '\r' => try buf.appendSlice("\\r"),
            '\t' => try buf.appendSlice("\\t"),
            else => try buf.append(c),
        }
    }
}

/// Session manager for handling multiple sessions
pub const SessionManager = struct {
    allocator: std.mem.Allocator,
    sessions: std.StringHashMap(Session),

    pub fn init(allocator: std.mem.Allocator) SessionManager {
        return .{
            .allocator = allocator,
            .sessions = std.StringHashMap(Session).init(allocator),
        };
    }

    pub fn deinit(self: *SessionManager) void {
        var it = self.sessions.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.sessions.deinit();
    }

    /// Create a new session
    pub fn createSession(self: *SessionManager, id: []const u8) !*Session {
        const session = try self.sessions.createEntry(id);
        session.value_ptr.* = try Session.init(self.allocator, id);
        return session.value_ptr;
    }

    /// Get a session by ID
    pub fn getSession(self: *const SessionManager, id: []const u8) ?*Session {
        return self.sessions.get(id);
    }
};

test "Session create and basic operations" {
    const allocator = std.testing.allocator;
    var session = try Session.init(allocator, "test-session-1");
    defer session.deinit(allocator);

    try std.testing.expect(session.tasks.items.len == 0);
    try std.testing.expect(session.messages.items.len == 0);
    try std.testing.expect(!session.allTasksDone());

    // Add a task
    try session.addTask(.{ .id = "task-1", .description = "First task", .priority = 1 });
    try std.testing.expect(session.tasks.items.len == 1);

    // Get next task
    const next = session.nextTask();
    try std.testing.expect(next != null);
    try std.testing.expect(mem.eql(u8, next.?.id, "task-1"));

    // Complete task
    session.completeTask("task-1");
    try std.testing.expect(session.allTasksDone());
}

test "Session save and load" {
    const allocator = std.testing.allocator;
    var session = try Session.init(allocator, "test-session-2");
    defer session.deinit(allocator);

    // Add tasks and messages
    try session.addTask(.{ .id = "task-1", .description = "Test task", .priority = 1 });
    try session.addMessage(.{ .role = "user", .content = "Hello" });
    try session.addMessage(.{ .role = "assistant", .content = "Hi there!" });

    // Save to temp file
    const test_path = "/tmp/powerglide_test_session.json";
    try session.save(allocator, test_path);

    // Load the session
    var loaded = try Session.load(allocator, test_path);
    defer loaded.deinit(allocator);

    try std.testing.expect(mem.eql(u8, loaded.id, session.id));
    try std.testing.expect(loaded.tasks.items.len == 1);
    try std.testing.expect(loaded.messages.items.len == 2);

    // Clean up
    std.fs.cwd().deleteFile(test_path) catch {};
}

test "SessionManager basic operations" {
    const allocator = std.testing.allocator;
    var manager = SessionManager.init(allocator);
    defer manager.deinit();

    // Create a session
    const session = try manager.createSession("session-1");
    try std.testing.expect(session != null);

    // Get the session
    const retrieved = manager.getSession("session-1");
    try std.testing.expect(retrieved != null);
}
