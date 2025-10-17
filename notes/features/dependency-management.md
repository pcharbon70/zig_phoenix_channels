# Feature Planning Document: Dependency Management (Task 1.1.2)

## Document Information

- **Task ID**: 1.1.2
- **Task Name**: Dependency Management
- **Phase**: Phase 1 - Core Foundation
- **Priority**: Critical (Blocks all subsequent development)
- **Created**: 2025-10-17
- **Status**: Planning

---

## Problem Statement

### Why Dependency Management is Critical

The Phoenix Channels client library requires a robust WebSocket implementation to handle the underlying transport layer. Without proper dependency management, we face several critical challenges:

1. **No Transport Layer**: Phoenix Channels communicates over WebSocket protocol. Without a working WebSocket library, we cannot establish connections to Phoenix servers.

2. **Build Reproducibility**: Manually managing dependencies leads to version inconsistencies across development environments and makes builds non-reproducible.

3. **Integration Complexity**: The WebSocket library must integrate seamlessly with our build system, providing both compile-time and runtime compatibility with Zig 0.15.2.

4. **Thread Safety Requirements**: Phoenix Channels requires concurrent operations (heartbeat thread, message handler thread, application thread). The WebSocket library must support thread-safe operations.

5. **API Abstraction**: Direct dependency on a specific WebSocket implementation couples our code tightly to that library. We need an abstraction layer to allow future flexibility.

### What Problems This Task Solves

- **Establishes Transport Foundation**: Provides the WebSocket communication layer all Phoenix protocol operations depend on
- **Ensures Build Consistency**: Creates reproducible builds across all development and production environments
- **Validates Library Compatibility**: Confirms that karlseguin/websocket.zig works with our Zig version and requirements
- **Enables Development Progress**: Unblocks all subsequent implementation tasks that require network communication
- **Provides Abstraction**: Creates a wrapper that isolates our code from WebSocket library implementation details

---

## Solution Overview

### High-Level Approach

We will integrate karlseguin/websocket.zig as our WebSocket dependency using Zig's native build.zig.zon package management system. The approach consists of four main components:

1. **Package Declaration** (build.zig.zon):
   - Declare websocket.zig dependency with URL and content hash
   - Pin to specific commit/version for stability
   - Configure lazy fetching to optimize build performance

2. **Build Integration** (build.zig):
   - Import websocket module using dependency system
   - Expose websocket module to our library code
   - Configure linking and compilation flags
   - Add websocket to test executables

3. **Verification Testing**:
   - Create minimal test that imports and uses websocket
   - Verify compilation succeeds with no errors
   - Validate thread-safe operations work correctly
   - Confirm API matches our requirements

4. **Wrapper Abstraction Layer**:
   - Create src/websocket_wrapper.zig module
   - Wrap websocket.Client with Phoenix-specific interface
   - Provide connection, send, receive, close operations
   - Add error handling and logging hooks
   - Abstract WebSocket-specific types from rest of codebase

### Why karlseguin/websocket.zig?

Based on research from initial_research.md and current ecosystem analysis:

- **Maturity**: Most battle-tested WebSocket library for Zig
- **Active Maintenance**: Follows Zig master, with branches for stable versions
- **Standards Compliance**: Passes Autobahn WebSocket test suite
- **Thread Safety**: Designed for concurrent access patterns
- **Feature Complete**: Supports all WebSocket features needed (masking, ping/pong, close frames)
- **Zig Version Support**: Master branch targets Zig 0.15.1 (compatible with 0.15.2)
- **Production Usage**: Used in multiple production systems
- **Clean API**: Simple, idiomatic Zig interface

---

## Agent Consultations Performed

### Research Activities Conducted

#### 1. karlseguin/websocket.zig Repository Analysis

**Sources Consulted**:
- GitHub repository: https://github.com/karlseguin/websocket.zig
- README documentation
- Recent issues and activity (2025)

**Key Findings**:
- Master branch targets Zig 0.15.1 (compatible with our 0.15.2)
- Active development with issues opened as recently as May 2025
- 315 stars, 30 forks - healthy community engagement
- Integration with karlseguin's http.zig server demonstrates maturity
- Client API available via websocket.connect() and websocket.Client

**Client API Pattern**:
```zig
// Initialize client
var client = try websocket.Client.init(allocator, .{
    .host = "localhost",
    .port = 9001,
    .tls = false,
});
defer client.deinit();

// Handshake
try client.handshake("/socket/websocket", .{
    .timeout_ms = 5000,
    .headers = "Host: localhost:9001",
});

// Read loop with handler
const handler = Handler{.client = &client};
const thread = try client.readLoopInNewThread(handler);
thread.detach();

// Write operations (thread-safe)
try client.write(data);
try client.writeBin(binary_data);
try client.close(.{.code = 1000, .reason = "normal"});
```

