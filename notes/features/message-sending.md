# Feature Planning: Message Sending (Task 1.3.4)

## Problem Statement

Implement thread-safe message sending functionality for the PhoenixSocket that validates connection state, serializes Phoenix protocol messages to JSON, transmits them via WebSocket, and handles send failures gracefully. This is a critical component that bridges the high-level message API with low-level WebSocket transmission.

### Current State

- PhoenixSocket structure exists with connection state machine (DISCONNECTED, CONNECTING, CONNECTED, CLOSING, ERROR)
- Message serialization implemented in `src/protocol/serializer.zig` with `serialize()` function
- Message validation implemented with `validateForSend()` method
- WebSocket client integrated via karlseguin/websocket.zig library
- Connection lifecycle (connect/disconnect) implemented in Task 1.3.3
- Reference generation available via `nextRef()` and `nextRefString()`
- Thread safety primitives (mutex) in place

### Requirements

For Phase 1, message sending must:
1. Check connection state is CONNECTED before sending (return error otherwise, NO queuing in Phase 1)
2. Validate message meets Phoenix protocol requirements
3. Serialize message to JSON array format
4. Send serialized message via WebSocket text frame
5. Handle send errors (connection failures, timeout, etc.)
6. Provide thread-safe operation (multiple threads may call send simultaneously)
7. Support basic timeout for send operations
8. Clean up resources properly on all code paths (success and error)

### Constraints

- Phase 1 only: If state != CONNECTED, return error (queuing is Phase 2)
- Must use existing `serialize()` function from serializer.zig
- Must use karlseguin/websocket.zig Client.writeText() method
- karlseguin/websocket.zig requires MUTABLE buffer (modifies for masking)
- Thread safety required: mutex must protect state checks
- No retry logic in Phase 1 (basic retry may be added, but complex retry is Phase 2)
- Memory allocated for serialization must be freed on all paths

---

## Solution Overview

Implement a `send()` method on PhoenixSocket that follows this flow:

```
1. Acquire mutex lock
2. Check connection state == CONNECTED
3. Release mutex lock (to avoid holding during I/O)
4. Validate message (validateForSend)
5. Serialize message to JSON
6. Send via WebSocket (writeText with timeout)
7. Handle errors
8. Clean up allocated memory
```

### Key Design Decisions

1. **Two-phase locking**: Check state under lock, then release before I/O to prevent blocking other operations
2. **Mutable buffer handling**: Allocate writable buffer for serialization since karlseguin/websocket.zig modifies it
3. **Validation before serialization**: Fail fast if message is invalid
4. **Timeout support**: Use WebSocket client timeout configuration (already in Config)
5. **Error categorization**: Distinguish between state errors, validation errors, and send errors

### Method Signature

```zig
/// Send a Phoenix message over the WebSocket connection
/// Returns error if not connected or if send fails
/// Thread-safe: can be called from multiple threads
pub fn send(self: *PhoenixSocket, msg: *const message.PhoenixMessage) !void
```

---

## Technical Details

### Files to Modify

1. **`src/connection/socket.zig`** (primary changes)
   - Add `send()` method implementation
   - Import serializer module
   - Add send-related error handling

2. **`src/protocol/serializer.zig`** (may need minor updates)
   - Current `serialize()` returns `[]u8` (owned slice)
   - Verify it works with WebSocket client requirements

3. **`src/common/errors.zig`** (verify existing errors)
   - `ConnectionError.NotConnected` - already exists
   - `ProtocolError.ValidationError` - already exists
   - `ProtocolError.SerializationError` - already exists
   - May need to add `SendFailed` or similar

### Dependencies

- **Message serialization**: `src/protocol/serializer.zig::serialize()`
  - Takes `*const PhoenixMessage` and allocator
  - Returns owned `[]u8` that caller must free
  - Handles all Phoenix message types correctly

- **Message validation**: `src/protocol/message.zig::validateForSend()`
  - Validates message meets protocol requirements
  - Returns `error.ValidationError` on failure
  - No side effects (const method)

