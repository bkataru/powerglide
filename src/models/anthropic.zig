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

test "AnthropicClient initialization" {
    const allocator = std.testing.allocator;
    const client = try AnthropicClient.init(allocator, "test-key", "claude-3-opus");
    defer client.deinit();

    try std.testing.expect(std.mem.eql(u8, client.api_key, "test-key"));
    try std.testing.expect(std.mem.eql(u8, client.model, "claude-3-opus"));
    try std.testing.expect(std.mem.eql(u8, client.base_url, "https://api.anthropic.com"));
}

test "AnthropicClient with different model" {
    const allocator = std.testing.allocator;
    const client = try AnthropicClient.init(allocator, "key", "claude-3-haiku");
    defer client.deinit();

    try std.testing.expect(std.mem.eql(u8, client.model, "claude-3-haiku"));
}

test "Message struct" {
    const msg = Message{
        .role = "user",
        .content = "Hello, Claude!",
    };
    try std.testing.expect(std.mem.eql(u8, msg.role, "user"));
    try std.testing.expect(std.mem.eql(u8, msg.content, "Hello, Claude!"));
}

test "Multiple messages" {
    const messages = [_]Message{
        .{ .role = "system", .content = "You are helpful" },
        .{ .role = "user", .content = "test" },
        .{ .role = "assistant", .content = "response" },
    };
    try std.testing.expect(messages.len == 3);
    try std.testing.expect(std.mem.eql(u8, messages[2].role, "assistant"));
}

test "ContentBlock text variant" {
    const block = ContentBlock{
        .text = .{ .text = "This is text content" },
    };
    try std.testing.expect(block == .text);
    try std.testing.expect(std.mem.eql(u8, block.text.text, "This is text content"));
}

test "ContentBlock tool_use variant" {
    const allocator = std.testing.allocator;
    const block = ContentBlock{
        .tool_use = .{
            .id = "tool_123",
            .name = "search",
            .input = .{ .string = "query" },
        },
    };
    try std.testing.expect(block == .tool_use);
    try std.testing.expect(std.mem.eql(u8, block.tool_use.id, "tool_123"));
    try std.testing.expect(std.mem.eql(u8, block.tool_use.name, "search"));
    _ = allocator;
}

test "ApiResponse with text content" {
    const allocator = std.testing.allocator;
    var content = try allocator.alloc(ContentBlock, 1);
    content[0] = ContentBlock{ .text = .{ .text = "Response text" } };

    var response = ApiResponse{
        .id = try allocator.dupe(u8, "msg_123"),
        .content = content,
        .stop_reason = "end_turn",
        .input_tokens = 10,
        .output_tokens = 20,
    };
    defer response.deinit(allocator);

    try std.testing.expect(std.mem.eql(u8, response.id, "msg_123"));
    try std.testing.expect(std.mem.eql(u8, response.stop_reason, "end_turn"));
    try std.testing.expect(response.input_tokens == 10);
    try std.testing.expect(response.output_tokens == 20);
}

test "ApiResponse getText returns text" {
    const allocator = std.testing.allocator;
    var content = try allocator.alloc(ContentBlock, 1);
    content[0] = ContentBlock{ .text = .{ .text = "Hello" } };

    var response = ApiResponse{
        .id = try allocator.dupe(u8, "id"),
        .content = content,
        .stop_reason = "end_turn",
        .input_tokens = 5,
        .output_tokens = 5,
    };
    defer response.deinit(allocator);

    const text = response.getText();
    try std.testing.expect(text != null);
    try std.testing.expect(std.mem.eql(u8, text.?, "Hello"));
}

test "ApiResponse getText returns null for tool_use" {
    const allocator = std.testing.allocator;
    var content = try allocator.alloc(ContentBlock, 1);
    content[0] = ContentBlock{
        .tool_use = .{ .id = "t1", .name = "search", .input = .{ .string = "q" } },
    };

    var response = ApiResponse{
        .id = try allocator.dupe(u8, "id"),
        .content = content,
        .stop_reason = "tool_use",
        .input_tokens = 5,
        .output_tokens = 0,
    };
    defer response.deinit(allocator);

    const text = response.getText();
    try std.testing.expect(text == null);
}

