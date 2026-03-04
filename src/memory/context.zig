const std = @import("std");

/// A message in the context window
pub const ContextMessage = struct {
    role: []const u8,
    content: []const u8,
    token_estimate: u32,
    timestamp: i64,
};

/// Context window management — decides what to include in the LLM context
pub const ContextWindow = struct {
    allocator: std.mem.Allocator,
    max_tokens: u32,
    current_tokens: u32,
    messages: std.ArrayList(ContextMessage),

    /// Initialize a new ContextWindow
    pub fn init(allocator: std.mem.Allocator, max_tokens: u32) ContextWindow {
        return .{
            .allocator = allocator,
            .max_tokens = max_tokens,
            .current_tokens = 0,
            .messages = std.ArrayList(ContextMessage).init(allocator),
        };
    }

    /// Free all memory
    pub fn deinit(self: *ContextWindow) void {
        for (self.messages.items) |msg| {
            self.allocator.free(msg.role);
            self.allocator.free(msg.content);
        }
        self.messages.deinit();
    }

    /// Add a message to context (may trigger compaction if over budget)
    pub fn addMessage(self: *ContextWindow, role: []const u8, content: []const u8) !void {
        const token_estimate = ContextWindow.estimateTokens(content);
        const timestamp = std.time.timestamp();

        const owned_role = try self.allocator.dupe(u8, role);
        const owned_content = try self.allocator.dupe(u8, content);

        const message = ContextMessage{
            .role = owned_role,
            .content = owned_content,
            .token_estimate = token_estimate,
            .timestamp = timestamp,
        };

        try self.messages.append(message);
        self.current_tokens += token_estimate;

        // Auto-compact if over budget (at 90% threshold)
        const threshold = @as(u32, @floatCast(@as(f32, @floatFromInt(self.max_tokens)) * 0.9));
        if (self.current_tokens > threshold) {
            try self.compact(threshold);
        }
    }

    /// Remove oldest messages to fit within token budget
    pub fn compact(self: *ContextWindow, target_tokens: u32) !void {
        // Keep at least the most recent message if we have any
        while (self.current_tokens > target_tokens and self.messages.items.len > 1) {
            // Remove oldest message (from the front)
            const removed = self.messages.orderedRemove(0);
            self.current_tokens -= removed.token_estimate;

            // Free the memory
            self.allocator.free(removed.role);
            self.allocator.free(removed.content);
        }

        // If still over budget (shouldn't happen with >1 message), clear all but last
        while (self.current_tokens > target_tokens and self.messages.items.len > 0) {
            const removed = self.messages.pop();
            self.current_tokens -= removed.token_estimate;

            self.allocator.free(removed.role);
            self.allocator.free(removed.content);
        }
    }

    /// Get all messages suitable for sending to LLM
    pub fn getMessages(self: *const ContextWindow) []const ContextMessage {
        return self.messages.items;
    }

    /// Estimate tokens (rough: chars/4)
    pub fn estimateTokens(text: []const u8) u32 {
        // Rough approximation: 4 characters per token
        // This is a very rough estimate; real tokenization varies
        return @as(u32, @intCast((text.len + 3) / 4));
    }

    /// Clear all messages
    pub fn clear(self: *ContextWindow) void {
        for (self.messages.items) |msg| {
            self.allocator.free(msg.role);
            self.allocator.free(msg.content);
        }
        self.messages.clearRetainingCapacity();
        self.current_tokens = 0;
    }

    /// Get current token count
    pub fn tokenCount(self: *const ContextWindow) u32 {
        return self.current_tokens;
    }

    /// Get max token budget
    pub fn maxTokenCount(self: *const ContextWindow) u32 {
        return self.max_tokens;
    }

    /// Get number of messages
    pub fn messageCount(self: *const ContextWindow) usize {
        return self.messages.items.len;
    }
};

test "ContextWindow initialization" {
    const allocator = std.testing.allocator;
    const window = ContextWindow.init(allocator, 1000);
    defer window.deinit();

    try std.testing.expect(window.max_tokens == 1000);
    try std.testing.expect(window.current_tokens == 0);
    try std.testing.expect(window.messages.items.len == 0);
}

test "ContextWindow addMessage increments token count" {
    const allocator = std.testing.allocator;
    var window = ContextWindow.init(allocator, 1000);
    defer window.deinit();

    try window.addMessage("user", "Hello, world!");

    try std.testing.expect(window.messages.items.len == 1);
    try std.testing.expect(window.current_tokens > 0);
    try std.testing.expect(std.mem.eql(u8, window.messages.items[0].role, "user"));
}

test "ContextWindow estimateTokens" {
    const text1 = "Hello"; // 5 chars / 4 = 2 tokens
    const tokens1 = ContextWindow.estimateTokens(text1);
    try std.testing.expect(tokens1 == 2);

    const text2 = ""; // empty string
    const tokens2 = ContextWindow.estimateTokens(text2);
    try std.testing.expect(tokens2 == 0);

    const text3 = "abcdefghijklmnopqrstuvwxyz"; // 26 chars / 4 = 7 tokens
    const tokens3 = ContextWindow.estimateTokens(text3);
    try std.testing.expect(tokens3 == 7);
}

test "ContextWindow auto-compact at 90% threshold" {
    const allocator = std.testing.allocator;
    var window = ContextWindow.init(allocator, 100);
    defer window.deinit();

    // Add messages that will trigger compaction
    // Each "Hello" is ~2 tokens, need 45 messages to reach 90% of 100
    for (0..50) |_| {
        try window.addMessage("user", "Hello, this is a longer message that uses tokens");
    }

    // Should have compacted
    try std.testing.expect(window.current_tokens < window.max_tokens);
    // Should keep some messages
    try std.testing.expect(window.messages.items.len > 0);
}

