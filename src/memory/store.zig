const std = @import("std");

/// Memory entry with id, timestamp, content, tags, and optional embedding
pub const MemoryEntry = struct {
    id: u64,
    timestamp: i64,
    content: []const u8,
    tags: []const []const u8,
    embedding: ?[]f32 = null,

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

/// Simple file-based persistent memory store
/// Stores entries as JSONL (one JSON object per line) at store_path
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
            .entries = std.ArrayList(MemoryEntry).init(allocator),
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
        self.entries.deinit();
    }

    /// Load existing entries from disk
    pub fn load(self: *MemoryStore) !void {
        const file = std.fs.cwd().openFile(self.store_path, .{}) catch {
            // File doesn't exist yet, that's OK
            return;
        };
        defer file.close();

        var reader = std.io.bufferedReader(file.reader());
        var stream_reader = reader.reader();

        var buffer: [4096]u8 = undefined;
        while (stream_reader.readUntilDelimiterOrEof(&buffer, '\n') catch null) |line| {
            if (line.len == 0) continue;

            // Parse JSON line
            const parsed = try std.json.parseFromSlice(MemoryEntryJson, self.allocator, line, .{
                .ignore_unknown_fields = true,
            });
            defer parsed.deinit();

            const json_entry = parsed.value;

            // Copy strings from the JSON into owned memory
            const content = try self.allocator.dupe(u8, json_entry.content);
            var tags = try self.allocator.alloc([]const u8, json_entry.tags.len);
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

            try self.entries.append(entry);

            // Update next_id to be greater than any existing id
            if (json_entry.id >= self.next_id) {
                self.next_id = json_entry.id + 1;
            }
        }
    }

    /// Append a new entry and persist to disk immediately
    pub fn append(self: *MemoryStore, content: []const u8, tags: []const []const u8) !u64 {
        const id = self.next_id;
        self.next_id += 1;

        const timestamp = std.time.timestamp() * 1000; // milliseconds

        // Copy content and tags
        const owned_content = try self.allocator.dupe(u8, content);
        var owned_tags = try self.allocator.alloc([]const u8, tags.len);
        for (tags, 0..) |tag, i| {
            owned_tags[i] = try self.allocator.dupe(u8, tag);
        }

        const entry = MemoryEntry{
            .id = id,
            .timestamp = timestamp,
            .content = owned_content,
            .tags = owned_tags,
            .embedding = null,
        };

        try self.entries.append(entry);

        // Persist to disk immediately
        try self.appendToFile(entry);

        return id;
    }

    /// Append a single entry to the JSONL file
    fn appendToFile(self: *const MemoryStore, entry: MemoryEntry) !void {
        // Ensure parent directory exists
        const parent_dir = std.fs.path.dirname(self.store_path);
        if (parent_dir) |dir| {
            try std.fs.cwd().makeOpenPath(dir, .{}) catch {
                // Directory might already exist
            };
        }

        // Open file in append mode
        const file = try std.fs.cwd().openFile(self.store_path, .{
            .mode = .write_only,
        });
        defer file.close();

        // Seek to end for append
        try file.seekTo(try file.getEndPos());

        // Build JSON
        var json_buffer = std.ArrayList(u8).init(self.allocator);
        defer json_buffer.deinit();

        try self.writeEntryJson(&json_buffer, entry);
        try json_buffer.append('\n');
        try file.writeAll(json_buffer.items);
    }

    /// Write entry as JSON to the buffer
    fn writeEntryJson(self: *const MemoryStore, buffer: *std.ArrayList(u8), entry: MemoryEntry) !void {
        try buffer.append('{');
        try buffer.writer().print("\"id\":{},\"timestamp\":{},", .{ entry.id, entry.timestamp });

        // Content (escaped)
        try buffer.appendSlice("\"content\":\"");
        try self.escapeJsonString(buffer, entry.content);
        try buffer.appendSlice("\",\"tags\":[");

        // Tags
        for (entry.tags, 0..) |tag, i| {
            if (i > 0) try buffer.append(',');
            try buffer.append('"');
            try self.escapeJsonString(buffer, tag);
            try buffer.append('"');
        }

        try buffer.append(']');
        try buffer.append('}');
    }

    /// Escape special characters for JSON string
    fn escapeJsonString(buffer: *std.ArrayList(u8), text: []const u8) !void {
        for (text) |c| {
            switch (c) {
                '"' => try buffer.appendSlice("\\\""),
                '\\' => try buffer.appendSlice("\\\\"),
                '\n' => try buffer.appendSlice("\\n"),
                '\r' => try buffer.appendSlice("\\r"),
                '\t' => try buffer.appendSlice("\\t"),
                else => try buffer.append(c),
            }
        }
    }

    /// Search entries by tag (e.g. "project:powerglide")
    pub fn searchByTag(self: *const MemoryStore, allocator: std.mem.Allocator, tag: []const u8) ![]const MemoryEntry {
        var results = std.ArrayList(MemoryEntry).init(allocator);

        for (self.entries.items) |entry| {
            for (entry.tags) |entry_tag| {
                if (std.mem.eql(u8, entry_tag, tag)) {
                    try results.append(entry);
                    break;
                }
            }
        }

        return results.items;
    }

    /// Search entries by keyword (simple substring match in content)
    pub fn searchByKeyword(self: *const MemoryStore, allocator: std.mem.Allocator, keyword: []const u8) ![]const MemoryEntry {
        var results = std.ArrayList(MemoryEntry).init(allocator);

        for (self.entries.items) |entry| {
            if (std.mem.indexOf(u8, entry.content, keyword) != null) {
                try results.append(entry);
            }
        }

        return results.items;
    }

    /// Delete entry by ID
    pub fn delete(self: *MemoryStore, id: u64) !void {
        var found_index: ?usize = null;
        for (self.entries.items, 0..) |entry, i| {
            if (entry.id == id) {
                found_index = i;
                break;
            }
        }

        if (found_index) |idx| {
            // Free the entry's memory
            self.entries.items[idx].deinit(self.allocator);
            // Remove from list
            _ = self.entries.orderedRemove(idx);
            // Rewrite the file
            try self.flush();
        }
    }

    /// Rewrite entire store to disk (after deletion)
    pub fn flush(self: *MemoryStore) !void {
        // Create/truncate the file
        const file = try std.fs.cwd().createFile(self.store_path, .{
            .truncate = true,
        });
        defer file.close();

        for (self.entries.items) |entry| {
            var json_buffer = std.ArrayList(u8).init(self.allocator);
            defer json_buffer.deinit();

            try self.writeEntryJson(&json_buffer, entry);
            try json_buffer.append('\n');
            try file.writeAll(json_buffer.items);
        }
    }

    /// Get last N entries
    pub fn recent(self: *const MemoryStore, allocator: std.mem.Allocator, n: usize) ![]const MemoryEntry {
        const count = @min(n, self.entries.items.len);
        if (count == 0) {
            return &([_]MemoryEntry{});
        }

        var results = std.ArrayList(MemoryEntry).init(allocator);
        errdefer results.deinit();

        // Get last n entries
        const start = self.entries.items.len - count;
        for (self.entries.items[start..]) |entry| {
            try results.append(entry);
        }

        return results.items;
    }
};

