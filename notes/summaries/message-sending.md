# Message Sending Implementation Summary

**Task**: 1.3.4 - Message Sending
**Branch**: `feature/message-sending`
**Date**: 2025-10-20
**Status**: ✅ Complete

## Overview

Implemented thread-safe message sending functionality for PhoenixSocket that validates connection state, serializes Phoenix protocol messages to JSON, and transmits them via WebSocket. The implementation uses a two-phase locking pattern to prevent blocking I/O operations while maintaining thread safety.

## Implementation Details

### Files Modified

**`src/connection/socket.zig`** (+150 lines, 862 total)

### Key Components

#### 1. Send Method

**Method Signature**:
```zig
pub fn send(self: *PhoenixSocket, msg: *const PhoenixMessage) !void
```

**Implementation Flow**:

1. **State Validation (Phase 1)**
   - Acquire mutex
   - Check `self.state == .CONNECTED`
   - Release mutex
   - Return `error.NotConnected` if not connected

2. **WebSocket Client Acquisition (Phase 2)**
   - Acquire mutex again
   - Re-check `ws_client` exists (handles race conditions)
   - Release mutex
   - Return `error.NotConnected` if null

3. **Message Validation**
   - Call `msg.validateForSend()`
   - Validates required fields
   - Validates payload is object
   - Validates system event requirements

4. **Message Serialization**
   - Call `serializer.serialize(allocator, msg)`
   - Returns owned `[]u8` buffer
   - Must be freed by caller

5. **Mutable Buffer Allocation**
   - Duplicate serialized buffer
   - Required because WebSocket library modifies buffer for masking
   - Must be freed by caller

6. **Send with Timeout**
   - Set write timeout via `client.writeTimeout(timeout_ms)`
   - Send via `client.writeText(send_buffer)`
   - Reset timeout to 0 after send

**Thread Safety Pattern**:

The implementation uses **two-phase locking**:
- **Phase 1**: Check state under lock, release immediately
- **Phase 2**: Get ws_client under lock, release immediately
- **I/O**: Perform all I/O operations outside locks

This prevents:
- Blocking other operations during slow I/O
- Holding mutex during network operations
- Deadlocks from nested locks

**Race Condition Mitigation**:

The double-check pattern handles the race:
```
Thread A: Checks state (CONNECTED) → releases lock
Thread B: Calls disconnect() → sets ws_client to null
Thread A: Tries to get ws_client → returns error.NotConnected
```

#### 2. Error Handling

**Errors Returned**:

| Error | Cause | When |
|-------|-------|------|
| `error.NotConnected` | State != CONNECTED | State validation (phase 1) |
| `error.NotConnected` | ws_client == null | Client acquisition (phase 2) |
| Validation errors | Invalid message | Message validation |
| Serialization errors | JSON encoding failed | Serialization |
| Memory errors | Allocation failed | Buffer allocation |
| Network errors | Send failed, timeout | WebSocket write |

**Error Cleanup**:

All allocations use `defer` for cleanup:
```zig
const json_bytes = try serializer.serialize(self.allocator, msg);
defer self.allocator.free(json_bytes);

const send_buffer = try self.allocator.dupe(u8, json_bytes);
defer self.allocator.free(send_buffer);
```

This ensures no memory leaks on error paths.

#### 3. Timeout Support

**Configuration**:
- Uses existing `config.timeout_ms` field
- Applied via `client.writeTimeout(ms)`
- Reset to 0 after send

**Timeout Behavior**:
- Timeout applies to WebSocket write operation
- If exceeded, write returns error
- No retry logic in Phase 1 (Phase 2 feature)

## Test Coverage

**26 comprehensive tests** (21 from previous tasks + 5 new):

### Message Sending Tests (5 tests)

1. **send: returns error when DISCONNECTED**
   - Setup: Socket in DISCONNECTED state
   - Action: Call send()
   - Expected: error.NotConnected

