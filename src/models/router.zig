const std = @import("std");
const anthropic = @import("anthropic.zig");
const openai = @import("openai.zig");

pub const Provider = enum {
    anthropic,
    openai_compat,
};

pub const ModelConfig = struct {
    provider: Provider,
    model: []const u8,
    api_key: ?[]const u8 = null,
    base_url: ?[]const u8 = null,
};

pub const UnifiedMessage = struct {
    role: []const u8,
    content: []const u8,
};

pub const UnifiedResponse = struct {
    text: ?[]const u8,
    stop_reason: []const u8,
    input_tokens: u32,
    output_tokens: u32,

    pub fn deinit(self: *UnifiedResponse, allocator: std.mem.Allocator) void {
        if (self.text) |t| allocator.free(t);
        allocator.free(self.stop_reason);
    }
};

pub const Router = struct {
    allocator: std.mem.Allocator,
    primary: ModelConfig,
    fallback: ?ModelConfig,

    pub fn init(allocator: std.mem.Allocator, primary: ModelConfig) Router {
        return .{
            .allocator = allocator,
            .primary = primary,
            .fallback = null,
        };
    }

    pub fn deinit(self: *Router) void {
        // Nothing to clean up currently
        _ = self;
    }

    pub fn send(
        self: *Router,
        allocator: std.mem.Allocator,
        system: ?[]const u8,
        messages: []const UnifiedMessage,
        max_tokens: u32,
    ) !UnifiedResponse {
        // Try primary first
        const primary_result = self.sendToProvider(self.primary, allocator, system, messages, max_tokens) catch |err| {
            // If primary fails and we have a fallback, try that
            if (self.fallback) |fallback| {
                return self.sendToProvider(fallback, allocator, system, messages, max_tokens);
            }
            return err;
        };

        return primary_result;
    }

fn sendToProvider(
    _: *Router,
    config: ModelConfig,
    allocator: std.mem.Allocator,
    system: ?[]const u8,
    messages: []const UnifiedMessage,
    max_tokens: u32,
) !UnifiedResponse {
        switch (config.provider) {
            .anthropic => {
                // Convert unified messages to anthropic messages
                var anthropic_messages = try allocator.alloc(anthropic.Message, messages.len);
                defer allocator.free(anthropic_messages);

                for (messages, 0..) |msg, i| {
                    anthropic_messages[i] = .{ .role = msg.role, .content = msg.content };
                }

                const api_key = config.api_key orelse return error.ApiKeyRequired;
                var client = try anthropic.AnthropicClient.init(allocator, api_key, config.model);
                defer client.deinit();

                const response = try client.send(allocator, system, anthropic_messages, max_tokens);
                defer response.deinit(allocator);

                return UnifiedResponse{
                    .text = response.getText(),
                    .stop_reason = response.stop_reason,
                    .input_tokens = response.input_tokens,
                    .output_tokens = response.output_tokens,
                };
            },
            .openai_compat => {
                // Convert unified messages to OpenAI messages
                var oai_messages = try allocator.alloc(openai.OAIMessage, messages.len);
                defer allocator.free(oai_messages);

                for (messages, 0..) |msg, i| {
                    oai_messages[i] = .{ .role = msg.role, .content = msg.content };
                }

                const base_url = config.base_url orelse "https://api.openai.com/v1";
                var client = try openai.OpenAIClient.init(allocator, base_url, config.api_key, config.model);
                defer client.deinit();

                const response = try client.send(allocator, oai_messages, max_tokens);
                defer response.deinit(allocator);

                return UnifiedResponse{
                    .text = response.text,
                    .stop_reason = response.finish_reason,
                    .input_tokens = response.prompt_tokens,
                    .output_tokens = response.completion_tokens,
                };
            },
        }
    }
};

test "Router initialization with primary config" {
    const allocator = std.testing.allocator;
    const config = ModelConfig{
        .provider = .anthropic,
        .model = "claude-3-opus",
        .api_key = "test-key",
    };
    var router = Router.init(allocator, config);
    defer router.deinit();

    try std.testing.expect(router.primary.provider == .anthropic);
    try std.testing.expect(std.mem.eql(u8, router.primary.model, "claude-3-opus"));
    try std.testing.expect(router.fallback == null);
}

