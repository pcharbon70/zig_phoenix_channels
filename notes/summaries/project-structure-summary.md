# Project Structure - Quick Reference

**Feature Document**: `/home/ducky/code/zig_phoenix_channels/notes/features/project-structure.md`
**Phase**: 1.1.3 - Core Foundation
**Status**: Planning Complete, Ready for Implementation

## Directory Structure Overview

```
src/
├── root.zig                     # Public API entry point
├── protocol/                    # Message format and serialization
│   ├── message.zig             # PhoenixMessage struct
│   ├── serializer.zig          # JSON serialization
│   └── protocol.zig            # Protocol constants
├── connection/                  # Socket and WebSocket management
│   ├── socket.zig              # PhoenixSocket main component
│   ├── state.zig               # ConnectionState state machine
│   └── websocket_wrapper.zig   # WebSocket abstraction
├── channel/                     # Channel implementation
│   ├── channel.zig             # Channel component
│   └── state.zig               # ChannelState state machine
└── common/                      # Shared utilities
    ├── errors.zig              # Error definitions
    ├── types.zig               # Common types
    └── config.zig              # Configuration

tests/
├── protocol/                    # Protocol layer tests
├── connection/                  # Connection layer tests
├── channel/                     # Channel layer tests
├── integration/                 # End-to-end tests
└── test_utils.zig              # Test helpers

examples/
├── basic_connection.zig        # Simple example
└── README.md                   # Examples guide
```

## Key Design Principles

1. **Three-Layer Architecture**: Protocol → Connection → Channel
2. **State Machines Isolated**: Separate state.zig files
3. **Common Module First**: No dependencies on other library modules
4. **Test Structure Mirrors Source**: Easy to find corresponding tests
5. **Clear Import Hierarchy**: Prevents circular dependencies

## Implementation Steps

1. Create directory structure (mkdir commands)
2. Create protocol layer files (message, serializer, protocol)
3. Create connection layer files (socket, state, websocket_wrapper)
4. Create channel layer files (channel, state)
5. Create common module files (errors, types, config)
6. Create library entry point (root.zig)
7. Create test file stubs
8. Create example file stubs
9. Update build configuration
10. Validate complete structure

## Success Criteria

- [ ] All directories exist
- [ ] All module files created with proper structure
- [ ] `zig build` compiles the library
- [ ] `zig build test` runs successfully
- [ ] Examples compile and run
- [ ] No circular dependencies
- [ ] Each module has documentation

## Next Steps After Structure

Once the structure is in place, implementation proceeds in order:

1. **Task 1.1.4**: Core type definitions (errors, config, common types)
2. **Task 1.2**: Message format implementation (protocol layer)
3. **Task 1.3**: Socket state machine (connection layer)
4. **Task 1.4**: Channel state machine (channel layer)
5. **Task 1.5**: Basic communication flow (integration)

## Quick Commands

```bash
# Create all directories
mkdir -p src/{protocol,connection,channel,common}
mkdir -p tests/{protocol,connection,channel,integration}
mkdir -p examples

# Verify structure
tree -I 'zig-cache|zig-out|.git'

# Build library
zig build

# Run tests
zig build test

# Build examples
zig build examples
```

## Module Dependencies

```
Layer 4: examples/          (imports: root)
         └─> Layer 3

Layer 3: src/root.zig       (imports: all Layer 2)
         └─> Layer 2

Layer 2: protocol/          (imports: common)
         connection/        (imports: protocol, common)
         channel/           (imports: protocol, connection, common)
         └─> Layer 1

Layer 1: common/            (imports: std only, no internal deps)
```

## File Size Guidelines

- **Small** (50-200 lines): state.zig, config.zig, errors.zig, types.zig
- **Medium** (200-500 lines): message.zig, serializer.zig, channel.zig
- **Large** (500-1000 lines): socket.zig

Split into submodules if >1000 lines.

## Documentation Template

```zig
//! One-line module description
//!
//! Detailed explanation of module purpose and role.
//!
//! # Examples
//! ```zig
//! // Usage example
//! ```

const std = @import("std");

// Implementation here

test "module loads" {
    // Compilation verification
}
```

## Related Documents

- Full Planning: `/home/ducky/code/zig_phoenix_channels/notes/features/project-structure.md`
- Phase 1 Details: `/home/ducky/code/zig_phoenix_channels/planning/phase-01.md`
- Project Guidance: `/home/ducky/code/zig_phoenix_channels/CLAUDE.md`
