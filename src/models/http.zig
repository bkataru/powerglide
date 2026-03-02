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
        var response_body = std.ArrayList(u8).init(self.allocator);
        errdefer response_body.deinit();

        const response_writer = response_body.writer();

        const fetch_result = try self.client.fetch(.{
            .location = .{ .url = url },
            .method = method,
            .payload = body,
            .extra_headers = headers,
            .response_writer = response_writer,
            .keep_alive = true,
        });

        const status_code: u16 = @intCast(@intFromEnum(fetch_result.status));

        return Response{
            .status = status_code,
            .body = try response_body.toOwnedSlice(),
        };
    }
};

test "placeholder" {
    try std.testing.expect(true);
}