#### 2. Zig 0.15.2 Build System Research

**Sources Consulted**:
- Official Zig documentation: build.zig.zon specification
- Zig 0.15.1 release notes (closest to 0.15.2)
- Community articles on package management

**Key Findings on build.zig.zon Format**:

- **File Purpose**: Manifest for build.zig declaring package metadata and dependencies
- **Format**: Zig Object Notation (ZON) - Zig-native data format similar to JSON

**Required Fields**:
```zig
.{
    .name = "zig_phoenix_channels",
    .version = "0.1.0",
    .paths = .{""},  // Files/dirs included in package
    .dependencies = .{
        .websocket = .{
            .url = "https://github.com/karlseguin/websocket.zig/archive/<commit-hash>.tar.gz",
            .hash = "<multihash>",  // Source of truth for package identity
        },
    },
}
```

**Key Insights**:
- `hash` field is authoritative - URL just provides a mirror
- Hash computed from file contents after applying paths filters
- Can use `.lazy = true` for conditional fetching
- Alternative: `.path` for local dependencies (doesn't require hash)
- Updating URL requires deleting corresponding hash to force recalculation

#### 3. Dependency Integration Best Practices

**Sources Consulted**:
- Zig community articles on package management
- build.zig examples from mature projects
- Zig standard library patterns

**Integration Pattern**:
```zig
// In build.zig
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Import dependency
    const websocket_dep = b.dependency("websocket", .{
        .target = target,
        .optimize = optimize,
    });

    // Get module
    const websocket_mod = websocket_dep.module("websocket");

    // Add to library
    const lib = b.addStaticLibrary(.{
        .name = "phoenix_channels",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib.root_module.addImport("websocket", websocket_mod);
}
```

#### 4. WebSocket Client Requirements Analysis

**Phoenix Channels Specific Needs**:
- Client connection (not server) to Phoenix server
- Send text messages (JSON-encoded Phoenix messages)
- Receive messages in separate thread (readLoopInNewThread)
- Thread-safe write operations (heartbeat thread + application thread)
- Graceful connection close with codes
- Handshake with custom headers (authentication, version)
- Timeout support for handshake and operations

**websocket.zig Capabilities Verification**:
- ✅ Client mode supported via websocket.Client
- ✅ Text message support via client.write()
- ✅ Binary support via client.writeBin() (future: MessagePack)
- ✅ Thread-safe write operations confirmed in documentation
- ✅ readLoopInNewThread() for background message handling
- ✅ Handshake with custom headers and timeout
- ✅ Graceful close with codes and reasons
- ✅ Handler pattern for message callbacks

**API Match Assessment**: 100% compatibility with our requirements

---

## Technical Details

### File Locations

```
zig_phoenix_channels/
├── build.zig.zon                    # NEW: Package manifest with websocket dependency
├── build.zig                         # MODIFIED: Add websocket module import
├── src/
│   ├── main.zig                     # MODIFIED: Import websocket wrapper
│   ├── websocket_wrapper.zig        # NEW: WebSocket abstraction layer
│   └── ...
└── tests/
    └── websocket_integration_test.zig  # NEW: Verify websocket works
```

### build.zig.zon Specification

**Complete build.zig.zon**:
```zig
.{
    .name = "zig_phoenix_channels",
    .version = "0.1.0",

    // Minimum Zig version required
    .minimum_zig_version = "0.15.0",

    // Files included in package
    .paths = .{
        "build.zig",
        "build.zig.zon",
        "src",
        "tests",
        "examples",
        "README.md",
        "LICENSE",
    },

    .dependencies = .{
        .websocket = .{
            // URL points to specific commit for stability
            // Using tarball format: github.com/USER/REPO/archive/COMMIT.tar.gz
            .url = "https://github.com/karlseguin/websocket.zig/archive/COMMIT_SHA_HERE.tar.gz",

            // Hash will be generated on first fetch
            // Run: zig build to trigger hash calculation
            // Zig will output: "error: hash mismatch: expected HASH1, found HASH2"
            // Copy HASH2 into this field
            .hash = "122000000000000000000000000000000000000000000000000000000000000000000000",

            // Lazy fetch - only download if actually used
            .lazy = true,
        },
    },
}
```

**Hash Generation Process**:
1. Add dependency with placeholder hash
2. Run `zig build`
3. Zig fetches package and calculates actual hash
4. Error message shows expected vs actual hash
5. Copy actual hash into build.zig.zon
6. Run `zig build` again - should succeed

### build.zig Integration

**Key Modifications to build.zig**:

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // ======== DEPENDENCY IMPORT ========
    // Import websocket dependency from build.zig.zon
    const websocket_dep = b.dependency("websocket", .{
        .target = target,
        .optimize = optimize,
    });

    // Extract websocket module
    const websocket_mod = websocket_dep.module("websocket");

    // ======== LIBRARY TARGET ========
    const lib = b.addStaticLibrary(.{
        .name = "phoenix_channels",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add websocket module to library imports
    lib.root_module.addImport("websocket", websocket_mod);

    b.installArtifact(lib);

    // ======== TEST TARGET ========
    const main_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add websocket module to tests
    main_tests.root_module.addImport("websocket", websocket_mod);

    const run_main_tests = b.addRunArtifact(main_tests);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_main_tests.step);

    // ======== EXAMPLE TARGET ========
    const example = b.addExecutable(.{
        .name = "websocket_test",
        .root_source_file = b.path("examples/websocket_test.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add websocket module to example
    example.root_module.addImport("websocket", websocket_mod);

    b.installArtifact(example);

    const run_example = b.addRunArtifact(example);
    const example_step = b.step("example", "Run websocket example");
    example_step.dependOn(&run_example.step);
}
```

### WebSocket Wrapper Module Design

**src/websocket_wrapper.zig** - Abstraction Layer:

```zig
const std = @import("std");
const websocket = @import("websocket");

/// WebSocket connection wrapper for Phoenix Channels
/// Provides abstraction over karlseguin/websocket.zig client
pub const WebSocketConnection = struct {
    client: *websocket.Client,
    allocator: std.mem.Allocator,
    handler: ?*anyopaque = null,  // Generic handler pointer

    /// Configuration for WebSocket connection
    pub const Config = struct {
        host: []const u8,
        port: u16,
        path: []const u8 = "/socket/websocket",
        tls: bool = false,
        handshake_timeout_ms: u32 = 5000,
        headers: ?[]const u8 = null,
    };

    /// Initialize WebSocket connection
    pub fn init(allocator: std.mem.Allocator, config: Config) !WebSocketConnection {
        // Create websocket client
        var client = try allocator.create(websocket.Client);
        errdefer allocator.destroy(client);

        client.* = try websocket.Client.init(allocator, .{
            .host = config.host,
            .port = config.port,
            .tls = config.tls,
        });
        errdefer client.deinit();

        // Perform handshake
        try client.handshake(config.path, .{
            .timeout_ms = config.handshake_timeout_ms,
            .headers = config.headers orelse "",
        });

        return WebSocketConnection{
            .client = client,
            .allocator = allocator,
        };
    }

    /// Clean up WebSocket connection
    pub fn deinit(self: *WebSocketConnection) void {
        self.client.deinit();
        self.allocator.destroy(self.client);
    }

    /// Send text message (thread-safe)
    pub fn sendText(self: *WebSocketConnection, data: []const u8) !void {
        try self.client.write(data);
    }

    /// Send binary message (thread-safe)
    pub fn sendBinary(self: *WebSocketConnection, data: []const u8) !void {
        try self.client.writeBin(data);
    }

    /// Close connection gracefully
    pub fn close(self: *WebSocketConnection, code: u16, reason: []const u8) !void {
        try self.client.close(.{
            .code = code,
            .reason = reason,
        });
    }

    /// Start read loop in new thread with handler
    /// Handler must implement: handle(message: websocket.Message) !void
    pub fn startReadLoop(self: *WebSocketConnection, handler: anytype) !std.Thread {
        return try self.client.readLoopInNewThread(handler);
    }
};

// Re-export websocket.Message type for handler implementations
pub const Message = websocket.Message;
```

**Usage Pattern**:
```zig
const ws_wrapper = @import("websocket_wrapper.zig");

// In PhoenixSocket implementation:
var conn = try ws_wrapper.WebSocketConnection.init(allocator, .{
    .host = "localhost",
    .port = 4000,
    .path = "/socket/websocket?vsn=2.0.0",
    .tls = false,
});
defer conn.deinit();

// Send Phoenix message
const json_msg = try serializePhoenixMessage(allocator, msg);
defer allocator.free(json_msg);
try conn.sendText(json_msg);

// Start message handler
const handler = MessageHandler{.socket = self};
const thread = try conn.startReadLoop(handler);
thread.detach();
```

### Module System Integration

**src/main.zig** - Library Entry Point:

```zig
const std = @import("std");

// Re-export WebSocket wrapper
pub const websocket = @import("websocket_wrapper.zig");

// Future exports
// pub const Socket = @import("connection/socket.zig").Socket;
// pub const Channel = @import("channel/channel.zig").Channel;
// pub const Message = @import("protocol/message.zig").Message;

test {
    std.testing.refAllDecls(@This());
}
```

### WebSocket API Surface to Expose

**Required Operations** (from Phoenix protocol needs):

1. **Connection Management**:
   - `init()` - Create connection with config
   - `deinit()` - Clean up connection
   - `close()` - Graceful close with code/reason

2. **Message Sending** (must be thread-safe):
   - `sendText()` - Send Phoenix JSON messages
   - `sendBinary()` - Future: MessagePack serialization

3. **Message Receiving**:
   - `startReadLoop()` - Background thread for message handling
   - Handler interface for message callbacks

4. **Error Handling**:
   - Connection errors
   - Send/receive errors
   - Timeout errors

**Not Exposed** (internal to wrapper):
- Low-level WebSocket frame details
- Masking operations
- Ping/pong frame handling (automatic)
- Fragment handling (automatic)

---

## Success Criteria

### Critical Success Criteria (Must Pass)

1. **Build System Integration**:
   - ✅ `zig build` completes without errors
   - ✅ build.zig.zon correctly declares websocket dependency
   - ✅ Dependency hash verification succeeds
   - ✅ Module imports work in src/ files

2. **Compilation Verification**:
   - ✅ Library compiles with websocket import
   - ✅ Test suite compiles with websocket import
   - ✅ Example programs compile with websocket import
   - ✅ No linker errors or symbol conflicts

3. **Runtime Verification**:
   - ✅ Can create WebSocket client instance
   - ✅ Can connect to test WebSocket server
   - ✅ Can send text message successfully
   - ✅ Can receive messages via handler
   - ✅ Can close connection gracefully
   - ✅ No crashes or memory corruption

4. **Thread Safety Verification**:
   - ✅ Concurrent writes from multiple threads succeed
   - ✅ Read loop in separate thread works correctly
   - ✅ No race conditions or deadlocks
   - ✅ Clean shutdown with active threads

5. **Wrapper Module Quality**:
   - ✅ Wrapper compiles and links correctly
   - ✅ API is ergonomic for Phoenix use cases
   - ✅ Error handling is comprehensive
   - ✅ Memory management is correct (no leaks)

### Non-Critical Success Criteria (Nice to Have)

- 📋 Documentation for wrapper API
- 📋 Example demonstrating all wrapper operations
- 📋 Performance benchmarks for send/receive
- 📋 Comparison with alternative WebSocket libraries

### Test Requirements

**Unit Tests** (tests/websocket_wrapper_test.zig):
```zig
test "WebSocketConnection init and deinit" {
    const allocator = std.testing.allocator;

    var conn = try WebSocketConnection.init(allocator, .{
        .host = "echo.websocket.org",
        .port = 80,
        .tls = false,
    });
    defer conn.deinit();

    // Should not crash or leak memory
}

test "WebSocketConnection sendText" {
    // Connect to echo server
    // Send message
    // Verify no errors
}

test "WebSocketConnection concurrent writes" {
    // Spawn multiple threads
    // Each thread sends messages
    // Verify all succeed
}
```

**Integration Test** (examples/websocket_test.zig):
```zig
const std = @import("std");
const websocket_wrapper = @import("websocket_wrapper");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("Connecting to echo.websocket.org...\n", .{});

    var conn = try websocket_wrapper.WebSocketConnection.init(allocator, .{
        .host = "echo.websocket.org",
        .port = 80,
        .path = "/",
        .tls = false,
    });
    defer conn.deinit();

    std.debug.print("Connected! Sending message...\n", .{});

    try conn.sendText("Hello WebSocket!");

    std.debug.print("Message sent. Closing connection...\n", .{});

    try conn.close(1000, "Test complete");

    std.debug.print("Test passed!\n", .{});
}
```

---

## Implementation Plan

### Task Breakdown with Test Requirements

#### Task 1.1.2.1: Add websocket.zig dependency to build.zig.zon

**Implementation Steps**:

1. Research latest stable commit of karlseguin/websocket.zig
   - Visit https://github.com/karlseguin/websocket.zig
   - Check master branch for Zig 0.15.1 compatibility
   - Identify specific commit SHA to pin

2. Create build.zig.zon file
   - Add package metadata (name, version, paths)
   - Add websocket dependency with URL
   - Use placeholder hash initially
   - Document hash generation process in comments

3. Generate correct hash
   - Run `zig build`
   - Copy actual hash from error message
   - Update build.zig.zon with correct hash
   - Re-run `zig build` to verify

**Verification Tests**:
```bash
# Should succeed after hash is correct
zig build

# Should show websocket in dependency tree
zig build --help | grep websocket
```

**Success Criteria**:
- ✅ build.zig.zon exists and is syntactically valid
- ✅ `zig build` fetches websocket dependency
- ✅ Hash verification passes
- ✅ No fetch or parsing errors

**Estimated Time**: 1-2 hours

---

#### Task 1.1.2.2: Configure dependency fetch and build integration

**Implementation Steps**:

1. Modify build.zig to import websocket
   - Add `b.dependency("websocket", ...)` call
   - Extract websocket module
   - Store in variable for reuse

2. Add websocket to library target
   - Get or create library target
   - Call `lib.root_module.addImport("websocket", websocket_mod)`
   - Verify library compiles with import

3. Add websocket to test target
   - Get or create test target
   - Call `test.root_module.addImport("websocket", websocket_mod)`
   - Verify tests compile with import

4. Add websocket to example target
   - Create example executable target
   - Add websocket import
   - Create simple example program

**Verification Tests**:
```bash
# All should compile successfully
zig build
zig build test
zig build example
```

**Success Criteria**:
- ✅ Library compiles with websocket import
- ✅ Tests compile with websocket import
- ✅ Examples compile with websocket import
- ✅ No linker errors

**Estimated Time**: 2-3 hours

---

#### Task 1.1.2.3: Verify WebSocket library compiles and links correctly

**Implementation Steps**:

1. Create minimal test file
   - Import websocket module
   - Create test that instantiates Client
   - Verify compilation

2. Create integration test
   - Connect to public echo server
   - Send test message
   - Verify no crashes

3. Test thread safety
   - Create test with concurrent writes
   - Verify no race conditions

4. Test error handling
   - Test connection timeout
   - Test invalid host
   - Verify errors are catchable

**Test Files to Create**:

**tests/websocket_basic_test.zig**:
```zig
const std = @import("std");
const websocket = @import("websocket");
const testing = std.testing;

test "websocket module imports correctly" {
    // Should compile - just verifies module loads
}

test "can create websocket client config" {
    // Verify types are accessible
    _ = websocket.Client;
}
```

**examples/websocket_echo_test.zig**:
```zig
const std = @import("std");
const websocket = @import("websocket");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("Memory leaked!\n", .{});
        }
    }
    const allocator = gpa.allocator();

    std.debug.print("Testing WebSocket connection...\n", .{});

    // Connect to public echo server
    var client = try websocket.Client.init(allocator, .{
        .host = "echo.websocket.org",
        .port = 80,
        .tls = false,
    });
    defer client.deinit();

    std.debug.print("Client initialized\n", .{});

    try client.handshake("/", .{
        .timeout_ms = 5000,
        .headers = "Host: echo.websocket.org",
    });

    std.debug.print("Handshake complete\n", .{});

    try client.write("Test message");

    std.debug.print("Message sent\n", .{});

    try client.close(.{.code = 1000, .reason = "test complete"});

    std.debug.print("Connection closed - test passed!\n", .{});
}
```

**Verification Commands**:
```bash
# Run basic tests
zig build test

