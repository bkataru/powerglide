const std = @import("std");
const http = @import("http.zig");

pub const OAIMessage = struct {
    role: []const u8,
    content: []const u8,
};

pub const OAIResponse = struct {
    id: []const u8,
    text: ?[]const u8, // content of first choice message
    finish_reason: []const u8,
    prompt_tokens: u32,
    completion_tokens: u32,

    pub fn deinit(self: *OAIResponse, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        if (self.text) |t| allocator.free(t);
        allocator.free(self.finish_reason);
    }
};

pub const OpenAIClient = struct {
    allocator: std.mem.Allocator,
    api_key: ?[]const u8,
    base_url: []const u8,
    model: []const u8,
    http_client: http.HttpClient,

    pub fn init(allocator: std.mem.Allocator, base_url: []const u8, api_key: ?[]const u8, model: []const u8) !OpenAIClient {
        return .{
            .allocator = allocator,
            .api_key = api_key,
            .base_url = base_url,
            .model = model,
            .http_client = http.HttpClient.init(allocator),
        };
    }

    pub fn deinit(self: *OpenAIClient) void {
        self.http_client.deinit();
    }

    pub fn send(self: *OpenAIClient, allocator: std.mem.Allocator, messages: []const OAIMessage, max_tokens: u32) !OAIResponse {
        // Build request JSON
        var request_obj = std.StringArrayHashMap(std.json.Value).init(allocator);
        defer request_obj.deinit();

        // Add model
        try request_obj.put("model", .{ .string = self.model });
        try request_obj.put("max_tokens", .{ .integer = max_tokens });

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
        var request_json = std.ArrayList(u8).init(allocator);
        defer request_json.deinit();

        const stringify_options = std.json.StringifyOptions{ .whitespace = .indent_2 };
try std.json.stringify(request_obj, stringify_options, request_json.writer());

        // Build headers
        var headers = std.ArrayList(std.http.Header).init(allocator);
        defer headers.deinit();

        try headers.append(.{ .name = "content-type", .value = "application/json" });

        if (self.api_key) |key| {
            try headers.append(.{ .name = "authorization", .value = try std.fmt.allocPrint(allocator, "Bearer {s}", .{key}) });
        }

        // Build URL
        const url = try std.fmt.allocPrint(allocator, "{s}/chat/completions", .{self.base_url});
        defer allocator.free(url);

        // Make the request
        const response = try self.http_client.post(url, headers.items, request_json.items);

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
        const finish_reason = root.object.get("choices").?.array[0].object.get("finish_reason").?.string;

        // Extract content from first choice
        const content_val = root.object.get("choices").?.array[0].object.get("message").?.object.get("content");
        const text: ?[]const u8 = if (content_val) |c| c.string else null;

        // Extract usage
        const usage_obj = root.object.get("usage").?.object;
        const prompt_tokens: u32 = @intCast(usage_obj.get("prompt_tokens").?.integer);
        const completion_tokens: u32 = @intCast(usage_obj.get("completion_tokens").?.integer);

        return OAIResponse{
            .id = id,
            .text = text,
            .finish_reason = finish_reason,
            .prompt_tokens = prompt_tokens,
            .completion_tokens = completion_tokens,
        };
    }
};

test "OpenAIClient initialization with api_key" {
    const allocator = std.testing.allocator;
    const client = try OpenAIClient.init(allocator, "https://api.openai.com/v1", "test-key", "gpt-4");
    defer client.deinit();

    try std.testing.expect(client.api_key != null);
    try std.testing.expect(std.mem.eql(u8, client.api_key.?, "test-key"));
    try std.testing.expect(std.mem.eql(u8, client.model, "gpt-4"));
    try std.testing.expect(std.mem.eql(u8, client.base_url, "https://api.openai.com/v1"));
}

test "OpenAIClient initialization without api_key" {
    const allocator = std.testing.allocator;
    const client = try OpenAIClient.init(allocator, "https://api.openai.com/v1", null, "gpt-4");
    defer client.deinit();

    try std.testing.expect(client.api_key == null);
    try std.testing.expect(std.mem.eql(u8, client.model, "gpt-4"));
}

test "OpenAIClient with custom base_url" {
    const allocator = std.testing.allocator;
    const client = try OpenAIClient.init(allocator, "https://custom.api.com/v1", "key", "custom-model");
    defer client.deinit();

    try std.testing.expect(std.mem.eql(u8, client.base_url, "https://custom.api.com/v1"));
    try std.testing.expect(std.mem.eql(u8, client.model, "custom-model"));
}

test "OAIMessage struct" {
    const msg = OAIMessage{
        .role = "user",
        .content = "Hello, OpenAI!",
    };
    try std.testing.expect(std.mem.eql(u8, msg.role, "user"));
    try std.testing.expect(std.mem.eql(u8, msg.content, "Hello, OpenAI!"));
}

