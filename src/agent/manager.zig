const std = @import("std");
const json = std.json;
const mem = std.mem;
const fs = std.fs;
const process = std.process;

pub const Agent = struct {
    name: []const u8,
    model: []const u8 = "claude-opus-4-6",
    role: []const u8 = "coding",
    instructions: []const u8 = "",
    velocity: f64 = 1.0,
    provider: []const u8 = "anthropic",
    base_url: []const u8 = "",

    pub fn deinit(self: *Agent, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.model);
        allocator.free(self.role);
        if (self.instructions.len > 0) allocator.free(self.instructions);
        allocator.free(self.provider);
        if (self.base_url.len > 0) allocator.free(self.base_url);
    }
};

pub const AgentManager = struct {
    allocator: std.mem.Allocator,
    agents: std.StringHashMap(Agent),
    default_agent: ?[]const u8,
    config_path: []const u8,

    pub fn init(allocator: std.mem.Allocator) !AgentManager {
        var manager = AgentManager{
            .allocator = allocator,
            .agents = std.StringHashMap(Agent).init(allocator),
            .default_agent = null,
            .config_path = "",
        };
        manager.config_path = try getConfigPath(allocator);
        return manager;
    }

    pub fn deinit(self: *AgentManager) void {
        var it = self.agents.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.agents.deinit();
        if (self.default_agent) |agent| self.allocator.free(agent);
        self.allocator.free(self.config_path);
    }

    pub fn load(self: *AgentManager) !void {
        const file = fs.cwd().openFile(self.config_path, .{}) catch |err| {
            if (err == error.FileNotFound) {
                try self.createDefaultAgents();
                try self.save();
                return;
            }
            return err;
        };
        defer file.close();
        const content = try file.readToEndAlloc(self.allocator, 1024 * 1024);
        defer self.allocator.free(content);
        try self.parseFromJson(content);
    }

    pub fn save(self: *AgentManager) !void {
        if (mem.lastIndexOf(u8, self.config_path, "/")) |idx| {
            const dir_path = self.config_path[0..idx];
            if (dir_path.len > 0) try fs.cwd().makePath(dir_path);
        }
        const file = try fs.cwd().createFile(self.config_path, .{});
        defer file.close();
        try file.writeAll("{\n  \"agents\": [\n");
        var it = self.agents.iterator();
        var first = true;
        while (it.next()) |entry| {
            if (!first) try file.writeAll(",\n");
            first = false;
            const agent = entry.value_ptr.*;
            try file.writeAll("    {\"name\":\"");
            try escapeJsonStringDirect(agent.name, file);
            try file.writeAll("\",\"model\":\"");
            try escapeJsonStringDirect(agent.model, file);
            try file.writeAll("\",\"role\":\"");
            try escapeJsonStringDirect(agent.role, file);
            try file.writeAll("\",\"instructions\":\"");
            try escapeJsonStringDirect(agent.instructions, file);
            try file.writeAll("\",\"velocity\":");
            var buf: [64]u8 = undefined;
            const s = try std.fmt.bufPrint(&buf, "{d}", .{agent.velocity});
            try file.writeAll(s);
            try file.writeAll(",\"provider\":\"");
            try escapeJsonStringDirect(agent.provider, file);
            try file.writeAll("\",\"base_url\":\"");
            try escapeJsonStringDirect(agent.base_url, file);
            try file.writeAll("\"}");
        }
        try file.writeAll("\n  ],\n  \"default_agent\":");
        if (self.default_agent) |agent| {
            try file.writeAll("\"");
            try escapeJsonStringDirect(agent, file);
            try file.writeAll("\"");
        } else {
            try file.writeAll("null");
        }
        try file.writeAll("\n}\n");
    }

    pub fn createDefaultAgents(self: *AgentManager) !void {
        try self.addAgent(.{ .name = "hephaestus", .model = "claude-opus-4-6", .role = "senior_engineer", .instructions = "You are a senior staff engineer.", .velocity = 2.0 });
        try self.addAgent(.{ .name = "artistry", .model = "claude-3-5-sonnet-20241022", .role = "creative", .instructions = "You are a creative problem solver.", .velocity = 1.2 });
        try self.addAgent(.{ .name = "ultrabrain", .model = "claude-3-5-sonnet-20241022", .role = "analyst", .instructions = "You are a logic-heavy reasoning agent.", .velocity = 1.0 });
        try self.addAgent(.{ .name = "deep", .model = "claude-3-5-sonnet-20241022", .role = "researcher", .instructions = "You are a deep research agent.", .velocity = 0.6 });
        try self.addAgent(.{ .name = "local", .model = "Qwen3.5-4B-Q8_0.gguf", .role = "coding", .instructions = "You are a fast local assistant.", .velocity = 1.0, .provider = "openai_compat", .base_url = "http://127.0.0.1:8080/v1" });
    }

    pub fn addAgent(self: *AgentManager, agent: Agent) !void {
        const name = try self.allocator.dupe(u8, agent.name);
        errdefer self.allocator.free(name);
        const entry = try self.agents.getOrPut(name);
        if (entry.found_existing) {
            self.allocator.free(name);
            return error.AgentAlreadyExists;
        }
        entry.value_ptr.* = Agent{
            .name = name,
            .model = try self.allocator.dupe(u8, agent.model),
            .role = try self.allocator.dupe(u8, agent.role),
            .instructions = if (agent.instructions.len > 0)
                try self.allocator.dupe(u8, agent.instructions)
            else
                "",
            .velocity = agent.velocity,
            .provider = try self.allocator.dupe(u8, agent.provider),
            .base_url = if (agent.base_url.len > 0)
                try self.allocator.dupe(u8, agent.base_url)
            else
                "",
        };
    }

    pub fn removeAgent(self: *AgentManager, name: []const u8) !void {
        var entry = self.agents.fetchRemove(name);
        if (entry == null) return error.AgentNotFound;
        entry.?.value.deinit(self.allocator);
    }

    pub fn getAgent(self: *AgentManager, name: []const u8) ?Agent {
        return self.agents.get(name);
    }

    pub fn listAgents(self: *const AgentManager) std.StringHashMap(Agent).Iterator {
        return self.agents.iterator();
    }

    pub fn getDefaultAgent(self: *const AgentManager) []const u8 {
        return self.default_agent orelse "hephaestus";
    }

    pub fn setDefaultAgent(self: *AgentManager, name: []const u8) !void {
        if (self.agents.get(name) == null) return error.AgentNotFound;
        if (self.default_agent) |current| self.allocator.free(current);
        self.default_agent = try self.allocator.dupe(u8, name);
    }

    fn parseFromJson(self: *AgentManager, content: []const u8) !void {
        const parsed = try json.parseFromSlice(json.Value, self.allocator, content, .{});
        defer parsed.deinit();
        if (parsed.value != .object) return error.InvalidJson;
        const obj = parsed.value.object;
        if (obj.get("default_agent")) |val| {
            if (val == .string and val.string.len > 0) {
                self.default_agent = try self.allocator.dupe(u8, val.string);
            }
        }
        if (obj.get("agents")) |val| {
            if (val == .array) {
                for (val.array.items) |agent_val| {
                    if (agent_val == .object) {
                        const agent_obj = agent_val.object;
                        const name = parseStringField(agent_obj, "name") orelse continue;
                        const model = parseStringField(agent_obj, "model") orelse "claude-opus-4-6";
                        const role = parseStringField(agent_obj, "role") orelse "coding";
                        const instructions = parseStringField(agent_obj, "instructions") orelse "";
                        const velocity = parseFloatField(agent_obj, "velocity", 1.0);
                        const provider = parseStringField(agent_obj, "provider") orelse "anthropic";
                        const base_url = parseStringField(agent_obj, "base_url") orelse "";
                        try self.addAgent(.{ .name = name, .model = model, .role = role, .instructions = instructions, .velocity = velocity, .provider = provider, .base_url = base_url });
                    }
                }
            }
        }
    }
};