/// JSON structure for parsing (intermediate representation)
const MemoryEntryJson = struct {
    id: u64,
    timestamp: i64,
    content: []const u8,
    tags: []const []const u8,
};

test "MemoryStore initialization with new file" {
    const allocator = std.testing.allocator;
    const tmp_file = "/tmp/test_memory_store_1.jsonl";
    
    // Clean up if file exists from previous test run
    std.fs.cwd().deleteFile(tmp_file) catch |e| {
        if (e != error.FileNotFound) {
            return e;
        }
    };
    
    var store = try MemoryStore.init(allocator, tmp_file);
    defer store.deinit();
    
    try std.testing.expect(store.entries.items.len == 0);
    try std.testing.expect(store.next_id == 1);
    
    // Clean up test file
    std.fs.cwd().deleteFile(tmp_file) catch {};
}

test "MemoryStore append returns incrementing ids" {
    const allocator = std.testing.allocator;
    const tmp_file = "/tmp/test_memory_store_2.jsonl";
    
    std.fs.cwd().deleteFile(tmp_file) catch {};
    defer std.fs.cwd().deleteFile(tmp_file) catch {};
    
    var store = try MemoryStore.init(allocator, tmp_file);
    defer store.deinit();
    
    const id1 = try store.append("first entry", &[_][]const u8{"tag1"});
    const id2 = try store.append("second entry", &[_][]const u8{"tag2"});
    const id3 = try store.append("third entry", &[_][]const u8{"tag3"});
    
    try std.testing.expect(id1 == 1);
    try std.testing.expect(id2 == 2);
    try std.testing.expect(id3 == 3);
}

