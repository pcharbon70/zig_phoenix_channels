# Feature Planning: Build System Configuration (Task 1.1.1)

## Problem Statement

The Phoenix Channels client library project currently has no build system configuration. To enable development, testing, and eventual distribution of the library, we need a properly configured `build.zig` file that supports:

1. **Library compilation**: The project is a library, not a standalone executable
2. **Test execution**: Both unit and integration tests need to be runnable via `zig build test`
3. **Example programs**: Development validation requires example executables that demonstrate library usage
4. **Build configurations**: Support for debug and release modes with appropriate optimizations

Without a build system, developers cannot compile the library, run tests, or validate implementations. This is the foundational infrastructure upon which all subsequent development depends.

## Solution Overview

We will create a comprehensive `build.zig` that follows Zig 0.15.x conventions and best practices:

1. **Static Library Target**: Configure the main library as a static library (`addStaticLibrary`) with `src/root.zig` as the entry point
2. **Test Infrastructure**: Set up separate test targets for unit and integration tests with proper test runner configuration
3. **Example Targets**: Create executable targets for development examples that link against the library
4. **Build Options**: Configure standard optimization modes (Debug, ReleaseSafe, ReleaseFast, ReleaseSmall) and expose them as build options

The build system will be designed to be extensible for future phases when we add dependencies (Phase 1.1.2 will add websocket.zig dependency).

## Agent Consultations Performed

### Zig Build System Research (Web Search)

**Query 1**: "Zig build.zig library setup best practices 2025"

Key findings:
- Use `b.addStaticLibrary()` for library creation with name and root source file
- Convention is to use `src/root.zig` as the library root (not `main.zig`)
- Public library functions must have `pub` visibility for external consumption
- Build system provides full programmatic control without external DSLs
- Zig's native documentation generation via `-femit-docs` flag

**Query 2**: "Zig 0.15 build system module configuration test runner"

Key findings:
- Zig 0.15 uses `b.addTest()` with `.root_module` parameter
- Modules created via `b.createModule()` with `.root_source_file` and `.target`
- Custom test runners configured with `.test_runner` field pointing to runner file
- Tests require two-step setup: Compile step (`addTest`) and Run step (`addRunArtifact`)
- Test step dependency chain: `test_step.dependOn(&run_unit_tests.step)`

### Project Context Review

Reviewed `/home/ducky/code/zig_phoenix_channels/CLAUDE.md` and `/home/ducky/code/zig_phoenix_channels/planning/phase-01.md`:
- Project uses Zig 0.11.0+ (async removed, thread-based concurrency)
- Target version appears to be Zig 0.15.2 (from error output)
- Required build commands: `zig build`, `zig build test`, `zig build run`
- Future dependency: karlseguin/websocket.zig (Phase 1.1.2, not this task)
- Three-tier memory allocation strategy (GPA, Arena, FixedBuffer)
- Thread-based concurrency model with std.Thread

### Current Project State

- No existing build system (`build.zig` does not exist)
- No source directory structure (`src/` does not exist)
- No `.tool-versions` file (asdf/mise not configured yet)
- Clean slate for building proper structure

## Technical Details

### File Locations

```
/home/ducky/code/zig_phoenix_channels/
├── build.zig                    # Main build configuration (NEW)
├── build.zig.zon                # Package manifest (NEW, may be needed)
├── src/
│   └── root.zig                 # Library entry point (NEW)
├── tests/
│   ├── unit_tests.zig           # Unit test entry point (NEW)
│   └── integration_tests.zig    # Integration test entry point (NEW)
└── examples/
    └── basic_connection.zig     # Example program (NEW)
```

### Zig Version Considerations

**Target Version**: Zig 0.15.2 (latest stable as indicated by system output)

**Version-Specific Features**:
- Build system uses `b.addStaticLibrary()` (Zig 0.11+)
- Module system via `b.createModule()` (Zig 0.11+)
- Path specification via `b.path()` instead of `.{ .path = "..." }` (Zig 0.12+)
- Target resolution via `b.resolveTargetQuery()` (Zig 0.13+)
- Simplified dependency system via `build.zig.zon` (Zig 0.11+)

