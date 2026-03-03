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

test "placeholder" {
    try std.testing.expect(true);
}