- **WebSocket sending**: `karlseguin/websocket.zig::Client.writeText()`
  - Signature: `fn writeText(self: *Client, data: []u8) !void`
  - Requires MUTABLE buffer (masking operation)
  - May return connection errors

- **State checking**: `PhoenixSocket.state` (protected by mutex)
  - Must be CONNECTED for send to succeed
  - Thread-safe access via mutex

- **Reference generation**: `nextRefString()` (if needed)
  - Thread-safe (internal mutex in RefCounter)
  - Not required for send() itself (caller sets refs)

### Algorithm Pseudocode

```
fn send(self: *PhoenixSocket, msg: *const PhoenixMessage) !void {
    // Step 1: Thread-safe state check
    {
        self.mutex.lock()
        defer self.mutex.unlock()

        if self.state != .CONNECTED {
            return error.NotConnected
        }

        if self.ws_client == null {
            return error.NotConnected
        }
    }

    // Step 2: Validate message (outside lock)
    try msg.validateForSend()

    // Step 3: Serialize message to JSON (outside lock)
    const json = try serializer.serialize(self.allocator, msg)
    defer self.allocator.free(json)

    // Step 4: Send via WebSocket (outside lock)
    // Note: WebSocket library requires mutable buffer for masking
    // The json buffer is already mutable (we own it)
    {
        self.mutex.lock()
        defer self.mutex.unlock()

        if self.ws_client) |client| {
            try client.writeText(json)
        } else {
            return error.NotConnected
        }
    }
}
```

### Thread Safety Analysis

**Critical Section 1: State Check**
- Lock acquisition: Before checking state
- Lock release: Immediately after check
- Rationale: Minimize lock hold time

**Critical Section 2: WebSocket Write**
- Lock acquisition: Before accessing ws_client pointer
- Lock release: After write completes
- Rationale: Prevent ws_client from being nulled during disconnect

**Race Condition Considerations**:
1. **State changes during send**: State could transition from CONNECTED to CLOSING between step 1 and step 4
   - Mitigation: Re-check ws_client in step 4 under lock
   - If disconnect happens between checks, writeText will fail with connection error

2. **Concurrent sends**: Multiple threads calling send() simultaneously
   - Mitigation: WebSocket write is atomic (protected by our mutex in step 4)
   - Serialization happens in parallel (no shared state)
   - Each send has independent buffer

3. **Send during disconnect**: Thread A calls send() while thread B calls disconnect()
   - Mitigation: Both acquire mutex, operations are serialized
   - Either send completes first (then disconnect), or disconnect completes first (send fails)

### Error Handling

**Error Categories**:

1. **State Errors** (early return, no cleanup needed)
   - `error.NotConnected` - state != CONNECTED
   - `error.InvalidState` - state transition validation

2. **Validation Errors** (early return, no cleanup needed)
   - `error.ValidationError` - message violates protocol

3. **Serialization Errors** (no cleanup needed, allocator handles it)
   - `error.OutOfMemory` - allocation failed
   - `error.SerializationError` - JSON encoding failed

4. **Send Errors** (buffer cleanup via defer)
   - `error.BrokenPipe` - connection closed during write
   - `error.ConnectionReset` - connection lost
   - `error.Timeout` - write timeout

**Cleanup Pattern**:
```zig
const json = try serializer.serialize(self.allocator, msg);
defer self.allocator.free(json);  // Always freed, even on error

try client.writeText(json);  // If this fails, defer still executes
```

### Timeout Handling

**Phase 1 Approach** (basic):
- Use WebSocket client's built-in timeout mechanism
- No explicit timeout parameter in send() method
- Timeout value comes from `socket.config.timeout_ms`
- If write takes longer than timeout, WebSocket library returns error

**Future Enhancement** (Phase 2+):
- Add optional timeout parameter to send()
- Implement send retry with exponential backoff
- Add send queue with timeout per message

---

## Implementation Plan

### Step 1: Prepare Error Handling (15 minutes)

**Objective**: Ensure all necessary error types exist

**Tasks**:
1. Review `src/common/errors.zig` for existing error types
2. Verify `ConnectionError.NotConnected` exists
3. Verify `ProtocolError.ValidationError` exists
4. Add any missing errors if needed
5. Update error documentation if needed

