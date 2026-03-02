const std = @import("std");
const http = @import("http.zig");

pub const ContentBlock = union(enum) {
    text: struct {
        text: []const u8,
    },
    tool_use: struct {
        id: []const u8,
        name: []const u8,
        input: std.json.Value,
    },
};

pub const Message = struct {
    role: []const u8,
    content: []const u8,
};

pub const ApiResponse = struct {
    id: []const u8,
    content: []ContentBlock,
    stop_reason: []const u8, // "end_turn", "tool_use", "max_tokens"
    input_tokens: u32,
    output_tokens: u32,

    pub fn deinit(self: *ApiResponse, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.stop_reason);
        for (self.content) |*block| {
            switch (block.*) {
                .text => |t| allocator.free(t.text),
                .tool_use => |t| {
                    allocator.free(t.id);
                    allocator.free(t.name);
                    // std.json.Value is managed internally
                },
            }
        }
        allocator.free(self.content);
    }

    pub fn getText(self: *const ApiResponse) ?[]const u8 {
        for (self.content) |block| {
            if (block == .text) {
                return block.text.text;
            }
        }
        return null;
    }

    pub fn getToolCalls(self: *const ApiResponse) []const ContentBlock {
        var tool_calls = std.ArrayList(ContentBlock).init(std.heap.page_allocator);
        for (self.content) |block| {
            if (block == .tool_use) {
                tool_calls.append(block) catch {};
            }
        }
        return tool_calls.items;
    }
};

pub const AnthropicClient = struct {
    allocator: std.mem.Allocator,
    api_key: []const u8,
    base_url: []const u8,
    model: []const u8,
    http_client: http.HttpClient,

    pub fn init(allocator: std.mem.Allocator, api_key: []const u8, model: []const u8) !AnthropicClient {
        return .{
            .allocator = allocator,
            .api_key = api_key,
            .base_url = "https://api.anthropic.com",
            .model = model,
            .http_client = http.HttpClient.init(allocator),
        };
    }

    pub fn deinit(self: *AnthropicClient) void {
        self.http_client.deinit();
    }

    /// Send messages, get response (non-streaming)
    pub fn send(
        self: *AnthropicClient,
        allocator: std.mem.Allocator,
        system_prompt: ?[]const u8,
        messages: []const Message,
        max_tokens: u32,
    ) !ApiResponse {
        // Build request JSON
        var request_json = std.ArrayList(u8).init(allocator);
        defer request_json.deinit();

        var request_obj = std.StringArrayHashMap(std.json.Value).init(allocator);
        defer request_obj.deinit();

        // Add model
        try request_obj.put("model", .{ .string = self.model });

        // Add max_tokens
        try request_obj.put("max_tokens", .{ .integer = max_tokens });

        // Add system prompt if provided
        if (system_prompt) |sp| {
            try request_obj.put("system", .{ .string = sp });
        }

        // Build messages array
        var messages_array = std.json.Array.init(allocator);
        defer messages_array.deinit();

        for (messages) |msg| {
            var msg_obj = std.StringArrayHashMap(std.json.Value).init(allocator);
            try msg_obj.put("role", .{ .string = msg.role });
            try msg_obj.put("content", .{ .string = msg.content });
            try messages_array.append(.{ .object = msg_obj });
        }

        try request_obj.put("messages", .{ .array = messages_array });

        // Stringify the request
        const stringify_options = std.json.StringifyOptions{ .whitespace = .indent_2 };
try std.json.stringify(request_obj, stringify_options, request_json.writer());

        // Build headers
        var headers = [_]std.http.Header{
            .{ .name = "x-api-key", .value = self.api_key },
            .{ .name = "anthropic-version", .value = "2023-06-01" },
            .{ .name = "content-type", .value = "application/json" },
        };

        // Build URL
        const url = try std.fmt.allocPrint(allocator, "{s}/v1/messages", .{self.base_url});
        defer allocator.free(url);

        // Make the request
        const response = try self.http_client.post(url, &headers, request_json.items);

        if (!response.isSuccess()) {
            return error.HttpError;
        }

        defer response.deinit(allocator);

        // Parse the response JSON
        var parsed = try std.json.parseFromSlice(std.json.Value, allocator, response.body, .{});
        defer parsed.deinit();

        const root = parsed.value;

        // Extract fields
        const id = root.object.get("id").?.string;
        const stop_reason = root.object.get("stop_reason").?.string;

        // Extract usage
        const usage_obj = root.object.get("usage").?.object;
        const input_tokens: u32 = @intCast(usage_obj.get("input_tokens").?.integer);
        const output_tokens: u32 = @intCast(usage_obj.get("output_tokens").?.integer);

        // Parse content blocks
        var content_blocks = std.ArrayList(ContentBlock).init(allocator);
        const content_array = root.object.get("content").?.array;

        for (content_array) |block_val| {
            const block_type = block_val.object.get("type").?.string;
            if (std.mem.eql(u8, block_type, "text")) {
                const text_content = block_val.object.get("text").?.string;
                try content_blocks.append(.{ .text = .{ .text = text_content } });
            } else if (std.mem.eql(u8, block_type, "tool_use")) {
                const tool_id = block_val.object.get("id").?.string;
                const tool_name = block_val.object.get("name").?.string;
                const tool_input = block_val.object.get("input").?;
                try content_blocks.append(.{
                    .tool_use = .{
                        .id = tool_id,
                        .name = tool_name,
                        .input = tool_input,
                    },
                });
            }
        }

        return ApiResponse{
            .id = id,
            .content = try content_blocks.toOwnedSlice(),
            .stop_reason = stop_reason,
            .input_tokens = input_tokens,
            .output_tokens = output_tokens,
        };
    }
};

test "placeholder" {
    try std.testing.expect(true);
}