test "MemoryStore append persists to disk" {
    const allocator = std.testing.allocator;
    const tmp_file = "/tmp/test_memory_store_3.jsonl";
    
    std.fs.cwd().deleteFile(tmp_file) catch {};
    defer std.fs.cwd().deleteFile(tmp_file) catch {};
    
    {
        var store = try MemoryStore.init(allocator, tmp_file);
        defer store.deinit();
        _ = try store.append("persistent entry", &[_][]const u8{"test"});
    }
    
    // Reload and verify
    var store2 = try MemoryStore.init(allocator, tmp_file);
    defer store2.deinit();
    
    try std.testing.expect(store2.entries.items.len == 1);
    try std.testing.expect(std.mem.eql(u8, store2.entries.items[0].content, "persistent entry"));
    try std.testing.expect(store2.entries.items[0].tags.len == 1);
    try std.testing.expect(std.mem.eql(u8, store2.entries.items[0].tags[0], "test"));
}

test "MemoryStore load from existing file" {
    const allocator = std.testing.allocator;
    const tmp_file = "/tmp/test_memory_store_4.jsonl";
    
    std.fs.cwd().deleteFile(tmp_file) catch {};
    defer std.fs.cwd().deleteFile(tmp_file) catch {};
    
    // Create file with entries
    {
        var store = try MemoryStore.init(allocator, tmp_file);
        defer store.deinit();
        _ = try store.append("entry1", &[_][]const u8{"a"});
        _ = try store.append("entry2", &[_][]const u8{"b"});
    }
    
    // Reload
    var store2 = try MemoryStore.init(allocator, tmp_file);
    defer store2.deinit();
    
    try std.testing.expect(store2.entries.items.len == 2);
    try std.testing.expect(store2.next_id == 3); // Next id should be 3
}

test "MemoryStore searchByTag" {
    const allocator = std.testing.allocator;
    const tmp_file = "/tmp/test_memory_store_5.jsonl";
    
    std.fs.cwd().deleteFile(tmp_file) catch {};
    defer std.fs.cwd().deleteFile(tmp_file) catch {};
    
    var store = try MemoryStore.init(allocator, tmp_file);
    defer store.deinit();
    
    _ = try store.append("entry with tag1", &[_][]const u8{"tag1", "common"});
    _ = try store.append("entry with tag2", &[_][]const u8{"tag2", "common"});
    _ = try store.append("another tag1 entry", &[_][]const u8{"tag1"});
    
    const results = try store.searchByTag(allocator, "tag1");
    defer allocator.free(results);
    
    try std.testing.expect(results.len == 2);
    try std.testing.expect(std.mem.eql(u8, results[0].content, "entry with tag1"));
    try std.testing.expect(std.mem.eql(u8, results[1].content, "another tag1 entry"));
}

test "MemoryStore searchByTag returns empty for no matches" {
    const allocator = std.testing.allocator;
    const tmp_file = "/tmp/test_memory_store_6.jsonl";
    
    std.fs.cwd().deleteFile(tmp_file) catch {};
    defer std.fs.cwd().deleteFile(tmp_file) catch {};
    
    var store = try MemoryStore.init(allocator, tmp_file);
    defer store.deinit();
    
    _ = try store.append("entry", &[_][]const u8{"tag1"});
    
    const results = try store.searchByTag(allocator, "nonexistent");
    defer allocator.free(results);
    
    try std.testing.expect(results.len == 0);
}

