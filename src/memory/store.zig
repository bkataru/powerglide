const std = @import("std");

/// Memory entry with id, timestamp, content, tags, and optional embedding
pub const MemoryEntry = struct {
    id: u64,
    timestamp: i64,
    content: []const u8,
    tags: []const []const u8,
    embedding: ?[]const f32,

    pub fn deinit(self: *MemoryEntry, allocator: std.mem.Allocator) void {
        allocator.free(self.content);
        for (self.tags) |tag| {
            allocator.free(tag);
        }
        allocator.free(self.tags);
        if (self.embedding) |emb| {
            allocator.free(emb);
        }
    }
};

/// Persistent store for agent memory
pub const MemoryStore = struct {
    allocator: std.mem.Allocator,
    store_path: []const u8,
    entries: std.ArrayList(MemoryEntry),
    next_id: u64,

    /// Initialize a new MemoryStore
    pub fn init(allocator: std.mem.Allocator, store_path: []const u8) !MemoryStore {
        var store = MemoryStore{
            .allocator = allocator,
            .store_path = store_path,
            .entries = std.ArrayList(MemoryEntry){},
            .next_id = 1,
        };
        // Load existing entries from disk
        try store.load();
        return store;
    }

    /// Free all memory
    pub fn deinit(self: *MemoryStore) void {
        for (self.entries.items) |*entry| {
            entry.deinit(self.allocator);
        }
        self.entries.deinit(self.allocator);
    }

    /// Load existing entries from disk
    pub fn load(self: *MemoryStore) !void {
        const file = std.fs.cwd().openFile(self.store_path, .{}) catch {
            // File doesn't exist yet, that's OK
            return;
        };
        defer file.close();

        const file_content = file.readToEndAlloc(self.allocator, 10 * 1024 * 1024) catch return;
        defer self.allocator.free(file_content);
        var line_it = std.mem.splitScalar(u8, file_content, '\n');
        while (line_it.next()) |line| {
            if (line.len == 0) continue;

            // Parse JSON line
            const MemoryEntryJson = struct {
                id: u64,
                timestamp: i64,
                content: []const u8,
                tags: []const []const u8,
            };

            const parsed = try std.json.parseFromSlice(MemoryEntryJson, self.allocator, line, .{
                .ignore_unknown_fields = true,
            });
            defer parsed.deinit();

            const json_entry = parsed.value;
            const content = try self.allocator.dupe(u8, json_entry.content);
            const tags = try self.allocator.alloc([]const u8, json_entry.tags.len);
            for (json_entry.tags, 0..) |tag, i| {
                tags[i] = try self.allocator.dupe(u8, tag);
            }

            const entry = MemoryEntry{
                .id = json_entry.id,
                .timestamp = json_entry.timestamp,
                .content = content,
                .tags = tags,
                .embedding = null,
            };

            try self.entries.append(self.allocator, entry);

            // Update next_id to be greater than any existing id
            if (json_entry.id >= self.next_id) {
                self.next_id = json_entry.id + 1;
            }
        }
    }

    /// Append a new memory entry
    pub fn append(self: *MemoryStore, content: []const u8, tags: []const []const u8) !u64 {
        const id = self.next_id;
        self.next_id += 1;

        const owned_content = try self.allocator.dupe(u8, content);
        const owned_tags = try self.allocator.alloc([]const u8, tags.len);
        for (tags, 0..) |tag, i| {
            owned_tags[i] = try self.allocator.dupe(u8, tag);
        }

        const entry = MemoryEntry{
            .id = id,
            .timestamp = std.time.timestamp(),
            .content = owned_content,
            .tags = owned_tags,
            .embedding = null,
        };

        try self.entries.append(self.allocator, entry);

        // Persist to disk immediately
        try self.appendToFile(entry);

        return id;
    }

    /// Append a single entry to the JSONL file
    fn appendToFile(self: *const MemoryStore, entry: MemoryEntry) !void {
        // Ensure parent directory exists
        const parent_dir = std.fs.path.dirname(self.store_path);
        if (parent_dir) |dir| {
            if (std.fs.cwd().makeOpenPath(dir, .{})) |d| {
                var mut_d = d;
                mut_d.close();
            } else |_| {}
        }

        // Open file in append mode
        const file = try std.fs.cwd().createFile(self.store_path, .{
            .truncate = false,
        });
        defer file.close();
        try file.seekFromEnd(0);

        var json_buffer = std.ArrayList(u8){};
        defer json_buffer.deinit(self.allocator);

        try self.writeEntryJson(&json_buffer, entry);
        try json_buffer.append(self.allocator, '\n');

        try file.writeAll(json_buffer.items);
    }

    fn writeEntryJson(self: *const MemoryStore, buffer: *std.ArrayList(u8), entry: MemoryEntry) !void {
        try buffer.append(self.allocator, '{');
        try buffer.writer(self.allocator).print("\"id\":{},\"timestamp\":{},", .{ entry.id, entry.timestamp });
        try buffer.appendSlice(self.allocator, "\"content\":\"");
        try escapeJsonString(self.allocator, buffer, entry.content);
        try buffer.appendSlice(self.allocator, "\",\"tags\":[");
        for (entry.tags, 0..) |tag, i| {
            if (i > 0) try buffer.append(self.allocator, ',');
            try buffer.append(self.allocator, '"');
            try escapeJsonString(self.allocator, buffer, tag);
            try buffer.append(self.allocator, '"');
        }
        try buffer.appendSlice(self.allocator, "]}");
    }

    fn escapeJsonString(allocator: std.mem.Allocator, buffer: *std.ArrayList(u8), text: []const u8) !void {
        for (text) |c| {
            switch (c) {
                '"' => try buffer.appendSlice(allocator, "\\\""),
                '\\' => try buffer.appendSlice(allocator, "\\\\"),
                '\n' => try buffer.appendSlice(allocator, "\\n"),
                '\r' => try buffer.appendSlice(allocator, "\\r"),
                '\t' => try buffer.appendSlice(allocator, "\\t"),
                else => try buffer.append(allocator, c),
            }
        }
    }

    /// Search entries by tag
    pub fn searchByTag(self: *const MemoryStore, allocator: std.mem.Allocator, tag: []const u8) ![]const MemoryEntry {
        var results = std.ArrayList(MemoryEntry){};
        for (self.entries.items) |entry| {
            for (entry.tags) |t| {
                if (std.mem.eql(u8, t, tag)) {
                    try results.append(allocator, entry);
                    break;
                }
            }
        }
        return results.toOwnedSlice(allocator);
    }

    /// Search entries by keyword in content
    pub fn searchByKeyword(self: *const MemoryStore, allocator: std.mem.Allocator, keyword: []const u8) ![]const MemoryEntry {
        var results = std.ArrayList(MemoryEntry){};
        for (self.entries.items) |entry| {
            if (std.mem.indexOf(u8, entry.content, keyword) != null) {
                try results.append(allocator, entry);
            }
        }
        return results.toOwnedSlice(allocator);
    }

    /// Get recent memories
    pub fn recent(self: *const MemoryStore, allocator: std.mem.Allocator, n: usize) ![]const MemoryEntry {
        var results = std.ArrayList(MemoryEntry){};
        const start = if (self.entries.items.len > n) self.entries.items.len - n else 0;
        for (self.entries.items[start..]) |entry| {
            try results.append(allocator, entry);
        }
        return results.toOwnedSlice(allocator);
    }
};

