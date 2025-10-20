# Socket Structure Implementation (Task 1.3.2)

## Problem Statement

Task 1.3.2 requires implementing the complete PhoenixSocket struct with all necessary fields for connection management:
- WebSocket client integration
- Connection state tracking
- Reference counter for unique message IDs
- Thread-safe access via mutex
- Memory allocator
- State change callback support

**Current Status**: Basic struct exists with allocator, config, and state fields. Missing:
- WebSocket client field
- Reference counter
- Mutex for thread safety
- State change callback
- Callback context

## Solution Overview

Enhance the PhoenixSocket struct with:
1. **WebSocket client** - Optional field (null when disconnected)
2. **Reference counter** - Atomic counter for generating unique message IDs
3. **Mutex** - Thread-safe state access
4. **State callback** - Optional callback for monitoring state changes
5. **Callback context** - User data for callbacks

## Technical Details

**Files**:
- `src/connection/socket.zig` - Enhance PhoenixSocket struct
- `src/common/types.zig` - RefCounter utility (check if exists)

**Key Design Decisions**:
- Use `?*websocket.Client` for WebSocket (null when disconnected)
- Use `std.Thread.Mutex` for synchronization
- Use atomic operations for ref counter
- Make callback optional (nullable)
- Support user context for callbacks

**Dependencies**:
- `src/connection/state.zig` - ConnectionState and StateChangeCallback
- `websocket` - karlseguin/websocket.zig library
- `src/common/types.zig` - RefCounter if it exists

## Implementation Plan

### Step 1: Check RefCounter Implementation ✅
- Check if RefCounter exists in common/types.zig
- If not, implement it with atomic operations

### Step 2: Add WebSocket Client Field
- Add optional websocket.Client pointer
- Import websocket dependency
- Handle null checks in methods

### Step 3: Add Reference Counter
- Add RefCounter field for message IDs
- Initialize to 0
- Provide nextRef() method

### Step 4: Add Thread Safety
- Add std.Thread.Mutex field
- Protect state access with mutex
- Add lock/unlock patterns

### Step 5: Add Callback Support
- Add optional StateChangeCallback field
- Add optional callback context field
- Implement setState() method that invokes callback

### Step 6: Comprehensive Testing
- Test struct initialization
- Test reference counter increments
- Test thread-safe state access
- Test callback invocation
- Test WebSocket field management

### Step 7: Documentation
- Document all fields
- Add usage examples
- Update planning document

## Success Criteria

- ✅ PhoenixSocket has all required fields
- ✅ Reference counter generates unique IDs
- ✅ Mutex protects state access
- ✅ Callback mechanism works
- ✅ Comprehensive test suite (>10 tests)
- ✅ Planning document updated

## Current Status

**What Works**:
- Basic PhoenixSocket struct
- Config struct
- init() and deinit() methods
- getState() method

**What's Next**:
- Add WebSocket client field
- Add reference counter
- Add mutex
- Add callback fields
- Implement setState() method

**How to Run**:
```bash
zig test src/connection/socket.zig
```