**Validation**:
- Compile errors.zig successfully
- All error types used in send() are defined

### Step 2: Implement Basic send() Method (45 minutes)

**Objective**: Implement core send functionality without timeout

**Tasks**:
1. Add import for serializer module to socket.zig
2. Add import for message module to socket.zig
3. Implement send() method with:
   - State checking (with mutex)
   - Message validation
   - Message serialization
   - WebSocket transmission
   - Proper error handling
   - Resource cleanup (defer)
4. Add comprehensive inline documentation
5. Add error propagation with try

**Code Structure**:
```zig
const serializer = @import("../protocol/serializer.zig");
const message = @import("../protocol/message.zig");

pub fn send(self: *PhoenixSocket, msg: *const message.PhoenixMessage) !void {
    // Implementation following algorithm above
}
```

**Validation**:
- Code compiles without errors
- Static analysis passes (no obvious bugs)

### Step 3: Add Thread Safety (30 minutes)

**Objective**: Ensure send() is fully thread-safe

**Tasks**:
1. Add mutex locking for state check
2. Add mutex locking for WebSocket access
3. Verify lock is released before I/O operations
4. Add defer for automatic unlock
5. Document thread safety guarantees
6. Review for race conditions

**Critical Review Questions**:
- Is there any shared mutable state accessed without lock?
- Can state change between checks cause incorrect behavior?
- Are all error paths properly unlocking mutex?
- Is lock held during blocking I/O? (should be NO)

**Validation**:
- Manual code review for race conditions
- Verify mutex acquire/release pattern

### Step 4: Add Unit Tests (60 minutes)

**Objective**: Comprehensive test coverage for send()

**Test Cases**:

1. **Test: send succeeds when CONNECTED**
   - Setup: Socket in CONNECTED state with mock WebSocket client
   - Action: Call send() with valid message
   - Assert: No error returned, message serialized and sent

2. **Test: send fails when DISCONNECTED**
   - Setup: Socket in DISCONNECTED state
   - Action: Call send() with valid message
   - Assert: Returns error.NotConnected

3. **Test: send fails when CONNECTING**
   - Setup: Socket in CONNECTING state
   - Action: Call send() with valid message
   - Assert: Returns error.NotConnected (or InvalidState)

4. **Test: send fails when CLOSING**
   - Setup: Socket in CLOSING state
   - Action: Call send() with valid message
   - Assert: Returns error.NotConnected (or InvalidState)

5. **Test: send fails when ERROR**
   - Setup: Socket in ERROR state
   - Action: Call send() with valid message
   - Assert: Returns error.NotConnected (or InvalidState)

6. **Test: send fails with invalid message**
   - Setup: Socket in CONNECTED state
   - Action: Call send() with invalid message (e.g., join without join_ref)
   - Assert: Returns error.ValidationError

7. **Test: send handles serialization correctly**
   - Setup: Socket in CONNECTED state
   - Action: Send message with complex payload
   - Assert: Verify serialized JSON matches expected format

8. **Test: send cleans up memory on success**
   - Setup: Socket in CONNECTED state, use testing allocator
   - Action: Call send() multiple times
   - Assert: No memory leaks detected

9. **Test: send cleans up memory on error**
   - Setup: Socket that will fail during send
   - Action: Call send() and catch error
   - Assert: No memory leaks detected

10. **Test: send is thread-safe** (basic)
    - Setup: Socket in CONNECTED state
    - Action: Spawn multiple threads calling send() concurrently
    - Assert: No crashes, all sends complete or error cleanly

**Mocking Challenges**:
- WebSocket client is a real dependency, may need mock or skip write tests
- For Phase 1, testing state checks and validation may be sufficient
- Full integration tests will validate actual sending

**Test Location**: `src/connection/socket.zig` (inline tests at bottom)

**Validation**:
- All tests pass: `zig build test`
- No memory leaks: Tests with `std.testing.allocator`
- Good coverage: All major code paths tested

### Step 5: Add Integration Example (30 minutes)

