const std = @import("std");
const json = std.json;

/// Input to a tool execution
pub const ToolInput = struct {
    name: []const u8,
    arguments: json.Value,
};

/// Output from a tool execution
pub const ToolOutput = struct {
    content: []const u8,
    is_error: bool = false,

    /// Create a successful output
    pub fn success(content: []const u8) ToolOutput {
        return .{ .content = content, .is_error = false };
    }

    /// Create an error output
    pub fn failure(content: []const u8) ToolOutput {
        return .{ .content = content, .is_error = true };
    }
};

/// Tool function signature
pub const ToolFn = *const fn (allocator: std.mem.Allocator, input: ToolInput) anyerror!ToolOutput;

/// A registered tool with its metadata and handler
pub const Tool = struct {
    name: []const u8,
    description: []const u8,
    input_schema: []const u8, // JSON Schema string
    handler: ToolFn,
};

/// Result of a tool execution
pub const ToolResult = struct {
    success: bool,
    output: []const u8,
    err_msg: ?[]const u8 = null,

    pub fn toToolOutput(self: *const ToolResult) ToolOutput {
        if (self.success) {
            return ToolOutput.success(self.output);
        } else {
            return ToolOutput.failure(self.err_msg orelse self.output);
        }
    }

    pub fn ok(output: []const u8) ToolResult {
        return .{ .success = true, .output = output };
    }

    pub fn fail(msg: []const u8) ToolResult {
        return .{ .success = false, .output = "", .err_msg = msg };
    }
};

/// Built-in tool definitions
pub const BuiltinTools = struct {
    /// Static array of all built-in tools
    const tools_array = [_]Tool{
        bash_tool(),
        read_tool(),
        write_tool(),
        edit_tool(),
        grep_tool(),
        glob_tool(),
    };

    /// Get list of all built-in tools
    pub fn all() []const Tool {
        return &tools_array;
    }
    pub fn bash_tool() Tool {
        return .{
            .name = "bash",
            .description = "Execute a shell command and return its output",
            .input_schema = "{\"type\":\"object\",\"properties\":{\"command\":{\"type\":\"string\"}},\"required\":[\"command\"]}",
            .handler = bash_handler,
        };
    }

    pub fn read_tool() Tool {
        return .{
            .name = "read",
            .description = "Read contents of a file",
            .input_schema = "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"}},\"required\":[\"path\"]}",
            .handler = read_handler,
        };
    }

    pub fn write_tool() Tool {
        return .{
            .name = "write",
            .description = "Write content to a file",
            .input_schema = "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"},\"content\":{\"type\":\"string\"}},\"required\":[\"path\",\"content\"]}",
            .handler = write_handler,
        };
    }

    pub fn edit_tool() Tool {
        return .{
            .name = "edit",
            .description = "Edit a specific portion of a file (find and replace)",
            .input_schema = "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"},\"old\":{\"type\":\"string\"},\"new\":{\"type\":\"string\"}},\"required\":[\"path\",\"old\",\"new\"]}",
            .handler = edit_handler,
        };
    }

    pub fn grep_tool() Tool {
        return .{
            .name = "grep",
            .description = "Search for patterns in files",
            .input_schema = "{\"type\":\"object\",\"properties\":{\"pattern\":{\"type\":\"string\"},\"path\":{\"type\":\"string\"}},\"required\":[\"pattern\"]}",
            .handler = grep_handler,
        };
    }

    pub fn glob_tool() Tool {
        return .{
            .name = "glob",
            .description = "Find files matching a glob pattern",
            .input_schema = "{\"type\":\"object\",\"properties\":{\"pattern\":{\"type\":\"string\"},\"path\":{\"type\":\"string\"}},\"required\":[\"pattern\"]}",
            .handler = glob_handler,
        };
    }
};

