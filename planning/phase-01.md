# Phase 1: Core Foundation

## Overview

This phase establishes the foundational infrastructure for the Phoenix Channels client library. The goal is to implement the core protocol correctly and create the state machines that will govern all client behavior. By focusing on the fundamentals first, we ensure that all future features build on a solid, well-tested foundation.

The Phoenix Channels protocol is deceptively simple at the surface (5-field JSON arrays) but has specific requirements around state transitions, reference management, and message routing. This phase implements these requirements faithfully while following Zig best practices for memory management and error handling. We prioritize correctness over performance in this phase - optimization comes later once functionality is proven.

This phase represents approximately 2 weeks of work and serves as the critical foundation upon which all subsequent phases depend. A thorough, correct implementation here prevents costly refactoring later.

---

## 1.1 Project Setup and Dependencies

This section establishes the basic project structure, build configuration, and external dependencies. We create the foundational directory structure that will organize the library logically and set up the build system that will be used throughout development. Proper project setup from the start prevents organizational issues as the codebase grows.

The dependency setup requires careful consideration. We're using karlseguin/websocket.zig as our WebSocket foundation, which is the most mature and actively maintained WebSocket library for Zig. This decision is based on its production usage, compliance with WebSocket standards, and compatibility with current Zig versions.

### 1.1.1 Build System Configuration ✅ COMPLETED

Creating a robust build system is essential for efficient development and testing. The Zig build system is powerful but requires explicit configuration for library projects, tests, and examples. This task sets up the build.zig file that will be the central point for all build operations throughout the project lifecycle.

- ✅ 1.1.1.1 Create build.zig with library target configuration
- ✅ 1.1.1.2 Configure test runner for unit and integration tests
- ✅ 1.1.1.3 Add example executable targets for development validation
- ✅ 1.1.1.4 Set up build options for debug/release configurations

**Implementation Details:**
- Created `build.zig` using Zig 0.15.2 API with `addLibrary()` and `createModule()`
- Implemented static library target (`libphoenix_channels.a`)
- Configured separate unit and integration test targets with selective execution
- Added example executable (`basic_connection`) that links against the library
- Set up standard optimization modes (Debug, ReleaseSafe, ReleaseFast, ReleaseSmall)
- Created directory structure: `src/`, `tests/`, `examples/`
- All build targets verified working: `zig build`, `zig build test`, `zig build run`
- Tested with all optimization modes successfully

### 1.1.2 Dependency Management ✅ COMPLETED

Managing external dependencies in Zig requires explicit vendoring or build integration. The WebSocket library is our primary external dependency, and we need to ensure it integrates smoothly with our build system. Proper dependency management prevents version conflicts and ensures reproducible builds.

- ✅ 1.1.2.1 Add karlseguin/websocket.zig dependency to build.zig
- ✅ 1.1.2.2 Configure dependency fetch and build integration
- ✅ 1.1.2.3 Verify WebSocket library compiles and links correctly
- ✅ 1.1.2.4 Create wrapper module for WebSocket client abstraction

**Implementation Details:**
- Created `build.zig.zon` with proper Zig 0.15.2 format (enum literal syntax for package names)
- Added karlseguin/websocket.zig dependency using git commit SHA 43ce3ff21c5979ef5c0fa11b1f778705c35f47eb
- Configured dependency with correct hash: `websocket-0.1.0-ZPISdRJzAwAnbleES-QZyp0DlQzbzYVAb2FxwWT4p38K`
- Created shared `phoenix_mod` module in build.zig for use by library, tests, and examples
- Added websocket module import to all build targets (library, unit tests, integration tests, examples)
- Created `src/websocket_wrapper.zig` module providing Phoenix-specific WebSocket interface
- Wrapper properly handles karlseguin/websocket.zig API (mutable buffers, Client.done() for messages)
- Exposed WebSocketWrapper through `src/root.zig` for library consumers
- Added comprehensive unit tests validating dependency integration
- All tests passing: dependency accessible, types work correctly, wrapper handles disconnected state
- Library builds successfully and links with websocket dependency: `libphoenix_channels.a`

### 1.1.3 Project Structure

