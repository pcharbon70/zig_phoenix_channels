# Feature Planning: Project Structure (Task 1.1.3)

## Problem Statement

The Phoenix Channels Zig library requires a well-organized directory structure that clearly separates concerns and supports future development. Currently, the project has minimal structure (planning and research directories only, no source code). We need to establish a logical organization that:

1. Separates protocol implementation from connection management and channel logic
2. Follows Zig conventions for library organization and module structure
3. Provides clear boundaries between components (protocol, connection, channel)
4. Enables straightforward testing with corresponding test files
5. Supports example applications for demonstration and validation
6. Scales to accommodate future features (presence, binary messages, advanced features)

Without proper structure, the codebase becomes difficult to navigate, modules become tightly coupled, and future changes become costly. A well-designed structure established early prevents technical debt and facilitates parallel development.

## Solution Overview

We will create a hierarchical directory structure that mirrors the architectural components of the Phoenix Channels protocol:

```
/home/ducky/code/zig_phoenix_channels/
├── src/                          # Library source code
│   ├── root.zig                  # Main library entry point (public API)
│   ├── protocol/                 # Protocol layer: message format and serialization
│   │   ├── message.zig          # PhoenixMessage struct and serialization
│   │   ├── serializer.zig       # JSON serialization/deserialization
│   │   └── protocol.zig         # Protocol constants and validation
│   ├── connection/               # Connection layer: Socket and WebSocket management
│   │   ├── socket.zig           # PhoenixSocket struct and connection management
│   │   ├── state.zig            # ConnectionState enum and transitions
│   │   └── websocket_wrapper.zig # WebSocket client abstraction
│   ├── channel/                  # Channel layer: Channel logic and state
│   │   ├── channel.zig          # Channel struct and operations
│   │   └── state.zig            # ChannelState enum and transitions
│   └── common/                   # Shared utilities and types
│       ├── errors.zig           # Error sets and error handling
│       ├── types.zig            # Common types and aliases
│       └── config.zig           # Configuration structs
├── tests/                        # Test files mirroring src/ structure
│   ├── protocol/
│   │   ├── message_test.zig
│   │   ├── serializer_test.zig
│   │   └── protocol_test.zig
│   ├── connection/
│   │   ├── socket_test.zig
│   │   └── state_test.zig
│   ├── channel/
│   │   ├── channel_test.zig
│   │   └── state_test.zig
│   ├── integration/              # Integration tests against Phoenix server
│   │   ├── basic_flow_test.zig
│   │   └── multi_channel_test.zig
│   └── test_utils.zig           # Shared test utilities
├── examples/                     # Example applications
│   ├── basic_connection.zig     # Minimal connection example
│   ├── chat_client.zig          # Chat application example
│   └── README.md                # Examples documentation
├── build.zig                     # Build configuration
├── build.zig.zon                # Dependency configuration
└── CLAUDE.md                     # Project guidance
```

### Key Design Decisions

1. **Three-Layer Architecture**: Protocol → Connection → Channel
   - Protocol layer handles message format independently of transport
   - Connection layer manages WebSocket lifecycle and state
   - Channel layer implements channel-specific logic

2. **Separate State Modules**: Each component (Socket, Channel) has dedicated state.zig
   - Encapsulates state machine logic
   - Makes state transitions explicit and testable
   - Prevents state management code from cluttering main components

3. **Common Module**: Shared types, errors, and configuration
   - Avoids circular dependencies
   - Provides single source of truth for shared definitions
   - Makes error handling consistent across library

4. **Mirror Test Structure**: tests/ mirrors src/ directory structure
   - Easy to locate corresponding test file
   - Enables parallel development of code and tests
   - Supports comprehensive test coverage

5. **Integration Tests Separate**: Distinct integration/ subdirectory
   - Requires Phoenix server (different setup than unit tests)
   - Tests end-to-end scenarios
   - Can be run separately from fast unit tests

## Technical Details

### Module Hierarchy and Responsibilities

