const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Create the main library module
    const mod = b.addModule("powerglide", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .link_libc = true,
    });

    // Add clap dependency - available from build.zig.zon
    const clap = b.dependency("clap", .{});
    mod.addImport("clap", clap.module("clap"));

    // Add vaxis dependency - available from build.zig.zon
    const vaxis = b.dependency("vaxis", .{});
    mod.addImport("vaxis", vaxis.module("vaxis"));

    // Main executable
    const exe = b.addExecutable(.{
        .name = "powerglide",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = &.{
                .{ .name = "powerglide", .module = mod },
            },
        }),
    });

    b.installArtifact(exe);

    // Run step
    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // Library tests
    const mod_tests = b.addTest(.{
        .root_module = mod,
    });
    const run_mod_tests = b.addRunArtifact(mod_tests);

    // Executable tests
    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });
    const run_exe_tests = b.addRunArtifact(exe_tests);

    // Combined test step
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);

    // Trial harness executable (examples/trial.zig)
    const trial_exe = b.addExecutable(.{
        .name = "trial",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/trial.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = &.{
                .{ .name = "powerglide", .module = mod },
            },
        }),
    });
    b.installArtifact(trial_exe);
    const trial_step = b.step("trial", "Run the igllama agentic trial harness");
    const trial_cmd = b.addRunArtifact(trial_exe);
    trial_cmd.step.dependOn(b.getInstallStep());
    trial_step.dependOn(&trial_cmd.step);

    // Quantization variant trial harness (examples/trial_quant.zig)
    const trial_quant_exe = b.addExecutable(.{
        .name = "trial-quant",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/trial_quant.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = &.{
                .{ .name = "powerglide", .module = mod },
            },
        }),
    });
    b.installArtifact(trial_quant_exe);
    const trial_quant_step = b.step("trial-quant", "Run the igllama quantization sensitivity harness (Q4/Q5/Q6/Q8 on 2B and 9B)");
    const trial_quant_cmd = b.addRunArtifact(trial_quant_exe);
    trial_quant_cmd.step.dependOn(b.getInstallStep());
    trial_quant_step.dependOn(&trial_quant_cmd.step);
}