**Objective**: Create example demonstrating send() usage

**Tasks**:
1. Create or update example in `examples/` directory
2. Show typical usage pattern:
   - Connect to socket
   - Create message with proper ref
   - Send message
   - Handle errors
3. Include comments explaining each step
4. Make example runnable (even if server not available)

**Example Structure**:
```zig
// examples/send_message.zig
const std = @import("std");
const phoenix = @import("phoenix_channels");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create socket
    const config = phoenix.socket.Config{
        .url = "ws://localhost:4000/socket/websocket",
    };
    const socket = try phoenix.socket.PhoenixSocket.init(allocator, config);
    defer socket.deinit();

    // Connect
    try socket.connect();
    defer socket.disconnect() catch {};

    // Create message
    var payload = try phoenix.message.PhoenixMessage.emptyPayload(allocator);
    defer payload.object.deinit();

    const ref = try socket.nextRefString();
    defer allocator.free(ref);

    const msg = phoenix.message.PhoenixMessage.initEvent(
        allocator,
        "room:lobby",
        "ping",
        ref,
        payload,
    );

    // Send message
    try socket.send(&msg);

    std.debug.print("Message sent successfully!\n", .{});
}
```

**Validation**:
- Example compiles without errors
- Example runs (may fail at connect if no server)
- Code is clear and well-commented

### Step 6: Documentation (20 minutes)

**Objective**: Document send() API and usage

**Tasks**:
1. Add comprehensive doc comments to send() method
2. Document thread safety guarantees
3. Document error conditions
4. Document memory management (who owns what)
5. Add usage examples in doc comments
6. Update any architecture docs if needed

**Documentation Template**:
```zig
/// Send a Phoenix message over the WebSocket connection
///
/// This method validates the message, serializes it to JSON, and transmits
/// it via the WebSocket connection. The socket must be in CONNECTED state
/// for the send to succeed.
///
/// Thread Safety:
/// This method is thread-safe and can be called concurrently from multiple
/// threads. State checks and WebSocket writes are protected by mutex.
///
/// Memory Management:
/// The message is not modified and ownership is not transferred. This method
/// allocates a temporary buffer for serialization which is freed before
/// returning (even on error).
///
/// Parameters:
///   msg: Pointer to the message to send (not modified, not consumed)
///
/// Returns:
///   void on success
///   error.NotConnected if socket is not in CONNECTED state
///   error.ValidationError if message fails protocol validation
///   error.OutOfMemory if serialization buffer allocation fails
///   Connection errors if WebSocket write fails
///
/// Example:
///   const msg = PhoenixMessage.initHeartbeat(allocator, ref, payload);
///   try socket.send(&msg);
///
pub fn send(self: *PhoenixSocket, msg: *const message.PhoenixMessage) !void
```

**Validation**:
- Documentation is clear and complete
- Examples compile correctly
- All parameters and errors documented

### Step 7: Testing and Validation (30 minutes)

**Objective**: Verify implementation meets all requirements

**Tasks**:
1. Run all unit tests: `zig build test`
2. Run with leak detection: Verify no memory leaks
3. Test all error paths manually
4. Test with example program
5. Review code for:
   - Thread safety
   - Error handling
   - Resource cleanup
   - Edge cases
6. Performance check: Sending many messages shouldn't leak or slow down

**Checklist**:
- [ ] All unit tests pass
- [ ] No memory leaks (std.testing.allocator)
- [ ] Example compiles and runs
- [ ] All error conditions tested
- [ ] Thread safety verified
- [ ] Documentation complete
- [ ] Code reviewed for edge cases

**Validation**:
- All checklist items completed
- No outstanding bugs or issues
- Ready for integration

---

## Success Criteria

The implementation is considered successful when:

1. **Functionality**
   - [ ] send() method sends messages when CONNECTED
   - [ ] send() returns error when not CONNECTED
   - [ ] send() validates messages before sending
   - [ ] send() serializes messages correctly
   - [ ] send() uses WebSocket writeText() correctly

