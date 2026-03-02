const std = @import("std");

pub const MemoryStore = struct {
    allocator: std.mem.Allocator,
    entries: std.StringHashMap(MemoryEntry),

    pub const MemoryEntry = struct {
        key: []const u8,
        value: []const u8,
        timestamp: i64,
    };

    pub fn init(allocator: std.mem.Allocator) MemoryStore {
        return .{
            .allocator = allocator,
            .entries = std.StringHashMap(MemoryEntry).init(allocator),
        };
    }

    pub fn deinit(self: *MemoryStore) void {
        self.entries.deinit();
    }

    pub fn set(self: *MemoryStore, key: []const u8, value: []const u8) !void {
        _ = self;
        _ = key;
        _ = value;
    }

    pub fn get(self: *MemoryStore, key: []const u8) ?[]const u8 {
        _ = self;
        _ = key;
        return null;
    }
};

test "placeholder" {
    try std.testing.expect(true);
}
