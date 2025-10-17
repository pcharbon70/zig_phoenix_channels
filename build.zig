const std = @import("std");

pub fn build(b: *std.Build) void {
    // Standard build options for target and optimization
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // ===================================================================
    // Library Target
    // ===================================================================
    const lib = b.addLibrary(.{
        .name = "phoenix_channels",
        .linkage = .static,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Install the library artifact to zig-out/lib/
    b.installArtifact(lib);

    // ===================================================================
    // Unit Tests
    // ===================================================================
    const unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/unit_tests.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);

    // ===================================================================
    // Integration Tests
    // ===================================================================
    const integration_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/integration_tests.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const run_integration_tests = b.addRunArtifact(integration_tests);

    // ===================================================================
    // Test Steps
    // ===================================================================

    // Main test step runs both unit and integration tests
    const test_step = b.step("test", "Run all tests (unit + integration)");
    test_step.dependOn(&run_unit_tests.step);
    test_step.dependOn(&run_integration_tests.step);

    // Separate integration test step for selective execution
    const integration_step = b.step("test-integration", "Run integration tests only");
    integration_step.dependOn(&run_integration_tests.step);

    // Separate unit test step for selective execution
    const unit_step = b.step("test-unit", "Run unit tests only");
    unit_step.dependOn(&run_unit_tests.step);

    // ===================================================================
    // Example Executable
    // ===================================================================
    const example = b.addExecutable(.{
        .name = "basic_connection",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/basic_connection.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Link example against the library
    example.root_module.addImport("phoenix_channels", lib.root_module);

    // Install the example to zig-out/bin/
    b.installArtifact(example);

    // Run step for the example
    const run_example = b.addRunArtifact(example);
    const run_step = b.step("run", "Run the basic connection example");
    run_step.dependOn(&run_example.step);

    // ===================================================================
    // Documentation Generation (optional)
    // ===================================================================
    const docs_step = b.step("docs", "Generate documentation");
    const docs = b.addLibrary(.{
        .name = "phoenix_channels",
        .linkage = .static,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = .Debug,
        }),
    });
    const install_docs = b.addInstallDirectory(.{
        .source_dir = docs.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });
    docs_step.dependOn(&install_docs.step);
}