test "MemoryEntry deinit frees resources" {
    const allocator = std.testing.allocator;
    
    const tags_alloc = try allocator.alloc([]const u8, 2);
    tags_alloc[0] = try allocator.dupe(u8, "tag1");
    tags_alloc[1] = try allocator.dupe(u8, "tag2");

    var entry = MemoryEntry{
        .id = 1,
        .timestamp = 0,
        .content = try allocator.dupe(u8, "test content"),
        .tags = tags_alloc,
        .embedding = null,
    };
    
    entry.deinit(allocator); // Should not leak
}

test "MemoryStore append and search" {
    const allocator = std.testing.allocator;
    const tmp_file = "/tmp/test_memory_store.jsonl";
    std.fs.cwd().deleteFile(tmp_file) catch {};
    
    var store = try MemoryStore.init(allocator, tmp_file);
    defer store.deinit();
    
    const id = try store.append("hello world", &[_][]const u8{"greeting"});
    try std.testing.expect(id == 1);
    try std.testing.expect(store.entries.items.len == 1);
    
    const results = try store.searchByTag(allocator, "greeting");
    defer allocator.free(results);
    try std.testing.expect(results.len == 1);
    try std.testing.expect(std.mem.eql(u8, results[0].content, "hello world"));
}

test "MemoryStore persistence" {
    const allocator = std.testing.allocator;
    const tmp_file = "/tmp/test_memory_store_persist.jsonl";
    std.fs.cwd().deleteFile(tmp_file) catch {};
    
    {
        var store = try MemoryStore.init(allocator, tmp_file);
        _ = try store.append("first entry", &[_][]const u8{"a"});
        _ = try store.append("second entry", &[_][]const u8{"b"});
        store.deinit();
    }
    
    {
        var store = try MemoryStore.init(allocator, tmp_file);
        defer store.deinit();
        try std.testing.expect(store.entries.items.len == 2);
        try std.testing.expect(std.mem.eql(u8, store.entries.items[0].content, "first entry"));
        try std.testing.expect(std.mem.eql(u8, store.entries.items[1].content, "second entry"));
    }
}

test "MemoryStore deinit frees all entries" {
    const allocator = std.testing.allocator;
    const tmp_file = "/tmp/test_memory_store_leak.jsonl";
    std.fs.cwd().deleteFile(tmp_file) catch {};
    
    var store = try MemoryStore.init(allocator, tmp_file);
    
    for (0..10) |_| {
        _ = try store.append("entry", &[_][]const u8{"tag"});
    }
    
    store.deinit(); // Should not leak
}