2. **Thread Safety**
   - [ ] send() can be called from multiple threads safely
   - [ ] No race conditions in state checking
   - [ ] Mutex properly protects shared state
   - [ ] No deadlocks under concurrent access

3. **Error Handling**
   - [ ] Returns appropriate error for each failure mode
   - [ ] All error paths properly clean up resources
   - [ ] No panics or crashes on error
   - [ ] Error messages are descriptive

4. **Memory Management**
   - [ ] No memory leaks on success path
   - [ ] No memory leaks on error paths
   - [ ] Serialization buffer properly freed
   - [ ] Message ownership clear and documented

5. **Testing**
   - [ ] Unit tests cover success case
   - [ ] Unit tests cover all error cases
   - [ ] Unit tests verify thread safety (basic)
   - [ ] Unit tests check memory leaks
   - [ ] All tests pass consistently

6. **Documentation**
   - [ ] send() method fully documented
   - [ ] Thread safety guarantees documented
   - [ ] Error conditions documented
   - [ ] Usage example provided
   - [ ] Memory management documented

7. **Code Quality**
   - [ ] Code follows Zig style guidelines
   - [ ] No compiler warnings
   - [ ] Clean separation of concerns
   - [ ] Proper use of defer for cleanup
   - [ ] Good error propagation with try

---

## Testing Approach

### Unit Testing Strategy

**Test Organization**:
- Tests in `src/connection/socket.zig` (inline with implementation)
- Use `std.testing.allocator` for leak detection
- Group tests by scenario (success, state errors, validation errors, etc.)

**Test Utilities Needed**:
- Mock or stub for WebSocket client (challenge: real dependency)
- Helper to create test messages
- Helper to set socket to specific state
- Helper to verify serialization output

**Test Coverage Goals**:
- All connection states tested (DISCONNECTED, CONNECTING, CONNECTED, CLOSING, ERROR)
- All message types tested (join, leave, heartbeat, custom events)
- All error conditions tested
- Memory leak testing on all paths
- Basic concurrent access testing

### Integration Testing

**Phase 1 Integration** (minimal):
- Manual testing with real Phoenix server
- Verify messages appear correctly on server
- Verify send failures handled correctly
- Verify connection state integration

**Phase 2 Integration** (comprehensive):
- Automated testing with test Phoenix server
- Full send/receive cycle testing
- Stress testing with many messages
- Concurrent client testing

### Performance Testing

**Phase 1** (informal):
- Send 1000 messages and verify no memory growth
- Send from 10 concurrent threads and verify no crashes
- Measure basic throughput (messages per second)

**Phase 2** (formal):
- Benchmark send latency
- Benchmark throughput under load
- Profile memory usage over time
- Test with very large messages

---

## Risk Analysis

### High-Risk Areas

1. **WebSocket Library Dependency**
   - Risk: karlseguin/websocket.zig API changes or has bugs
   - Mitigation: Pin specific commit, test thoroughly, have fallback plan
   - Impact: High (core functionality)

2. **Thread Safety**
   - Risk: Race condition in state management or WebSocket access
   - Mitigation: Careful mutex design, code review, concurrent testing
   - Impact: High (data corruption, crashes)

3. **Memory Management**
   - Risk: Leak in serialization buffer or error paths
   - Mitigation: Use defer religiously, test with leak detector, code review
   - Impact: Medium (memory leak in long-running apps)

### Medium-Risk Areas

4. **Serialization Correctness**
   - Risk: Edge case in JSON serialization breaks protocol
   - Mitigation: Comprehensive serialization tests already exist
   - Impact: Medium (protocol violation)

5. **Error Handling Completeness**
   - Risk: Missing error case leads to panic or undefined behavior
   - Mitigation: Enumerate all error scenarios, test each
   - Impact: Medium (crashes in production)

### Low-Risk Areas

6. **Performance**
   - Risk: send() is too slow for high-throughput applications
   - Mitigation: Profile if needed, optimize in Phase 2
   - Impact: Low (functional correctness more important in Phase 1)

7. **Documentation**
   - Risk: Incomplete or incorrect documentation
   - Mitigation: Review docs, provide examples, get feedback
   - Impact: Low (usability issue, not functional)