A well-organized directory structure makes the codebase navigable and maintainable. We follow Zig conventions while adapting to the specific needs of a client library. The structure should clearly separate core protocol implementation, state management, and utilities.

- 1.1.3.1 Create src/ directory with main library entry point
- 1.1.3.2 Set up src/protocol/ for message format and protocol logic
- 1.1.3.3 Create src/connection/ for Socket and connection management
- 1.1.3.4 Set up src/channel/ for Channel implementation
- 1.1.3.5 Create tests/ directory with test file organization
- 1.1.3.6 Set up examples/ for demonstration applications

### 1.1.4 Core Type Definitions

Defining core types early establishes the vocabulary used throughout the library. These types should be carefully designed as changing them later is costly. We prioritize clarity and type safety, using Zig's type system to prevent errors at compile time.

- 1.1.4.1 Define core error sets for different error categories
- 1.1.4.2 Create common types (Allocator wrappers, callbacks)
- 1.1.4.3 Define configuration structs for Socket and Channel options
- 1.1.4.4 Create reference counter type for generating unique message refs

### Unit Tests - Section 1.1

- Test build system compiles library target successfully
- Test dependency resolution and linking of WebSocket library
- Test project structure allows proper module imports
- Test core type definitions compile and basic instantiation works

---

## 1.2 Message Format Implementation

This section implements the Phoenix V2 message format, which is the core protocol abstraction. Phoenix messages are 5-element JSON arrays with specific semantics for each position. Correct implementation of serialization and deserialization is critical - any bugs here propagate to all higher-level functionality.

The message format is deceptively simple but has several subtleties: join_ref is required only for phx_join, ref should be unique per socket, topic has special meaning for "phoenix", and payload must always be a JSON object (never a primitive). Getting these details right requires careful implementation and thorough testing.

### 1.2.1 Message Structure Definition

The PhoenixMessage struct is the central data structure for all protocol operations. It must accurately represent the 5-field format while being ergonomic to work with in Zig. We need to handle nullable fields correctly (join_ref, ref) and ensure the payload field can represent arbitrary JSON structures.

- 1.2.1.1 Define PhoenixMessage struct with 5 fields matching protocol spec
- 1.2.1.2 Implement field types (nullable strings, JSON value for payload)
- 1.2.1.3 Add convenience constructors for common message types
- 1.2.1.4 Implement deinit() for proper memory cleanup

### 1.2.2 JSON Serialization

Serialization converts PhoenixMessage structs to JSON array format for transmission. This must produce the exact 5-element array format Phoenix expects: [join_ref, ref, topic, event, payload]. We use std.json.stringify but need careful handling of nullable fields and nested JSON structures.

- 1.2.2.1 Implement toArray() method for converting to JSON array format
- 1.2.2.2 Handle nullable field serialization (null vs absent)
- 1.2.2.3 Ensure payload serialization preserves JSON structure
- 1.2.2.4 Add buffer management for serialized output

### 1.2.3 JSON Deserialization

Deserialization parses incoming JSON arrays into PhoenixMessage structs. This is more complex than serialization because we must validate the structure, handle malformed messages gracefully, and manage memory for string fields. We use arena allocation for temporary parsing structures.

- 1.2.3.1 Implement fromArray() method for parsing JSON arrays
- 1.2.3.2 Validate array has exactly 5 elements
- 1.2.3.3 Parse each field with appropriate type checking
- 1.2.3.4 Handle malformed messages with descriptive errors
- 1.2.3.5 Implement memory management for parsed strings

### 1.2.4 Message Validation

Not all syntactically valid messages are semantically correct. We need validation logic to catch protocol violations early. For example, phx_join must have join_ref, regular messages should not, payload must be an object. Validation prevents propagating invalid state.

- 1.2.4.1 Implement validation for required fields per message type
- 1.2.4.2 Validate topic format and reserved topics ("phoenix")
- 1.2.4.3 Ensure payload is always a JSON object (not primitive)
- 1.2.4.4 Add validation for system event names (phx_join, etc.)

### Unit Tests - Section 1.2

