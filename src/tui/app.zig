const std = @import("std");

pub const TUIApp = struct {
    allocator: std.mem.Allocator,
    running: bool = false,

    pub fn init(allocator: std.mem.Allocator) TUIApp {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *TUIApp) void {
        _ = self;
    }

    pub fn start(self: *TUIApp) !void {
        self.running = true;
    }

    pub fn stop(self: *TUIApp) void {
        self.running = false;
    }

    pub fn render(self: *TUIApp) void {
        _ = self;
    }
};

test "placeholder" {
    try std.testing.expect(true);
}
