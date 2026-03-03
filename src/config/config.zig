const std = @import("std");
const json = std.json;
const mem = std.mem;
const process = std.process;

/// Configuration for powerglide
pub const Config = struct {
    // Model settings
    model: []const u8 = "claude-opus-4-6",
    api_key: ?[]const u8 = null,
    api_base_url: []const u8 = "https://api.anthropic.com",

    // Loop/Velocity settings
    max_steps: u32 = 200,
    velocity_ms: u64 = 500,
    think_budget_ms: u64 = 120_000,

    // Terminal settings
    shell: []const u8 = "/bin/bash",
    terminal_pool_size: usize = 4,

    // Swarm settings
    max_agents: u32 = 8,
    agent_heartbeat_ms: u64 = 30_000,

    /// Get default configuration
    pub fn default() Config {
        return .{};
    }

    /// Load configuration from a JSON file
    pub fn fromFile(allocator: std.mem.Allocator, path: []const u8) !Config {
        const file = std.fs.cwd().openFile(path, .{}) catch |err| {
            if (err == error.FileNotFound) {
                return Config.default();
            }
            return err;
        };
        defer file.close();

        const content = try file.readToEndAlloc(allocator, 4096);
        defer allocator.free(content);

        return try parseConfig(allocator, content);
    }

    /// Load configuration from environment variables
    pub fn fromEnv(allocator: std.mem.Allocator) !Config {
        var config = Config.default();

        // Load API key from environment
        if (process.getEnvVarOwned(allocator, "ANTHROPIC_API_KEY")) |api_key| {
            config.api_key = api_key;
        } else |_| {}

        if (process.getEnvVarOwned(allocator, "OPENAI_API_KEY")) |api_key| {
            if (config.api_key == null) {
                config.api_key = api_key;
            }
        } else |_| {}

        // Override with POWERGLIDE_ prefixed env vars
        if (process.getEnvVarOwned(allocator, "POWERGLIDE_MODEL")) |model| {
            config.model = model;
        } else |_| {}

        if (process.getEnvVarOwned(allocator, "POWERGLIDE_API_BASE_URL")) |base_url| {
            config.api_base_url = base_url;
        } else |_| {}

        if (process.getEnvVarOwned(allocator, "POWERGLIDE_MAX_STEPS")) |max_steps_str| {
            config.max_steps = try parseUint(u32, max_steps_str);
            allocator.free(max_steps_str);
        } else |_| {}

        if (process.getEnvVarOwned(allocator, "POWERGLIDE_VELOCITY_MS")) |velocity_str| {
            config.velocity_ms = try parseUint(u64, velocity_str);
            allocator.free(velocity_str);
        } else |_| {}

        if (process.getEnvVarOwned(allocator, "POWERGLIDE_SHELL")) |shell| {
            config.shell = shell;
        } else |_| {}

        if (process.getEnvVarOwned(allocator, "POWERGLIDE_MAX_AGENTS")) |max_agents_str| {
            config.max_agents = try parseUint(u32, max_agents_str);
            allocator.free(max_agents_str);
        } else |_| {}

        return config;
    }

    /// Merge two configs - other overrides self
    pub fn merge(self: Config, other: Config) Config {
        return .{
            .model = if (other.model.len > 0 and !mem.eql(u8, other.model, "claude-opus-4-6")) other.model else self.model,
            .api_key = other.api_key orelse self.api_key,
            .api_base_url = if (other.api_base_url.len > 0 and !mem.eql(u8, other.api_base_url, "https://api.anthropic.com")) other.api_base_url else self.api_base_url,
            .max_steps = if (other.max_steps != 200) other.max_steps else self.max_steps,
            .velocity_ms = if (other.velocity_ms != 500) other.velocity_ms else self.velocity_ms,
            .think_budget_ms = if (other.think_budget_ms != 120_000) other.think_budget_ms else self.think_budget_ms,
            .shell = if (other.shell.len > 0 and !mem.eql(u8, other.shell, "/bin/bash")) other.shell else self.shell,
            .terminal_pool_size = if (other.terminal_pool_size != 4) other.terminal_pool_size else self.terminal_pool_size,
            .max_agents = if (other.max_agents != 8) other.max_agents else self.max_agents,
            .agent_heartbeat_ms = if (other.agent_heartbeat_ms != 30_000) other.agent_heartbeat_ms else self.agent_heartbeat_ms,
        };
    }

/// Clean up config resources - only free allocated memory
pub fn deinit(self: *const Config, allocator: std.mem.Allocator) void {
    _ = self;
    _ = allocator;
    // Note: strings are string literals by default, freed automatically
    // Only api_key is dynamically allocated and needs freeing
    // Caller must track what was allocated
}

    /// Save config to a JSON file
    pub fn save(self: *const Config, allocator: std.mem.Allocator, path: []const u8) !void {
        // Ensure directory exists
        if (mem.lastIndexOf(u8, path, "/")) |idx| {
            const dir_path = path[0..idx];
            if (dir_path.len > 0) {
                try std.fs.cwd().makePath(dir_path);
            }
        }

        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();

        var buf = std.ArrayList(u8){};
        errdefer buf.deinit(allocator);

        try buf.appendSlice(allocator, "{");
        try buf.appendSlice(allocator, "\"model\":\"");
        try buf.appendSlice(allocator, self.model);
        try buf.appendSlice(allocator, ",\n");
        try buf.appendSlice(allocator, "\"api_base_url\":\"");
        try buf.appendSlice(allocator, self.api_base_url);
        try buf.appendSlice(allocator, ",\n");
        try buf.appendSlice(allocator, "\"max_steps\":");
        try buf.writer(allocator).print("{}", .{self.max_steps});
        try buf.appendSlice(allocator, ",\n");
        try buf.appendSlice(allocator, "\"velocity_ms\":");
        try buf.writer(allocator).print("{}", .{self.velocity_ms});
        try buf.appendSlice(allocator, ",\n");
        try buf.appendSlice(allocator, "\"think_budget_ms\":");
        try buf.writer(allocator).print("{}", .{self.think_budget_ms});
        try buf.appendSlice(allocator, ",\n");
        try buf.appendSlice(allocator, "\"shell\":\"");
        try buf.appendSlice(allocator, self.shell);
        try buf.appendSlice(allocator, ",\n");
        try buf.appendSlice(allocator, "\"terminal_pool_size\":");
        try buf.writer(allocator).print("{}", .{self.terminal_pool_size});
        try buf.appendSlice(allocator, ",\n");
        try buf.appendSlice(allocator, "\"max_agents\":");
        try buf.writer(allocator).print("{}", .{self.max_agents});
        try buf.appendSlice(allocator, ",\n");
        try buf.appendSlice(allocator, "\"agent_heartbeat_ms\":");
        try buf.writer(allocator).print("{}", .{self.agent_heartbeat_ms});
        try buf.appendSlice(allocator, "}");

        try file.writeAll(buf.items);
    }
};