# Run integration test
zig build example
./zig-out/bin/websocket_echo_test
```

**Success Criteria**:
- ✅ Basic import test compiles
- ✅ Integration test connects successfully
- ✅ Can send and close connection
- ✅ No memory leaks detected
- ✅ Error handling works correctly

**Estimated Time**: 3-4 hours

---

#### Task 1.1.2.4: Create wrapper module for WebSocket client abstraction

**Implementation Steps**:

1. Design wrapper API
   - Identify Phoenix-specific needs
   - Design minimal, clean interface
   - Document intended usage

2. Implement src/websocket_wrapper.zig
   - Create WebSocketConnection struct
   - Implement init/deinit
   - Implement send operations
   - Implement read loop integration
   - Add error handling

3. Write wrapper tests
   - Test init/deinit
   - Test send operations
   - Test thread safety
   - Test error conditions

4. Create wrapper example
   - Demonstrate all wrapper operations
   - Show recommended patterns
   - Document gotchas and best practices

5. Update src/main.zig
   - Re-export wrapper module
   - Add top-level documentation

**Implementation File**: src/websocket_wrapper.zig

(See complete implementation in Technical Details section above)

**Test File**: tests/websocket_wrapper_test.zig

```zig
const std = @import("std");
const testing = std.testing;
const ws_wrapper = @import("websocket_wrapper");