test "MemoryStore searchByKeyword" {
    const allocator = std.testing.allocator;
    const tmp_file = "/tmp/test_memory_store_7.jsonl";
    
    std.fs.cwd().deleteFile(tmp_file) catch {};
    defer std.fs.cwd().deleteFile(tmp_file) catch {};
    
    var store = try MemoryStore.init(allocator, tmp_file);
    defer store.deinit();
    
    _ = try store.append("The quick brown fox", &[_][]const u8{});
    _ = try store.append("A lazy dog", &[_][]const u8{});
    _ = try store.append("quick action", &[_][]const u8{});
    
    const results = try store.searchByKeyword(allocator, "quick");
    defer allocator.free(results);
    
    try std.testing.expect(results.len == 2);
}

test "MemoryStore searchByKeyword case sensitive" {
    const allocator = std.testing.allocator;
    const tmp_file = "/tmp/test_memory_store_8.jsonl";
    
    std.fs.cwd().deleteFile(tmp_file) catch {};
    defer std.fs.cwd().deleteFile(tmp_file) catch {};
    
    var store = try MemoryStore.init(allocator, tmp_file);
    defer store.deinit();
    
    _ = try store.append("Hello World", &[_][]const u8{});
    _ = try store.append("hello world", &[_][]const u8{});
    
    const results_lower = try store.searchByKeyword(allocator, "hello");
    defer allocator.free(results_lower);
    try std.testing.expect(results_lower.len == 1);
    
    const results_upper = try store.searchByKeyword(allocator, "Hello");
    defer allocator.free(results_upper);
    try std.testing.expect(results_upper.len == 1);
}

test "MemoryStore recent returns last N entries" {
    const allocator = std.testing.allocator;
    const tmp_file = "/tmp/test_memory_store_9.jsonl";
    
    std.fs.cwd().deleteFile(tmp_file) catch {};
    defer std.fs.cwd().deleteFile(tmp_file) catch {};
    
    var store = try MemoryStore.init(allocator, tmp_file);
    defer store.deinit();
    
    _ = try store.append("first", &[_][]const u8{});
    _ = try store.append("second", &[_][]const u8{});
    _ = try store.append("third", &[_][]const u8{});
    _ = try store.append("fourth", &[_][]const u8{});
    _ = try store.append("fifth", &[_][]const u8{});
    
    const results = try store.recent(allocator, 3);
    defer allocator.free(results);
    
    try std.testing.expect(results.len == 3);
    try std.testing.expect(std.mem.eql(u8, results[0].content, "third"));
    try std.testing.expect(std.mem.eql(u8, results[1].content, "fourth"));
    try std.testing.expect(std.mem.eql(u8, results[2].content, "fifth"));
}

test "MemoryStore recent with N larger than entries" {
    const allocator = std.testing.allocator;
    const tmp_file = "/tmp/test_memory_store_10.jsonl";
    
    std.fs.cwd().deleteFile(tmp_file) catch {};
    defer std.fs.cwd().deleteFile(tmp_file) catch {};
    
    var store = try MemoryStore.init(allocator, tmp_file);
    defer store.deinit();
    
    _ = try store.append("a", &[_][]const u8{});
    _ = try store.append("b", &[_][]const u8{});
    
    const results = try store.recent(allocator, 100);
    defer allocator.free(results);
    
    try std.testing.expect(results.len == 2);
}

test "MemoryStore recent returns empty for empty store" {
    const allocator = std.testing.allocator;
    const tmp_file = "/tmp/test_memory_store_11.jsonl";
    
    std.fs.cwd().deleteFile(tmp_file) catch {};
    defer std.fs.cwd().deleteFile(tmp_file) catch {};
    
    var store = try MemoryStore.init(allocator, tmp_file);
    defer store.deinit();
    
    const results = try store.recent(allocator, 10);
    defer allocator.free(results);
    
    try std.testing.expect(results.len == 0);
}

test "MemoryStore delete removes entry" {
    const allocator = std.testing.allocator;
    const tmp_file = "/tmp/test_memory_store_12.jsonl";
    
    std.fs.cwd().deleteFile(tmp_file) catch {};
    defer std.fs.cwd().deleteFile(tmp_file) catch {};
    
    var store = try MemoryStore.init(allocator, tmp_file);
    defer store.deinit();
    
    const id1 = try store.append("first", &[_][]const u8{"tag1"});
    const id2 = try store.append("second", &[_][]const u8{"tag2"});
    
    try store.delete(id1);
    
    try std.testing.expect(store.entries.items.len == 1);
    try std.testing.expect(std.mem.eql(u8, store.entries.items[0].content, "second"));
}