---

## Future Enhancements (Phase 2+)

### Message Queuing
- Queue messages when not CONNECTED
- Flush queue when connection established
- Configurable queue size limits
- Queue overflow handling

### Retry Logic
- Automatic retry on transient failures
- Exponential backoff between retries
- Maximum retry count configuration
- Per-message retry policy

### Timeout Improvements
- Per-send timeout parameter
- Separate timeout for different message types
- Timeout callback notifications
- Better timeout error reporting

### Performance Optimizations
- Message batching (send multiple messages in one WebSocket frame)
- Buffer pooling (reuse serialization buffers)
- Zero-copy serialization (if possible)
- Compression for large messages

### Advanced Features
- Message priorities (send urgent messages first)
- Send callbacks (notify on send completion)
- Send guarantees (at-most-once, at-least-once)
- Flow control (backpressure when server slow)

---

## Appendix: Technical Reference

### WebSocket Client API

From karlseguin/websocket.zig:

```zig
pub const Client = struct {
    // Write text frame
    pub fn writeText(self: *Client, data: []u8) !void;

    // Write binary frame
    pub fn writeBin(self: *Client, data: []u8) !void;

    // Close connection
    pub fn close(self: *Client, opts: CloseOpts) !void;

    // Read next message
    pub fn read(self: *Client) !?Message;

    // Mark message as processed (required after read)
    pub fn done(self: *Client, msg: Message) void;
};
```

**Important Notes**:
- writeText() modifies the buffer for WebSocket masking
- Caller must ensure buffer is mutable and remains valid during call
- May block on slow network (use with timeout configuration)
- Returns errors on connection failure

### Phoenix Message Serialization

From `src/protocol/serializer.zig`:

```zig
/// Serialize a PhoenixMessage to JSON array format
/// Returns owned memory that must be freed by the caller
pub fn serialize(
    allocator: std.mem.Allocator,
    msg: *const message.PhoenixMessage,
) ![]u8
```

**Output Format**: `[join_ref, ref, topic, event, payload]`

**Example Output**:
- Join: `["1","1","room:lobby","phx_join",{}]`
- Heartbeat: `[null,"5","phoenix","heartbeat",{}]`
- Custom: `[null,"10","room:lobby","new_msg",{"text":"hello"}]`

### Connection State Machine

```
DISCONNECTED ----connect()----> CONNECTING
    ^                               |
    |                               v
    |                          CONNECTED ----disconnect()----> CLOSING
    |                               |                             |
    |                               v                             v
    +-----------------------------ERROR                      DISCONNECTED
```

**send() allowed ONLY in CONNECTED state**

All other states return `error.NotConnected` or `error.InvalidState`

### Error Hierarchy

```
Error (union of all)
├── ConnectionError
│   ├── ConnectionFailed
│   ├── ConnectionTimeout
│   ├── AlreadyConnected
│   ├── NotConnected  <-- Used by send()
│   ├── ConnectionClosed
│   ├── InvalidUrl
│   └── HandshakeFailed
├── ProtocolError
│   ├── InvalidMessage
│   ├── SerializationError
│   ├── DeserializationError
│   ├── InvalidState  <-- May be used by send()
│   └── ValidationError  <-- Used by send()
├── ChannelError
│   └── (not relevant for socket.send())
├── PhoenixError
│   ├── NotImplemented
│   ├── InvalidConfiguration
│   ├── Timeout
│   └── InternalError
└── std.mem.Allocator.Error
    └── OutOfMemory  <-- May occur during serialization
```

---

## Related Documents

- **Architecture**: `research/initial_research.md` - Phoenix protocol details
- **Planning**: `planning/phase-01.md` - Phase 1 overview and task breakdown
- **CLAUDE.md**: Project guidelines and Zig best practices
- **Connection Lifecycle**: `notes/summaries/connection-lifecycle.md` - Task 1.3.3 summary

---

**Document Version**: 1.0
**Created**: 2025-10-20
**Author**: Feature Planning Agent
**Task**: Phase 1, Task 1.3.4 - Message Sending