**API Stability**: Zig build system API has been relatively stable since 0.11.0, with minor refinements in 0.12-0.15. Our build script should work across this range with minimal changes.

### Build Targets

#### 1. Library Target (`phoenix_channels`)

```zig
const lib = b.addStaticLibrary(.{
    .name = "phoenix_channels",
    .root_source_file = b.path("src/root.zig"),
    .target = target,
    .optimize = optimize,
});

b.installArtifact(lib);
```

**Purpose**: Compiles the library to `zig-out/lib/libphoenix_channels.a`

**Configuration**:
- Static library (not shared/dynamic for now)
- Installed to default output directory
- Target and optimization from build options

#### 2. Unit Test Target (`unit_tests`)

```zig
const unit_tests = b.addTest(.{
    .root_source_file = b.path("tests/unit_tests.zig"),
    .target = target,
    .optimize = optimize,
});

const run_unit_tests = b.addRunArtifact(unit_tests);

const test_step = b.step("test", "Run unit tests");
test_step.dependOn(&run_unit_tests.step);
```

**Purpose**: Runs all unit tests via `zig build test`

**Configuration**:
- Tests compile with same target/optimize as library
- Test runner automatically invoked
- Step dependency chain ensures tests execute

#### 3. Integration Test Target (`integration_tests`)

```zig
const integration_tests = b.addTest(.{
    .root_source_file = b.path("tests/integration_tests.zig"),
    .target = target,
    .optimize = optimize,
});

const run_integration_tests = b.addRunArtifact(integration_tests);

const integration_step = b.step("test-integration", "Run integration tests");
integration_step.dependOn(&run_integration_tests.step);

// Also add to main test step
test_step.dependOn(&run_integration_tests.step);
```

**Purpose**: Runs integration tests (requires test Phoenix server in future)

**Configuration**:
- Separate step for selective test execution
- Included in main test step for full coverage
- Same target/optimize as library

#### 4. Example Target (`basic_connection`)

```zig
const example = b.addExecutable(.{
    .name = "basic_connection",
    .root_source_file = b.path("examples/basic_connection.zig"),
    .target = target,
    .optimize = optimize,
});

example.root_module.addImport("phoenix_channels", &lib.root_module);

const run_example = b.addRunArtifact(example);
const run_step = b.step("run", "Run the basic connection example");
run_step.dependOn(&run_example.step);
```

**Purpose**: Demonstrates library usage, validates library compiles and links

**Configuration**:
- Links against library via module import
- Executable for development testing
- Invoked via `zig build run`

### Configuration Options

#### Build Mode (Optimization)

```zig
const optimize = b.standardOptimizeOption(.{});
```

**Modes**:
- `Debug`: No optimization, safety checks enabled, debug info included
- `ReleaseSafe`: Optimized, safety checks enabled, assertions active
- `ReleaseFast`: Optimized, safety checks disabled, maximum performance
- `ReleaseSmall`: Optimized for size, safety checks disabled

**Usage**: `zig build -Doptimize=ReleaseSafe`

**Default**: Debug (safe for development)

#### Target Platform

```zig
const target = b.standardTargetOptions(.{});
```

**Purpose**: Cross-compilation support

**Default**: Native platform

**Usage**: `zig build -Dtarget=x86_64-linux-gnu`

### Directory Structure

Initial minimal structure to support build system:

```
src/root.zig:
- Library entry point
- Currently exports empty namespace
- Will export Socket, Channel, Message types in future phases

tests/unit_tests.zig:
- Unit test entry point
- Uses `test` blocks
- Imports library modules for testing

tests/integration_tests.zig:
- Integration test entry point
- Initially empty (requires test server)
- Separated for selective execution

examples/basic_connection.zig:
- Example program entry point
- Has main() function
- Demonstrates library usage
```

### Memory Management in Build Script

Build scripts use a GeneralPurposeAllocator automatically. We don't need explicit allocation in basic build.zig, but future dependency management will use build system allocators.

### Error Handling

Build scripts should validate:
1. Source files exist (handled by Zig automatically)
2. Dependencies are available (Phase 1.1.2)
3. Build steps complete successfully (Zig build system handles)

