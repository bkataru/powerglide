const std = @import("std");
const json = std.json;
const mem = std.mem;
const fs = std.fs;
const process = std.process;

pub const SwarmDef = struct {
    name: []const u8,
    agents: std.ArrayList([]const u8),
    working_dir: []const u8,
    max_workers: u32 = 8,
    heartbeat_timeout_ms: u64 = 60_000,
    poll_interval_ms: u64 = 5_000,
    default_agent: []const u8 = "hephaestus",

    pub fn deinit(self: *SwarmDef, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.working_dir);
        allocator.free(self.default_agent);
        for (self.agents.items) |agent| {
            allocator.free(agent);
        }
        self.agents.deinit(allocator);
    }
};

pub const SwarmManager = struct {
    allocator: std.mem.Allocator,
    swarms: std.StringHashMap(SwarmDef),
    config_path: []const u8,

    pub fn init(allocator: std.mem.Allocator) !SwarmManager {
        var manager = SwarmManager{
            .allocator = allocator,
            .swarms = std.StringHashMap(SwarmDef).init(allocator),
            .config_path = "",
        };
        manager.config_path = try getConfigPath(allocator);
        return manager;
    }

    pub fn deinit(self: *SwarmManager) void {
        var it = self.swarms.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.swarms.deinit();
        self.allocator.free(self.config_path);
    }

    pub fn load(self: *SwarmManager) !void {
        const file = fs.cwd().openFile(self.config_path, .{}) catch |err| {
            if (err == error.FileNotFound) {
                return; // No swarms yet
            }
            return err;
        };
        defer file.close();
        const content = try file.readToEndAlloc(self.allocator, 1024 * 1024);
        defer self.allocator.free(content);
        try self.parseFromJson(content);
    }

    pub fn save(self: *SwarmManager) !void {
        if (mem.lastIndexOf(u8, self.config_path, "/")) |idx| {
            const dir_path = self.config_path[0..idx];
            if (dir_path.len > 0) try fs.cwd().makePath(dir_path);
        }
        const file = try fs.cwd().createFile(self.config_path, .{});
        defer file.close();
        try file.writeAll("{\n  \"swarms\": [\n");
        var it = self.swarms.iterator();
        var first = true;
        while (it.next()) |entry| {
            if (!first) try file.writeAll(",\n");
            first = false;
            const swarm = entry.value_ptr.*;
            try file.writeAll("    {\"name\":\"");
            try escapeJsonStringDirect(swarm.name, file);
            try file.writeAll("\",\"working_dir\":\"");
            try escapeJsonStringDirect(swarm.working_dir, file);
            try file.writeAll("\",\"max_workers\":");
            var buf: [32]u8 = undefined;
            const s = try std.fmt.bufPrint(&buf, "{d}", .{swarm.max_workers});
            try file.writeAll(s);
            try file.writeAll(",\"default_agent\":\"");
            try escapeJsonStringDirect(swarm.default_agent, file);
            try file.writeAll("\",\"agents\":[");
            for (swarm.agents.items, 0..) |agent, i| {
                if (i > 0) try file.writeAll(",");
                try file.writeAll("\"");
                try escapeJsonStringDirect(agent, file);
                try file.writeAll("\"");
            }
            try file.writeAll("]}");
        }
        try file.writeAll("\n  ]\n}\n");
    }

    pub fn createSwarm(self: *SwarmManager, name: []const u8, working_dir: []const u8) !void {
        const name_duped = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(name_duped);
        const wd_duped = try self.allocator.dupe(u8, working_dir);
        errdefer self.allocator.free(wd_duped);

        const entry = try self.swarms.getOrPut(name_duped);
        if (entry.found_existing) {
            self.allocator.free(name_duped);
            self.allocator.free(wd_duped);
            return error.SwarmAlreadyExists;
        }

        // Create with empty ArrayList
        const duped_default_agent = try self.allocator.dupe(u8, "hephaestus");
        
        entry.value_ptr.* = SwarmDef{
            .name = name_duped,
            .working_dir = wd_duped,
            .agents = std.ArrayList([]const u8){},
            .default_agent = duped_default_agent,
        };
    }

    pub fn addAgent(self: *SwarmManager, swarm_name: []const u8, agent_name: []const u8) !void {
        const swarm = self.swarms.getPtr(swarm_name) orelse return error.SwarmNotFound;
        const agent_duped = try self.allocator.dupe(u8, agent_name);
        try swarm.agents.append(self.allocator, agent_duped);
    }

    pub fn removeAgent(self: *SwarmManager, swarm_name: []const u8, agent_name: []const u8) !void {
        const swarm = self.swarms.getPtr(swarm_name) orelse return error.SwarmNotFound;
        for (swarm.agents.items, 0..) |agent, i| {
            if (mem.eql(u8, agent, agent_name)) {
                self.allocator.free(swarm.agents.orderedRemove(i));
                return;
            }
        }
        return error.AgentNotFound;
    }

    pub fn deleteSwarm(self: *SwarmManager, name: []const u8) !void {
        var entry = self.swarms.fetchRemove(name) orelse return error.SwarmNotFound;
        entry.value.deinit(self.allocator);
    }

    pub fn getSwarm(self: *SwarmManager, name: []const u8) ?*const SwarmDef {
        return self.swarms.getPtr(name);
    }

    pub fn listSwarms(self: *const SwarmManager) std.StringHashMap(SwarmDef).Iterator {
        return self.swarms.iterator();
    }

    fn parseFromJson(self: *SwarmManager, content: []const u8) !void {
        const parsed = try json.parseFromSlice(json.Value, self.allocator, content, .{});
        defer parsed.deinit();
        if (parsed.value != .object) return error.InvalidJson;
        const obj = parsed.value.object;
        if (obj.get("swarms")) |val| {
            if (val == .array) {
                for (val.array.items) |swarm_val| {
                    if (swarm_val == .object) {
                        const swarm_obj = swarm_val.object;
                        const name = parseStringField(swarm_obj, "name") orelse continue;
                        const working_dir = parseStringField(swarm_obj, "working_dir") orelse continue;
                        const default_agent = parseStringField(swarm_obj, "default_agent") orelse "hephaestus";
                        const max_workers = parseUintField(swarm_obj, "max_workers", 8);

                        try self.createSwarm(name, working_dir);
                        const swarm = self.swarms.getPtr(name).?;

                        // Update fields
                        self.allocator.free(swarm.default_agent);
                        swarm.default_agent = try self.allocator.dupe(u8, default_agent);
                        swarm.max_workers = max_workers;

                        // Add agents
                        if (swarm_obj.get("agents")) |agents_val| {
                            if (agents_val == .array) {
                                for (agents_val.array.items) |agent_val| {
                                    if (agent_val == .string) {
                                        self.addAgent(name, agent_val.string) catch {};
                                    }
                                }
                            }
                        }
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

fn parseUintField(obj: std.json.ObjectMap, field: []const u8, default_val: u32) u32 {
    if (obj.get(field)) |val| {
        if (val == .integer) return @intCast(val.integer);
    }
    return default_val;
}

fn getConfigPath(allocator: std.mem.Allocator) ![]const u8 {
    const home = try process.getEnvVarOwned(allocator, "HOME");
    defer allocator.free(home);
    return try std.fmt.allocPrint(allocator, "{s}/.config/powerglide/swarms.json", .{home});
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

test "SwarmManager basic operations" {
    const allocator = std.testing.allocator;
    var manager = try SwarmManager.init(allocator);
    defer manager.deinit();

    try manager.createSwarm("test-swarm", "/tmp/test");
    try std.testing.expect(manager.swarms.count() == 1);

    try manager.addAgent("test-swarm", "hephaestus");
    try manager.addAgent("test-swarm", "artistry");

    const swarm = manager.getSwarm("test-swarm");
    try std.testing.expect(swarm != null);
    try std.testing.expect(swarm.?.agents.items.len == 2);

    try manager.removeAgent("test-swarm", "hephaestus");
    try std.testing.expect(swarm.?.agents.items.len == 1);

    try manager.deleteSwarm("test-swarm");
    try std.testing.expect(manager.swarms.count() == 0);
}