#### src/root.zig (Library Entry Point)
```zig
// Public API exported by the library
pub const PhoenixSocket = @import("connection/socket.zig").PhoenixSocket;
pub const Channel = @import("channel/channel.zig").Channel;
pub const PhoenixMessage = @import("protocol/message.zig").PhoenixMessage;

// Re-export commonly used types
pub const ConnectionState = @import("connection/state.zig").ConnectionState;
pub const ChannelState = @import("channel/state.zig").ChannelState;

// Configuration
pub const SocketConfig = @import("common/config.zig").SocketConfig;
pub const ChannelConfig = @import("common/config.zig").ChannelConfig;

// Errors
pub const PhoenixError = @import("common/errors.zig").PhoenixError;
```

#### src/protocol/ (Protocol Layer)

**message.zig**: PhoenixMessage struct representing the 5-field protocol format
```zig
pub const PhoenixMessage = struct {
    join_ref: ?[]const u8,
    ref: ?[]const u8,
    topic: []const u8,
    event: []const u8,
    payload: std.json.Value,

    pub fn init(...) PhoenixMessage { ... }
    pub fn deinit(self: *PhoenixMessage) void { ... }
};
```

**serializer.zig**: JSON serialization/deserialization
```zig
pub fn serialize(allocator: Allocator, msg: PhoenixMessage) ![]u8 { ... }
pub fn deserialize(allocator: Allocator, data: []const u8) !PhoenixMessage { ... }
```

**protocol.zig**: Protocol constants and validation
```zig
pub const PROTOCOL_VERSION = "2.0.0";
pub const SYSTEM_EVENTS = [_][]const u8{ "phx_join", "phx_leave", "phx_reply", "phx_error", "phx_close" };
pub fn validateMessage(msg: *const PhoenixMessage) !void { ... }
```

#### src/connection/ (Connection Layer)

**socket.zig**: PhoenixSocket managing WebSocket connection
```zig
pub const PhoenixSocket = struct {
    allocator: Allocator,
    state: ConnectionState,
    ws_client: *WebSocketWrapper,
    ref_counter: u64,
    mutex: std.Thread.Mutex,

    pub fn init(allocator: Allocator, config: SocketConfig) !PhoenixSocket { ... }
    pub fn deinit(self: *PhoenixSocket) void { ... }
    pub fn connect(self: *PhoenixSocket, url: []const u8) !void { ... }
    pub fn disconnect(self: *PhoenixSocket) void { ... }
    pub fn send(self: *PhoenixSocket, msg: PhoenixMessage) !void { ... }
    pub fn makeRef(self: *PhoenixSocket) []const u8 { ... }
};
```

**state.zig**: ConnectionState enum and transitions
```zig
pub const ConnectionState = enum {
    disconnected,
    connecting,
    connected,
    closing,
    error_state,

    pub fn canTransitionTo(self: ConnectionState, next: ConnectionState) bool { ... }
};
```

**websocket_wrapper.zig**: WebSocket client abstraction
```zig
pub const WebSocketWrapper = struct {
    // Wraps karlseguin/websocket.zig with our interface
    pub fn init(allocator: Allocator) !WebSocketWrapper { ... }
    pub fn connect(self: *WebSocketWrapper, url: []const u8) !void { ... }
    pub fn send(self: *WebSocketWrapper, data: []const u8) !void { ... }
    pub fn close(self: *WebSocketWrapper) void { ... }
};
```

#### src/channel/ (Channel Layer)

**channel.zig**: Channel struct and operations
```zig
pub const Channel = struct {
    allocator: Allocator,
    socket: *PhoenixSocket,
    topic: []const u8,
    state: ChannelState,
    join_ref: ?[]const u8,
    mutex: std.Thread.Mutex,

    pub fn init(allocator: Allocator, socket: *PhoenixSocket, topic: []const u8) !Channel { ... }
    pub fn deinit(self: *Channel) void { ... }
    pub fn join(self: *Channel, params: std.json.Value) !void { ... }
    pub fn leave(self: *Channel) !void { ... }
    pub fn push(self: *Channel, event: []const u8, payload: std.json.Value) !void { ... }
    pub fn on(self: *Channel, event: []const u8, callback: CallbackFn) !void { ... }
};
```

**state.zig**: ChannelState enum and transitions
```zig
pub const ChannelState = enum {
    closed,
    joining,
    joined,
    leaving,
    error_state,

    pub fn canTransitionTo(self: ChannelState, next: ChannelState) bool { ... }
};
```

