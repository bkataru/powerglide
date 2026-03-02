const std = @import("std");

pub const HttpClient = struct {
    allocator: std.mem.Allocator,
    base_url: []const u8,
    timeout_ms: u32 = 30000,

    pub fn init(allocator: std.mem.Allocator, base_url: []const u8) HttpClient {
        return .{
            .allocator = allocator,
            .base_url = base_url,
        };
    }

    pub fn deinit(self: *HttpClient) void {
        _ = self;
    }

    pub fn get(self: *HttpClient, path: []const u8) ![]const u8 {
        _ = self;
        _ = path;
        return "";
    }

    pub fn post(self: *HttpClient, path: []const u8, body: []const u8) ![]const u8 {
        _ = self;
        _ = path;
        _ = body;
        return "";
    }
};

test "placeholder" {
    try std.testing.expect(true);
}
