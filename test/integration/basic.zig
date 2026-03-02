//! Basic integration tests for powerglide CLI binary
const std = @import("std");

/// Helper function to check if binary exists
fn binaryExists() bool {
    std.fs.accessAbsolute("/root/powerglide/zig-out/bin/powerglide", .{}) catch {
        return false;
    };
    return true;
}

test "powerglide --help runs successfully" {
    if (!binaryExists()) {
        // Binary not built yet, skip this test
        return;
    }

    const result = std.process.Child.run(.{
        .allocator = std.testing.allocator,
        .argv = &[_][]const u8{ "/root/powerglide/zig-out/bin/powerglide", "--help" },
    }) catch {
        return error.BinaryNotFound;
    };
    defer {
        std.testing.allocator.free(result.stdout);
        std.testing.allocator.free(result.stderr);
    }

    try std.testing.expectEqual(@as(u8, 0), result.term.Exited);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "powerglide") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "USAGE") != null);
}

test "powerglide version runs successfully" {
    if (!binaryExists()) {
        // Binary not built yet, skip this test
        return;
    }

    const result = std.process.Child.run(.{
        .allocator = std.testing.allocator,
        .argv = &[_][]const u8{ "/root/powerglide/zig-out/bin/powerglide", "version" },
    }) catch {
        return error.BinaryNotFound;
    };
    defer {
        std.testing.allocator.free(result.stdout);
        std.testing.allocator.free(result.stderr);
    }

    try std.testing.expectEqual(@as(u8, 0), result.term.Exited);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "powerglide") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "0.1.0") != null);
}

test "powerglide doctor runs successfully" {
    if (!binaryExists()) {
        // Binary not built yet, skip this test
        return;
    }

    const result = std.process.Child.run(.{
        .allocator = std.testing.allocator,
        .argv = &[_][]const u8{ "/root/powerglide/zig-out/bin/powerglide", "doctor" },
    }) catch {
        return error.BinaryNotFound;
    };
    defer {
        std.testing.allocator.free(result.stdout);
        std.testing.allocator.free(result.stderr);
    }

    try std.testing.expectEqual(@as(u8, 0), result.term.Exited);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "powerglide doctor") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "zig") != null);
}

test "powerglide --version runs successfully" {
    if (!binaryExists()) {
        // Binary not built yet, skip this test
        return;
    }

    const result = std.process.Child.run(.{
        .allocator = std.testing.allocator,
        .argv = &[_][]const u8{ "/root/powerglide/zig-out/bin/powerglide", "--version" },
    }) catch {
        return error.BinaryNotFound;
    };
    defer {
        std.testing.allocator.free(result.stdout);
        std.testing.allocator.free(result.stderr);
    }

    try std.testing.expectEqual(@as(u8, 0), result.term.Exited);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "0.1.0") != null);
}

test "powerglide help runs successfully" {
    if (!binaryExists()) {
        // Binary not built yet, skip this test
        return;
    }

    const result = std.process.Child.run(.{
        .allocator = std.testing.allocator,
        .argv = &[_][]const u8{ "/root/powerglide/zig-out/bin/powerglide", "help" },
    }) catch {
        return error.BinaryNotFound;
    };
    defer {
        std.testing.allocator.free(result.stdout);
        std.testing.allocator.free(result.stderr);
    }

    try std.testing.expectEqual(@as(u8, 0), result.term.Exited);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "COMMANDS") != null);
}
