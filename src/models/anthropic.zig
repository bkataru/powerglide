const std = @import("std");

pub const AnthropicClient = struct {
    api_key: []const u8,
    http_client: *anyopaque,

    pub const Message = struct {
        role: []const u8,
        content: []const u8,
    };

    pub const Response = struct {
        id: []const u8,
        content: []const u8,
        model: []const u8,
    };

    pub fn init(api_key: []const u8) AnthropicClient {
        return .{ .api_key = api_key, .http_client = undefined };
    }

    pub fn createMessage(self: *AnthropicClient, messages: []Message) !Response {
        _ = self;
        _ = messages;
        return .{ .id = "", .content = "", .model = "" };
    }
};

test "placeholder" {
    try std.testing.expect(true);
}
