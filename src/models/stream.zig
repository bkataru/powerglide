const std = @import("std");

pub const StreamEvent = union(enum) {
    text_delta: []const u8,
    done: void,
    parse_error: []const u8,
};

pub const SseParser = struct {
    buf: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator) SseParser {
        _ = allocator;
        return .{
            .buf = std.ArrayList(u8){},
        };
    }

    pub fn deinit(self: *SseParser, allocator: std.mem.Allocator) void {
        self.buf.deinit(allocator);
    }

    pub fn feed(self: *SseParser, allocator: std.mem.Allocator, chunk: []const u8) ![]StreamEvent {
        // Append the chunk to the buffer
        try self.buf.appendSlice(allocator, chunk);

        var events = std.ArrayList(StreamEvent){};
        errdefer events.deinit(allocator);

        // Process lines in the buffer
        var start: usize = 0;
        while (start < self.buf.items.len) {
            // Find end of line (either \n or \r\n)
            var end = start;
            while (end < self.buf.items.len and self.buf.items[end] != '\n') {
                end += 1;
            }

            if (end > start) {
                var line = self.buf.items[start..end];
                // Remove trailing \r if present
                if (line.len > 0 and line[line.len - 1] == '\r') {
                    line = line[0 .. line.len - 1];
                }

                if (line.len > 0) {
                    // Parse SSE line
                    if (std.mem.startsWith(u8, line, "data: ")) {
                        const data = line[6..];
                        if (std.mem.eql(u8, data, "[DONE]")) {
                            try events.append(allocator, .done);
                        } else {
                            try events.append(allocator, .{ .text_delta = data });
                        }
                    }
                }
            }

            start = end + 1;
        }

        // Keep any partial line at the end
        if (start < self.buf.items.len) {
            const remaining = try allocator.dupe(u8, self.buf.items[start..]);
            defer allocator.free(remaining);
            self.buf.clearRetainingCapacity();
            try self.buf.appendSlice(allocator, remaining);
        } else {
            self.buf.clearRetainingCapacity();
        }

        return events.toOwnedSlice(allocator);
    }
};

test "SseParser init and deinit" {
    const allocator = std.testing.allocator;
    var parser = SseParser.init(allocator);
    defer parser.deinit(allocator);
    try std.testing.expect(parser.buf.items.len == 0);
}

test "SseParser feed single text_delta" {
    const allocator = std.testing.allocator;
    var parser = SseParser.init(allocator);
    defer parser.deinit(allocator);

    const events = try parser.feed(allocator, "data: hello\n");
    defer allocator.free(events);

    try std.testing.expect(events.len == 1);
    try std.testing.expect(events[0] == .text_delta);
    try std.testing.expect(std.mem.eql(u8, events[0].text_delta, "hello"));
}

test "SseParser feed DONE event" {
    const allocator = std.testing.allocator;
    var parser = SseParser.init(allocator);
    defer parser.deinit(allocator);

    const events = try parser.feed(allocator, "data: [DONE]\n");
    defer allocator.free(events);

    try std.testing.expect(events.len == 1);
    try std.testing.expect(events[0] == .done);
}

test "SseParser feed multiple events" {
    const allocator = std.testing.allocator;
    var parser = SseParser.init(allocator);
    defer parser.deinit(allocator);

    const events = try parser.feed(allocator, "data: foo\ndata: bar\ndata: [DONE]\n");
    defer allocator.free(events);

    try std.testing.expect(events.len == 3);
    try std.testing.expect(events[0] == .text_delta);
    try std.testing.expect(std.mem.eql(u8, events[0].text_delta, "foo"));
    try std.testing.expect(events[1] == .text_delta);
    try std.testing.expect(std.mem.eql(u8, events[1].text_delta, "bar"));
    try std.testing.expect(events[2] == .done);
}

test "SseParser ignores non-data lines" {
    const allocator = std.testing.allocator;
    var parser = SseParser.init(allocator);
    defer parser.deinit(allocator);

    const events = try parser.feed(allocator, "event: message\ndata: content\n");
    defer allocator.free(events);

    try std.testing.expect(events.len == 1);
    try std.testing.expect(events[0] == .text_delta);
}

test "SseParser handles CRLF line endings" {
    const allocator = std.testing.allocator;
    var parser = SseParser.init(allocator);
    defer parser.deinit(allocator);

    const events = try parser.feed(allocator, "data: hello\r\n");
    defer allocator.free(events);

    try std.testing.expect(events.len == 1);
    try std.testing.expect(events[0] == .text_delta);
    try std.testing.expect(std.mem.eql(u8, events[0].text_delta, "hello"));
}

test "SseParser multiple feeds accumulate correctly" {
    const allocator = std.testing.allocator;
    var parser = SseParser.init(allocator);
    defer parser.deinit(allocator);

    // First feed: complete line
    const events1 = try parser.feed(allocator, "data: first\n");
    defer allocator.free(events1);
    try std.testing.expect(events1.len == 1);
    try std.testing.expect(std.mem.eql(u8, events1[0].text_delta, "first"));

    // Second feed: another complete line
    const events2 = try parser.feed(allocator, "data: second\n");
    defer allocator.free(events2);
    try std.testing.expect(events2.len == 1);
    try std.testing.expect(std.mem.eql(u8, events2[0].text_delta, "second"));
}

test "StreamEvent union variants" {
    const e1 = StreamEvent{ .text_delta = "test" };
    const e2 = StreamEvent{ .done = {} };
    const e3 = StreamEvent{ .parse_error = "bad" };
    try std.testing.expect(e1 == .text_delta);
    try std.testing.expect(e2 == .done);
    try std.testing.expect(e3 == .parse_error);
}
