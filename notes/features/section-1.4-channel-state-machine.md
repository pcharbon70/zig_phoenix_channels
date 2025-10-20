# Feature Planning: Section 1.4 - Channel State Machine

**Phase**: Phase 1 - Core Foundation
**Section**: 1.4 - Channel State Machine
**Date**: 2025-10-20
**Status**: Planning

## Table of Contents

1. [Problem Statement and Goals](#problem-statement-and-goals)
2. [Solution Overview](#solution-overview)
3. [Technical Details](#technical-details)
4. [Implementation Plan](#implementation-plan)
5. [Testing Strategy](#testing-strategy)
6. [Success Criteria](#success-criteria)

---

## Problem Statement and Goals

### Background

The Socket Component (Section 1.3) successfully implements WebSocket connection management with 145 passing tests. Now we need to implement the Channel Component, which represents logical subscriptions to Phoenix topics. While the Socket manages the physical WebSocket connection, Channels provide the abstraction for topic-based communication.

### Problem Statement

Phoenix Channels operate on a multiplexing model where a single WebSocket connection supports multiple independent channels, each subscribed to different topics. Each channel has its own lifecycle independent of the socket state:

- A channel can be JOINING while the socket is CONNECTED
- A channel can be JOINED while the socket temporarily DISCONNECTED (though messages won't send until reconnection)
- Channels need to handle protocol-specific behaviors: `phx_error` triggers rejoin, `phx_close` does not

The challenge is implementing this independent channel state machine while coordinating with the socket for message transmission and handling the Phoenix protocol's specific semantics.

### Goals

1. **State Machine Implementation**: Define and implement the five-state channel state machine (CLOSED, JOINING, JOINED, LEAVING, ERROR) with proper transition validation
2. **Channel Lifecycle**: Implement join, leave, and push operations that respect channel state
3. **Event Handling**: Create a callback system for routing incoming messages to application handlers
4. **Socket Integration**: Coordinate with Socket for message transmission while maintaining state independence
5. **Thread Safety**: Ensure all channel operations are thread-safe for concurrent access
6. **Phoenix Protocol Compliance**: Correctly handle system events (phx_join, phx_leave, phx_reply, phx_error, phx_close)

### Non-Goals (Deferred to Phase 2)

- Message queuing/buffering when channel not joined
- Automatic rejoin on `phx_error`
- Join/leave timeout handling
- Push reply callback management (ok, error, timeout)
- Exponential backoff for rejoin attempts

---

## Solution Overview

### Architecture Approach

We follow the same pattern established in the Socket Component:

1. **Separate State Machine Module**: `src/channel/state.zig` defines the ChannelState enum with transition validation (already exists with basic implementation)
2. **Channel Structure Module**: `src/channel/channel.zig` implements the Channel struct with all operations (skeletal implementation exists)
3. **Independent State Management**: Channel state transitions are independent of Socket state but coordinate for message sending
4. **Callback-Based Event Routing**: Events received on a channel are dispatched to registered callbacks

### Key Design Decisions

#### 1. State Machine Independence

**Decision**: Channel state machine operates completely independently from Socket state machine.

**Rationale**:
- A channel can be JOINED even when socket is temporarily disconnected
- State independence simplifies reasoning about channel lifecycle
- Matches Phoenix.js behavior

**Implementation**:
- Channel tracks its own state with its own mutex
- Channel delegates message sending to Socket but doesn't check socket state
- Socket returns error if not connected; channel handles the error

#### 2. Back-Reference to Socket

**Decision**: Channel stores a pointer to its parent Socket.

**Rationale**:
- Needed for sending messages (join, leave, push)
- Needed for generating unique message references
- Avoids passing socket to every operation

**Implementation**:
```zig
pub const Channel = struct {
    socket: *PhoenixSocket,  // Back-reference to parent
    // ... other fields
};
```

**Lifetime Management**: Socket owns channels and is responsible for cleanup. Channel never outlives socket.

#### 3. Event Callback Registry

**Decision**: Use `std.StringHashMap(EventCallback)` to map event names to handler functions.

**Rationale**:
- Efficient O(1) lookup for event routing
- Straightforward API: `channel.on("event_name", callback)`
- Matches common patterns in Node.js/Phoenix.js

**Implementation**:
```zig
pub const EventCallback = *const fn(payload: std.json.Value, context: ?*anyopaque) void;

pub const Channel = struct {
    callbacks: std.StringHashMap(EventCallback),
    // ...
};
```

#### 4. Join Reference Management

**Decision**: Store join_ref as owned string in Channel struct.

**Rationale**:
- Join reference must persist for the lifetime of the join attempt
- Needed to match phx_reply responses
- Must survive state transitions

**Implementation**:
```zig
pub const Channel = struct {
    join_ref: ?[]u8,  // Owned, allocated with channel's allocator
    // ...
};
```

#### 5. State Change Callbacks (Optional)

**Decision**: Provide optional state change callback similar to Socket implementation.

**Rationale**:
- Consistency with Socket API
- Useful for debugging and monitoring
- Applications can track channel lifecycle

**Implementation**:
```zig
pub const ChannelStateCallback = *const fn(
    old_state: ChannelState,
    new_state: ChannelState,
    context: ?*anyopaque,
) void;
```

### Constraints and Trade-offs

**Constraint**: Phase 1 focuses on basic functionality without queuing or retry logic.

**Trade-off**: This means push() will fail immediately if channel not JOINED rather than buffering. This is acceptable for Phase 1 and will be enhanced in Phase 2.

**Constraint**: No timeout handling in Phase 1.

**Trade-off**: Join and leave operations won't have timeout detection. Applications must implement their own timeouts if needed. Phase 2 will add comprehensive timeout support.

---

## Technical Details

### Files and Dependencies

#### Files to Modify

1. **`src/channel/state.zig`** (already exists with basic implementation)
   - Enhance ChannelState enum with helper methods
   - Add ChannelStateCallback type
   - Add StateTransition struct (similar to Socket)
   - Add validation and error message methods

2. **`src/channel/channel.zig`** (skeletal implementation exists)
   - Complete Channel struct definition
   - Implement init() and deinit()
   - Implement join() operation
   - Implement leave() operation
   - Implement push() operation
   - Implement on() for callback registration
   - Implement handleMessage() for incoming message routing (internal)

#### Files to Create

1. **`tests/channel/state_machine_test.zig`**
   - State transition validation tests
   - Valid and invalid transition tests
   - State callback tests
   - Edge case tests

2. **`tests/channel/channel_structure_test.zig`**
   - Channel initialization tests
   - Configuration tests
   - Memory management tests
   - Multiple channel independence tests

3. **`tests/channel/join_operation_test.zig`**
   - Join with various parameters
   - Join state transitions
   - Join reference generation
   - Join error handling

4. **`tests/channel/leave_operation_test.zig`**
   - Leave operation
   - Leave state transitions
   - Leave confirmation handling

5. **`tests/channel/push_operation_test.zig`**
   - Push in JOINED state
   - Push validation (only when JOINED)
   - Push with various payloads
   - Push error handling

6. **`tests/channel/event_callbacks_test.zig`**
   - Callback registration
   - Callback invocation
   - Multiple callbacks per channel
   - Callback removal

#### Dependencies

**Existing Modules**:
- `src/connection/socket.zig` - For sending messages
- `src/protocol/message.zig` - For message construction
- `src/common/types.zig` - For RefCounter, callbacks
- `std.Thread.Mutex` - For thread-safe state access
- `std.StringHashMap` - For callback registry

**External Dependencies**:
- None (uses only Zig standard library and existing project modules)

### Data Structures

#### Enhanced ChannelState (in `src/channel/state.zig`)

```zig
pub const ChannelState = enum {
    CLOSED,
    JOINING,
    JOINED,
    LEAVING,
    ERROR,

    // Existing methods
    pub fn canTransitionTo(self: ChannelState, target: ChannelState) bool { ... }
    pub fn toString(self: ChannelState) []const u8 { ... }

    // New methods to add
    pub fn validateTransition(self: ChannelState, target: ChannelState) !void { ... }
    pub fn getTransitionError(self: ChannelState, target: ChannelState) []const u8 { ... }
    pub fn isJoined(self: ChannelState) bool { ... }
    pub fn canPush(self: ChannelState) bool { ... }
    pub fn isTransitional(self: ChannelState) bool { ... }
};

pub const ChannelStateCallback = *const fn(
    old_state: ChannelState,
    new_state: ChannelState,
    context: ?*anyopaque,
) void;

pub const StateTransition = struct {
    from: ChannelState,
    to: ChannelState,
    reason: ?[]const u8 = null,

    pub fn init(from: ChannelState, to: ChannelState, reason: ?[]const u8) StateTransition { ... }
    pub fn isValid(self: StateTransition) bool { ... }
};
```

#### Complete Channel Structure (in `src/channel/channel.zig`)

```zig
pub const EventCallback = *const fn(
    payload: std.json.Value,
    context: ?*anyopaque,
) void;

pub const Channel = struct {
    /// Memory allocator for dynamic allocations
    allocator: std.mem.Allocator,

    /// Back-reference to parent socket (not owned)
    socket: *PhoenixSocket,

    /// Channel topic (e.g., "room:lobby")
    topic: []const u8,  // Owned string

    /// Current channel state
    state: ChannelState,

    /// Join reference (owned, null when not joining/joined)
    join_ref: ?[]u8,

    /// Event callback registry: event_name -> callback
    callbacks: std.StringHashMap(CallbackEntry),

    /// Mutex for thread-safe state access
    mutex: std.Thread.Mutex,

    /// Optional state change callback
    state_callback: ?ChannelStateCallback,

    /// Optional context for state callback
    callback_context: ?*anyopaque,

    // Public API
    pub fn init(allocator: std.mem.Allocator, socket: *PhoenixSocket, topic: []const u8) !*Channel { ... }
    pub fn deinit(self: *Channel) void { ... }

    pub fn join(self: *Channel, params: ?std.json.Value) !void { ... }
    pub fn leave(self: *Channel) !void { ... }
    pub fn push(self: *Channel, event: []const u8, payload: std.json.Value) !void { ... }

    pub fn on(self: *Channel, event: []const u8, callback: EventCallback, context: ?*anyopaque) !void { ... }
    pub fn off(self: *Channel, event: []const u8) void { ... }

    pub fn getState(self: *const Channel) ChannelState { ... }
    pub fn setState(self: *Channel, new_state: ChannelState) !void { ... }
    pub fn setStateCallback(self: *Channel, callback: ?ChannelStateCallback, context: ?*anyopaque) void { ... }

    // Internal methods (not exposed)
    fn handleMessage(self: *Channel, message: *const PhoenixMessage) !void { ... }
    fn invokeCallback(self: *Channel, event: []const u8, payload: std.json.Value) void { ... }
};

const CallbackEntry = struct {
    callback: EventCallback,
    context: ?*anyopaque,
};
```

### API Design

#### Channel Creation (via Socket)

```zig
// In Socket:
pub fn channel(self: *PhoenixSocket, topic: []const u8) !*Channel {
    const chan = try Channel.init(self.allocator, self, topic);
    // Phase 1: Just return the channel
    // Phase 3: Add to channel registry
    return chan;
}
```

#### Join Operation

```zig
// Basic join with no parameters
const channel = try socket.channel("room:lobby");
try channel.join(null);

// Join with parameters (e.g., authentication token)
var params = std.json.ObjectMap.init(allocator);
defer params.deinit();
try params.put("token", .{ .string = "auth_token" });
try channel.join(.{ .object = params });
```

**Behavior**:
1. Validates state is CLOSED (returns error.InvalidState otherwise)
2. Generates unique join_ref using socket.nextRefString()
3. Transitions to JOINING state
4. Constructs phx_join message with topic, join_ref, and params
5. Delegates to socket.send() for transmission
6. Returns immediately (async response via callback in Phase 2)

**Message Format**:
```json
["join_ref_123", "join_ref_123", "room:lobby", "phx_join", {"token": "auth_token"}]
```

#### Leave Operation

```zig
try channel.leave();
```

**Behavior**:
1. Validates state is JOINED (returns error.InvalidState otherwise)
2. Generates unique ref using socket.nextRefString()
3. Transitions to LEAVING state
4. Constructs phx_leave message
5. Delegates to socket.send()
6. Returns immediately (state transition to CLOSED handled when phx_reply received)

**Message Format**:
```json
[null, "ref_456", "room:lobby", "phx_leave", {}]
```

#### Push Operation

```zig
var payload = std.json.ObjectMap.init(allocator);
defer payload.deinit();
try payload.put("message", .{ .string = "Hello" });

try channel.push("new_msg", .{ .object = payload });
```

**Behavior**:
1. Validates state is JOINED (returns error.NotJoined otherwise)
2. Generates unique ref using socket.nextRefString()
3. Constructs message with channel topic and event
4. Delegates to socket.send()
5. Returns immediately (Phase 1 does not track replies)

**Message Format**:
```json
[null, "ref_789", "room:lobby", "new_msg", {"message": "Hello"}]
```

#### Event Callback Registration

```zig
const MyContext = struct {
    count: usize,
};

fn onNewMsg(payload: std.json.Value, context: ?*anyopaque) void {
    if (context) |ctx| {
        const my_ctx: *MyContext = @ptrCast(@alignCast(ctx));
        my_ctx.count += 1;
    }
    // Handle message
    std.debug.print("Received: {any}\n", .{payload});
}

var ctx = MyContext{ .count = 0 };
try channel.on("new_msg", onNewMsg, &ctx);
```

**Behavior**:
1. Stores callback in HashMap with event name as key
2. When message arrives with matching event, invokes callback with payload
3. Callbacks invoked outside mutex to prevent deadlock

#### State Change Callback

```zig
fn onStateChange(old: ChannelState, new: ChannelState, context: ?*anyopaque) void {
    std.debug.print("Channel state: {} -> {}\n", .{old.toString(), new.toString()});
}

channel.setStateCallback(onStateChange, null);
```

### Thread Safety Strategy

Following the pattern from Socket Component:

1. **Mutex Protection**: All state access and modification protected by `channel.mutex`
2. **Two-Phase Locking**:
   - Acquire lock to check state
   - Release lock before calling external functions (socket.send, callbacks)
   - Re-acquire if needed
3. **Callback Invocation**: Always invoke callbacks outside mutex to prevent deadlock
4. **Reference Counter**: Socket's RefCounter has its own mutex, safe to call

**Example Pattern**:
```zig
pub fn push(self: *Channel, event: []const u8, payload: std.json.Value) !void {
    // Phase 1: Check state
    {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.state != .JOINED) {
            return error.NotJoined;
        }
    }

    // Phase 2: Build and send message (no lock held)
    const ref = try self.socket.nextRefString();
    defer self.socket.allocator.free(ref);

    const msg = try PhoenixMessage.initEvent(
        self.allocator,
        ref,
        self.topic,
        event,
        payload,
    );
    defer msg.deinit();

    try self.socket.send(&msg);
}
```

### Error Handling

**New Error Types** (add to `src/common/errors.zig`):

```zig
pub const ChannelError = error{
    NotJoined,        // Operation requires JOINED state
    NotClosed,        // Join requires CLOSED state
    AlreadyJoined,    // Duplicate join attempt
    InvalidTopic,     // Empty or malformed topic
    CallbackNotFound, // Attempted to remove non-existent callback
    InvalidState,     // Generic invalid state error
};
```

**Error Propagation**:
- State validation errors propagate immediately
- Socket.send() errors propagate to caller
- Callback invocation errors are caught and logged (don't fail operation)

### Memory Management

**Allocation Patterns**:

1. **Channel Lifetime**:
   - Allocated by `socket.channel()` using socket's allocator
   - Owned by socket (or application in Phase 1)
   - Cleaned up by explicit `channel.deinit()` call

2. **Topic String**:
   - Duplicated during init() using channel's allocator
   - Freed during deinit()

3. **Join Reference**:
   - Allocated during join() using channel's allocator
   - Freed during leave() or deinit()
   - Replaced on re-join

4. **Callback HashMap**:
   - HashMap owns keys (duplicated event name strings)
   - Callbacks and context pointers are not owned (caller responsibility)
   - HashMap freed during deinit()

5. **Message Construction**:
   - Temporary messages allocated for join/leave/push
   - Freed immediately after socket.send()
   - Message references freed after use

**Cleanup Order** (in deinit()):
```zig
pub fn deinit(self: *Channel) void {
    self.mutex.lock();
    defer self.mutex.unlock();

    // Free topic string
    self.allocator.free(self.topic);

    // Free join_ref if exists
    if (self.join_ref) |ref| {
        self.allocator.free(ref);
    }

    // Free callback HashMap (keys are owned)
    var it = self.callbacks.iterator();
    while (it.next()) |entry| {
        self.allocator.free(entry.key_ptr.*);
    }
    self.callbacks.deinit();

    // Free the channel itself
    self.allocator.destroy(self);
}
```

---

## Implementation Plan

### Phase 1: State Machine Enhancement (Task 1.4.1)

**Goal**: Complete the ChannelState enum with all helper methods and callbacks.

**Steps**:

1. **Enhance `src/channel/state.zig`**:
   - Add `validateTransition()` method
   - Add `getTransitionError()` method
   - Add `isJoined()` helper
   - Add `canPush()` helper
   - Add `isTransitional()` helper
   - Add `ChannelStateCallback` type definition
   - Add `StateTransition` struct

2. **Write tests in `tests/channel/state_machine_test.zig`**:
   - Valid transitions (all states)
   - Invalid transitions (all invalid paths)
   - State helper methods
   - State sequences
   - Edge cases
   - **Target**: 40+ tests

**Acceptance Criteria**:
- All state transitions properly validated
- Helper methods return correct values
- StateTransition struct works correctly
- All tests passing

### Phase 2: Channel Structure (Task 1.4.2)

**Goal**: Complete the Channel struct with all fields and basic operations.

**Steps**:

1. **Complete `src/channel/channel.zig`**:
   - Add all struct fields (socket, topic, state, join_ref, callbacks, mutex, state_callback, callback_context)
   - Implement `init()` with proper initialization
   - Implement `deinit()` with proper cleanup
   - Implement `getState()` method
   - Implement `setState()` with validation and callback
   - Implement `setStateCallback()` method

2. **Write tests in `tests/channel/channel_structure_test.zig`**:
   - Channel initialization with various topics
   - Configuration validation
   - State getter/setter
   - State callbacks
   - Memory management (no leaks)
   - Multiple channels are independent
   - **Target**: 30+ tests

**Acceptance Criteria**:
- Channel initializes with correct defaults
- State transitions validated
- State callbacks work
- No memory leaks in init/deinit cycles
- All tests passing

### Phase 3: Join Operation (Task 1.4.3)

**Goal**: Implement the join() method with proper state management and message construction.

**Steps**:

1. **Implement `join()` in `src/channel/channel.zig`**:
   - Validate current state is CLOSED
   - Generate unique join_ref using socket
   - Store join_ref in channel
   - Transition to JOINING state
   - Construct phx_join message
   - Delegate to socket.send()
   - Handle errors with proper cleanup

2. **Write tests in `tests/channel/join_operation_test.zig`**:
   - Join with null params
   - Join with params payload
   - Join state transitions (CLOSED -> JOINING)
   - Join reference generation and storage
   - Join from invalid states returns error
   - Join message format validation
   - Multiple join attempts (second fails)
   - **Target**: 25+ tests

**Acceptance Criteria**:
- Join only works from CLOSED state
- Join_ref properly generated and stored
- State transitions to JOINING
- Message sent to socket
- Errors handled gracefully
- All tests passing

### Phase 4: Leave Operation (Task 1.4.4)

**Goal**: Implement the leave() method with proper state management.

**Steps**:

1. **Implement `leave()` in `src/channel/channel.zig`**:
   - Validate current state is JOINED
   - Generate unique ref using socket
   - Transition to LEAVING state
   - Construct phx_leave message
   - Delegate to socket.send()
   - Handle errors with proper cleanup

2. **Write tests in `tests/channel/leave_operation_test.zig`**:
   - Leave from JOINED state
   - Leave state transitions (JOINED -> LEAVING)
   - Leave from invalid states returns error
   - Leave message format validation
   - Multiple leave attempts
   - **Target**: 20+ tests

**Acceptance Criteria**:
- Leave only works from JOINED state
- State transitions to LEAVING
- Message sent to socket
- Errors handled gracefully
- All tests passing

### Phase 5: Push Operation (Task 1.4.5)

**Goal**: Implement the push() method for sending custom events.

**Steps**:

1. **Implement `push()` in `src/channel/channel.zig`**:
   - Validate current state is JOINED
   - Generate unique ref using socket
   - Construct message with topic, event, payload
   - Delegate to socket.send()
   - Handle errors

2. **Write tests in `tests/channel/push_operation_test.zig`**:
   - Push in JOINED state succeeds
   - Push in non-JOINED states returns error.NotJoined
   - Push with various payloads
   - Push with empty payload
   - Push with nested payload
   - Push message format validation
   - Multiple push operations
   - **Target**: 20+ tests

**Acceptance Criteria**:
- Push only works from JOINED state
- Message constructed correctly with topic and event
- Message sent to socket
- All payload types handled
- All tests passing

### Phase 6: Event Callbacks (Task 1.4.6)

**Goal**: Implement callback registration and message routing.

**Steps**:

1. **Implement callback system in `src/channel/channel.zig`**:
   - Implement `on()` to register callbacks
   - Implement `off()` to remove callbacks
   - Implement `handleMessage()` for routing incoming messages
   - Implement `invokeCallback()` helper
   - Handle system events (phx_reply, phx_error, phx_close)
   - Route custom events to registered callbacks

2. **Write tests in `tests/channel/event_callbacks_test.zig`**:
   - Register callback with on()
   - Callback invoked on matching event
   - Remove callback with off()
   - Multiple callbacks for different events
   - Callback with context
   - Callback with null context
   - Unknown event doesn't crash
   - System event handling (phx_reply with ok/error status)
   - **Target**: 25+ tests

**Acceptance Criteria**:
- Callbacks registered and stored correctly
- Callbacks invoked on matching events
- Callbacks can be removed
- Context passed correctly
- System events handled
- All tests passing

### Phase 7: Integration and Cleanup

**Goal**: Integrate all components and ensure everything works together.

**Steps**:

1. **Update `src/root.zig`**:
   - Export Channel module
   - Export ChannelState enum
   - Export callback types

2. **Update `tests/unit_tests.zig`**:
   - Import all new test files
   - Organize by task

3. **Update `planning/phase-01.md`**:
   - Mark all Task 1.4 subtasks as complete
   - Update success criteria

4. **Write summary document** (`notes/summaries/section-1.4-channel-state-machine.md`):
   - Implementation summary
   - Test coverage summary
   - Known limitations
   - Next steps

**Acceptance Criteria**:
- All modules properly exported
- All tests passing
- Documentation updated
- Summary written

### Implementation Order Rationale

1. **State Machine First**: Establishes the foundation, similar to Socket
2. **Structure Second**: Provides the container for all operations
3. **Join Third**: Most complex operation, establishes patterns
4. **Leave Fourth**: Similar to join but simpler
5. **Push Fifth**: Straightforward once join/leave established
6. **Callbacks Last**: Ties everything together

This order minimizes dependencies and allows incremental testing.

---

## Testing Strategy

### Test Organization

Following the successful pattern from Section 1.3, organize tests by component responsibility:

```
tests/channel/
├── state_machine_test.zig        (~40 tests)
├── channel_structure_test.zig    (~30 tests)
├── join_operation_test.zig       (~25 tests)
├── leave_operation_test.zig      (~20 tests)
├── push_operation_test.zig       (~20 tests)
└── event_callbacks_test.zig      (~25 tests)
```

**Total Target**: 160+ tests for Section 1.4

### Test Categories

#### 1. State Machine Tests (~40 tests)

**Valid Transitions**:
- CLOSED → JOINING
- JOINING → JOINED
- JOINING → ERROR
- JOINING → CLOSED
- JOINED → LEAVING
- JOINED → ERROR
- JOINED → CLOSED
- LEAVING → CLOSED
- ERROR → CLOSED
- ERROR → JOINING

**Invalid Transitions**:
- CLOSED → JOINED (must go through JOINING)
- CLOSED → LEAVING (can't leave if not joined)
- CLOSED → ERROR (can't error if not active)
- JOINING → LEAVING (can't leave while joining)
- JOINED → JOINING (can't rejoin without leaving)
- LEAVING → JOINING (must close first)
- LEAVING → JOINED (can't complete join while leaving)
- LEAVING → ERROR (leaving is terminal operation)
- All idempotent transitions (state → same state)

**Helper Methods**:
- isJoined() correct for each state
- canPush() correct for each state
- isTransitional() correct for each state
- toString() returns correct names

**StateTransition Struct**:
- Valid transition creation
- Invalid transition detection
- Reason field preserved

**State Callbacks**:
- Callback invoked on transition
- Callback with context
- Callback with null context
- Callback not invoked on invalid transition

#### 2. Channel Structure Tests (~30 tests)

**Initialization**:
- Basic initialization with topic
- Initialization with socket reference
- All fields initialized correctly
- Multiple channels are independent
- Topic string is owned (duplicated)

**State Management**:
- getState() returns current state
- setState() validates transition
- setState() invokes callback
- Invalid setState() returns error
- State remains unchanged on error

**State Callbacks**:
- setStateCallback() registers callback
- State change invokes callback
- Multiple state changes tracked
- Callback replacement works
- Remove callback works

**Memory Management**:
- init/deinit doesn't leak
- Multiple init/deinit cycles safe
- Topic string freed on deinit
- Join_ref freed on deinit
- Callbacks HashMap freed on deinit

**Configuration**:
- Topic validation (non-empty)
- Special topics ("phoenix")
- Topics with colons ("room:lobby")
- Long topic names

#### 3. Join Operation Tests (~25 tests)

**Basic Join**:
- Join from CLOSED state
- Join transitions to JOINING
- Join_ref generated and stored
- Join message sent to socket

**Join with Parameters**:
- Join with null params
- Join with empty object params
- Join with authentication token
- Join with nested params

**State Validation**:
- Join from JOINING fails (already joining)
- Join from JOINED fails (already joined)
- Join from LEAVING fails (must wait)
- Join from ERROR allowed (retry)

**Message Format**:
- Join message has correct format
- Join_ref equals ref for join messages
- Topic matches channel topic
- Event is "phx_join"
- Params in payload

**Error Handling**:
- Join when socket not connected
- Join with invalid state
- Socket.send() error propagates

**Join Reference**:
- Unique join_ref for each join
- Join_ref stored in channel
- Join_ref freed on leave/deinit

#### 4. Leave Operation Tests (~20 tests)

**Basic Leave**:
- Leave from JOINED state
- Leave transitions to LEAVING
- Leave message sent to socket

**State Validation**:
- Leave from CLOSED fails
- Leave from JOINING fails (not joined yet)
- Leave from LEAVING fails (already leaving)
- Leave from ERROR allowed (cleanup)

**Message Format**:
- Leave message has correct format
- Join_ref is null for leave
- Ref is unique
- Topic matches channel topic
- Event is "phx_leave"
- Empty payload object

**Error Handling**:
- Leave when socket not connected
- Leave with invalid state
- Socket.send() error propagates

#### 5. Push Operation Tests (~20 tests)

**Basic Push**:
- Push from JOINED state succeeds
- Push constructs correct message
- Push delegates to socket

**State Validation**:
- Push from CLOSED returns error.NotJoined
- Push from JOINING returns error.NotJoined
- Push from LEAVING returns error.NotJoined
- Push from ERROR returns error.NotJoined

**Message Format**:
- Push message has correct format
- Join_ref is null
- Ref is unique
- Topic matches channel topic
- Event matches provided event
- Payload matches provided payload

**Payload Variations**:
- Empty payload object
- Payload with single field
- Payload with nested objects
- Payload with arrays
- Payload with various types

**Error Handling**:
- Push when socket not connected
- Push with invalid state
- Socket.send() error propagates

#### 6. Event Callback Tests (~25 tests)

**Callback Registration**:
- on() registers callback
- on() with context
- on() with null context
- Multiple callbacks for different events
- Replacing callback for same event

**Callback Invocation**:
- Callback invoked on matching event
- Callback receives correct payload
- Callback receives context
- Multiple events route to correct callbacks

**Callback Removal**:
- off() removes callback
- off() non-existent event is safe
- After off(), callback not invoked

**System Event Handling** (Phase 1 basic):
- phx_reply with "ok" status
- phx_reply with "error" status
- phx_error event
- phx_close event
- Unknown system event

**Edge Cases**:
- Callback for non-existent event (no crash)
- Callback throws error (caught and logged)
- Callback during state transition
- Concurrent callback invocation

**Thread Safety**:
- Register callback from multiple threads
- Invoke callbacks concurrently
- Remove callback while invoking (edge case)

### Test Quality Standards

Following Section 1.3 patterns:

1. **Memory Safety**: All tests use `testing.allocator` with automatic leak detection
2. **Resource Cleanup**: Use `defer` for all cleanup
3. **Error Path Coverage**: Test both success and error paths
4. **Thread Safety**: Include concurrent access tests where relevant
5. **Clear Naming**: Test names describe what is being tested
6. **Comments**: Explain non-obvious test logic
7. **Independence**: Each test is self-contained

### Integration Testing Considerations

**Deferred to Section 1.5**:
- Actual Socket-Channel integration
- Message routing from Socket to Channel
- Complete join-push-leave flow
- Multiple channels on same socket
- Channel cleanup when socket disconnects

**Phase 1 Limitations**:
- Tests use mock socket or manual state management
- Message receiving not tested (Task 1.3.5 not implemented yet)
- No timeout behavior tested
- No queuing behavior tested

---

## Success Criteria

### Functional Requirements

- [ ] ChannelState enum has all five states with proper transitions
- [ ] Channel struct has all required fields
- [ ] Channel initializes correctly with topic and socket reference
- [ ] Join operation transitions CLOSED → JOINING and sends message
- [ ] Leave operation transitions JOINED → LEAVING and sends message
- [ ] Push operation only works in JOINED state
- [ ] Event callbacks can be registered and invoked
- [ ] State change callbacks work correctly
- [ ] All state transitions validated

### Technical Requirements

- [ ] Thread-safe access to channel state using mutex
- [ ] No memory leaks detected by testing.allocator
- [ ] All error paths return appropriate errors
- [ ] Proper cleanup in deinit() for all resources
- [ ] Channel never crashes on invalid operations
- [ ] Topic string properly owned and freed
- [ ] Join_ref properly managed
- [ ] Callback HashMap properly managed

### Test Coverage

- [ ] Minimum 160 tests for Section 1.4
- [ ] All valid state transitions tested
- [ ] All invalid state transitions tested
- [ ] All operations tested in all states
- [ ] Thread safety validated
- [ ] Memory safety validated
- [ ] Error paths covered
- [ ] All tests passing

### Documentation

- [ ] All public methods have doc comments
- [ ] State machine transitions documented
- [ ] API examples in doc comments
- [ ] Implementation summary document written
- [ ] phase-01.md updated with completion status

### Code Quality

- [ ] Follows existing code patterns from Section 1.3
- [ ] Consistent naming conventions
- [ ] Proper error propagation
- [ ] Clear separation of concerns
- [ ] No TODO comments remaining
- [ ] Code formatted with `zig fmt`

### Phoenix Protocol Compliance

- [ ] Join message format matches Phoenix V2 protocol
- [ ] Leave message format matches Phoenix V2 protocol
- [ ] Push message format matches Phoenix V2 protocol
- [ ] System events (phx_join, phx_leave) handled correctly
- [ ] Join_ref equals ref for phx_join messages
- [ ] Topic field always matches channel topic

---

## Timeline Estimate

Based on Section 1.3 experience (145 tests in 5 files):

- **Task 1.4.1** (State Machine): 3-4 hours (40 tests)
- **Task 1.4.2** (Channel Structure): 4-5 hours (30 tests)
- **Task 1.4.3** (Join Operation): 4-5 hours (25 tests)
- **Task 1.4.4** (Leave Operation): 3-4 hours (20 tests)
- **Task 1.4.5** (Push Operation): 3-4 hours (20 tests)
- **Task 1.4.6** (Event Callbacks): 4-5 hours (25 tests)
- **Integration & Cleanup**: 2-3 hours

**Total Estimate**: 23-30 hours (3-4 days)

---

## Dependencies and Blockers

### Prerequisites (Completed)

- ✅ Section 1.1: Project Setup
- ✅ Section 1.2: Message Format Implementation
- ✅ Section 1.3: Socket State Machine

### Parallel Work Possible

- Section 1.3.5 (Message Receiving) can be implemented in parallel
- These components will integrate in Section 1.5

### Blockers

None. All dependencies satisfied.

---

## Risks and Mitigations

### Risk 1: Socket-Channel Coordination Complexity

**Risk**: Managing independent state machines that must coordinate for operations.

**Mitigation**:
- Clear API boundaries: Channel delegates sending to Socket
- Socket returns errors if not connected; Channel handles errors
- Phase 1 keeps it simple (no queuing, no retries)

### Risk 2: Thread Safety Deadlocks

**Risk**: Deadlock if channel holds lock while calling socket methods that acquire locks.

**Mitigation**:
- Follow two-phase locking pattern from Socket
- Never call external methods while holding lock
- Document locking order (Socket mutex, then Channel mutex)

### Risk 3: Memory Management Complexity

**Risk**: Multiple owned strings (topic, join_ref) and HashMap keys to manage.

**Mitigation**:
- Clear ownership model documented
- Comprehensive init/deinit tests
- Use testing.allocator to catch leaks early

### Risk 4: Callback Error Handling

**Risk**: Callbacks throwing errors could crash the library.

**Mitigation**:
- Wrap callback invocation in catch
- Log callback errors but continue operation
- Document that callbacks should not throw

---

## Future Enhancements (Phase 2+)

### Phase 2 Additions

1. **Message Queuing**:
   - Buffer pushes when not JOINED
   - Flush buffer on successful join
   - Configurable queue size limits

2. **Join Timeout**:
   - Timer starts on join()
   - Transition to ERROR if no phx_reply
   - Configurable timeout duration

3. **Automatic Rejoin**:
   - On phx_error, automatically rejoin
   - Exponential backoff for retries
   - Configurable retry limits

4. **Push Reply Callbacks**:
   - Track pending pushes by ref
   - Invoke ok/error/timeout callbacks
   - Memory management for callback contexts

### Phase 3 Additions

1. **Channel Registry**:
   - Socket maintains HashMap of topic → Channel
   - Message routing from Socket to Channel
   - Automatic cleanup on disconnect

2. **Multi-Channel Coordination**:
   - Multiple channels on same socket
   - Independent state per channel
   - Efficient message routing

---

## Appendix: Code Examples

### Complete Usage Example

```zig
const std = @import("std");
const phoenix = @import("phoenix_channels");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create socket
    const socket_config = phoenix.connection.SocketConfig{
        .url = "ws://localhost:4000/socket/websocket",
    };
    const socket = try phoenix.connection.PhoenixSocket.init(allocator, socket_config);
    defer socket.deinit();

    // Connect to server
    try socket.connect();
    defer socket.disconnect() catch {};

    // Create channel
    const channel = try socket.channel("room:lobby");
    defer channel.deinit();

    // Register event handler
    const Context = struct {
        pub fn onMessage(payload: std.json.Value, ctx: ?*anyopaque) void {
            _ = ctx;
            std.debug.print("Received message: {any}\n", .{payload});
        }
    };
    try channel.on("new_msg", Context.onMessage, null);

    // Join channel
    try channel.join(null);

    // Wait for join confirmation (Phase 2 will handle this automatically)
    // For now, assume join succeeded after some time

    // Push message
    var payload = std.json.ObjectMap.init(allocator);
    defer payload.deinit();
    try payload.put("body", .{ .string = "Hello, Phoenix!" });

    try channel.push("new_msg", .{ .object = payload });

    // Leave channel
    try channel.leave();
}
```

### State Callback Example

```zig
const ChannelMonitor = struct {
    name: []const u8,

    pub fn onStateChange(old: ChannelState, new: ChannelState, context: ?*anyopaque) void {
        if (context) |ctx| {
            const monitor: *ChannelMonitor = @ptrCast(@alignCast(ctx));
            std.debug.print("[{s}] State change: {s} -> {s}\n", .{
                monitor.name,
                old.toString(),
                new.toString(),
            });
        }
    }
};

var monitor = ChannelMonitor{ .name = "lobby_channel" };
channel.setStateCallback(ChannelMonitor.onStateChange, &monitor);
```

### Multiple Event Handlers Example

```zig
const Handler = struct {
    pub fn onNewMsg(payload: std.json.Value, ctx: ?*anyopaque) void {
        _ = ctx;
        std.debug.print("New message: {any}\n", .{payload});
    }

    pub fn onUserJoined(payload: std.json.Value, ctx: ?*anyopaque) void {
        _ = ctx;
        std.debug.print("User joined: {any}\n", .{payload});
    }

    pub fn onUserLeft(payload: std.json.Value, ctx: ?*anyopaque) void {
        _ = ctx;
        std.debug.print("User left: {any}\n", .{payload});
    }
};

try channel.on("new_msg", Handler.onNewMsg, null);
try channel.on("user_joined", Handler.onUserJoined, null);
try channel.on("user_left", Handler.onUserLeft, null);
```

---

## References

- **Planning Document**: `/home/ducky/code/zig_phoenix_channels/planning/phase-01.md`
- **Socket Implementation**: `/home/ducky/code/zig_phoenix_channels/src/connection/socket.zig`
- **Socket State Machine**: `/home/ducky/code/zig_phoenix_channels/src/connection/state.zig`
- **Section 1.3 Tests Summary**: `/home/ducky/code/zig_phoenix_channels/notes/summaries/section-1.3-unit-tests.md`
- **Phoenix Channels Documentation**: https://hexdocs.pm/phoenix/channels.html
- **Writing a Channels Client**: https://hexdocs.pm/phoenix/writing_a_channels_client.html
- **Phoenix.js Source**: https://github.com/phoenixframework/phoenix/tree/main/assets/js/phoenix

---

**End of Feature Planning Document**
