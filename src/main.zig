const std = @import("std");

pub fn main() !void {
    // Simple approach: use arena allocator
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len > 1) {
        if (std.mem.eql(u8, args[1], "--version")) {
            std.debug.print("powerglide v0.1.0\n", .{});
            return;
        }
        if (std.mem.eql(u8, args[1], "--help") or std.mem.eql(u8, args[1], "-h")) {
            printHelp();
            return;
        }
    }

    printHelp();
}

fn printHelp() void {
    std.debug.print(
        \\powerglide — the CLI coding agent that slides
        \\
        \\Usage: powerglide [options]
        \\
        \\Options:
        \\  --help, -h     Show this help message
        \\  --version      Show version information
        \\
        \\Quick start:
        \\  zig build run -- --help
        \\
    , .{});
}

test "placeholder" {
    try std.testing.expect(true);
}