test "Multiple OAIMessages" {
    const messages = [_]OAIMessage{
        .{ .role = "system", .content = "You are helpful" },
        .{ .role = "user", .content = "test" },
        .{ .role = "assistant", .content = "response" },
    };
    try std.testing.expect(messages.len == 3);
    try std.testing.expect(std.mem.eql(u8, messages[0].role, "system"));
    try std.testing.expect(std.mem.eql(u8, messages[1].role, "user"));
    try std.testing.expect(std.mem.eql(u8, messages[2].role, "assistant"));
}

test "OAIResponse with text" {
    const allocator = std.testing.allocator;
    var response = OAIResponse{
        .id = try allocator.dupe(u8, "chatcmpl-123"),
        .text = try allocator.dupe(u8, "Response text"),
        .finish_reason = "stop",
        .prompt_tokens = 10,
        .completion_tokens = 20,
    };
    defer response.deinit(allocator);

    try std.testing.expect(std.mem.eql(u8, response.id, "chatcmpl-123"));
    try std.testing.expect(response.text != null);
    try std.testing.expect(std.mem.eql(u8, response.text.?, "Response text"));
    try std.testing.expect(std.mem.eql(u8, response.finish_reason, "stop"));
    try std.testing.expect(response.prompt_tokens == 10);
    try std.testing.expect(response.completion_tokens == 20);
}

test "OAIResponse with null text" {
    const allocator = std.testing.allocator;
    var response = OAIResponse{
        .id = try allocator.dupe(u8, "chatcmpl-456"),
        .text = null,
        .finish_reason = "length",
        .prompt_tokens = 5,
        .completion_tokens = 100,
    };
    defer response.deinit(allocator);

    try std.testing.expect(response.text == null);
    try std.testing.expect(std.mem.eql(u8, response.finish_reason, "length"));
}

test "OAIResponse deinit frees resources" {
    const allocator = std.testing.allocator;
    var response = OAIResponse{
        .id = try allocator.dupe(u8, "id"),
        .text = try allocator.dupe(u8, "text"),
        .finish_reason = "stop",
        .prompt_tokens = 1,
        .completion_tokens = 1,
    };
    response.deinit(allocator); // Should not leak
}

test "OAIResponse finish_reason values" {
    const allocator = std.testing.allocator;
    
    var response1 = OAIResponse{
        .id = try allocator.dupe(u8, "id"),
        .text = try allocator.dupe(u8, "t"),
        .finish_reason = "stop",
        .prompt_tokens = 1,
        .completion_tokens = 1,
    };
    defer response1.deinit(allocator);
    try std.testing.expect(std.mem.eql(u8, response1.finish_reason, "stop"));

    var response2 = OAIResponse{
        .id = try allocator.dupe(u8, "id"),
        .text = try allocator.dupe(u8, "t"),
        .finish_reason = "length",
        .prompt_tokens = 1,
        .completion_tokens = 1,
    };
    defer response2.deinit(allocator);
    try std.testing.expect(std.mem.eql(u8, response2.finish_reason, "length"));

    var response3 = OAIResponse{
        .id = try allocator.dupe(u8, "id"),
        .text = try allocator.dupe(u8, "t"),
        .finish_reason = "content_filter",
        .prompt_tokens = 1,
        .completion_tokens = 1,
    };
    defer response3.deinit(allocator);
    try std.testing.expect(std.mem.eql(u8, response3.finish_reason, "content_filter"));
}

test "OAIResponse token counts" {
    const allocator = std.testing.allocator;
    var response = OAIResponse{
        .id = try allocator.dupe(u8, "id"),
        .text = try allocator.dupe(u8, "text"),
        .finish_reason = "stop",
        .prompt_tokens = 1000,
        .completion_tokens = 2000,
    };
    defer response.deinit(allocator);

    try std.testing.expect(response.prompt_tokens == 1000);
    try std.testing.expect(response.completion_tokens == 2000);
    try std.testing.expect(response.prompt_tokens + response.completion_tokens == 3000);
}

test "OpenAIClient deinit is safe" {
    const allocator = std.testing.allocator;
    var client = try OpenAIClient.init(allocator, "url", "key", "model");
    client.deinit(); // Should not panic
}

test "OAIMessage with empty content" {
    const msg = OAIMessage{
        .role = "user",
        .content = "",
    };
    try std.testing.expect(std.mem.eql(u8, msg.role, "user"));
    try std.testing.expect(msg.content.len == 0);
}

test "OAIResponse with zero tokens" {
    const allocator = std.testing.allocator;
    var response = OAIResponse{
        .id = try allocator.dupe(u8, "id"),
        .text = try allocator.dupe(u8, ""),
        .finish_reason = "stop",
        .prompt_tokens = 0,
        .completion_tokens = 0,
    };
    defer response.deinit(allocator);

    try std.testing.expect(response.prompt_tokens == 0);
