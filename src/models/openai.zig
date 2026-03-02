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

test "placeholder" {
    try std.testing.expect(true);
}