/// Get the default config file path
pub fn defaultConfigPath(allocator: std.mem.Allocator) ![]const u8 {
    const home = try process.getEnvVarOwned(allocator, "HOME");
    defer allocator.free(home);

    const path = try std.fmt.allocPrint(allocator, "{s}/.config/powerglide/config.json", .{home});
    return path;
}

/// Parse configuration from JSON content
fn parseConfig(allocator: std.mem.Allocator, content: []const u8) !Config {
    const parsed = try json.parseFromSlice(json.Value, allocator, content, .{});
    defer parsed.deinit();

    if (parsed.value != .object) {
        return error.InvalidJson;
    }

    const obj = parsed.value.object;

    var config = Config.default();

    // Parse model
    if (obj.get("model")) |val| {
        if (val == .string) {
            config.model = try allocator.dupe(u8, val.string);
        }
    }

    // Parse api_key
    if (obj.get("api_key")) |val| {
        if (val == .string and val.string.len > 0) {
            config.api_key = try allocator.dupe(u8, val.string);
        }
    }

    // Parse api_base_url
    if (obj.get("api_base_url")) |val| {
        if (val == .string) {
            config.api_base_url = try allocator.dupe(u8, val.string);
        }
    }

    // Parse max_steps
    if (obj.get("max_steps")) |val| {
        if (val == .integer) {
            config.max_steps = @intCast(val.integer);
        }
    }

    // Parse velocity_ms
    if (obj.get("velocity_ms")) |val| {
        if (val == .integer) {
            config.velocity_ms = @intCast(val.integer);
        }
    }

    // Parse think_budget_ms
    if (obj.get("think_budget_ms")) |val| {
        if (val == .integer) {
            config.think_budget_ms = @intCast(val.integer);
        }
    }

    // Parse shell
    if (obj.get("shell")) |val| {
        if (val == .string) {
            config.shell = try allocator.dupe(u8, val.string);
        }
    }

    // Parse terminal_pool_size
    if (obj.get("terminal_pool_size")) |val| {
        if (val == .integer) {
            config.terminal_pool_size = @intCast(val.integer);
        }
    }

    // Parse max_agents
    if (obj.get("max_agents")) |val| {
        if (val == .integer) {
            config.max_agents = @intCast(val.integer);
        }
    }

    // Parse agent_heartbeat_ms
    if (obj.get("agent_heartbeat_ms")) |val| {
        if (val == .integer) {
            config.agent_heartbeat_ms = @intCast(val.integer);
        }
    }

    return config;
}