#### src/common/ (Shared Utilities)

**errors.zig**: Comprehensive error sets
```zig
pub const ConnectionError = error{
    ConnectionFailed,
    Disconnected,
    Timeout,
    InvalidState,
};

pub const ProtocolError = error{
    InvalidMessage,
    UnknownTopic,
    MalformedPayload,
};

pub const ChannelError = error{
    JoinFailed,
    NotJoined,
    AlreadyJoined,
};

pub const PhoenixError = ConnectionError || ProtocolError || ChannelError || std.mem.Allocator.Error;
```

**types.zig**: Common type definitions
```zig
pub const CallbackFn = *const fn (payload: std.json.Value) void;
pub const ReplyCallback = *const fn (status: []const u8, response: std.json.Value) void;
```

**config.zig**: Configuration structs
```zig
pub const SocketConfig = struct {
    heartbeat_interval_ms: u32 = 30000,
    reconnect_after_ms: []const u32 = &[_]u32{ 1000, 5000, 10000 },
    timeout_ms: u32 = 10000,
};

pub const ChannelConfig = struct {
    rejoin_after_ms: []const u32 = &[_]u32{ 1000, 5000, 10000 },
    timeout_ms: u32 = 10000,
};
```

### Import Patterns

**From Application Code**:
```zig
const phoenix = @import("phoenix");

var socket = try phoenix.PhoenixSocket.init(allocator, .{});
const channel = try socket.channel("room:lobby");
```

**Within Library** (from src/connection/socket.zig):
```zig
const std = @import("std");
const PhoenixMessage = @import("../protocol/message.zig").PhoenixMessage;
const ConnectionState = @import("state.zig").ConnectionState;
const PhoenixError = @import("../common/errors.zig").PhoenixError;
const SocketConfig = @import("../common/config.zig").SocketConfig;
```

### Build System Integration

**build.zig** will define:
```zig
// Library target
const lib = b.addStaticLibrary(.{
    .name = "phoenix",
    .root_source_file = .{ .path = "src/root.zig" },
    .target = target,
    .optimize = optimize,
});

// Test targets
const protocol_tests = b.addTest(.{
    .root_source_file = .{ .path = "tests/protocol/message_test.zig" },
    .target = target,
    .optimize = optimize,
});

// Example executables
const basic_example = b.addExecutable(.{
    .name = "basic_connection",
    .root_source_file = .{ .path = "examples/basic_connection.zig" },
    .target = target,
    .optimize = optimize,
});
basic_example.linkLibrary(lib);
```

## Success Criteria

The project structure is complete when:

1. **All directories exist**: src/, src/protocol/, src/connection/, src/channel/, src/common/, tests/, examples/
2. **All module files created**: Each component has its corresponding .zig file
3. **Files compile**: All placeholder modules compile without errors (even if implementations are minimal)
4. **Imports work**: root.zig can import all modules, examples can import library
5. **Tests discoverable**: Build system can find and run test files
6. **Clear boundaries**: Each module has single responsibility, minimal coupling
7. **Documentation present**: Each module has top-level doc comments explaining purpose

### Verification Steps

```bash
# 1. Directory structure exists
ls -R src/ tests/ examples/

# 2. Library compiles
zig build

# 3. Tests compile (even if empty)
zig build test

# 4. Examples compile
zig build examples

# 5. Module imports work (no circular dependencies)
zig build check

# 6. Project tree is clean
tree -I 'zig-cache|zig-out|.git'
```

## Implementation Plan

### Step 1: Create Directory Structure
**Task**: Create all directories following the planned hierarchy

**Commands**:
```bash
mkdir -p src/protocol
mkdir -p src/connection
mkdir -p src/channel
mkdir -p src/common
mkdir -p tests/protocol
mkdir -p tests/connection
mkdir -p tests/channel
mkdir -p tests/integration
mkdir -p examples
```

**Verification**: All directories exist and are empty

### Step 2: Create Protocol Layer Files
**Task**: Create placeholder files for protocol layer with basic structure

