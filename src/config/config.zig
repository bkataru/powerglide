const std = @import("std");

pub const Config = struct {
    allocator: std.mem.Allocator,

    // Model settings
    model_provider: []const u8 = "anthropic",
    model_name: []const u8 = "claude-3-5-sonnet-20241022",
    api_key: ?[]const u8 = null,

    // Agent settings
    max_iterations: u32 = 100,
    velocity_ms: u32 = 100,

    // Terminal settings
    terminal_pool_size: usize = 4,
    default_shell: []const u8 = "/bin/bash",

    // Swarm settings
    max_agents: u32 = 8,
    swarm_timeout_ms: u32 = 300000,

    pub fn init(allocator: std.mem.Allocator) Config {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Config) void {
        _ = self;
    }

    pub fn loadFromEnv(self: *Config) void {
        if (std.process.getEnvVar(self.allocator, "ANTHROPIC_API_KEY")) |key| {
            self.api_key = key;
        }
    }
};

test "placeholder" {
    try std.testing.expect(true);
}