/// Parse a unsigned integer from a string
fn parseUint(comptime T: type, str: []const u8) !T {
    var value: T = 0;
    for (str) |c| {
        if (c < '0' or c > '9') {
            return error.InvalidNumber;
        }
        value = value * 10 + (c - '0');
    }
    return value;
}

/// Load configuration with full precedence chain:
/// 1. Default config
/// 2. Config file (~/.config/powerglide/config.json)
/// 3. Environment variables
pub fn load(allocator: std.mem.Allocator) !Config {
    var config = Config.default();

    // Load from file
    const config_path = try defaultConfigPath(allocator);
    defer allocator.free(config_path);

const file_config = Config.fromFile(allocator, config_path) catch |err| {
            if (err != error.FileNotFound) {
                std.debug.print("Warning: Failed to load config from {s}: {}\n", .{ config_path, err });
            }
            return Config.default();
        };

    config = config.merge(file_config);

    // Load from environment (overrides file)
    const env_config = try Config.fromEnv(allocator);
    config = config.merge(env_config);

    return config;
}

test "Config default values" {
    const config = Config.default();

    try std.testing.expect(mem.eql(u8, config.model, "claude-opus-4-6"));
    try std.testing.expect(config.api_key == null);
    try std.testing.expect(config.max_steps == 200);
    try std.testing.expect(config.velocity_ms == 500);
    try std.testing.expect(config.terminal_pool_size == 4);
    try std.testing.expect(config.max_agents == 8);
}

test "Config merge" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const base = Config.default();
    const override = Config{
        .model = "claude-sonnet-4",
        .max_steps = 100,
        .api_key = try allocator.dupe(u8, "test-key"),
    };

    var merged = base.merge(override);
    defer merged.deinit(allocator);

    try std.testing.expect(mem.eql(u8, merged.model, "claude-sonnet-4"));
    try std.testing.expect(merged.max_steps == 100);
    // velocity_ms should remain default (not in override)
    try std.testing.expect(merged.velocity_ms == 500);
}

test "Config from JSON file" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const json_content =
        \\{
        \\ "model": "claude-3-5-sonnet",
        \\ "max_steps": 150,
        \\ "velocity_ms": 1000
        \\}
    ;

    const config = try parseConfig(allocator, json_content);

    try std.testing.expect(mem.eql(u8, config.model, "claude-3-5-sonnet"));
    try std.testing.expect(config.max_steps == 150);
    try std.testing.expect(config.velocity_ms == 1000);
}
