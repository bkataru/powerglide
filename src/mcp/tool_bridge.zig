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