2. **send: returns error when CONNECTING**
   - Setup: Socket in CONNECTING state
   - Action: Call send()
   - Expected: error.NotConnected

3. **send: returns error when CLOSING**
   - Setup: Socket in CLOSING state
   - Action: Call send()
   - Expected: error.NotConnected

4. **send: returns error when ERROR**
   - Setup: Socket in ERROR state
   - Action: Call send()
   - Expected: error.NotConnected

5. **send: returns error when ws_client is null despite CONNECTED state**
   - Setup: State manually set to CONNECTED without actual connection
   - Action: Call send()
   - Expected: error.NotConnected (race condition simulation)

### From Previous Tasks (21 tests)

- Socket initialization and configuration
- Reference counter (numeric and string)
- State transitions and validation
- State callbacks
- URL parsing (7 tests)
- Connection lifecycle (3 tests)

**Test Results**:
```bash
$ zig build test
All 26 tests passed.
```

## Usage Examples

### Basic Message Send

```zig
const allocator = std.heap.page_allocator;

// Create socket and connect
const config = Config{
    .url = "ws://localhost:4000/socket/websocket",
    .timeout_ms = 5000,
};

const socket = try PhoenixSocket.init(allocator, config);
defer socket.deinit();

try socket.connect();

// Create message
var payload_obj = std.json.ObjectMap.init(allocator);
defer payload_obj.deinit();

try payload_obj.put("user_id", .{ .string = "123" });
try payload_obj.put("message", .{ .string = "Hello, world!" });

const msg = PhoenixMessage{
    .join_ref = null,
    .ref = try socket.nextRefString(), // Auto-generate unique ref
    .topic = "room:lobby",
    .event = "new_msg",
    .payload = .{ .object = payload_obj },
};
defer allocator.free(msg.ref.?);

// Send message
try socket.send(&msg);
std.debug.print("Message sent successfully\n", .{});
```

### Error Handling

```zig
socket.send(&msg) catch |err| switch (err) {
    error.NotConnected => {
        std.log.err("Cannot send: not connected to server", .{});
        // Maybe queue for later (Phase 2) or reconnect
    },
    error.ValidationError => {
        std.log.err("Invalid message format", .{});
        // Fix message structure
    },
    error.Timeout => {
        std.log.err("Send timeout exceeded", .{});
        // Maybe retry or report error
    },
    else => {
        std.log.err("Send failed: {}", .{err});
        // Handle other errors
    },
};
```

### Join Channel Example

```zig
// Join a channel
var join_payload = std.json.ObjectMap.init(allocator);
defer join_payload.deinit();

const join_msg = PhoenixMessage{
    .join_ref = try socket.nextRefString(),
    .ref = try socket.nextRefString(),
    .topic = "room:lobby",
    .event = "phx_join",
    .payload = .{ .object = join_payload },
};
defer allocator.free(join_msg.join_ref.?);
defer allocator.free(join_msg.ref.?);

try socket.send(&join_msg);
```

### Heartbeat Example

```zig
// Send heartbeat
var hb_payload = std.json.ObjectMap.init(allocator);
defer hb_payload.deinit();

const heartbeat = PhoenixMessage{
    .join_ref = null,
    .ref = try socket.nextRefString(),
    .topic = "phoenix",
    .event = "heartbeat",
    .payload = .{ .object = hb_payload },
};
defer allocator.free(heartbeat.ref.?);

try socket.send(&heartbeat);
```

## Integration Points

### Task 1.2.1-1.2.4 (Message Protocol)
- ✅ Uses `PhoenixMessage` struct
- ✅ Uses `validateForSend()` method
- ✅ Uses `serialize()` function

### Task 1.3.1 (State Machine)
- ✅ Checks `ConnectionState.CONNECTED`
- ✅ Returns error if not in correct state

### Task 1.3.2 (Socket Structure)
- ✅ Uses `mutex` for thread safety
- ✅ Uses `ws_client` field
- ✅ Uses `config.timeout_ms`
- ✅ Uses `nextRefString()` for message refs

