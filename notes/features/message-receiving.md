# Feature Planning: Message Receiving (Task 1.3.5)

## 1. Problem Statement

### Current State
As of Task 1.3.4, the PhoenixSocket can:
- Establish WebSocket connections (Task 1.3.3)
- Send messages over the connection (Task 1.3.4)
- Manage connection state with proper transitions (Task 1.3.1-1.3.2)

However, the socket cannot yet receive messages from the server. Without message reception, the client cannot:
- Process heartbeat replies (needed for connection keepalive)
- Receive channel join confirmations (phx_reply)
- Handle server-initiated events (phx_error, phx_close)
- Receive custom events from channels
- Detect connection failures from the server side

### Requirements
For Phase 1, we need a basic message receiving implementation that:

1. **Runs in a separate thread** to avoid blocking the main application
2. **Continuously reads messages** from the WebSocket connection
3. **Deserializes messages** using the existing protocol implementation
4. **Routes messages** to appropriate handlers (basic routing for Phase 1)
5. **Handles errors gracefully** without crashing the application
6. **Supports graceful shutdown** when disconnecting
7. **Respects thread safety** for shared state access
8. **Detects connection failures** and transitions to ERROR state

### Constraints
- Must use karlseguin/websocket.zig Client API (read() method with done() lifecycle)
- Must integrate with existing PhoenixSocket state machine
- Cannot use async/await (removed in Zig 0.11.0+)
- Must handle WebSocket close frames and network errors
- Phase 1 scope: basic message handling only (full channel registry in Phase 3)

### Phoenix Protocol Requirements
According to the protocol specification:
- Messages are JSON arrays: `[join_ref, ref, topic, event, payload]`
- Heartbeat replies come on "phoenix" topic with "phx_reply" event
- Channel messages come on channel-specific topics
- System events (phx_error, phx_close, phx_reply) affect state
- Connection loss should trigger reconnection (Phase 2)

## 2. Solution Overview

### Architecture
The message receiving system consists of:

1. **Receive Thread**: A separate thread spawned during connect() that runs the receive loop
2. **Receive Loop**: Continuously calls WebSocket read() and processes messages
3. **Message Deserialization**: Uses existing `serializer.deserialize()` to parse JSON
4. **Message Router**: Basic routing logic to handle messages (Phase 1: logging/callbacks)
5. **Error Handler**: Gracefully handles read errors and connection failures
6. **Shutdown Mechanism**: Allows graceful thread termination on disconnect()

### Thread Model
```
Main Thread (Application)          Receive Thread
     |                                  |
     |--- connect() ----------------->  |
     |    - transitions to CONNECTED    |
     |    - spawns receive thread ---->[start]
     |                                  |
     |                                  |- receive loop:
     |                                  |   - read message
     |                                  |   - deserialize
     |                                  |   - route/handle
     |                                  |   - repeat
     |                                  |
     |--- send() -------------------->  |
     |    (concurrent with receive)     |
     |                                  |
     |--- disconnect() --------------> [stop]
     |    - signals shutdown            |
     |    - waits for thread join       |
     |    - transitions to DISCONNECTED |
     |<-------------------------------- |
```

### Message Flow
```
WebSocket                Receive Thread           PhoenixSocket
    |                         |                        |
    |--- text frame --------> |                        |
    |                         |                        |
    |                    read() returns                |
    |                         |                        |
    |                    deserialize()                 |
    |                         |                        |
    |                    validate message              |
    |                         |                        |
    |                    route message                 |
    |                         |                        |
    |                         |--- handleMessage() --->|
    |                         |                        |
    |                    done(msg)                     |
    |                         |                        |
    |                    [loop continues]              |
```

### Phase 1 Message Handling Strategy
Since we don't have a full channel registry yet (Phase 3), we'll implement basic handlers:
- **Heartbeat replies**: Log or update last heartbeat time
- **Other messages**: Store in a simple queue or invoke a generic callback
- **Error events**: Trigger state transitions
- **Close events**: Graceful shutdown

This provides the infrastructure for full channel routing in Phase 3.

## 3. Technical Details

### 3.1 Files to Modify

**Primary Implementation:**
- `/home/ducky/code/zig_phoenix_channels/src/connection/socket.zig`
  - Add receive thread handle field
  - Add receive loop function
  - Add message routing logic
  - Add thread lifecycle management in connect()/disconnect()
  - Add graceful shutdown signaling

