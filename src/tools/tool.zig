const std = @import("std");

pub const Tool = struct {
    name: []const u8,
    description: []const u8,
    parameters: ?[]const u8 = null,
};

pub const ToolExecutor = struct {
    pub fn execute(tool: *const Tool, args: std.json.Value) !ToolResult {
        _ = tool;
        _ = args;
        return .{
            .success = true,
            .output = "",
        };
    }
};

pub const ToolResult = struct {
    success: bool,
    output: []const u8,
    err: ?[]const u8 = null,
};

test "placeholder" {
    try std.testing.expect(true);
}