fn parseStringField(obj: std.json.ObjectMap, field: []const u8) ?[]const u8 {
    if (obj.get(field)) |val| {
        if (val == .string) return val.string;
    }
    return null;
}

fn parseFloatField(obj: std.json.ObjectMap, field: []const u8, default_val: f64) f64 {
    if (obj.get(field)) |val| {
        if (val == .float) return val.float;
        if (val == .integer) return @floatFromInt(val.integer);
    }
    return default_val;
}

fn getConfigPath(allocator: std.mem.Allocator) ![]const u8 {
    const home = try process.getEnvVarOwned(allocator, "HOME");
    defer allocator.free(home);
    return try std.fmt.allocPrint(allocator, "{s}/.config/powerglide/agents.json", .{home});
}

fn escapeJsonString(allocator: std.mem.Allocator, src: []const u8, buf: *std.ArrayList(u8)) !void {
    for (src) |c| {
        switch (c) {
            '"' => try buf.appendSlice(allocator, "\\\""),
            '\\' => try buf.appendSlice(allocator, "\\\\"),
            '\n' => try buf.appendSlice(allocator, "\\n"),
            '\r' => try buf.appendSlice(allocator, "\\r"),
            '\t' => try buf.appendSlice(allocator, "\\t"),
            else => try buf.append(allocator, c),
        }
    }
}

fn escapeJsonStringDirect(src: []const u8, file: fs.File) !void {
    for (src) |c| {
        switch (c) {
            '"' => try file.writeAll("\\\""),
            '\\' => try file.writeAll("\\\\"),
            '\n' => try file.writeAll("\\n"),
            '\r' => try file.writeAll("\\r"),
            '\t' => try file.writeAll("\\t"),
            else => try file.writeAll(&[1]u8{c}),
        }
    }
}

test "AgentManager basic operations" {
    const allocator = std.testing.allocator;
    var manager = try AgentManager.init(allocator);
    defer manager.deinit();
    try manager.createDefaultAgents();
    try std.testing.expect(manager.agents.count() >= 1);
    const agent = manager.getAgent("hephaestus");
    try std.testing.expect(agent != null);
}

test "AgentManager add and remove" {
    const allocator = std.testing.allocator;
    var manager = try AgentManager.init(allocator);
    defer manager.deinit();
    try manager.addAgent(.{ .name = "test_agent", .model = "claude-3-5-sonnet-20241022", .role = "tester", .instructions = "Test", .velocity = 1.0 });
    const agent = manager.getAgent("test_agent");
    try std.testing.expect(agent != null);
    try manager.removeAgent("test_agent");
    try std.testing.expect(manager.getAgent("test_agent") == null);
}