**Supporting Files:**
- `/home/ducky/code/zig_phoenix_channels/src/common/errors.zig`
  - May need additional error types for receive failures

**Test Files:**
- Create `/home/ducky/code/zig_phoenix_channels/tests/connection/socket_receive_tests.zig`
  - Unit tests for receive loop logic
  - Thread lifecycle tests
  - Error handling tests
  - Timeout tests

### 3.2 Dependencies

**Existing Code:**
- `src/protocol/serializer.zig` - deserialize() function (Task 1.2.3)
- `src/protocol/message.zig` - PhoenixMessage structure (Task 1.2.1)
- `src/connection/state.zig` - ConnectionState enum (Task 1.3.1)
- `websocket.Client` - read(), done(), readTimeout() methods

**Zig Standard Library:**
- `std.Thread` - For spawning and managing receive thread
- `std.Thread.Mutex` - For protecting shared state
- `std.atomic.Value` - For shutdown signaling (atomic bool)

### 3.3 Data Structures

**New Fields in PhoenixSocket:**
```zig
pub const PhoenixSocket = struct {
    // ... existing fields ...

    /// Receive thread handle (null when not running)
    receive_thread: ?std.Thread = null,

    /// Atomic flag for signaling receive thread to stop
    should_stop_receive: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),

    /// Optional callback for handling received messages (Phase 1 only)
    /// Phase 3 will replace this with proper channel routing
    message_callback: ?MessageCallback = null,

    /// Context for message callback
    message_callback_context: ?*anyopaque = null,
};

/// Callback for received messages (Phase 1 temporary API)
pub const MessageCallback = *const fn (
    msg: *const PhoenixMessage,
    ctx: ?*anyopaque
) void;
```

**Receive Thread Context:**
```zig
/// Context passed to receive thread function
const ReceiveThreadContext = struct {
    socket: *PhoenixSocket,
    allocator: std.mem.Allocator,
};
```

### 3.4 Key Algorithms

**Receive Loop (receiveLoop function):**
```zig
fn receiveLoop(ctx: *ReceiveThreadContext) void {
    const socket = ctx.socket;
    const allocator = ctx.allocator;

    while (!socket.should_stop_receive.load(.acquire)) {
        // Get WebSocket client with lock
        const client = blk: {
            socket.mutex.lock();
            defer socket.mutex.unlock();
            if (socket.ws_client) |c| break :blk c else return;
        };

        // Read message with timeout (non-blocking)
        const msg = client.read() catch |err| {
            handleReadError(socket, err);
            break;
        };

        if (msg) |m| {
            defer client.done(m);  // CRITICAL: Must call done()

            // Only handle text frames (Phoenix uses JSON)
            if (m.type == .text) {
                processTextMessage(socket, allocator, m.data);
            }
        }
        // null means timeout - check should_stop and continue
    }
}

fn processTextMessage(
    socket: *PhoenixSocket,
    allocator: std.mem.Allocator,
    data: []const u8
) void {
    // Deserialize message
    const phoenix_msg = serializer.deserialize(allocator, data) catch |err| {
        // Log deserialization error, continue loop
        std.log.err("Failed to deserialize message: {}", .{err});
        return;
    };
    defer serializer.deinitOwned(allocator, phoenix_msg);

    // Validate message
    phoenix_msg.validateFromServer() catch |err| {
        std.log.err("Invalid message from server: {}", .{err});
        return;
    };

    // Route message (Phase 1: basic routing)
    routeMessage(socket, &phoenix_msg);
}

fn routeMessage(socket: *PhoenixSocket, msg: *const PhoenixMessage) void {
    // Phase 1: Basic message routing

    // Handle heartbeat replies (phoenix topic)
    if (std.mem.eql(u8, msg.topic, "phoenix")) {
        handlePhoenixTopicMessage(socket, msg);
        return;
    }

    // Invoke generic callback if registered (Phase 1 only)
    if (socket.message_callback) |callback| {
        callback(msg, socket.message_callback_context);
    }
}
```

**Error Handling:**
```zig
fn handleReadError(socket: *PhoenixSocket, err: anyerror) void {
    std.log.err("WebSocket read error: {}", .{err});

    // Transition to ERROR state
    socket.setState(.ERROR) catch |state_err| {
        std.log.err("Failed to transition to ERROR state: {}", .{state_err});
    };

    // Error state will trigger reconnection in Phase 2
}
```