test "MemoryStore delete persists to disk" {
    const allocator = std.testing.allocator;
    const tmp_file = "/tmp/test_memory_store_13.jsonl";
    
    std.fs.cwd().deleteFile(tmp_file) catch {};
    defer std.fs.cwd().deleteFile(tmp_file) catch {};
    
    {
        var store = try MemoryStore.init(allocator, tmp_file);
        defer store.deinit();
        const id1 = try store.append("first", &[_][]const u8{});
        _ = try store.append("second", &[_][]const u8{});
        try store.delete(id1);
    }
    
    // Reload and verify
    var store2 = try MemoryStore.init(allocator, tmp_file);
    defer store2.deinit();
    
    try std.testing.expect(store2.entries.items.len == 1);
    try std.testing.expect(std.mem.eql(u8, store2.entries.items[0].content, "second"));
}

test "MemoryStore delete nonexistent id is no-op" {
    const allocator = std.testing.allocator;
    const tmp_file = "/tmp/test_memory_store_14.jsonl";
    
    std.fs.cwd().deleteFile(tmp_file) catch {};
    defer std.fs.cwd().deleteFile(tmp_file) catch {};
    
    var store = try MemoryStore.init(allocator, tmp_file);
    defer store.deinit();
    
    _ = try store.append("entry", &[_][]const u8{});
    
    // Delete non-existent id (should not panic)
    store.delete(999) catch |e| {
        try std.testing.expect(e == error.EntryNotFound);
    };
}

test "MemoryEntry deinit frees resources" {
    const allocator = std.testing.allocator;
    
    var entry = MemoryEntry{
        .id = 1,
        .timestamp = 0,
        .content = try allocator.dupe(u8, "test content"),
        .tags = try allocator.alloc([]const u8, 2),
        .embedding = null,
    };
    entry.tags[0] = try allocator.dupe(u8, "tag1");
    entry.tags[1] = try allocator.dupe(u8, "tag2");
    
    entry.deinit(allocator); // Should not leak
}

test "MemoryStore append with multiple tags" {
    const allocator = std.testing.allocator;
    const tmp_file = "/tmp/test_memory_store_15.jsonl";
    
    std.fs.cwd().deleteFile(tmp_file) catch {};
    defer std.fs.cwd().deleteFile(tmp_file) catch {};
    
    var store = try MemoryStore.init(allocator, tmp_file);
    defer store.deinit();
    
    const tags = [_][]const u8{"tag1", "tag2", "tag3", "tag4"};
    _ = try store.append("multi-tag entry", &tags);
    
    try std.testing.expect(store.entries.items.len == 1);
    try std.testing.expect(store.entries.items[0].tags.len == 4);
}

test "MemoryStore content with special characters" {
    const allocator = std.testing.allocator;
    const tmp_file = "/tmp/test_memory_store_16.jsonl";
    
    std.fs.cwd().deleteFile(tmp_file) catch {};
    defer std.fs.cwd().deleteFile(tmp_file) catch {};
    
    var store = try MemoryStore.init(allocator, tmp_file);
    defer store.deinit();
    
    const special_content = "Line 1\nLine 2\tTabbed\"Quoted\\Backslash";
    _ = try store.append(special_content, &[_][]const u8{});
    
    try std.testing.expect(std.mem.eql(u8, store.entries.items[0].content, special_content));
}

test "MemoryStore deinit frees all entries" {
    const allocator = std.testing.allocator;
    const tmp_file = "/tmp/test_memory_store_17.jsonl";
    
    std.fs.cwd().deleteFile(tmp_file) catch {};
    defer std.fs.cwd().deleteFile(tmp_file) catch {};
    
    var store = try MemoryStore.init(allocator, tmp_file);
    
    for (0..10) |_| {
        _ = try store.append("entry", &[_][]const u8{"tag"});
    }
    