test "ApiResponse getText returns null for empty content" {
    const allocator = std.testing.allocator;
    var content = try allocator.alloc(ContentBlock, 0);

    var response = ApiResponse{
        .id = try allocator.dupe(u8, "id"),
        .content = content,
        .stop_reason = "end_turn",
        .input_tokens = 0,
        .output_tokens = 0,
    };
    defer response.deinit(allocator);

    const text = response.getText();
    try std.testing.expect(text == null);
}

test "ApiResponse getToolCalls" {
    const allocator = std.testing.allocator;
    var content = try allocator.alloc(ContentBlock, 3);
    content[0] = ContentBlock{ .text = .{ .text = "Text" } };
    content[1] = ContentBlock{
        .tool_use = .{ .id = "t1", .name = "search", .input = .{ .string = "q" } },
    };
    content[2] = ContentBlock{
        .tool_use = .{ .id = "t2", .name = "write", .input = .{ .string = "data" } },
    };

    var response = ApiResponse{
        .id = try allocator.dupe(u8, "id"),
        .content = content,
        .stop_reason = "tool_use",
        .input_tokens = 10,
        .output_tokens = 5,
    };
    defer response.deinit(allocator);

    const tool_calls = response.getToolCalls();
    try std.testing.expect(tool_calls.len == 2);
}

test "ApiResponse deinit cleans up resources" {
    const allocator = std.testing.allocator;
    var content = try allocator.alloc(ContentBlock, 2);
    content[0] = ContentBlock{ .text = .{ .text = "Text" } };
    content[1] = ContentBlock{
        .tool_use = .{ .id = "t1", .name = "search", .input = .{ .string = "q" } },
    };

    var response = ApiResponse{
        .id = try allocator.dupe(u8, "msg_id"),
        .content = content,
        .stop_reason = "end_turn",
        .input_tokens = 5,
        .output_tokens = 5,
    };
    response.deinit(allocator); // Should not leak
}

test "ApiResponse with mixed content" {
    const allocator = std.testing.allocator;
    var content = try allocator.alloc(ContentBlock, 3);
    content[0] = ContentBlock{ .text = .{ .text = "First" } };
    content[1] = ContentBlock{
        .tool_use = .{ .id = "t1", .name = "calc", .input = .{ .integer = 42 } },
    };
    content[2] = ContentBlock{ .text = .{ .text = "Second" } };

    var response = ApiResponse{
        .id = try allocator.dupe(u8, "id"),
        .content = content,
        .stop_reason = "end_turn",
        .input_tokens = 15,
        .output_tokens = 10,
    };
    defer response.deinit(allocator);

    const text = response.getText();
    try std.testing.expect(text != null);
    try std.testing.expect(std.mem.eql(u8, text.?, "First"));
}

test "ApiResponse stop_reason values" {
    const allocator = std.testing.allocator;
    var content = try allocator.alloc(ContentBlock, 1);
    content[0] = ContentBlock{ .text = .{ .text = "" } };

    var response = ApiResponse{
        .id = try allocator.dupe(u8, "id"),
        .content = content,
        .stop_reason = "max_tokens",
        .input_tokens = 100,
        .output_tokens = 1000,
    };
    defer response.deinit(allocator);

    try std.testing.expect(std.mem.eql(u8, response.stop_reason, "max_tokens"));
}

test "AnthropicClient deinit is safe" {
    const allocator = std.testing.allocator;
    var client = try AnthropicClient.init(allocator, "key", "model");
    client.deinit(); // Should not panic
}

test "ContentBlock union memory layout" {
    // Ensure both variants can be stored
    const allocator = std.testing.allocator;
    
    var block1 = ContentBlock{ .text = .{ .text = "text" } };
    try std.testing.expect(block1 == .text);
    
    var block2 = ContentBlock{
        .tool_use = .{ .id = "id", .name = "name", .input = .{ .bool = true } },
    };
    try std.testing.expect(block2 == .tool_use);
    
    _ = allocator;
}
    try std.testing.expect(true);
}
