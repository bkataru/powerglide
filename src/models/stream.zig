const std = @import("std");

pub const StreamEvent = union(enum) {
    text_delta: []const u8,
    done: void,
    parse_error: []const u8,
};

pub const SseParser = struct {
    buf: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator) SseParser {
        return .{
            .buf = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *SseParser) void {
        self.buf.deinit();
    }

    pub fn feed(self: *SseParser, allocator: std.mem.Allocator, chunk: []const u8) ![]StreamEvent {
        // Append the chunk to the buffer
        try self.buf.appendSlice(chunk);

        var events = std.ArrayList(StreamEvent).init(allocator);
        errdefer events.deinit();

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
                            try events.append(.done);
                        } else {
                            try events.append(.{ .text_delta = data });
                        }
                    }
                }
            }

            start = end + 1;
        }

        // Keep any partial line at the end
        if (start < self.buf.items.len) {
            const remaining = self.buf.items[start..];
            self.buf.clearRetainingCapacity();
            try self.buf.appendSlice(remaining);
        } else {
            self.buf.clearRetainingCapacity();
        }

        return events.toOwnedSlice();
    }
};

test "placeholder" {
    try std.testing.expect(true);
}