**Thread Lifecycle in connect():**
```zig
pub fn connect(self: *PhoenixSocket) !void {
    // ... existing connection code ...

    // After WebSocket handshake succeeds and state is CONNECTED:

    // Reset shutdown flag
    self.should_stop_receive.store(false, .release);

    // Spawn receive thread
    const ctx = try self.allocator.create(ReceiveThreadContext);
    ctx.* = .{
        .socket = self,
        .allocator = self.allocator,
    };

    const thread = try std.Thread.spawn(.{}, receiveLoop, .{ctx});

    {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.receive_thread = thread;
    }
}
```

**Thread Lifecycle in disconnect():**
```zig
pub fn disconnect(self: *PhoenixSocket) !void {
    // Signal receive thread to stop
    self.should_stop_receive.store(true, .release);

    // Get receive thread handle
    const thread = blk: {
        self.mutex.lock();
        defer self.mutex.unlock();
        break :blk self.receive_thread;
    };

    // Wait for receive thread to finish
    if (thread) |t| {
        t.join();
        self.mutex.lock();
        defer self.mutex.unlock();
        self.receive_thread = null;
    }

    // ... existing disconnect code ...
}
```

### 3.5 Thread Safety Considerations

**Shared State Access:**
- `ws_client`: Protected by mutex, may be null
- `state`: Protected by mutex, accessed via setState()/getState()
- `should_stop_receive`: Atomic bool for lock-free signaling
- `receive_thread`: Protected by mutex

**Lock Ordering:**
Always acquire mutex briefly and release before blocking operations:
1. Lock mutex to get ws_client pointer
2. Release mutex
3. Call blocking read() operation
4. Process message (no locks held during processing)
5. Lock mutex only for state updates

**Deadlock Prevention:**
- Never call WebSocket operations (read/write) while holding mutex
- Never call state callbacks while holding mutex (already handled in setState())
- Always use `defer mutex.unlock()` pattern

**Shutdown Race Conditions:**
- disconnect() sets atomic flag before joining thread
- receive loop checks flag frequently (each iteration)
- Thread join ensures complete cleanup before proceeding

### 3.6 Timeout Handling

**Read Timeout Strategy:**
```zig
// Before starting receive loop, set read timeout
client.readTimeout(5000) catch {};  // 5 second timeout
```

This allows:
- Periodic checking of should_stop_receive flag
- Responsive shutdown (max 5 second delay)
- Non-blocking loop operation
- Detection of slow/stalled connections

**Timeout vs Connection Loss:**
- `read() == null`: Timeout, continue loop
- `read() == error`: Connection failure, exit loop and transition to ERROR

## 4. Implementation Plan

### Step 1: Add Thread Infrastructure (Subtask 1.3.5.1)
**Goal:** Add necessary fields and basic thread spawning to PhoenixSocket

**Tasks:**
1. Add new fields to PhoenixSocket struct:
   - `receive_thread: ?std.Thread`
   - `should_stop_receive: std.atomic.Value(bool)`
   - `message_callback: ?MessageCallback` (Phase 1 only)
   - `message_callback_context: ?*anyopaque`

2. Define MessageCallback type and ReceiveThreadContext struct

3. Add method to set message callback:
   ```zig
   pub fn setMessageCallback(
       self: *PhoenixSocket,
       callback: ?MessageCallback,
       context: ?*anyopaque,
   ) void
   ```

4. Create stub receiveLoop function that just logs and exits

5. Modify connect() to spawn receive thread after handshake

6. Modify disconnect() to signal shutdown and join thread

7. Update deinit() to ensure thread is stopped

**Tests:**
- Test thread is spawned on connect()
- Test thread is joined on disconnect()
- Test thread handle is null when disconnected
- Test multiple connect/disconnect cycles
- Test deinit() with active thread

**Validation:**
- Connection still works (no regressions)
- Thread spawns and terminates cleanly
- No memory leaks (verify with GeneralPurposeAllocator)

### Step 2: Implement Message Reading (Subtask 1.3.5.2 & 1.3.5.5)
**Goal:** Read messages from WebSocket and handle basic lifecycle

**Tasks:**
1. Implement receiveLoop function:
   - Set read timeout before loop
   - Check should_stop_receive flag each iteration
   - Call client.read() to get message
   - Handle timeout (null return) vs error
   - Call client.done(msg) in defer
   - Filter for text frames only

