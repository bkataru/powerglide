//! MCP Tool Bridge
//! Converts MCP tool definitions to powerglide's Tool struct and handles tool calls

const std = @import("std");
const json = std.json;
const mem = std.mem;

const Tool = @import("../tools/tool.zig").Tool;
const ToolInput = @import("../tools/tool.zig").ToolInput;
const ToolOutput = @import("../tools/tool.zig").ToolOutput;
const ToolFn = @import("../tools/tool.zig").ToolFn;

const McpClient = @import("client.zig").McpClient;
const McpTool = @import("client.zig").McpTool;

/// Context for MCP tool handlers
pub const McpToolContext = struct {
    client: *McpClient,
    tool_name: []const u8,

    pub fn deinit(self: *McpToolContext, allocator: std.mem.Allocator) void {
        allocator.free(self.tool_name);
        allocator.destroy(self);
    }
};

/// Validate that a name contains only alphanumeric characters, underscores, and hyphens.
/// Returns true if safe to use in a prefixed tool name.
fn isValidToolName(name: []const u8) bool {
    if (name.len == 0) return false;
    for (name) |c| {
        if (!std.ascii.isAlphanumeric(c) and c != '_' and c != '-') return false;
    }
    return true;
}

/// Convert MCP tool definition to powerglide Tool struct
pub fn mcpToolToTool(allocator: std.mem.Allocator, client: *McpClient, mcp_tool: McpTool, server_name: []const u8) !Tool {
    // Convert input schema to JSON string
    var buf = std.ArrayList(u8){};
try buf.writer(allocator).print("{f}", .{json.fmt(mcp_tool.inputSchema, .{})});
const schema_str = try buf.toOwnedSlice(allocator);

    // Create a context for this tool
    const context = try allocator.create(McpToolContext);
    context.* = .{
        .client = client,
        .tool_name = try allocator.dupe(u8, mcp_tool.name),
    };

    if (!isValidToolName(server_name) or !isValidToolName(mcp_tool.name))
        return error.InvalidToolName;
    const prefixed_name = try std.fmt.allocPrint(allocator, "mcp_{s}_{s}", .{ server_name, mcp_tool.name });

    return Tool{
        .name = prefixed_name,
        .description = try allocator.dupe(u8, mcp_tool.description),
        .input_schema = schema_str,
        .handler = mcpToolHandler,
        .ctx = context,
    };
}

/// Generic MCP tool handler
fn mcpToolHandler(_: std.mem.Allocator, ctx: ?*anyopaque, input: ToolInput) anyerror!ToolOutput {
    if (ctx == null) return ToolOutput.failure("MCP tool context is null");
    const mcp_ctx: *McpToolContext = @ptrCast(@alignCast(ctx.?));

    const result = try mcp_ctx.client.callTool(mcp_ctx.tool_name, input.arguments);
    
    if (result.isError) {
        return ToolOutput.failure(result.content);
    } else {
        return ToolOutput.success(result.content);
    }
}

/// Convert multiple MCP tools to powerglide tools
pub fn convertMcpTools(allocator: std.mem.Allocator, client: *McpClient, mcp_tools: []McpTool, server_name: []const u8) ![]Tool {
    var tools = try allocator.alloc(Tool, mcp_tools.len);

    for (mcp_tools, 0..) |mcp_tool, i| {
        tools[i] = try mcpToolToTool(allocator, client, mcp_tool, server_name);
    }

    return tools;
}

// ==================== Tests ====================

test "McpToolContext init and deinit" {
    const allocator = std.testing.allocator;
    // We can't create a real McpClient without a process, so test the context struct directly
    const ctx = try allocator.create(McpToolContext);
    ctx.* = .{
        .client = undefined, // not called
        .tool_name = try allocator.dupe(u8, "test_tool"),
    };
    ctx.deinit(allocator);
    // No leak = pass
}

test "mcpToolToTool creates prefixed name" {
    const allocator = std.testing.allocator;
    var schema_obj = std.json.ObjectMap.init(allocator);
    defer schema_obj.deinit();
    try schema_obj.put("type", .{ .string = "object" });

    const mcp_tool = McpTool{
        .name = "read_file",
        .description = "Reads a file",
        .inputSchema = .{ .object = schema_obj },
    };

    // We pass undefined for client since mcpToolToTool only stores it in context
    const tool = try mcpToolToTool(allocator, undefined, mcp_tool, "filesystem");
    defer {
        allocator.free(tool.name);
        allocator.free(tool.description);
        allocator.free(tool.input_schema);
        if (tool.ctx) |ctx| {
            const mcp_ctx: *McpToolContext = @ptrCast(@alignCast(ctx));
            allocator.free(mcp_ctx.tool_name);
            allocator.destroy(mcp_ctx);
        }
    }

    try std.testing.expect(std.mem.eql(u8, tool.name, "mcp_filesystem_read_file"));
    try std.testing.expect(std.mem.eql(u8, tool.description, "Reads a file"));
    try std.testing.expect(tool.ctx != null);
    try std.testing.expect(tool.handler == mcpToolHandler);
}

test "mcpToolToTool stores original tool name in context" {
    const allocator = std.testing.allocator;
    var schema_obj = std.json.ObjectMap.init(allocator);
    defer schema_obj.deinit();
    try schema_obj.put("type", .{ .string = "object" });

    const mcp_tool = McpTool{
        .name = "search_code",
        .description = "Search code",
        .inputSchema = .{ .object = schema_obj },
    };

    const tool = try mcpToolToTool(allocator, undefined, mcp_tool, "myserver");
    defer {
        allocator.free(tool.name);
        allocator.free(tool.description);
        allocator.free(tool.input_schema);
        if (tool.ctx) |ctx| {
            const mcp_ctx: *McpToolContext = @ptrCast(@alignCast(ctx));
            allocator.free(mcp_ctx.tool_name);
            allocator.destroy(mcp_ctx);
        }
    }

    const mcp_ctx: *McpToolContext = @ptrCast(@alignCast(tool.ctx.?));
    try std.testing.expect(std.mem.eql(u8, mcp_ctx.tool_name, "search_code"));
    try std.testing.expect(std.mem.eql(u8, tool.name, "mcp_myserver_search_code"));
}

test "mcpToolToTool schema is valid JSON" {
    const allocator = std.testing.allocator;
    var props = std.json.ObjectMap.init(allocator);
    defer props.deinit();
    var path_prop = std.json.ObjectMap.init(allocator);
    defer path_prop.deinit();
    try path_prop.put("type", .{ .string = "string" });
    try props.put("path", .{ .object = path_prop });

    var schema_obj = std.json.ObjectMap.init(allocator);
    defer schema_obj.deinit();
    try schema_obj.put("type", .{ .string = "object" });
    try schema_obj.put("properties", .{ .object = props });

    const mcp_tool = McpTool{
        .name = "read_file",
        .description = "Read a file",
        .inputSchema = .{ .object = schema_obj },
    };

    const tool = try mcpToolToTool(allocator, undefined, mcp_tool, "fs");
    defer {
        allocator.free(tool.name);
        allocator.free(tool.description);
        allocator.free(tool.input_schema);
        if (tool.ctx) |ctx| {
            const mcp_ctx: *McpToolContext = @ptrCast(@alignCast(ctx));
            allocator.free(mcp_ctx.tool_name);
            allocator.destroy(mcp_ctx);
        }
    }

    // Schema should be parseable JSON
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, tool.input_schema, .{});
    defer parsed.deinit();
    try std.testing.expect(parsed.value == .object);
}