test "Router initialization with openai provider" {
    const allocator = std.testing.allocator;
    const config = ModelConfig{
        .provider = .openai_compat,
        .model = "gpt-4",
        .api_key = "test-key",
        .base_url = "https://api.openai.com/v1",
    };
    var router = Router.init(allocator, config);
    defer router.deinit();

    try std.testing.expect(router.primary.provider == .openai_compat);
    try std.testing.expect(std.mem.eql(u8, router.primary.model, "gpt-4"));
    try std.testing.expect(std.mem.eql(u8, router.primary.base_url.?, "https://api.openai.com/v1"));
}

test "Router requires api_key for anthropic provider" {
    const allocator = std.testing.allocator;
    const config = ModelConfig{
        .provider = .anthropic,
        .model = "claude-3-opus",
        .api_key = null,
    };
    var router = Router.init(allocator, config);
    defer router.deinit();

    const messages = [_]UnifiedMessage{
        .{ .role = "user", .content = "test" },
    };

    const result = router.send(allocator, null, &messages, 100);
    try std.testing.expectError(error.ApiKeyRequired, result);
}

test "UnifiedResponse deinit frees text" {
    const allocator = std.testing.allocator;
    var response = UnifiedResponse{
        .text = try allocator.dupe(u8, "test response"),
        .stop_reason = "end_turn",
        .input_tokens = 10,
        .output_tokens = 20,
    };
    defer response.deinit(allocator);

    try std.testing.expect(std.mem.eql(u8, response.text.?, "test response"));
    try std.testing.expect(std.mem.eql(u8, response.stop_reason, "end_turn"));
    try std.testing.expect(response.input_tokens == 10);
    try std.testing.expect(response.output_tokens == 20);
}

test "UnifiedResponse with null text" {
    const allocator = std.testing.allocator;
    var response = UnifiedResponse{
        .text = null,
        .stop_reason = "tool_use",
        .input_tokens = 5,
        .output_tokens = 0,
    };
    defer response.deinit(allocator);

    try std.testing.expect(response.text == null);
    try std.testing.expect(std.mem.eql(u8, response.stop_reason, "tool_use"));
}

test "Provider enum values" {
    try std.testing.expect(@intFromEnum(Provider.anthropic) == 0);
    try std.testing.expect(@intFromEnum(Provider.openai_compat) == 1);
}

test "ModelConfig with null base_url" {
    const config = ModelConfig{
        .provider = .openai_compat,
        .model = "gpt-4",
        .api_key = "test-key",
        .base_url = null,
    };
    try std.testing.expect(config.base_url == null);
}

test "UnifiedMessage struct" {
    const msg = UnifiedMessage{
        .role = "user",
        .content = "Hello, world!",
    };
    try std.testing.expect(std.mem.eql(u8, msg.role, "user"));
    try std.testing.expect(std.mem.eql(u8, msg.content, "Hello, world!"));
}

test "Multiple UnifiedMessage creation" {
    const messages = [_]UnifiedMessage{
        .{ .role = "system", .content = "You are helpful" },
        .{ .role = "user", .content = "test" },
        .{ .role = "assistant", .content = "response" },
    };
    try std.testing.expect(messages.len == 3);
    try std.testing.expect(std.mem.eql(u8, messages[0].role, "system"));
    try std.testing.expect(std.mem.eql(u8, messages[1].role, "user"));
    try std.testing.expect(std.mem.eql(u8, messages[2].role, "assistant"));
}

test "Router deinit is safe to call" {
    const allocator = std.testing.allocator;
    const config = ModelConfig{
        .provider = .anthropic,
        .model = "claude-3-opus",
        .api_key = "test-key",
    };
    var router = Router.init(allocator, config);
    router.deinit(); // Should not panic
}

test "UnifiedResponse token counts" {
    const allocator = std.testing.allocator;
    var response = UnifiedResponse{
        .text = try allocator.dupe(u8, "response"),
        .stop_reason = "end_turn",
        .input_tokens = 1000,
        .output_tokens = 2000,
    };
    defer response.deinit(allocator);

    try std.testing.expect(response.input_tokens == 1000);
    try std.testing.expect(response.output_tokens == 2000);
    try std.testing.expect(response.input_tokens + response.output_tokens == 3000);

}
