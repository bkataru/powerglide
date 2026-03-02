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

test "placeholder" {
    try std.testing.expect(true);
}
