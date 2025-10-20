# Connection Lifecycle Implementation (Task 1.3.3)

## Problem Statement

Task 1.3.3 requires implementing the complete connection lifecycle for PhoenixSocket:
- Connect method with WebSocket handshake
- Disconnect method for graceful closure
- Connection error handling with proper state transitions
- Connection timeout detection
- Connection parameter handling (URL, query params, headers)

**Current Status**: PhoenixSocket has placeholder methods that return `error.NotImplemented`. The struct has all necessary fields including `ws_client`, `state`, and `mutex` from task 1.3.2.

## Solution Overview

Implement connect() and disconnect() methods using the karlseguin/websocket.zig library with:
1. **WebSocket handshake** - Establish connection and set ws_client field
2. **State transitions** - Use existing setState() for proper validation
3. **Error handling** - Catch connection errors and transition to ERROR state
4. **Timeout detection** - Use config.timeout_ms for connection timeout
5. **Parameter handling** - Parse URL, add query params, set headers

## Technical Details

**Files to modify**:
- `src/connection/socket.zig` - Implement connect() and disconnect() methods

**Key Design Decisions**:
- Use karlseguin/websocket.zig client library
- Connection runs on calling thread (not spawned thread)
- Timeout handled via websocket client configuration
- WebSocket client owned by PhoenixSocket (created on connect, destroyed on disconnect)
- State transitions: DISCONNECTED → CONNECTING → CONNECTED (success) or ERROR (failure)
- Disconnect transitions: CONNECTED → CLOSING → DISCONNECTED

**Dependencies**:
- `websocket` library (already imported)
- `src/connection/state.zig` - ConnectionState and transitions
- `std.net` - URL parsing
- `std.time` - Timeout handling

## Implementation Plan

### Step 1: Research WebSocket Client API ✅
- Read karlseguin/websocket.zig client documentation
- Understand client creation, connection, and cleanup
- Determine required configuration parameters

### Step 2: Implement connect() Method
- Validate current state (must be DISCONNECTED)
- Transition to CONNECTING state
- Parse WebSocket URL from config
- Create websocket.Client with timeout configuration
- Perform WebSocket handshake
- On success: set ws_client field, transition to CONNECTED
- On error: transition to ERROR state, return error

### Step 3: Implement disconnect() Method
- Validate current state (must be CONNECTED or ERROR)
- Transition to CLOSING state
- Send WebSocket close frame
- Close WebSocket connection
- Cleanup ws_client (set to null)
- Transition to DISCONNECTED state

### Step 4: Handle Connection Errors
- Catch all WebSocket errors (connection refused, timeout, DNS, etc.)
- Ensure state transitions to ERROR on any failure
- Clean up resources on error (errdefer pattern)
- Return descriptive errors to caller

### Step 5: Add Connection Timeout
- Use config.timeout_ms for WebSocket timeout
- Timeout applies to handshake phase only
- If timeout occurs, transition to ERROR and return error.ConnectionTimeout

### Step 6: Handle Connection Parameters
- Parse URL with query parameters
- Support adding custom headers (if needed for auth)
- Handle vsn parameter for Phoenix protocol version

### Step 7: Comprehensive Testing
- Test successful connection and disconnection
- Test connection to non-existent server (error)
- Test connection timeout
- Test disconnect while DISCONNECTED (error)
- Test state transitions during lifecycle
- Test cleanup of ws_client field
- Test thread safety of connect/disconnect

### Step 8: Documentation
- Document connect() method with examples
- Document disconnect() method
- Add usage examples to tests
- Update planning document

## Success Criteria

- ✅ connect() establishes WebSocket connection
- ✅ disconnect() gracefully closes connection
- ✅ State transitions are correct and validated
- ✅ Connection errors handled properly
- ✅ Timeout detection works
- ✅ ws_client field managed correctly (set/null)
- ✅ Comprehensive test suite (>8 tests)
- ✅ Planning document updated

## Current Status

**What Works**:
- PhoenixSocket struct with all fields
- State machine with validation
- Thread-safe state access
- Placeholder connect()/disconnect() methods

**What's Next**:
- Research websocket.zig client API
- Implement connect() with handshake
- Implement disconnect() with cleanup
- Add error handling and timeout

**How to Run**:
```bash
zig test src/connection/socket.zig
```

## WebSocket Client Usage Pattern

Based on karlseguin/websocket.zig, expected pattern:

```zig
// Connect
const client = try websocket.connect(allocator, url, .{
    .timeout_ms = config.timeout_ms,
});
self.ws_client = client;

// Disconnect
if (self.ws_client) |client| {
    try client.close();
    client.deinit();
    self.ws_client = null;
}
```

## Integration Points

### Task 1.3.2 (Socket Structure)
- ✅ Uses ws_client field
- ✅ Uses setState() for transitions
- ✅ Uses mutex for thread safety

### Future Tasks
- 🔜 Message sending (Phase 2) - will use ws_client to send
- 🔜 Heartbeat (Phase 2) - will check connection state
- 🔜 Reconnection (Phase 2) - will call connect() again