/// Run a shell command, return combined stdout+stderr output
fn runCommand(allocator: std.mem.Allocator, argv: []const []const u8) ![]u8 {
    const result = try std.process.Child.run(.{
        .argv = argv,
        .allocator = allocator,
        .max_output_bytes = 4 * 1024 * 1024,
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.stderr.len > 0 and result.stdout.len > 0) {
        const combined = try std.fmt.allocPrint(allocator, "{s}\n--- stderr ---\n{s}", .{ result.stdout, result.stderr });
        return combined;
    } else if (result.stderr.len > 0) {
        return try allocator.dupe(u8, result.stderr);
    }
    return try allocator.dupe(u8, result.stdout);
}

fn bash_handler(allocator: std.mem.Allocator, input: ToolInput) !ToolOutput {
    const command = extractStringField(&input.arguments, "command") orelse {
        return ToolOutput.failure("Missing required field: command");
    };
    const argv = &[_][]const u8{ "/bin/sh", "-c", command };
    const output = runCommand(allocator, argv) catch |e| {
        return ToolOutput.failure(try std.fmt.allocPrint(allocator, "Command failed: {}", .{e}));
    };
    return ToolOutput.success(output);
}

fn read_handler(allocator: std.mem.Allocator, input: ToolInput) !ToolOutput {
    const path = extractStringField(&input.arguments, "path") orelse {
        return ToolOutput.failure("Missing required field: path");
    };
    const file = std.fs.cwd().openFile(path, .{}) catch |e| {
        return ToolOutput.failure(try std.fmt.allocPrint(allocator, "Failed to open {s}: {}", .{ path, e }));
    };
    defer file.close();
    const content = file.readToEndAlloc(allocator, 4 * 1024 * 1024) catch |e| {
        return ToolOutput.failure(try std.fmt.allocPrint(allocator, "Failed to read {s}: {}", .{ path, e }));
    };
    return ToolOutput.success(content); // caller owns content
}

fn write_handler(allocator: std.mem.Allocator, input: ToolInput) !ToolOutput {
    const path = extractStringField(&input.arguments, "path") orelse {
        return ToolOutput.failure("Missing required field: path");
    };
    const content = extractStringField(&input.arguments, "content") orelse {
        return ToolOutput.failure("Missing required field: content");
    };
    // Create parent dirs
    if (std.mem.lastIndexOf(u8, path, "/")) |idx| {
        const dir = path[0..idx];
        if (dir.len > 0) std.fs.cwd().makePath(dir) catch {};
    }
    const file = std.fs.cwd().createFile(path, .{}) catch |e| {
        return ToolOutput.failure(try std.fmt.allocPrint(allocator, "Failed to create {s}: {}", .{ path, e }));
    };
    defer file.close();
    file.writeAll(content) catch |e| {
        return ToolOutput.failure(try std.fmt.allocPrint(allocator, "Failed to write {s}: {}", .{ path, e }));
    };
    return ToolOutput.success(try std.fmt.allocPrint(allocator, "Written {d} bytes to {s}", .{ content.len, path }));
}

fn edit_handler(allocator: std.mem.Allocator, input: ToolInput) !ToolOutput {
    const path = extractStringField(&input.arguments, "path") orelse {
        return ToolOutput.failure("Missing required field: path");
    };
    const old_text = extractStringField(&input.arguments, "old") orelse {
        return ToolOutput.failure("Missing required field: old");
    };
    const new_text = extractStringField(&input.arguments, "new") orelse {
        return ToolOutput.failure("Missing required field: new");
    };
    const file = std.fs.cwd().openFile(path, .{}) catch |e| {
        return ToolOutput.failure(try std.fmt.allocPrint(allocator, "Failed to open {s}: {}", .{ path, e }));
    };
    const original = try file.readToEndAlloc(allocator, 4 * 1024 * 1024);
    file.close();
    defer allocator.free(original);

    if (std.mem.indexOf(u8, original, old_text) == null) {
        return ToolOutput.failure("Pattern not found in file");
    }

    // Count replacements needed
    var count: usize = 0;
    var search = original;
    while (std.mem.indexOf(u8, search, old_text)) |idx| {
        count += 1;
        search = search[idx + old_text.len ..];
    }

    const new_len = original.len - count * old_text.len + count * new_text.len;
    const new_content = try allocator.alloc(u8, new_len);
    defer allocator.free(new_content);
    _ = std.mem.replace(u8, original, old_text, new_text, new_content);

    const write_file = std.fs.cwd().createFile(path, .{}) catch |e| {
        return ToolOutput.failure(try std.fmt.allocPrint(allocator, "Failed to write {s}: {}", .{ path, e }));
    };
    defer write_file.close();
    try write_file.writeAll(new_content);

    return ToolOutput.success(try std.fmt.allocPrint(allocator, "Replaced {d} occurrence(s) in {s}", .{ count, path }));
}

fn grep_handler(allocator: std.mem.Allocator, input: ToolInput) !ToolOutput {
    const pattern = extractStringField(&input.arguments, "pattern") orelse {
        return ToolOutput.failure("Missing required field: pattern");
    };
    const path = extractStringField(&input.arguments, "path") orelse ".";
    const command = try std.fmt.allocPrint(allocator, "grep -rn -- {s} {s} 2>/dev/null | head -100", .{ pattern, path });
    defer allocator.free(command);
    const argv = &[_][]const u8{ "/bin/sh", "-c", command };
    const output = runCommand(allocator, argv) catch |e| {
        return ToolOutput.failure(try std.fmt.allocPrint(allocator, "grep failed: {}", .{e}));
    };
    if (output.len == 0) {
        allocator.free(output);
        return ToolOutput.success(try allocator.dupe(u8, "No matches found"));
    }
    return ToolOutput.success(output);
}

fn glob_handler(allocator: std.mem.Allocator, input: ToolInput) !ToolOutput {
    const pattern = extractStringField(&input.arguments, "pattern") orelse {
        return ToolOutput.failure("Missing required field: pattern");
    };
    const path = extractStringField(&input.arguments, "path") orelse ".";
    const command = try std.fmt.allocPrint(allocator, "find {s} -name '{s}' -type f 2>/dev/null | head -100", .{ path, pattern });
    defer allocator.free(command);
    const argv = &[_][]const u8{ "/bin/sh", "-c", command };
    const output = runCommand(allocator, argv) catch |e| {
        return ToolOutput.failure(try std.fmt.allocPrint(allocator, "find failed: {}", .{e}));
    };
    if (output.len == 0) {
        allocator.free(output);
        return ToolOutput.success(try allocator.dupe(u8, "No matches found"));
    }
    return ToolOutput.success(output);
}

fn extractStringField(args: *const json.Value, field: []const u8) ?[]const u8 {
    if (args.* != .object) return null;
    const val = args.*.object.get(field) orelse return null;
    if (val != .string) return null;
    return val.string;
}

test "Tool definitions compile" {
    const tools = BuiltinTools.all();
    try std.testing.expect(tools.len == 6);
    try std.testing.expectEqualStrings("bash", tools[0].name);
    try std.testing.expectEqualStrings("read", tools[1].name);
}

test "ToolOutput helpers" {
    const s = ToolOutput.success("hello");
    try std.testing.expect(!s.is_error);
    try std.testing.expectEqualStrings("hello", s.content);

    const f = ToolOutput.failure("oops");
    try std.testing.expect(f.is_error);
    try std.testing.expectEqualStrings("oops", f.content);
}

test "ToolResult conversion" {
    const ok = ToolResult.ok("output");
    const out = ok.toToolOutput();
    try std.testing.expect(!out.is_error);

    const fail = ToolResult.fail("error message");
    const fail_out = fail.toToolOutput();
    try std.testing.expect(fail_out.is_error);
}