test "WebSocketConnection - init and deinit" {
    const allocator = testing.allocator;

    // Should be able to create and destroy without issues
    var conn = try ws_wrapper.WebSocketConnection.init(allocator, .{
        .host = "echo.websocket.org",
        .port = 80,
        .tls = false,
    });
    defer conn.deinit();

    // If we get here, init/deinit work
    try testing.expect(true);
}

test "WebSocketConnection - sendText" {
    const allocator = testing.allocator;

    var conn = try ws_wrapper.WebSocketConnection.init(allocator, .{
        .host = "echo.websocket.org",
        .port = 80,
    });
    defer conn.deinit();

    try conn.sendText("Test message");

    // Should not crash or error
}

test "WebSocketConnection - close with reason" {
    const allocator = testing.allocator;

    var conn = try ws_wrapper.WebSocketConnection.init(allocator, .{
        .host = "echo.websocket.org",
        .port = 80,
    });
    defer conn.deinit();

    try conn.close(1000, "Normal closure");

    // Should close gracefully
}

test "WebSocketConnection - concurrent writes" {
    const allocator = testing.allocator;

    var conn = try ws_wrapper.WebSocketConnection.init(allocator, .{
        .host = "echo.websocket.org",
        .port = 80,
    });
    defer conn.deinit();

    // TODO: Spawn multiple threads sending messages
    // Verify no race conditions or crashes
}
```

**Example File**: examples/wrapper_demo.zig

```zig
const std = @import("std");
const ws_wrapper = @import("websocket_wrapper");