### Task 1.3.3 (Connection Lifecycle)
- ✅ Requires connection established
- ✅ Uses `ws_client.writeText()` method

### Task 1.3.5 (Message Receiving)
- 🔜 Will handle `phx_reply` messages
- 🔜 Will correlate refs for request/response

### Future Tasks
- **Phase 2**: Message queuing when not connected
- **Phase 2**: Retry logic on send failures
- **Phase 2**: Automatic reconnection handling

## Architecture Benefits

1. **Thread Safety**
   - Two-phase locking prevents blocking
   - No mutex held during I/O operations
   - Race conditions handled with double-check

2. **Resource Management**
   - All allocations cleaned up with defer
   - No memory leaks on error paths
   - Explicit ownership of buffers

3. **Error Handling**
   - Clear error categorization
   - Fail-fast on validation errors
   - Descriptive error messages

4. **Timeout Support**
   - Configurable per socket
   - Prevents indefinite blocking
   - Proper cleanup after timeout

5. **WebSocket Integration**
   - Handles mutable buffer requirement
   - Proper masking by library
   - Text frame transmission

## Performance Characteristics

- **State Check**: O(1) - single mutex operation
- **Client Check**: O(1) - single mutex operation
- **Validation**: O(n) where n = message fields
- **Serialization**: O(m) where m = message size
- **Buffer Duplication**: O(m) - single memory copy
- **Send**: O(1) + network latency
- **Memory**: 2x message size (serialized + mutable copy)

## Known Limitations

1. **No Message Queuing**: Returns error if not CONNECTED (Phase 1 constraint)
2. **No Retry Logic**: Single attempt only (Phase 2 feature)
3. **Synchronous Send**: Blocks until send completes or times out
4. **No Send Confirmation**: No way to know if server received (awaiting Phase 1.3.5)
5. **Fixed Timeout**: Same timeout for all messages (could be per-message)

## Future Enhancements

### Phase 2
- Add message queuing when not connected
- Implement retry logic with exponential backoff
- Add per-message timeout configuration
- Queue size limits and overflow handling

### Task 1.3.5 (Message Receiving)
- Correlate `phx_reply` with original message refs
- Provide request/response pairing
- Handle reply timeouts

### Advanced Features
- Send callbacks for confirmation
- Priority queuing for important messages
- Batch sending for efficiency
- Compression support

## Error Catalog

### Send Errors

| Error | Cause | Recovery |
|-------|-------|----------|
| `error.NotConnected` | State != CONNECTED | Wait for connection, or reconnect |
| `error.NotConnected` | ws_client == null | Race condition, retry after brief delay |
| `error.ValidationError` | Invalid message format | Fix message structure |
| `error.SerializationError` | JSON encoding failed | Check payload structure |
| `error.OutOfMemory` | Allocation failed | Reduce message size or free memory |
| `error.Timeout` | Send timeout exceeded | Increase timeout or check network |
| Network errors | WebSocket write failed | Check connection, reconnect |

## Documentation

### Code Documentation
- ✅ Module-level documentation
- ✅ Method documentation for send()
- ✅ Inline comments for critical sections
- ✅ Usage examples in tests

### Planning Documentation
- ✅ Updated `planning/phase-01.md` with completion status
- ✅ Feature planning doc: `notes/features/message-sending.md`
- ✅ This summary document

## Conclusion

Task 1.3.4 is complete with a robust, thread-safe message sending implementation. The implementation provides:
- Thread-safe message transmission with two-phase locking
- State validation and race condition handling
- Message serialization using existing protocol code
- WebSocket transmission with timeout support
- Comprehensive error handling and resource cleanup
- Foundation for bidirectional communication

All 26 tests pass, and the implementation is ready for Task 1.3.5 (Message Receiving).

**Next Steps**: Implement receive loop to handle incoming Phoenix messages from the WebSocket connection.
