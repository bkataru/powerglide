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

test "placeholder" {
    try std.testing.expect(true);
}