2. Add processTextMessage helper function:
   - Call serializer.deserialize()
   - Use defer for serializer.deinitOwned()
   - Log deserialization errors
   - Call routeMessage()

3. Add basic routeMessage function:
   - Identify phoenix topic for heartbeats
   - Call message callback if registered
   - Log unhandled messages

4. Add handleReadError function:
   - Log error
   - Transition socket to ERROR state
   - Exit receive loop

**Tests:**
- Test read timeout returns null (continues loop)
- Test text message is deserialized correctly
- Test binary messages are ignored
- Test deserialization errors are logged (don't crash)
- Test message callback is invoked with correct data
- Test read error triggers ERROR state

**Validation:**
- Messages can be received from WebSocket
- Message deserialization works correctly
- Errors don't crash the thread
- Memory is cleaned up properly

### Step 3: Implement Message Routing (Subtask 1.3.5.2 continued)
**Goal:** Route messages to appropriate handlers

**Tasks:**
1. Implement handlePhoenixTopicMessage function:
   - Check for heartbeat replies
   - Update last heartbeat timestamp (add field to PhoenixSocket)
   - Log heartbeat confirmation

2. Enhance routeMessage to identify message types:
   - Phoenix topic → handlePhoenixTopicMessage
   - Other topics → message callback (Phase 1)
   - No callback → log warning

3. Add message validation before routing:
   - Call validateFromServer()
   - Log validation failures

**Tests:**
- Test heartbeat reply is recognized and handled
- Test custom messages invoke callback
- Test messages without callback are logged
- Test invalid messages are rejected
- Test message topic routing is correct

**Validation:**
- Different message types route correctly
- Heartbeat mechanism has foundation for Phase 2
- Phase 1 callback API works for testing

### Step 4: Error Handling and Robustness (Subtask 1.3.5.3)
**Goal:** Handle all error conditions gracefully

**Tasks:**
1. Add comprehensive error handling in receiveLoop:
   - WebSocket read errors
   - Deserialization errors
   - Validation errors
   - Routing errors

2. Implement error recovery strategies:
   - Deserialization error → log and continue
   - Read error → transition to ERROR and exit
   - Validation error → log and continue

3. Add error logging throughout:
   - Use std.log.err for errors
   - Include context (message data, error type)

4. Add connection failure detection:
   - Detect connection_closed error
   - Detect network errors
   - Transition to ERROR state

**Tests:**
- Test malformed JSON doesn't crash thread
- Test WebSocket close frame stops thread cleanly
- Test network error transitions to ERROR state
- Test error during deserialization continues loop
- Test multiple errors don't cause issues

**Validation:**
- All error paths are handled
- No crashes or panics under any error condition
- State machine transitions correctly on errors

### Step 5: Graceful Shutdown (Subtask 1.3.5.4)
**Goal:** Ensure clean thread termination on disconnect

**Tasks:**
1. Implement atomic flag checking in receive loop:
   - Check should_stop_receive at loop start
   - Exit cleanly when flag is set

2. Update disconnect() method:
   - Set should_stop_receive before other operations
   - Join thread with proper synchronization
   - Clear thread handle after join
   - Handle null thread case

3. Add timeout to thread join (prevent indefinite blocking):
   - Consider maximum shutdown time
   - Force close WebSocket if thread doesn't exit

4. Update deinit() to ensure cleanup:
   - Call disconnect() if still connected
   - Verify thread is stopped

**Tests:**
- Test disconnect() waits for thread to finish
- Test shutdown flag stops receive loop promptly
- Test multiple disconnect() calls are safe
- Test deinit() cleans up active thread
- Test shutdown during message processing

**Validation:**
- Thread always terminates within reasonable time (< 10s)
- No resource leaks after disconnect
- Clean shutdown under all conditions

### Step 6: Integration and Testing
**Goal:** Validate complete receive implementation

**Tasks:**
1. Create comprehensive unit test suite:
   - Test all subtasks in isolation
   - Test integration between components
   - Test concurrent send/receive
   - Test error scenarios

2. Add integration test with test server:
   - Connect and receive heartbeat replies
   - Send message and receive reply
   - Test connection failure scenarios

3. Validate thread safety:
   - Test concurrent operations
   - Run with thread sanitizer if available
   - Test under high message load

4. Performance testing:
   - Measure message throughput
   - Check CPU usage
   - Verify no memory growth over time

**Tests:**
- Full receive loop lifecycle test
- Concurrent send/receive test
- Error handling end-to-end test
- Memory leak test (long-running)
- Thread safety stress test

**Validation:**
- All tests pass
- No memory leaks (GeneralPurposeAllocator)
- Thread safety verified
- Performance acceptable

## 5. Success Criteria

### Functional Requirements
- [ ] Receive thread spawns successfully on connect()
- [ ] Messages are continuously read from WebSocket
- [ ] Messages are deserialized correctly using existing code
- [ ] Heartbeat replies are identified and handled
- [ ] Custom messages invoke callback (Phase 1 API)
- [ ] Read errors transition socket to ERROR state
- [ ] Receive thread terminates gracefully on disconnect()
- [ ] Thread joins complete before disconnect() returns

### Non-Functional Requirements
- [ ] Thread-safe access to all shared state
- [ ] No memory leaks under any scenario
- [ ] No deadlocks or race conditions
- [ ] Responsive shutdown (< 10 seconds)
- [ ] Handles malformed messages without crashing
- [ ] Logging for debugging (errors and key events)

### Test Coverage
- [ ] Unit tests for all new functions (>90% coverage)
- [ ] Thread lifecycle tests (spawn, run, stop)
- [ ] Error handling tests (all error paths)
- [ ] Integration test with real WebSocket connection
- [ ] Concurrent access stress test
- [ ] Memory leak test (extended operation)

### Documentation
- [ ] Code comments explain thread model
- [ ] Public API documented (setMessageCallback)
- [ ] Thread safety guarantees documented
- [ ] Phase 1 temporary APIs marked as such

### Integration
- [ ] Works with existing send() implementation
- [ ] Integrates with connection state machine
- [ ] Compatible with existing error types
- [ ] No breaking changes to public API

## 6. Testing Approach

### 6.1 Unit Tests

**Thread Lifecycle Tests:**
```zig
test "receive thread spawns on connect" {
    // Create socket, connect to test server
    // Verify receive_thread is not null
    // Verify thread is running
}

test "receive thread stops on disconnect" {
    // Create socket, connect, then disconnect
    // Verify thread joined successfully
    // Verify receive_thread is null
}

test "multiple connect/disconnect cycles" {
    // Connect and disconnect 10 times
    // Verify no resource leaks
    // Verify consistent behavior
}
```

**Message Reception Tests:**
```zig
test "text message is deserialized" {
    // Mock WebSocket client returning test message
    // Verify deserialize() is called
    // Verify message callback is invoked
}

test "binary message is ignored" {
    // Mock WebSocket returning binary frame
    // Verify no deserialization attempted
    // Verify callback not invoked
}

test "malformed JSON logs error and continues" {
    // Mock WebSocket returning invalid JSON
    // Verify error is logged
    // Verify loop continues (doesn't crash)
}
```

**Error Handling Tests:**
```zig
test "read error transitions to ERROR state" {
    // Mock WebSocket read() returning error
    // Verify socket transitions to ERROR
    // Verify receive loop exits
}

test "deserialization error doesn't crash" {
    // Send invalid JSON
    // Verify thread continues running
    // Verify error is logged
}

test "connection close stops receive loop" {
    // Close WebSocket from server side
    // Verify receive loop exits cleanly
    // Verify no crashes or errors
}
```

**Routing Tests:**
```zig
test "heartbeat reply is handled" {
    // Send phoenix topic message
    // Verify handlePhoenixTopicMessage called
    // Verify heartbeat timestamp updated
}

test "custom message invokes callback" {
    // Register message callback
    // Send custom topic message
    // Verify callback invoked with correct data
}

test "message without callback is logged" {
    // Don't register callback
    // Send message
    // Verify warning is logged
}
```

**Shutdown Tests:**
```zig
test "shutdown flag stops receive loop" {
    // Start receive loop
    // Set should_stop_receive flag
    // Verify loop exits within timeout
}

test "disconnect waits for thread" {
    // Start receive loop with slow messages
    // Call disconnect()
    // Verify disconnect() blocks until thread exits
}
```

### 6.2 Integration Tests

**Basic Communication Flow:**
```zig
test "integration: receive heartbeat reply" {
    // Connect to test Phoenix server
    // Send heartbeat message
    // Verify reply is received
    // Verify heartbeat handler is called
}

test "integration: send and receive custom event" {
    // Connect to test server
    // Join test channel
    // Send custom event
    // Verify reply is received via callback
}

test "integration: server closes connection" {
    // Connect to test server
    // Server closes connection
    // Verify ERROR state transition
    // Verify receive loop exits
}
```

**Concurrent Operation Tests:**
```zig
test "integration: concurrent send and receive" {
    // Connect to test server
    // Spawn thread to send messages continuously
    // Main thread verifies messages received
    // Verify no race conditions
}

test "integration: multiple channels multiplexed" {
    // Connect to test server
    // Join multiple channels
    // Send messages on each channel
    // Verify correct routing to callbacks
}
```

**Error Recovery Tests:**
```zig
test "integration: handle server errors gracefully" {
    // Connect to test server
    // Trigger server error conditions
    // Verify client handles errors without crash
    // Verify state remains consistent
}
```

### 6.3 Memory and Performance Tests

**Memory Leak Tests:**
```zig
test "no memory leaks during operation" {
    const gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.testing.expect(gpa.deinit() == .ok) catch unreachable;

    // Perform 1000 message receive cycles
    // Verify no leaked memory
}

test "no memory leaks on error paths" {
    // Trigger various error conditions
    // Verify all memory is cleaned up
}
```

**Performance Tests:**
```zig
test "receive throughput is acceptable" {
    // Send 1000 messages rapidly
    // Measure time to receive all
    // Verify throughput > 100 msg/sec
}

test "CPU usage is reasonable" {
    // Run receive loop for extended period
    // Verify CPU usage < 10% when idle
}
```

### 6.4 Thread Safety Tests

**Concurrent Access Tests:**
```zig
test "thread safety: concurrent state access" {
    // Spawn multiple threads calling getState()
    // Spawn thread calling setState()
    // Verify no crashes or corruption
}

test "thread safety: send during receive" {
    // Receive loop running
    // Send messages from main thread
    // Verify no deadlocks or race conditions
}
```

### 6.5 Test Infrastructure

**Mock WebSocket Client:**
Create a mock WebSocket client for testing without network:
- Returns predetermined messages
- Simulates errors on demand
- Tracks calls to read(), done()

**Test Phoenix Server:**
Use existing test server infrastructure (to be created in Task 1.6.1):
- Echoes messages back
- Supports configurable delays
- Can inject errors

**Test Utilities:**
```zig
// Helper to create test socket with mock client
fn createTestSocket(allocator: Allocator) !*PhoenixSocket

// Helper to verify message callback invocation
fn expectMessageCallback(expected: PhoenixMessage) void

// Helper to wait for thread completion with timeout
fn waitForThread(thread: std.Thread, timeout_ms: u32) !void
```

## 7. Risks and Mitigations

### Risk 1: Thread Shutdown Hangs
**Risk:** receive thread may not exit promptly on disconnect()

**Mitigation:**
- Use read timeout (5 seconds) for responsive flag checking
- Add maximum wait time in disconnect() (10 seconds)
- Force close WebSocket if thread doesn't exit
- Test shutdown under various conditions

### Risk 2: Memory Leaks in Error Paths
**Risk:** Error handling may not clean up allocated memory

**Mitigation:**
- Use defer and errdefer consistently
- Test all error paths with GeneralPurposeAllocator
- Add explicit tests for error path memory cleanup
- Use arena allocator for message processing

### Risk 3: Race Conditions in State Access
**Risk:** Concurrent access to ws_client or state may cause crashes

**Mitigation:**
- Always access shared state under mutex protection
- Use atomic flag for shutdown signaling
- Never hold mutex during blocking operations
- Test with thread sanitizer (if available)

### Risk 4: Deadlock During Shutdown
**Risk:** disconnect() may deadlock waiting for thread

**Mitigation:**
- Never acquire mutex in receiveLoop during shutdown check
- Set atomic flag before any mutex operations in disconnect()
- Use timeout in thread join operations
- Test shutdown during message processing

### Risk 5: Message Processing Errors Crash Thread
**Risk:** Unexpected errors during deserialization/routing crash receive thread

**Mitigation:**
- Catch all errors in processTextMessage
- Log errors but continue loop
- Add top-level catch in receiveLoop
- Test with malformed/unexpected messages

## 8. Future Enhancements (Post-Phase 1)

### Phase 2 Enhancements
- Heartbeat mechanism: Track last heartbeat time, trigger reconnection
- Message queue: Buffer messages when disconnected
- Reconnection: Automatic reconnection on connection loss
- Timeout handling: Comprehensive timeout for all operations

### Phase 3 Enhancements
- Channel registry: Full hashtable of topic → channel
- Message routing: Route to specific channel handlers
- Remove message_callback: Replace with channel-based API
- Multiple channels: Handle multiplexed channels correctly

### Phase 4 Enhancements
- Presence tracking: Handle presence_state and presence_diff
- Reply matching: Match phx_reply to outbound messages by ref
- Push callbacks: Invoke ok/error/timeout callbacks for pushes

### Phase 5 Enhancements
- Performance optimization: Reduce allocations, optimize routing
- Enhanced logging: Configurable log levels, structured logging
- Metrics: Track message rates, errors, latency
- Production hardening: Additional error scenarios, stress testing

## 9. Open Questions

### Q1: Should Phase 1 include basic heartbeat time tracking?
**Answer:** Yes, add `last_heartbeat_at: i64` field and update on heartbeat reply.
This provides foundation for Phase 2 watchdog timer without much additional work.

### Q2: How should Phase 1 handle messages for non-existent channels?
**Answer:** Log a warning and invoke the generic message_callback if registered.
Phase 3 will implement proper channel registry and routing.

### Q3: Should we use an arena allocator for message processing?
**Answer:** Yes, use arena allocator in processTextMessage for message lifetime.
This simplifies cleanup and prevents leaks even on error paths.

### Q4: What timeout value should we use for read()?
**Answer:** 5 seconds provides good balance between responsiveness and efficiency.
This allows checking shutdown flag every 5s while avoiding busy-waiting.

### Q5: Should disconnect() have a maximum wait time for thread join?
**Answer:** Yes, wait maximum 10 seconds then log error and continue.
This prevents indefinite blocking while allowing time for clean shutdown.

## 10. References

### Internal Documentation
- `/home/ducky/code/zig_phoenix_channels/CLAUDE.md` - Project guidelines and architecture
- `/home/ducky/code/zig_phoenix_channels/planning/phase-01.md` - Phase 1 plan
- `/home/ducky/code/zig_phoenix_channels/src/protocol/serializer.zig` - deserialize() implementation
- `/home/ducky/code/zig_phoenix_channels/src/connection/socket.zig` - PhoenixSocket structure

### External Documentation
- Phoenix Channels Protocol: https://hexdocs.pm/phoenix/channels.html
- Writing a Channels Client: https://hexdocs.pm/phoenix/writing_a_channels_client.html
- karlseguin/websocket.zig: https://github.com/karlseguin/websocket.zig
- Zig Threading: https://ziglang.org/documentation/master/std/#std.Thread

### Related Tasks
- Task 1.2.3: JSON Deserialization (provides deserialize() function)
- Task 1.3.1: Socket State Machine (provides state transitions)
- Task 1.3.3: Connection Lifecycle (provides connect()/disconnect())
- Task 1.3.4: Message Sending (concurrent with receiving)
- Task 1.6.1: Test Phoenix Server Setup (for integration testing)

## 11. Appendix: API Design

### Public API (Phase 1)

**Message Callback Registration:**
```zig
/// Set callback for received messages (Phase 1 temporary API)
/// Phase 3 will replace this with channel-based message routing
///
/// callback: Function to invoke for each received message
/// context: Optional user context passed to callback
pub fn setMessageCallback(
    self: *PhoenixSocket,
    callback: ?MessageCallback,
    context: ?*anyopaque,
) void
```

**Message Callback Type:**
```zig
/// Callback invoked for received messages
/// msg: Received Phoenix message (read-only, lifetime limited to callback)
/// ctx: User-provided context from setMessageCallback()
pub const MessageCallback = *const fn (
    msg: *const PhoenixMessage,
    ctx: ?*anyopaque
) void;
```

### Internal API

**Receive Loop:**
```zig
/// Main receive loop running in separate thread
/// Continuously reads messages from WebSocket until shutdown
fn receiveLoop(ctx: *ReceiveThreadContext) void
```

**Message Processing:**
```zig
/// Process a received text message
/// Deserializes, validates, and routes the message
fn processTextMessage(
    socket: *PhoenixSocket,
    allocator: std.mem.Allocator,
    data: []const u8
) void
```

**Message Routing:**
```zig
/// Route a message to appropriate handler
/// Phase 1: basic routing to callback or phoenix topic handler
fn routeMessage(socket: *PhoenixSocket, msg: *const PhoenixMessage) void

/// Handle messages on phoenix topic (heartbeats)
fn handlePhoenixTopicMessage(socket: *PhoenixSocket, msg: *const PhoenixMessage) void
```

**Error Handling:**
```zig
/// Handle error during WebSocket read
/// Logs error and transitions to ERROR state
fn handleReadError(socket: *PhoenixSocket, err: anyerror) void
```

### Example Usage (Phase 1)

```zig
const std = @import("std");
const phoenix = @import("phoenix_channels");

fn messageHandler(msg: *const phoenix.PhoenixMessage, ctx: ?*anyopaque) void {
    _ = ctx;
    std.debug.print("Received: topic={s}, event={s}\n", .{
        msg.topic,
        msg.event,
    });
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create socket
    const config = phoenix.PhoenixSocket.Config{
        .url = "ws://localhost:4000/socket/websocket",
    };
    const socket = try phoenix.PhoenixSocket.init(allocator, config);
    defer socket.deinit();

    // Register message callback
    socket.setMessageCallback(messageHandler, null);

    // Connect (starts receive thread automatically)
    try socket.connect();

    // Receive thread now running in background, calling messageHandler
    // for each received message

    // Send a message
    var payload = try phoenix.PhoenixMessage.emptyPayload(allocator);
    defer payload.object.deinit();

    const msg = phoenix.PhoenixMessage.initHeartbeat(
        allocator,
        try socket.nextRefString(),
        payload,
    );
    try socket.send(&msg);

    // Wait for some messages...
    std.time.sleep(5 * std.time.ns_per_s);

    // Disconnect (stops receive thread automatically)
    try socket.disconnect();
}
```

## 12. Implementation Checklist

- [ ] **Step 1: Thread Infrastructure**
  - [ ] Add fields to PhoenixSocket
  - [ ] Define MessageCallback and ReceiveThreadContext
  - [ ] Add setMessageCallback method
  - [ ] Create stub receiveLoop function
  - [ ] Modify connect() to spawn thread
  - [ ] Modify disconnect() to join thread
  - [ ] Update deinit() for thread cleanup
  - [ ] Write and pass thread lifecycle tests

- [ ] **Step 2: Message Reading**
  - [ ] Implement receiveLoop with WebSocket read
  - [ ] Add processTextMessage helper
  - [ ] Add basic routeMessage function
  - [ ] Add handleReadError function
  - [ ] Handle read timeout correctly
  - [ ] Call client.done() properly
  - [ ] Write and pass message reading tests

- [ ] **Step 3: Message Routing**
  - [ ] Implement handlePhoenixTopicMessage
  - [ ] Add last_heartbeat_at tracking
  - [ ] Enhance routeMessage for different types
  - [ ] Add message validation before routing
  - [ ] Write and pass routing tests

- [ ] **Step 4: Error Handling**
  - [ ] Add comprehensive error handling in loop
  - [ ] Implement error recovery strategies
  - [ ] Add error logging throughout
  - [ ] Handle connection failure detection
  - [ ] Write and pass error handling tests

- [ ] **Step 5: Graceful Shutdown**
  - [ ] Implement atomic flag checking
  - [ ] Update disconnect() with thread join
  - [ ] Add shutdown timeout handling
  - [ ] Update deinit() for cleanup
  - [ ] Write and pass shutdown tests

- [ ] **Step 6: Integration and Testing**
  - [ ] Create comprehensive unit test suite
  - [ ] Add integration tests with server
  - [ ] Validate thread safety
  - [ ] Perform memory leak testing
  - [ ] Document Phase 1 APIs as temporary

## 13. Acceptance Criteria

This feature is complete when:

1. [ ] Receive thread spawns successfully on connect()
2. [ ] Messages are continuously read from WebSocket
3. [ ] Messages are deserialized using existing serializer
4. [ ] Heartbeat replies update last_heartbeat_at timestamp
5. [ ] Custom messages invoke message callback
6. [ ] Read errors transition to ERROR state gracefully
7. [ ] Receive thread terminates cleanly on disconnect()
8. [ ] All unit tests pass (>90% coverage)
9. [ ] Integration test with Phoenix server passes
10. [ ] No memory leaks detected by GeneralPurposeAllocator
11. [ ] Thread safety verified (no race conditions/deadlocks)
12. [ ] Shutdown completes within 10 seconds
13. [ ] Code is documented with comments
14. [ ] Phase 1 temporary APIs marked clearly
15. [ ] Ready for Phase 2 heartbeat and reconnection features
