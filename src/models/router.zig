const std = @import("std");

pub const ModelProvider = enum {
    anthropic,
    openai,
    openai_compatible,
};

pub const ModelRouter = struct {
    allocator: std.mem.Allocator,
    default_provider: ModelProvider = .anthropic,
    selected_model: []const u8 = "claude-3-5-sonnet-20241022",

    pub fn init(allocator: std.mem.Allocator) ModelRouter {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ModelRouter) void {
        _ = self;
    }

    pub fn selectModel(self: *ModelRouter, name: []const u8) void {
        _ = self;
        _ = name;
    }

    pub fn getProvider(self: *ModelRouter) ModelProvider {
        return self.default_provider;
    }
};

test "placeholder" {
    try std.testing.expect(true);
}