test "ContextWindow compact removes oldest messages" {
    const allocator = std.testing.allocator;
    var window = ContextWindow.init(allocator, 100);
    defer window.deinit();

    try window.addMessage("system", "System prompt");
    try window.addMessage("user", "First");
    try window.addMessage("assistant", "Response");
    try window.addMessage("user", "Second");
    try window.addMessage("assistant", "Response 2");

    const before_count = window.messages.items.len;
    try std.testing.expect(before_count == 5);

    // Compact to very low budget
    try window.compact(20);

    const after_count = window.messages.items.len;
    try std.testing.expect(after_count < before_count);
    try std.testing.expect(window.current_tokens <= 20);
}

test "ContextWindow getMessages returns all messages" {
    const allocator = std.testing.allocator;
    var window = ContextWindow.init(allocator, 1000);
    defer window.deinit();

    try window.addMessage("user", "First message");
    try window.addMessage("assistant", "First response");
    try window.addMessage("user", "Second message");

    const messages = window.getMessages();
    try std.testing.expect(messages.len == 3);
    try std.testing.expect(std.mem.eql(u8, messages[0].role, "user"));
    try std.testing.expect(std.mem.eql(u8, messages[1].role, "assistant"));
    try std.testing.expect(std.mem.eql(u8, messages[2].role, "user"));
}

test "ContextWindow clear removes all messages" {
    const allocator = std.testing.allocator;
    var window = ContextWindow.init(allocator, 1000);
    defer window.deinit();

    try window.addMessage("user", "test");
    try window.addMessage("assistant", "response");

    try std.testing.expect(window.messages.items.len == 2);
    try std.testing.expect(window.current_tokens > 0);

    window.clear();

    try std.testing.expect(window.messages.items.len == 0);
    try std.testing.expect(window.current_tokens == 0);
}

test "ContextWindow tokenCount" {
    const allocator = std.testing.allocator;
    var window = ContextWindow.init(allocator, 1000);
    defer window.deinit();

    try window.addMessage("user", "test message");

    const count = window.tokenCount();
    try std.testing.expect(count == window.current_tokens);
    try std.testing.expect(count > 0);
}

test "ContextWindow maxTokenCount" {
    const allocator = std.testing.allocator;
    const window = ContextWindow.init(allocator, 5000);
    defer window.deinit();

    try std.testing.expect(window.maxTokenCount() == 5000);
}

test "ContextWindow messageCount" {
    const allocator = std.testing.allocator;
    var window = ContextWindow.init(allocator, 1000);
    defer window.deinit();

    try std.testing.expect(window.messageCount() == 0);

    try window.addMessage("user", "first");
    try std.testing.expect(window.messageCount() == 1);

    try window.addMessage("assistant", "second");
    try std.testing.expect(window.messageCount() == 2);

    try window.addMessage("user", "third");
    try std.testing.expect(window.messageCount() == 3);
}

test "ContextWindow deinit frees resources" {
    const allocator = std.testing.allocator;
    var window = ContextWindow.init(allocator, 1000);

    for (0..10) |_| {
        try window.addMessage("user", "test message");
    }

    window.deinit(); // Should not leak
}

test "ContextMessage struct fields" {
    const allocator = std.testing.allocator;
    var window = ContextWindow.init(allocator, 1000);
    defer window.deinit();

    try window.addMessage("system", "You are helpful");

    const msg = window.messages.items[0];
    try std.testing.expect(std.mem.eql(u8, msg.role, "system"));
    try std.testing.expect(std.mem.eql(u8, msg.content, "You are helpful"));
    try std.testing.expect(msg.token_estimate > 0);
    try std.testing.expect(msg.timestamp > 0);
}

test "ContextWindow with empty message" {
    const allocator = std.testing.allocator;
    var window = ContextWindow.init(allocator, 1000);
    defer window.deinit();

    try window.addMessage("user", "");

    try std.testing.expect(window.messages.items.len == 1);
    try std.testing.expect(window.current_tokens == 0);
}

test "ContextWindow compact with single message" {
    const allocator = std.testing.allocator;
    var window = ContextWindow.init(allocator, 1000);
    defer window.deinit();

    try window.addMessage("user", "test");
    const before_len = window.messages.items.len;

    try window.compact(10);

    // Should keep at least one message
    try std.testing.expect(window.messages.items.len >= 1);
    try std.testing.expect(window.messages.items.len <= before_len);
}

test "ContextWindow multiple roles" {
    const allocator = std.testing.allocator;
    var window = ContextWindow.init(allocator, 1000);
    defer window.deinit();

    const roles = [_][]const u8{"system", "user", "assistant", "user", "assistant"};
    for (roles) |role| {
        try window.addMessage(role, "content");
    }

    try std.testing.expect(window.messages.items.len == 5);
    for (window.messages.items, 0..) |msg, i| {
        try std.testing.expect(std.mem.eql(u8, msg.role, roles[i]));
    }
}

test "ContextWindow large message handling" {
    const allocator = std.testing.allocator;
    var window = ContextWindow.init(allocator, 100);
    defer window.deinit();

    // Add a message larger than the window
    const large_msg = "x" ** 500;
    try window.addMessage("user", large_msg);

    // Should still have the message but token count is high
    try std.testing.expect(window.messages.items.len == 1);

    try std.testing.expect(window.messages.items.len == 1);
}
