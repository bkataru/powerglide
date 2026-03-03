const std = @import("std");
const fs = std.fs;
const mem = std.mem;
const process = std.process;
const session_mod = @import("session.zig");
const Session = session_mod.Session;

pub const PersistenceManager = struct {
    allocator: std.mem.Allocator,
    sessions_dir: []const u8,

    pub fn init(allocator: std.mem.Allocator) !PersistenceManager {
        const home = try process.getEnvVarOwned(allocator, "HOME");
        defer allocator.free(home);
        const sessions_dir = try std.fmt.allocPrint(allocator, "{s}/.config/powerglide/sessions", .{home});
        
        // Ensure directory exists
        try fs.cwd().makePath(sessions_dir);
        
        return .{
            .allocator = allocator,
            .sessions_dir = sessions_dir,
        };
    }

    pub fn deinit(self: *PersistenceManager) void {
        self.allocator.free(self.sessions_dir);
    }

    pub fn getSessionPath(self: *const PersistenceManager, allocator: std.mem.Allocator, id: []const u8) ![]const u8 {
        return try std.fmt.allocPrint(allocator, "{s}/{s}.json", .{ self.sessions_dir, id });
    }

    pub fn saveSession(self: *const PersistenceManager, session: *const Session) !void {
        const path = try self.getSessionPath(self.allocator, session.id);
        defer self.allocator.free(path);
        try session.save(self.allocator, path);
    }

    pub fn loadSession(self: *const PersistenceManager, id: []const u8) !Session {
        const path = try self.getSessionPath(self.allocator, id);
        defer self.allocator.free(path);
        return try Session.load(self.allocator, path);
    }

    pub fn listSessions(self: *const PersistenceManager, allocator: std.mem.Allocator) ![]const []const u8 {
        var list = std.ArrayList([]const u8){};
        errdefer {
            for (list.items) |item| allocator.free(item);
            list.deinit(allocator);
        }

        var dir = try fs.cwd().openDir(self.sessions_dir, .{ .iterate = true });
        defer dir.close();

        var it = dir.iterate();
        while (try it.next()) |entry| {
            if (entry.kind == .file and mem.endsWith(u8, entry.name, ".json")) {
                const id = entry.name[0 .. entry.name.len - 5];
                try list.append(allocator, try allocator.dupe(u8, id));
            }
        }

        return list.toOwnedSlice(allocator);
    }

    pub fn deleteSession(self: *const PersistenceManager, id: []const u8) !void {
        const path = try self.getSessionPath(self.allocator, id);
        defer self.allocator.free(path);
        try fs.cwd().deleteFile(path);
}
};