- Test serialization of all message types (join, leave, push, reply, etc.)
- Test deserialization of valid Phoenix messages
- Test deserialization error handling for malformed messages
- Test message validation catches protocol violations
- Test memory management (no leaks after many serialize/deserialize cycles)
- Test round-trip: serialize then deserialize produces equivalent message

---

## 1.3 Socket State Machine

This section implements the Socket component, which manages the WebSocket connection lifecycle. The Socket is responsible for connection state, message routing to channels, heartbeat coordination, and recovery from failures. It implements a clear state machine with explicit transitions to prevent invalid operations.

The connection state machine has five states: DISCONNECTED, CONNECTING, CONNECTED, CLOSING, and ERROR. Each state allows specific operations and transitions. For example, you can only send messages in CONNECTED state, and ERROR state automatically triggers reconnection (implemented in Phase 2). Clear state management prevents race conditions and undefined behavior.

### 1.3.1 State Machine Definition

The state machine must be explicitly defined with all states and valid transitions documented. We use an enum for states and implement transition logic that validates each state change. This prevents bugs where operations happen in inappropriate states.

- 1.3.1.1 Define ConnectionState enum with all five states
- 1.3.1.2 Document valid transitions between states
- 1.3.1.3 Implement transition validation logic
- 1.3.1.4 Add state change callbacks for debugging and monitoring

### 1.3.2 Socket Structure

The Socket struct contains all connection-related state: WebSocket client, connection state, channel registry (added Phase 3), ref counter, and synchronization primitives. The structure must be carefully designed to support thread-safe operation with minimal locking.

- 1.3.2.1 Define PhoenixSocket struct with core fields
- 1.3.2.2 Add connection state and WebSocket client fields
- 1.3.2.3 Include reference counter for unique message IDs
- 1.3.2.4 Add mutex for thread-safe state access
- 1.3.2.5 Include allocator field for memory management

### 1.3.3 Connection Lifecycle

The connection lifecycle manages the actual WebSocket handshake and teardown. Connect establishes the WebSocket and transitions to CONNECTED. Disconnect gracefully closes the connection. Both operations must handle threading correctly and ensure clean state transitions.

- 1.3.3.1 Implement connect() method with WebSocket handshake
- 1.3.3.2 Implement disconnect() for graceful connection closure
- 1.3.3.3 Handle connection errors and state transitions
- 1.3.3.4 Add connection timeout detection
- 1.3.3.5 Implement connection parameter handling (URL, query params, headers)

### 1.3.4 Message Sending

Message sending must check connection state before attempting to send. In CONNECTED state, serialize the message and send via WebSocket. In other states, either queue (Phase 2) or return an error. Thread safety is critical - multiple threads may try to send simultaneously.

- 1.3.4.1 Implement send() method with state checking
- 1.3.4.2 Add message serialization and WebSocket frame creation
- 1.3.4.3 Handle send errors and connection failures
- 1.3.4.4 Implement thread-safe sending with mutex protection
- 1.3.4.5 Add send timeout and retry logic (basic)

### 1.3.5 Message Receiving

The receive loop runs in a separate thread, continuously reading from the WebSocket. Received messages are deserialized and routed to appropriate handlers (heartbeat responses to Socket, others to Channels). The receive loop must handle errors gracefully and trigger reconnection on connection loss.

- 1.3.5.1 Implement receive loop running in separate thread
- 1.3.5.2 Add message deserialization and routing logic
- 1.3.5.3 Handle receive errors and connection failures
- 1.3.5.4 Implement graceful thread shutdown on disconnect
- 1.3.5.5 Add receive timeout handling

### 1.3.6 Reference Generation

Each message needs a unique reference for matching replies. The ref counter must be thread-safe and produce unique string references. We use a simple counter but ensure thread safety with mutex protection. References only need uniqueness per socket, not globally.

- 1.3.6.1 Implement makeRef() method with thread-safe counter
- 1.3.6.2 Convert counter to string format for protocol
- 1.3.6.3 Handle counter overflow (wrap or error)
- 1.3.6.4 Add ref validation and collision detection

### Unit Tests - Section 1.3