**Files**:
- `src/protocol/message.zig`: PhoenixMessage struct stub
- `src/protocol/serializer.zig`: Serialize/deserialize function stubs
- `src/protocol/protocol.zig`: Protocol constants

**Structure for each file**:
```zig
//! Module documentation explaining purpose
//!
//! This module is part of the Phoenix Channels protocol implementation.

const std = @import("std");

// Type definitions and functions here

test "module loads" {
    // Basic test to verify compilation
}
```

**Verification**: `zig test src/protocol/message.zig` succeeds

### Step 3: Create Connection Layer Files
**Task**: Create placeholder files for connection layer

**Files**:
- `src/connection/socket.zig`: PhoenixSocket struct stub
- `src/connection/state.zig`: ConnectionState enum
- `src/connection/websocket_wrapper.zig`: WebSocket wrapper stub

**Dependencies**: Import from `../protocol/` and `../common/`

**Verification**: Files compile with cross-module imports

### Step 4: Create Channel Layer Files
**Task**: Create placeholder files for channel layer

**Files**:
- `src/channel/channel.zig`: Channel struct stub
- `src/channel/state.zig`: ChannelState enum

**Dependencies**: Import from `../protocol/`, `../connection/`, and `../common/`

**Verification**: Files compile with all imports

### Step 5: Create Common Module Files
**Task**: Create shared utilities module

**Files**:
- `src/common/errors.zig`: Error set definitions
- `src/common/types.zig`: Common type aliases
- `src/common/config.zig`: Configuration structs

**Note**: This module should have no dependencies on other library modules (to avoid circular dependencies)

**Verification**: Common module is self-contained

### Step 6: Create Library Entry Point
**Task**: Create `src/root.zig` that exports public API

**Content**:
- Import all major types from submodules
- Re-export public API
- Add module-level documentation

**Template**:
```zig
//! Phoenix Channels client library for Zig
//!
//! This library provides a complete implementation of the Phoenix Channels
//! protocol, enabling real-time communication with Phoenix/Elixir servers.
//!
//! # Quick Start
//! ```zig
//! const phoenix = @import("phoenix");
//!
//! var socket = try phoenix.PhoenixSocket.init(allocator, .{});
//! defer socket.deinit();
//!
//! try socket.connect("ws://localhost:4000/socket/websocket");
//! const channel = try socket.channel("room:lobby");
//! try channel.join(.{});
//! ```

const std = @import("std");

// Public API exports
pub const PhoenixSocket = @import("connection/socket.zig").PhoenixSocket;
pub const Channel = @import("channel/channel.zig").Channel;
pub const PhoenixMessage = @import("protocol/message.zig").PhoenixMessage;

// State types
pub const ConnectionState = @import("connection/state.zig").ConnectionState;
pub const ChannelState = @import("channel/state.zig").ChannelState;

// Configuration
pub const SocketConfig = @import("common/config.zig").SocketConfig;
pub const ChannelConfig = @import("common/config.zig").ChannelConfig;

// Errors
pub const PhoenixError = @import("common/errors.zig").PhoenixError;

test {
    // Include all submodule tests
    std.testing.refAllDecls(@This());
}
```

**Verification**: `zig build` compiles the library

### Step 7: Create Test Files
**Task**: Create test file stubs mirroring src/ structure

**Files**:
- `tests/protocol/message_test.zig`
- `tests/protocol/serializer_test.zig`
- `tests/protocol/protocol_test.zig`
- `tests/connection/socket_test.zig`
- `tests/connection/state_test.zig`
- `tests/channel/channel_test.zig`
- `tests/channel/state_test.zig`
- `tests/integration/basic_flow_test.zig`
- `tests/test_utils.zig`

**Template for test files**:
```zig
const std = @import("std");
const testing = std.testing;
const ModuleName = @import("../../src/module/file.zig").ModuleName;

