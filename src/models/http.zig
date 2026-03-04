const std = @import("std");

pub const Response = struct {
    status: u16,
    body: []u8, // caller owns (allocated with provided allocator)

    pub fn deinit(self: *Response, allocator: std.mem.Allocator) void {
        allocator.free(self.body);
    }

    pub fn isSuccess(self: *const Response) bool {
        return self.status >= 200 and self.status < 300;
    }
};

pub const HttpClient = struct {
    allocator: std.mem.Allocator,
    client: std.http.Client,

    pub fn init(allocator: std.mem.Allocator) HttpClient {
        return .{
            .allocator = allocator,
            .client = std.http.Client{ .allocator = allocator },
        };
    }

    pub fn deinit(self: *HttpClient) void {
        self.client.deinit();
    }

    pub fn post(self: *HttpClient, url: []const u8, headers: []const std.http.Header, body: []const u8) !Response {
        return self.request(.POST, url, headers, body);
    }

    pub fn get(self: *HttpClient, url: []const u8, headers: []const std.http.Header) !Response {
        return self.request(.GET, url, headers, null);
    }

    fn request(self: *HttpClient, method: std.http.Method, url: []const u8, headers: []const std.http.Header, body: ?[]const u8) !Response {
        var allocating_writer = std.Io.Writer.Allocating.init(self.allocator);
        defer allocating_writer.deinit();

        const fetch_result = try self.client.fetch(.{
            .location = .{ .url = url },
            .method = method,
            .payload = body,
            .extra_headers = headers,
            .response_writer = &allocating_writer.writer,
            .keep_alive = true,
        });

        const status_code: u16 = @intCast(@intFromEnum(fetch_result.status));

        return Response{
            .status = status_code,
            .body = try allocating_writer.toOwnedSlice(),
        };
    }
};

test "HttpClient initialization" {
    const allocator = std.testing.allocator;
    var client = HttpClient.init(allocator);
    defer client.deinit();
}

test "Response isSuccess with 200" {
    const allocator = std.testing.allocator;
    var resp = Response{
        .status = 200,
        .body = try allocator.dupe(u8, "ok"),
    };
    defer resp.deinit(allocator);
    try std.testing.expect(resp.isSuccess());
}

test "Response isSuccess with 201" {
    const allocator = std.testing.allocator;
    var resp = Response{
        .status = 201,
        .body = try allocator.dupe(u8, "created"),
    };
    defer resp.deinit(allocator);
    try std.testing.expect(resp.isSuccess());
}

test "Response isSuccess false for 400" {
    const allocator = std.testing.allocator;
    var resp = Response{
        .status = 400,
        .body = try allocator.dupe(u8, "bad request"),
    };
    defer resp.deinit(allocator);
    try std.testing.expect(!resp.isSuccess());
}

test "Response isSuccess false for 500" {
    const allocator = std.testing.allocator;
    var resp = Response{
        .status = 500,
        .body = try allocator.dupe(u8, "server error"),
    };
    defer resp.deinit(allocator);
    try std.testing.expect(!resp.isSuccess());
}

test "Response deinit frees body" {
    const allocator = std.testing.allocator;
    var resp = Response{
        .status = 200,
        .body = try allocator.dupe(u8, "test body"),
    };
    resp.deinit(allocator);
    // No leak = pass
}