No custom error handling needed for basic configuration.

## Success Criteria

### CRITICAL: Compilation Success

- [ ] `zig build` completes without errors
- [ ] Library artifact created at `zig-out/lib/libphoenix_channels.a`
- [ ] No compilation warnings or errors
- [ ] Build system validates on clean checkout

### CRITICAL: Test Execution

- [ ] `zig build test` runs without errors (even if no tests exist yet)
- [ ] Unit test runner invokes successfully
- [ ] Integration test runner invokes successfully
- [ ] Test output clearly indicates pass/fail status
- [ ] Tests can be run repeatedly without state issues

### Build Target Functionality

- [ ] `zig build` produces library artifact
- [ ] `zig build test` runs all tests (unit + integration)
- [ ] `zig build test-integration` runs only integration tests
- [ ] `zig build run` executes basic example
- [ ] `zig build -Doptimize=ReleaseSafe` applies optimization
- [ ] All targets work with different optimize modes

### Code Quality

- [ ] build.zig follows Zig style conventions
- [ ] Source files have proper module structure
- [ ] No hardcoded paths (use b.path())
- [ ] Build script is well-commented
- [ ] Target/optimize options exposed properly

### Development Workflow

- [ ] Clean builds work: `rm -rf zig-cache zig-out && zig build`
- [ ] Incremental builds are fast (only recompile changed files)
- [ ] Build errors are clear and actionable
- [ ] Build system supports future dependency addition

### Documentation

- [ ] build.zig includes explanatory comments
- [ ] README.md documents build commands (if updated)
- [ ] Source files have basic module documentation

## Implementation Plan

### Step 1: Create Source Structure

**Actions**:
1. Create `src/` directory
2. Create `src/root.zig` with minimal library entry point:
   ```zig
   //! Phoenix Channels client library for Zig
   //!
   //! This library provides a client implementation of the Phoenix Channels
   //! protocol for real-time communication with Phoenix servers.

   const std = @import("std");

   // Library version
   pub const version = "0.1.0";

   // This is the library entry point. Components will be exported here
   // as they are implemented in subsequent phases.

   test "library imports std" {
       _ = std;
   }
   ```

3. Create `tests/` directory
4. Create `tests/unit_tests.zig`:
   ```zig
   //! Unit tests for Phoenix Channels library

   const std = @import("std");
   const testing = std.testing;

   test "placeholder unit test" {
       try testing.expect(true);
   }
   ```

5. Create `tests/integration_tests.zig`:
   ```zig
   //! Integration tests for Phoenix Channels library
   //! These tests require a test Phoenix server (to be implemented)

   const std = @import("std");
   const testing = std.testing;

   test "placeholder integration test" {
       try testing.expect(true);
   }
   ```

6. Create `examples/` directory
7. Create `examples/basic_connection.zig`:
   ```zig
   //! Basic connection example
   //! Demonstrates minimal library usage

   const std = @import("std");
   const phoenix = @import("phoenix_channels");

   pub fn main() !void {
       std.debug.print("Phoenix Channels Library v{s}\n", .{phoenix.version});
       std.debug.print("Build system configuration successful!\n", .{});
   }
   ```

**Testing**:
- Verify directory structure matches plan
- Verify all files are valid Zig syntax

**Success Metric**: All source files created and contain valid Zig code

---

### Step 2: Create build.zig

**Actions**:
1. Create `build.zig` in project root
2. Implement complete build configuration with:
   - Standard build options (target, optimize)
   - Static library target
   - Unit test target
   - Integration test target
   - Example executable target
   - Test step configuration
   - Run step configuration

**Full build.zig implementation**:
```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    // Standard build options for target and optimization
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // ===================================================================
    // Library Target
    // ===================================================================
    const lib = b.addStaticLibrary(.{
        .name = "phoenix_channels",
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Install the library artifact to zig-out/lib/
    b.installArtifact(lib);

    // ===================================================================
    // Unit Tests
    // ===================================================================
    const unit_tests = b.addTest(.{
        .root_source_file = b.path("tests/unit_tests.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);

    // ===================================================================
    // Integration Tests
    // ===================================================================
    const integration_tests = b.addTest(.{
        .root_source_file = b.path("tests/integration_tests.zig"),
        .target = target,
        .optimize = optimize,
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
        .root_source_file = b.path("examples/basic_connection.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Link example against the library
    example.root_module.addImport("phoenix_channels", &lib.root_module);

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
    const docs = b.addStaticLibrary(.{
        .name = "phoenix_channels",
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = .Debug,
    });
    const install_docs = b.addInstallDirectory(.{
        .source_dir = docs.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });
    docs_step.dependOn(&install_docs.step);
}
```