test "placeholder test" {
    // Placeholder to verify test infrastructure
    try testing.expect(true);
}
```

**Verification**: `zig build test` runs successfully

### Step 8: Create Example Files
**Task**: Create example application stubs

**Files**:
- `examples/basic_connection.zig`: Minimal connection example
- `examples/README.md`: Examples documentation

**Template for examples**:
```zig
const std = @import("std");
const phoenix = @import("phoenix");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("Phoenix Channels Basic Connection Example\n", .{});

    // TODO: Implement example when library is ready
    _ = allocator;
}
```

**Verification**: Examples compile and run (even if they do nothing yet)

### Step 9: Update Build Configuration
**Task**: Ensure build.zig properly configures all targets

**Configuration**:
- Library target pointing to src/root.zig
- Test targets for each test file
- Example executables
- Dependency on websocket.zig (already configured per task 1.1.2)

**Verification**: `zig build --help` shows all targets

### Step 10: Validate Complete Structure
**Task**: Final validation of entire project structure

**Checks**:
1. Run `zig build` - library compiles
2. Run `zig build test` - all tests pass (even if empty)
3. Run `zig build examples` - examples compile
4. Check no circular dependencies
5. Verify module isolation (each module can be tested independently)
6. Review directory structure matches plan

**Deliverable**: Complete, compiling project structure ready for implementation

## Notes and Considerations

### Zig Module System

Zig uses file-based module system where `@import("path/to/file.zig")` loads a module. Key patterns:

1. **Relative imports**: Use `../` to navigate up directories
2. **Package imports**: Use `@import("package_name")` for dependencies
3. **Standard library**: Use `@import("std")`
4. **Test inclusion**: Use `std.testing.refAllDecls(@This())` to run all tests

### Avoiding Circular Dependencies

The structure prevents circular dependencies by establishing clear layering:

```
Layer 4: Examples (depends on Layer 3)
Layer 3: Root API (depends on Layer 2)
Layer 2: Protocol, Connection, Channel (depends on Layer 1)
Layer 1: Common (no internal dependencies)
```

Rules:
- Common never imports from other library modules
- Protocol/Connection/Channel can import from Common
- Root imports from all layers but is only imported externally
- Examples only import the public API (root)

### Future Extensibility

This structure supports future additions:

- `src/presence/`: Presence tracking implementation (Phase 4)
- `src/binary/`: Binary message support (Phase 4)
- `src/push/`: Push buffer and queuing (Phase 2)
- `src/timer/`: Timer and backoff logic (Phase 2)
- `tests/performance/`: Performance benchmarks (Phase 4)
- `examples/advanced/`: Advanced usage examples (Phase 5)

Each new feature can be added as a new subdirectory without restructuring existing code.

### Module Size Guidelines

Keep modules focused and reasonably sized:

- **Small** (50-200 lines): state.zig files, config.zig, errors.zig
- **Medium** (200-500 lines): message.zig, serializer.zig, channel.zig
- **Large** (500-1000 lines): socket.zig (manages complex connection lifecycle)

If a module grows beyond 1000 lines, consider splitting into submodules.

### Testing Strategy Per Module

Each module should have:

1. **Unit tests** in the module file itself (using `test` blocks)
2. **Integration tests** in tests/ directory (testing module interactions)
3. **Example usage** in examples/ directory (demonstrating real usage)

This three-level testing approach ensures modules work in isolation, work together, and are usable in practice.

### Documentation Standards

Each module file should begin with:

```zig
//! One-line description of module purpose
//!
//! Detailed explanation of what this module does, its role in the library,
//! and any important usage notes or caveats.
//!
//! # Examples
//! ```zig
//! // Brief usage example
//! ```

const std = @import("std");
```

This provides context for developers navigating the codebase.

## Alignment with Phase 1 Tasks

This structure directly supports Phase 1 implementation tasks:

- **1.2 Message Format**: Implemented in `src/protocol/`
- **1.3 Socket State Machine**: Implemented in `src/connection/`
- **1.4 Channel State Machine**: Implemented in `src/channel/`
- **1.5 Basic Communication Flow**: Integration across all layers
- **1.6 Integration Tests**: Supported by `tests/integration/`

Each task has a clear home in the directory structure, preventing code from being placed arbitrarily.

## Conclusion

This project structure provides a solid foundation for implementing the Phoenix Channels client library. It enforces clear separation of concerns, prevents circular dependencies, supports comprehensive testing, and scales to accommodate future features. By establishing this structure now (task 1.1.3), we enable efficient parallel development of the protocol, connection, and channel components in subsequent tasks.