const MessageHandler = struct {
    pub fn handle(_: MessageHandler, message: ws_wrapper.Message) !void {
        std.debug.print("Received: {s}\n", .{message.data});
    }

    pub fn close(_: MessageHandler) void {
        std.debug.print("Connection closed by server\n", .{});
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("WebSocket Wrapper Demo\n", .{});
    std.debug.print("=======================\n\n", .{});

    std.debug.print("1. Connecting to echo server...\n", .{});
    var conn = try ws_wrapper.WebSocketConnection.init(allocator, .{
        .host = "echo.websocket.org",
        .port = 80,
        .path = "/",
        .tls = false,
        .handshake_timeout_ms = 5000,
    });
    defer conn.deinit();
    std.debug.print("   ✓ Connected\n\n", .{});

    std.debug.print("2. Starting message handler in background thread...\n", .{});
    const handler = MessageHandler{};
    const thread = try conn.startReadLoop(handler);
    thread.detach();
    std.debug.print("   ✓ Handler started\n\n", .{});

    std.debug.print("3. Sending text message...\n", .{});
    try conn.sendText("Hello from Zig Phoenix Channels!");
    std.debug.print("   ✓ Message sent\n\n", .{});

    std.debug.print("4. Waiting for echo...\n", .{});
    std.time.sleep(2 * std.time.ns_per_s);
    std.debug.print("   ✓ Message should have been echoed\n\n", .{});

    std.debug.print("5. Closing connection...\n", .{});
    try conn.close(1000, "Demo complete");
    std.debug.print("   ✓ Connection closed gracefully\n\n", .{});

    std.debug.print("Demo complete!\n", .{});
}
```

**Verification Commands**:
```bash
# Run wrapper tests
zig build test --summary all

# Run wrapper demo
zig build
./zig-out/bin/wrapper_demo
```

**Success Criteria**:
- ✅ Wrapper module compiles without errors
- ✅ All wrapper tests pass
- ✅ Wrapper demo runs successfully
- ✅ API is clean and Phoenix-specific
- ✅ Error handling is comprehensive
- ✅ No memory leaks in wrapper
- ✅ Thread safety verified

**Estimated Time**: 4-6 hours

---

### Total Estimated Time

- Task 1.1.2.1: 1-2 hours
- Task 1.1.2.2: 2-3 hours
- Task 1.1.2.3: 3-4 hours
- Task 1.1.2.4: 4-6 hours
- **Total: 10-15 hours (1.5-2 days)**

### Task Dependencies

```
1.1.2.1 (build.zig.zon)
    ↓
1.1.2.2 (build.zig integration)
    ↓
1.1.2.3 (verification)
    ↓
1.1.2.4 (wrapper module)
```

All tasks must be completed sequentially. Each task depends on the previous one.

---

## Notes and Considerations

### Version Pinning Strategy

**Why Pin to Specific Commit**:
- Ensures reproducible builds across all environments
- Prevents breaking changes from upstream updates
- Allows controlled upgrades with testing
- Documents exact dependency version used

**Pinning Process**:
1. Identify latest stable commit on master branch
2. Test locally to verify compatibility
3. Pin to that commit SHA in build.zig.zon URL
4. Document commit SHA and date in comments
5. Periodically review for security updates

**Upgrade Process**:
1. Test new commit in feature branch
2. Run full test suite
3. Update build.zig.zon commit SHA
4. Regenerate hash
5. Update documentation
6. Merge after CI passes

### Edge Cases and Gotchas

#### 1. Hash Mismatch Errors

**Problem**: First `zig build` will fail with hash mismatch

**Solution**: This is expected! Copy actual hash from error into build.zig.zon

**Example**:
```
error: hash mismatch:
  expected: 1220abc...
  found:    1220def...
```
Copy `1220def...` into `.hash` field.

#### 2. Websocket Module Not Found

**Problem**: Import fails with "module 'websocket' not found"

**Possible Causes**:
- Dependency not declared in build.zig.zon
- Module not added to target in build.zig
- Typo in module name

**Solution**: Verify dependency chain:
1. build.zig.zon declares dependency
2. build.zig imports dependency
3. build.zig adds module to target
4. Source file imports with correct name

#### 3. Thread Safety Issues

**Problem**: Crashes or race conditions with concurrent writes

**Investigation**:
- websocket.zig client.write() is thread-safe per documentation
- If issues occur, add mutex in wrapper layer
- Verify we're not mixing read/write from same thread

**Mitigation**: Wrapper module can add additional locking if needed

#### 4. Memory Leaks in Long-Running Connections

**Problem**: Memory usage grows over time

**Investigation**:
- Ensure all messages are properly freed
- Verify arena allocators are reset/freed
- Check for accumulated state

**Mitigation**:
- Use GeneralPurposeAllocator in debug builds
- Regular leak testing
- Arena allocators for message processing

#### 5. Handshake Timeout on Slow Networks

**Problem**: Connection fails on slow/high-latency networks

**Solution**:
- Make handshake timeout configurable
- Default to 5000ms (reasonable for most cases)
- Allow override via config
- Document timeout requirements

### Security Considerations

#### 1. Dependency Trust

**Risk**: External dependency could be compromised

**Mitigations**:
- Pin to specific commit (immutable)
- Hash verification ensures integrity
- Review websocket.zig code periodically
- Monitor security advisories
- Consider vendoring for production

#### 2. TLS/SSL Support

**Current Status**: websocket.zig supports TLS

**Considerations**:
- Production deployments should use WSS (TLS)
- Certificate validation required
- CA bundle management
- Certificate pinning for extra security

**Future Work**: Configure TLS properly in Phase 2

#### 3. Input Validation

**Risk**: Malformed WebSocket frames could crash client

**Mitigations**:
- websocket.zig handles frame parsing
- We validate Phoenix message format separately
- Catch and handle all parsing errors
- Never panic on network input

### Performance Considerations

#### 1. Allocation Strategy

**Current Approach**:
- Use provided allocator throughout
- Avoid allocations in hot paths where possible
- Pre-allocate buffers for common message sizes

**Future Optimizations**:
- Pool allocator for message buffers
- Fixed-size buffers for heartbeats
- Reduce allocations in send path

#### 2. Thread Model

**Current Design**:
- Read loop in separate thread (websocket.zig pattern)
- Write operations from multiple threads (heartbeat + app)
- Mutex protection where needed

**Considerations**:
- Thread creation overhead (one-time cost)
- Context switching (minimal impact)
- Lock contention (unlikely with our access pattern)

#### 3. Message Throughput

**Expected Performance**:
- websocket.zig is production-tested
- Should handle thousands of messages/second
- Bottleneck likely in JSON serialization, not WebSocket

**Future Optimizations**:
- MessagePack serialization (binary)
- Batch message sending
- Zero-copy message handling

### Future Improvements

#### 1. Alternative WebSocket Libraries

**Current**: karlseguin/websocket.zig (thread-based)

**Alternatives to Consider**:
- async_zocket (event loop based)
- Custom implementation (full control)

**Decision**: Wrapper module makes switching easier if needed

#### 2. WebSocket Extensions

**Not Currently Used**:
- Compression (permessage-deflate)
- Subprotocols
- Extensions negotiation

**Future**: Could add compression support for bandwidth reduction

#### 3. Connection Pooling

**Not Needed Now**: Single connection per client

**Future**: Multiple connections for load distribution or failover

#### 4. Metrics and Monitoring

**Future Additions**:
- Connection uptime
- Message counts (sent/received)
- Error rates
- Latency measurements
- Reconnection statistics

### Testing Strategy

#### Unit Tests
- Wrapper module in isolation
- Mock WebSocket for testing error cases
- Memory leak detection

#### Integration Tests
- Real WebSocket echo server
- Phoenix test server (Phase 1.6)
- Concurrent access tests

#### Performance Tests
- Message throughput benchmarks
- Memory usage over time
- Thread overhead measurement

#### Compatibility Tests
- Different Zig versions (0.15.x)
- Different platforms (Linux, macOS, Windows)
- Different WebSocket servers

---

## Dependencies

### Upstream Dependencies

This task depends on:
- **1.1.1 Build System Configuration**: Must have working build.zig before adding dependencies

### Downstream Dependencies

These tasks depend on this task:
- **1.1.3 Project Structure**: Needs working WebSocket to create connection modules
- **1.2 Message Format**: Will use WebSocket to send serialized messages
- **1.3 Socket State Machine**: Wraps WebSocket connection
- **All subsequent phases**: Entire library depends on WebSocket transport

### External Dependencies

- **karlseguin/websocket.zig**: External library (stable, actively maintained)
- **Zig 0.15.2**: Build system and standard library
- **Internet connection**: For dependency fetch (one-time)

---

## Approval and Sign-off

This planning document should be reviewed and approved before implementation begins.

**Review Checklist**:
- [ ] Problem statement accurately describes the need
- [ ] Solution approach is sound and follows best practices
- [ ] Technical details are comprehensive and correct
- [ ] Success criteria are measurable and achievable
- [ ] Implementation plan is detailed and realistic
- [ ] Time estimates are reasonable
- [ ] Edge cases and security considerations addressed
- [ ] Testing strategy is comprehensive

**Reviewers**:
- [ ] Senior Engineer - Architecture and approach
- [ ] Security Reviewer - Security considerations
- [ ] QA Reviewer - Testing strategy and success criteria

**Approval Required Before**: Starting Task 1.1.2.1

---

## Revision History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2025-10-17 | feature-planner | Initial comprehensive planning document |

---

## Appendix

### A. Useful Commands

```bash
# Fetch dependencies
zig build

# Run tests
zig build test --summary all

# Run specific test
zig build test --summary all -Dtest-filter="websocket"

# Run example
zig build example
./zig-out/bin/websocket_echo_test

# Clean build artifacts
rm -rf zig-cache/ zig-out/

# Check for memory leaks
zig build test -Doptimize=Debug

# View dependency tree
zig build --verbose
```

### B. Reference Links

**External Resources**:
- karlseguin/websocket.zig: https://github.com/karlseguin/websocket.zig
- Zig build.zig.zon spec: https://github.com/ziglang/zig/blob/master/doc/build.zig.zon.md
- Zig package manager guide: https://zig.news/edyu/zig-package-manager-wtf-is-zon-558e
- WebSocket RFC 6455: https://datatracker.ietf.org/doc/html/rfc6455

**Project References**:
- research/initial_research.md - Detailed protocol and implementation research
- planning/phase-01.md - Complete Phase 1 plan
- CLAUDE.md - Project guidelines and architecture overview

### C. Troubleshooting Guide

**Problem**: zig build fails with "dependency not found"

**Solution**:
1. Verify build.zig.zon exists
2. Check dependency name spelling
3. Ensure hash is correct
4. Try deleting zig-cache/ and rebuilding

**Problem**: Tests hang or timeout

**Solution**:
1. Check network connectivity to echo server
2. Increase handshake timeout
3. Verify firewall not blocking connections
4. Try different echo server

**Problem**: Memory leaks reported

**Solution**:
1. Ensure all deinit() calls are made
2. Check for missing defer statements
3. Verify arena allocators are freed
4. Use GeneralPurposeAllocator for leak detection

**Problem**: Thread safety issues

**Solution**:
1. Verify writes from different threads
2. Check for shared mutable state
3. Add additional mutex protection in wrapper
4. Review karlseguin/websocket.zig thread safety guarantees

---

**End of Document**
