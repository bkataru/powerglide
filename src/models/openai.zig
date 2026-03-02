const std = @import("std");

pub const OpenAIClient = struct {
    api_key: []const u8,
    base_url: []const u8 = "https://api.openai.com/v1",
    model: []const u8 = "gpt-4",

    pub const ChatMessage = struct {
        role: []const u8,
        content: []const u8,
    };

    pub const ChatResponse = struct {
        id: []const u8,
        content: []const u8,
        model: []const u8,
        finish_reason: []const u8,
    };

    pub fn init(api_key: []const u8) OpenAIClient {
        return .{ .api_key = api_key };
    }

    pub fn chat(self: *OpenAIClient, messages: []ChatMessage) !ChatResponse {
        _ = self;
        _ = messages;
        return .{
            .id = "",
            .content = "",
            .model = "",
            .finish_reason = "",
        };
    }
};

test "placeholder" {
    try std.testing.expect(true);
}
