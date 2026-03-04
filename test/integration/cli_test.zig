const std = @import("std");
const process = std.process;
const testing = std.testing;

fn runCli(allocator: std.mem.Allocator, args: []const []const u8) !std.process.Child.RunResult {
    var argv = std.ArrayList([]const u8).init(allocator);
    defer argv.deinit();
    try argv.append("./zig-out/bin/powerglide");
    try argv.appendSlice(args);
    
    return std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv.items,
    });
}

test "CLI: version command" {
    const allocator = testing.allocator;
    const result = try runCli(allocator, &.{ "version" });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    
    try testing.expect(std.mem.indexOf(u8, result.stdout, "powerglide 0.1.1") != null);
}

test "CLI: help command" {
    const allocator = testing.allocator;
    const result = try runCli(allocator, &.{ "help" });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    
    try testing.expect(std.mem.indexOf(u8, result.stdout, "USAGE:") != null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "COMMANDS:") != null);
}

test "CLI: doctor command" {
    const allocator = testing.allocator;
    const result = try runCli(allocator, &.{ "doctor" });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    
    try testing.expect(std.mem.indexOf(u8, result.stdout, "powerglide doctor") != null);
}

test "CLI: config list" {
    const allocator = testing.allocator;
    const result = try runCli(allocator, &.{ "config", "list" });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    
    try testing.expect(std.mem.indexOf(u8, result.stdout, "Configuration:") != null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "velocity:") != null);
}

test "CLI: tools list" {
    const allocator = testing.allocator;
    const result = try runCli(allocator, &.{ "tools", "list" });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    
    try testing.expect(std.mem.indexOf(u8, result.stdout, "Available tools:") != null);
}