**Testing**:
- Verify build.zig syntax is valid: `zig build --help`
- Check that all build steps are listed
- Verify no syntax errors

**Success Metric**: `zig build --help` displays all configured steps without errors

---

### Step 3: Verify Library Compilation

**Actions**:
1. Run `zig build` to compile the library
2. Verify artifact created at `zig-out/lib/libphoenix_channels.a`
3. Check for compilation warnings or errors
4. Test different optimization modes:
   - `zig build -Doptimize=Debug`
   - `zig build -Doptimize=ReleaseSafe`
   - `zig build -Doptimize=ReleaseFast`
   - `zig build -Doptimize=ReleaseSmall`

**Testing**:
- Library artifact exists after build
- No warnings or errors in output
- All optimization modes work
- Incremental rebuild is fast

**Success Metric**: Library compiles successfully in all modes, artifact created

---

### Step 4: Verify Test Execution

**Actions**:
1. Run `zig build test` to execute all tests
2. Verify both unit and integration tests run
3. Check test output format and clarity
4. Run selective test execution:
   - `zig build test-unit`
   - `zig build test-integration`
5. Verify tests pass (our placeholder tests should always pass)

**Testing**:
- All test commands complete successfully
- Test output clearly shows which tests ran
- Pass/fail status is clear
- No false negatives

**Success Metric**: All test commands work, placeholder tests pass

---

### Step 5: Verify Example Execution

**Actions**:
1. Run `zig build run` to execute the example
2. Verify example output displays correctly
3. Check that example links against library
4. Verify example can import library modules
5. Test example with different build modes

**Testing**:
- Example prints expected output
- No linking errors
- Example can access library exports
- Works in all optimization modes

**Success Metric**: Example runs successfully and displays library version

---

### Step 6: Clean Build Verification

**Actions**:
1. Clean build artifacts: `rm -rf zig-cache zig-out`
2. Run full build from scratch: `zig build`
3. Run tests: `zig build test`
4. Run example: `zig build run`
5. Verify all steps work on clean state

**Testing**:
- Clean build completes successfully
- No errors about missing files
- All artifacts regenerated correctly
- Tests and example still work

**Success Metric**: Full workflow works from clean state

---

### Step 7: Documentation and Comments

