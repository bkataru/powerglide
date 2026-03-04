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

test "powerglide agent list runs successfully" {
    if (!binaryExists()) {
        return;
    }

    const result = std.process.Child.run(.{
        .allocator = std.testing.allocator,
        .argv = &[_][]const u8{ "/root/powerglide/zig-out/bin/powerglide", "agent", "list" },
    }) catch {
        return error.BinaryNotFound;
    };
    defer {
        std.testing.allocator.free(result.stdout);
        std.testing.allocator.free(result.stderr);
    }

    try std.testing.expectEqual(@as(u8, 0), result.term.Exited);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "agent") != null);
}

test "powerglide session list runs successfully" {
    if (!binaryExists()) {
        return;
    }

    const result = std.process.Child.run(.{
        .allocator = std.testing.allocator,
        .argv = &[_][]const u8{ "/root/powerglide/zig-out/bin/powerglide", "session", "list" },
    }) catch {
        return error.BinaryNotFound;
    };
    defer {
        std.testing.allocator.free(result.stdout);
        std.testing.allocator.free(result.stderr);
    }

    try std.testing.expectEqual(@as(u8, 0), result.term.Exited);
}

test "powerglide config list runs successfully" {
    if (!binaryExists()) {
        return;
    }

    const result = std.process.Child.run(.{
        .allocator = std.testing.allocator,
        .argv = &[_][]const u8{ "/root/powerglide/zig-out/bin/powerglide", "config", "list" },
    }) catch {
        return error.BinaryNotFound;
    };
    defer {
        std.testing.allocator.free(result.stdout);
        std.testing.allocator.free(result.stderr);
    }

    try std.testing.expectEqual(@as(u8, 0), result.term.Exited);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "config") != null);
}

test "powerglide tools list runs successfully" {
    if (!binaryExists()) {
        return;
    }

    const result = std.process.Child.run(.{
        .allocator = std.testing.allocator,
        .argv = &[_][]const u8{ "/root/powerglide/zig-out/bin/powerglide", "tools", "list" },
    }) catch {
        return error.BinaryNotFound;
    };
    defer {
        std.testing.allocator.free(result.stdout);
        std.testing.allocator.free(result.stderr);
    }

    try std.testing.expectEqual(@as(u8, 0), result.term.Exited);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "tool") != null);
}

test "powerglide swarm help runs successfully" {
    if (!binaryExists()) {
        return;
    }

    const result = std.process.Child.run(.{
        .allocator = std.testing.allocator,
        .argv = &[_][]const u8{ "/root/powerglide/zig-out/bin/powerglide", "swarm", "--help" },
    }) catch {
        return error.BinaryNotFound;
    };
    defer {
        std.testing.allocator.free(result.stdout);
        std.testing.allocator.free(result.stderr);
    }

    try std.testing.expectEqual(@as(u8, 0), result.term.Exited);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "swarm") != null);
}

test "powerglide run --help runs successfully" {
    if (!binaryExists()) {
        return;
    }

    const result = std.process.Child.run(.{
        .allocator = std.testing.allocator,
        .argv = &[_][]const u8{ "/root/powerglide/zig-out/bin/powerglide", "run", "--help" },
    }) catch {
        return error.BinaryNotFound;
    };
    defer {
        std.testing.allocator.free(result.stdout);
        std.testing.allocator.free(result.stderr);
    }

    try std.testing.expectEqual(@as(u8, 0), result.term.Exited);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "run") != null);
}

test "powerglide config --help runs successfully" {
    if (!binaryExists()) {
        return;
    }

    const result = std.process.Child.run(.{
        .allocator = std.testing.allocator,
        .argv = &[_][]const u8{ "/root/powerglide/zig-out/bin/powerglide", "config", "--help" },
    }) catch {
        return error.BinaryNotFound;
    };
    defer {
        std.testing.allocator.free(result.stdout);
        std.testing.allocator.free(result.stderr);
    }

    try std.testing.expectEqual(@as(u8, 0), result.term.Exited);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "config") != null);
}

test "powerglide agent --help runs successfully" {
    if (!binaryExists()) {
        return;
    }

    const result = std.process.Child.run(.{
        .allocator = std.testing.allocator,
        .argv = &[_][]const u8{ "/root/powerglide/zig-out/bin/powerglide", "agent", "--help" },
    }) catch {
        return error.BinaryNotFound;
    };
    defer {
        std.testing.allocator.free(result.stdout);
        std.testing.allocator.free(result.stderr);
    }

    try std.testing.expectEqual(@as(u8, 0), result.term.Exited);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "agent") != null);
}

test "powerglide session --help runs successfully" {
    if (!binaryExists()) {
        return;
    }

    const result = std.process.Child.run(.{
        .allocator = std.testing.allocator,
        .argv = &[_][]const u8{ "/root/powerglide/zig-out/bin/powerglide", "session", "--help" },
    }) catch {
        return error.BinaryNotFound;
    };
    defer {
        std.testing.allocator.free(result.stdout);
        std.testing.allocator.free(result.stderr);
    }

    try std.testing.expectEqual(@as(u8, 0), result.term.Exited);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "session") != null);
}

test "powerglide tools --help runs successfully" {
    if (!binaryExists()) {
        return;
    }

    const result = std.process.Child.run(.{
        .allocator = std.testing.allocator,
        .argv = &[_][]const u8{ "/root/powerglide/zig-out/bin/powerglide", "tools", "--help" },
    }) catch {
        return error.BinaryNotFound;
    };
    defer {
        std.testing.allocator.free(result.stdout);
        std.testing.allocator.free(result.stderr);
    }

    try std.testing.expectEqual(@as(u8, 0), result.term.Exited);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "tools") != null);
}

test "powerglide invalid command returns error" {
    if (!binaryExists()) {
        return;
    }

    const result = std.process.Child.run(.{
        .allocator = std.testing.allocator,
        .argv = &[_][]const u8{ "/root/powerglide/zig-out/bin/powerglide", "invalid_command_xyz" },
    }) catch {
        return error.BinaryNotFound;
    };
    defer {
        std.testing.allocator.free(result.stdout);
        std.testing.allocator.free(result.stderr);
    }

    // Invalid command should return non-zero exit
    try std.testing.expect(result.term.Exited != 0);
}

test "powerglide binary is executable" {
    if (!binaryExists()) {
        return;
    }

    // Check that the file exists and is accessible
    const file = std.fs.cwd().openFile("/root/powerglide/zig-out/bin/powerglide", .{}) catch {
        return error.FileNotFound;
    };
    defer file.close();

    const stat = file.stat() catch {
        return error.StatFailed;
    };

    try std.testing.expect(stat.kind == .file);
    try std.testing.expect(stat.size > 0);
}

test "powerglide doctor checks zig" {
    if (!binaryExists()) {
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
    // Doctor should mention zig
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "zig") != null);
}

test "powerglide version output format" {
    if (!binaryExists()) {
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
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "0.1.0") != null);
}

test "powerglide --version output format" {
    if (!binaryExists()) {
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