- Test state machine transitions (valid and invalid)
- Test connection establishment and disconnection
- Test message sending in CONNECTED state
- Test message sending errors in non-CONNECTED states
- Test receive loop message parsing and routing
- Test reference generation uniqueness and thread safety
- Test concurrent access to Socket from multiple threads
- Test connection timeout detection

---

## 1.4 Channel State Machine

This section implements the Channel component, which represents a logical subscription to a topic. Channels have their own state machine independent of the Socket state. A channel can be CLOSED, JOINING, JOINED, LEAVING, or ERROR. Channels buffer messages when not joined and flush them upon successful join.

The channel state machine interacts with the socket state machine but operates independently. A channel may be JOINING while the socket is CONNECTED, or JOINED while the socket is DISCONNECTED (though it can't send until socket reconnects). This independence adds complexity but provides flexibility and correct semantics.

### 1.4.1 State Machine Definition

The channel state machine has five states with specific transition rules. CLOSED→JOINING on join(), JOINING→JOINED on phx_reply OK, JOINED→ERROR on phx_error (triggers automatic rejoin in Phase 2), JOINED→CLOSED on phx_close (no rejoin). Clear state definitions prevent protocol violations.

- 1.4.1.1 Define ChannelState enum with all five states
- 1.4.1.2 Document valid state transitions and triggers
- 1.4.1.3 Implement transition validation logic
- 1.4.1.4 Add state change callbacks for observability

### 1.4.2 Channel Structure

The Channel struct contains topic, current state, join reference, event callbacks, pending messages (Phase 2), and back-reference to parent Socket. The structure must support thread-safe operation as channels may be accessed from multiple threads.

- 1.4.2.1 Define Channel struct with core fields
- 1.4.2.2 Add topic and state fields
- 1.4.2.3 Include join reference for tracking join request
- 1.4.2.4 Add event callback registry (event name → handler)
- 1.4.2.5 Include back-reference to parent Socket
- 1.4.2.6 Add mutex for thread-safe state access

### 1.4.3 Join Operation

Join subscribes to a channel by sending phx_join with parameters. This generates a unique join_ref, transitions to JOINING state, sends the message, and starts a timeout timer. The response (phx_reply) will trigger transition to JOINED or ERROR state.

- 1.4.3.1 Implement join() method with parameter handling
- 1.4.3.2 Generate unique join reference
- 1.4.3.3 Construct and send phx_join message
- 1.4.3.4 Transition to JOINING state
- 1.4.3.5 Start join timeout timer (basic timeout, full implementation Phase 2)
- 1.4.3.6 Handle join errors and state transitions

### 1.4.4 Leave Operation

Leave unsubscribes from a channel by sending phx_leave. This transitions to LEAVING state and waits for phx_reply. After confirmation (or timeout), transition to CLOSED. Leave is a graceful operation that doesn't trigger rejoin.

- 1.4.4.1 Implement leave() method
- 1.4.4.2 Construct and send phx_leave message
- 1.4.4.3 Transition to LEAVING state
- 1.4.4.4 Handle leave confirmation and timeout
- 1.4.4.5 Transition to CLOSED state after completion

### 1.4.5 Push Operation

Push sends a custom event on the channel. The channel must be JOINED to push (or buffer for later). Push creates a message with the channel's topic and delegates to Socket for sending. Push optionally takes callbacks for handling replies.

- 1.4.5.1 Implement push() method for sending custom events
- 1.4.5.2 Validate channel is JOINED (or handle buffering)
- 1.4.5.3 Construct message with topic and event
- 1.4.5.4 Delegate to Socket.send() for transmission
- 1.4.5.5 Register reply callbacks (ok, error, timeout) if provided

### 1.4.6 Event Handling

Channels receive messages from the Socket and must route them to appropriate handlers. System events (phx_reply, phx_error, phx_close) affect channel state. Custom events are routed to application callbacks registered with on().

- 1.4.6.1 Implement handleMessage() for incoming message routing
- 1.4.6.2 Handle phx_reply messages (match by ref, check status)
- 1.4.6.3 Handle phx_error messages (transition to ERROR)
- 1.4.6.4 Handle phx_close messages (transition to CLOSED)
- 1.4.6.5 Route custom events to registered callbacks
- 1.4.6.6 Implement on() method for registering event callbacks

### Unit Tests - Section 1.4

- Test channel state machine transitions (valid and invalid)
- Test join operation with parameters
- Test join success handling (phx_reply OK)
- Test join failure handling (phx_reply error)
- Test leave operation and confirmation
- Test push operation in JOINED state
- Test push operation errors in non-JOINED states
- Test event callback registration and invocation
- Test phx_error and phx_close handling
- Test concurrent access to Channel from multiple threads

---

## 1.5 Basic Communication Flow

This section integrates Socket and Channel to enable basic end-to-end communication with a Phoenix server. We implement the complete flow: connect socket, create channel, join channel, push events, receive events, leave channel, disconnect socket. This validates that all components work together correctly.

The communication flow exercises the entire protocol stack and reveals integration issues. Testing against a real Phoenix server (or mock server) ensures protocol compliance and correct state management. This section represents the first time the library can actually communicate with Phoenix.

### 1.5.1 Socket-Channel Integration

Integrating Socket and Channel requires careful coordination. Socket must route messages to the correct Channel based on topic. Channels must delegate sending to Socket. Both must handle state transitions correctly when the other component changes state.

- 1.5.1.1 Implement channel creation via Socket.channel() method
- 1.5.1.2 Add channel registry in Socket (simple HashMap for now)
- 1.5.1.3 Implement message routing from Socket to correct Channel
- 1.5.1.4 Handle channel not found during message routing
- 1.5.1.5 Coordinate state transitions between Socket and Channels

### 1.5.2 Complete Communication Flow

Implement and test the complete sequence: connect, join, push, receive, leave, disconnect. This validates the protocol implementation against Phoenix server behavior. Each step must work correctly for the library to be usable.

- 1.5.2.1 Implement connection establishment with Phoenix server
- 1.5.2.2 Implement channel join flow with confirmation
- 1.5.2.3 Implement bidirectional event exchange
- 1.5.2.4 Implement channel leave flow with confirmation
- 1.5.2.5 Implement graceful disconnection

### 1.5.3 Error Path Testing

Communication can fail at many points: connection failures, join rejections, message send failures, unexpected disconnects. Testing error paths ensures the library handles failures gracefully without crashes or corruption.

- 1.5.3.1 Test connection failure handling
- 1.5.3.2 Test join rejection scenarios
- 1.5.3.3 Test send errors during communication
- 1.5.3.4 Test unexpected disconnection handling
- 1.5.3.5 Test malformed message handling

### 1.5.4 Memory Management Validation

Long-running connections must not leak memory. We use GeneralPurposeAllocator's leak detection to validate proper cleanup. Arena allocators must be freed after message processing. All dynamically allocated state must have corresponding deinit calls.

- 1.5.4.1 Validate no memory leaks during connection lifecycle
- 1.5.4.2 Test arena allocator cleanup after message processing
- 1.5.4.3 Verify proper cleanup on error paths (errdefer)
- 1.5.4.4 Test memory usage under prolonged operation

### Unit Tests - Section 1.5

- Test Socket.channel() creates and registers channels correctly
- Test message routing to correct channel by topic
- Test handling of messages for non-existent channels
- Test complete join-push-receive-leave flow
- Test error handling throughout communication flow
- Test memory cleanup after operations complete
- Test memory stability over multiple operation cycles

---

## 1.6 Integration Tests

This section provides comprehensive integration testing against a real Phoenix server. Integration tests validate that the library works correctly with actual Phoenix backend implementation, not just against protocol specifications. These tests exercise the full stack and catch issues that unit tests miss.

Setting up integration testing infrastructure is essential for validating correctness. We create a simple Phoenix test server with configurable channels and behaviors. Integration tests run against this server, testing happy paths and error scenarios. These tests complement unit tests by validating real-world behavior.

### 1.6.1 Test Phoenix Server Setup

A proper test server allows controlled testing of all scenarios. The server should support configurable channels, delayed responses, forced disconnects, and error injection. This enables testing both success and failure paths reliably.

- 1.6.1.1 Create minimal Phoenix application for testing
- 1.6.1.2 Implement test channels with various behaviors
- 1.6.1.3 Add configurable delays and error injection
- 1.6.1.4 Set up automated server startup/shutdown for tests
- 1.6.1.5 Document server API and available test channels

### 1.6.2 Basic Protocol Compliance Tests

These tests validate that the client implements the Phoenix protocol correctly by exercising all protocol operations against the real server. Each test should verify correct message format, state transitions, and response handling.

- 1.6.2.1 Test connection establishment with server
- 1.6.2.2 Test channel join with various parameters
- 1.6.2.3 Test custom event push and reception
- 1.6.2.4 Test channel leave operation
- 1.6.2.5 Test graceful disconnection
- 1.6.2.6 Test heartbeat exchange (basic validation, full implementation Phase 2)

### 1.6.3 Multi-Channel Scenarios

Real applications use multiple channels simultaneously. These tests validate that multiplexing works correctly: messages route to the right channels, state is independent per channel, and operations on one channel don't affect others.

- 1.6.3.1 Test connecting to multiple channels simultaneously
- 1.6.3.2 Test message routing to correct channels
- 1.6.3.3 Test independent state management per channel
- 1.6.3.4 Test leaving one channel while others remain active
- 1.6.3.5 Test rejoining a channel after leaving

### 1.6.4 Error Scenario Testing

Error handling is critical for production reliability. These tests verify that the client handles server errors, rejections, and unexpected conditions gracefully. The client should never crash or corrupt state when the server misbehaves.

- 1.6.4.1 Test join rejection handling (authorization failures)
- 1.6.4.2 Test server-side channel termination (phx_close)
- 1.6.4.3 Test server-side channel crash (phx_error)
- 1.6.4.4 Test malformed message handling
- 1.6.4.5 Test timeout scenarios (slow server responses)

### 1.6.5 State Consistency Validation

State consistency tests verify that client state accurately reflects reality. After operations, the client's view of channel state, connection state, and pending operations should match the server's view. Inconsistencies lead to subtle bugs.

- 1.6.5.1 Verify channel state consistency after operations
- 1.6.5.2 Verify message reference tracking correctness
- 1.6.5.3 Test state recovery after error conditions
- 1.6.5.4 Validate no state corruption under concurrent access

---

## Success Criteria

This phase is complete when:

1. **Protocol Implementation**: Message serialization/deserialization working correctly for all message types
2. **State Machines**: Socket and Channel state machines implemented with proper transition validation
3. **Basic Communication**: Can connect, join channels, send/receive events, leave, and disconnect
4. **Test Coverage**: Unit tests cover all core components with >85% coverage
5. **Integration Validation**: Integration tests pass against real Phoenix server
6. **Memory Safety**: No memory leaks detected by GeneralPurposeAllocator
7. **Thread Safety**: Concurrent access to Socket and Channels works correctly
8. **Error Handling**: All error paths return appropriate errors (no panics)

## Provides Foundation For

This phase establishes the foundation for:
- **Phase 2**: Reliability features (reconnection, heartbeat, queuing) build on correct state management
- **Phase 3**: Multiplexing and error handling extend the basic channel registry
- **Phase 4**: Advanced features require solid protocol and state machine implementation
- **Phase 5**: Production readiness validates and documents the complete system

## Key Outputs

1. **Implemented Components**:
   - PhoenixMessage struct with serialization/deserialization
   - PhoenixSocket with connection state machine
   - Channel with channel state machine
   - Basic message routing and event handling

2. **Test Infrastructure**:
   - Unit test suite for all components
   - Phoenix test server for integration testing
   - Integration test suite covering basic flows

3. **Documentation**:
   - Architecture documentation explaining state machines
   - API documentation for public functions
   - Examples demonstrating basic usage

4. **Development Tools**:
   - Build system configured for development and testing
   - Basic debugging and logging infrastructure
   - Development guidelines for contributors

## Next Phase Preview

Phase 2 builds on this foundation by adding reliability features:
- Automatic reconnection with exponential backoff
- Message queuing when disconnected or channel not joined
- Heartbeat mechanism with watchdog timer
- Comprehensive timeout handling

These features transform the client from a basic protocol implementation to a production-ready library that handles real-world network conditions reliably.
