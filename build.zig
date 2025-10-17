const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Create shared library module
    const phoenix_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Library artifact
    const lib = b.addLibrary(.{
        .name = "phoenix_channels",
        .linkage = .static,
        .root_module = phoenix_mod,
    });

    b.installArtifact(lib);

    // Unit tests
    const unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/unit_tests.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    unit_tests.root_module.addImport("phoenix_channels", phoenix_mod);

    const run_unit_tests = b.addRunArtifact(unit_tests);

    // Integration tests
    const integration_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/integration_tests.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    integration_tests.root_module.addImport("phoenix_channels", phoenix_mod);

    const run_integration_tests = b.addRunArtifact(integration_tests);

    // Test steps
    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(&run_unit_tests.step);
    test_step.dependOn(&run_integration_tests.step);

    const unit_step = b.step("test-unit", "Run unit tests only");
    unit_step.dependOn(&run_unit_tests.step);

    const integration_step = b.step("test-integration", "Run integration tests only");
    integration_step.dependOn(&run_integration_tests.step);
}