**Actions**:
1. Add comprehensive comments to build.zig explaining each section
2. Ensure source files have module documentation (//!)
3. Verify documentation generation works: `zig build docs`
4. Add any necessary inline comments for complex logic

**Testing**:
- Comments are clear and helpful
- Documentation builds without errors
- Generated docs are viewable in browser

**Success Metric**: Build system is well-documented, docs generate successfully

---

### Step 8: Integration Validation

**Actions**:
1. Perform complete workflow test:
   - Clean: `rm -rf zig-cache zig-out`
   - Build: `zig build`
   - Test: `zig build test`
   - Run: `zig build run`
   - Docs: `zig build docs`
2. Test with different Zig versions if available
3. Verify build system is ready for Phase 1.1.2 (dependency addition)

**Testing**:
- All commands work in sequence
- No state corruption between steps
- Build system is stable and reliable

**Success Metric**: Complete workflow executes successfully, system ready for dependencies

---

## Notes/Considerations

### Edge Cases

1. **Missing Source Files**: Zig will error clearly if files don't exist - no special handling needed
2. **Empty Library**: Our minimal `root.zig` is valid - library can be empty initially
3. **No Tests**: Empty test files are valid - placeholder tests ensure test runner works
4. **Module Import Path**: The name "phoenix_channels" in `addImport()` must match usage in examples

### Future Improvements

1. **Custom Test Runner**: Phase 1.2+ may need custom test runner for better output formatting
2. **Benchmark Target**: Could add benchmark step for performance testing
3. **Install Step Customization**: May want custom install paths for different artifacts
4. **Cross-Compilation Tests**: Could add CI targets for multiple platforms
5. **Documentation Hosting**: Could add step to publish docs to GitHub Pages
6. **Code Coverage**: Could integrate coverage tooling when available

### Risks and Mitigations

**Risk**: Zig version incompatibility
- **Mitigation**: Target Zig 0.15.x API which is stable. Document minimum version.

**Risk**: Build system breaks when adding dependencies (Phase 1.1.2)
- **Mitigation**: Design with extensibility in mind. Leave clear TODOs for dependency integration points.

**Risk**: Test infrastructure inadequate for complex tests
- **Mitigation**: Start simple, extend as needed. Separate unit/integration allows evolution.

**Risk**: Example too simple to validate library functionality
- **Mitigation**: This is acceptable for Phase 1.1.1. Phase 1.5 will add comprehensive examples.

### Dependencies on Other Tasks

**Blocks**:
- 1.1.2: Dependency Management (needs build system to add dependencies)
- 1.1.3: Project Structure (builds on this foundation)
- 1.1.4: Core Type Definitions (needs compilable project)

**Blocked By**:
- None - This is the first task in Phase 1

### Performance Considerations

- **Incremental Builds**: Zig's build system handles incremental compilation automatically
- **Parallel Compilation**: Multi-threaded compilation enabled by default
- **Cache Management**: `zig-cache/` stores incremental build state
- **Test Caching**: Tests only recompile if sources change

### Security Considerations

- **Build Script Execution**: build.zig runs with developer privileges - no external code execution
- **Dependency Integrity**: Phase 1.1.2 will add hash verification for dependencies
- **Output Validation**: Build artifacts are deterministic and reproducible

### Compatibility Notes

**Zig Version Compatibility**:
- Minimum: Zig 0.11.0 (async removal, new build system)
- Target: Zig 0.15.2 (latest stable)
- Forward Compatibility: Should work with 0.16+ (build API is stabilizing)

**Platform Compatibility**:
- Linux: Primary development platform (confirmed working)
- macOS: Should work (standard Zig support)
- Windows: Should work (standard Zig support)
- Cross-compilation: Supported via `-Dtarget` flag

### Testing Strategy

**Unit Testing**:
- Each component gets dedicated test file
- Test files import library modules
- Use `std.testing` for assertions

**Integration Testing**:
- Separate test entry point
- Will require test Phoenix server (Phase 1.6)
- Can be skipped if server unavailable

**Example Testing**:
- Examples serve as manual integration tests
- Should compile and run without errors
- Demonstrate real library usage patterns

### Maintenance Considerations

**Build System Evolution**:
- Keep build.zig simple initially
- Add complexity only as needed
- Document why each build step exists

**Version Tracking**:
- Library version in `src/root.zig`
- Zig version requirement documented
- Update version on releases

**CI/CD Preparation**:
- Build system should work in CI environment
- No interactive prompts
- Clear exit codes for automation

### Success Validation Checklist

Before marking task complete, verify:

- [ ] All source files created and valid
- [ ] build.zig compiles and runs
- [ ] `zig build` produces library artifact
- [ ] `zig build test` runs without errors
- [ ] `zig build run` executes example
- [ ] All optimization modes work
- [ ] Clean builds work correctly
- [ ] Documentation is comprehensive
- [ ] Code follows Zig style conventions
- [ ] No TODO comments left unresolved
- [ ] Ready for Phase 1.1.2 (dependency addition)

---

## Conclusion

This feature plan provides a comprehensive roadmap for implementing Task 1.1.1 (Build System Configuration). The build system will serve as the foundation for all subsequent development phases, providing reliable compilation, testing, and example execution capabilities.

The implementation is straightforward but critical - it must be done correctly from the start to avoid costly refactoring. The plan follows Zig best practices and community conventions while remaining flexible for future expansion.

Upon completion, developers will have a fully functional build system that supports the entire development workflow, from initial implementation through testing and validation.
