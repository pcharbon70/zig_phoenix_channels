# Section 1.3 Unit Tests - Feature Planning Document

**Task**: Unit Tests for Section 1.3 (Socket Component)
**Phase**: Phase 1 - Core Foundation
**Date**: 2025-10-20
**Status**: Planning

## Table of Contents

1. [Overview](#overview)
2. [Current State Analysis](#current-state-analysis)
3. [Test Organization Strategy](#test-organization-strategy)
4. [Test Categories](#test-categories)
5. [Detailed Test Cases by Subtask](#detailed-test-cases-by-subtask)
6. [Test File Organization](#test-file-organization)
7. [Dependencies and Setup](#dependencies-and-setup)
8. [Success Criteria](#success-criteria)
9. [Implementation Plan](#implementation-plan)

---

## Overview

### Purpose

This document provides comprehensive planning for implementing dedicated unit tests for Section 1.3 (Socket Component) of Phase 1. Currently, tests are scattered throughout implementation files. This planning document organizes and consolidates test coverage into a dedicated, maintainable test suite.

### Scope

Section 1.3 includes six subtasks:

- **1.3.1**: State Machine (ConnectionState enum, transitions)
- **1.3.2**: Socket Structure (PhoenixSocket struct, initialization, reference counter)
- **1.3.3**: Connection Lifecycle (connect, disconnect, WebSocket integration)
- **1.3.4**: Message Sending (send method, thread-safe transmission)
- **1.3.5**: Message Receiving (receive loop, background thread, message callbacks)
- **1.3.6**: Reference Generation (RefCounter, thread-safe counter)

### Goals

1. **Consolidate**: Move tests from implementation files to dedicated test files
2. **Organize**: Group tests logically by functionality
3. **Expand**: Add missing test coverage for edge cases and error paths
4. **Document**: Provide clear test documentation and rationale
5. **Maintain**: Establish maintainable test structure for future additions

---

## Current State Analysis

### Existing Tests

#### Tests in `src/connection/socket.zig` (26 tests)

**Socket Initialization and Structure** (2 tests):
- socket initialization
- socket configuration

**Reference Generation** (2 tests):
- reference counter generates unique IDs
- reference counter generates string IDs

**State Management** (9 tests):
- state transition validation
- state callback invocation
- state callback with null context
- remove state callback
- thread-safe state access
- complete state transition sequence
- error state transitions

**URL Parsing** (7 tests):
- ws with port and path
- wss with port and path
- ws without port
- wss without port
- without path
- invalid protocol
- invalid port

**Connection Lifecycle** (3 tests):
- connect: invalid state
- disconnect: invalid state when DISCONNECTED
- disconnect: valid state when ERROR

**Message Sending** (5 tests):
- send: returns error when DISCONNECTED
- send: returns error when CONNECTING
- send: returns error when CLOSING
- send: returns error when ERROR
- send: returns error when ws_client is null despite CONNECTED state

#### Tests in `src/common/types.zig` (2 tests)

**RefCounter Tests**:
- RefCounter generates unique references
- RefCounter reset works

#### Tests in `src/connection/state.zig` (21 tests)

**State Machine Tests** (21 tests covering all state transitions and validation)

### Coverage Gaps

Based on the planning document requirements, we need to add:

1. **Concurrent Access Tests**: Multi-threaded stress testing
2. **Connection Timeout Tests**: Actual timeout detection
3. **Receive Loop Tests**: Task 1.3.5 not yet implemented
4. **Message Routing Tests**: Callback invocation and message handling
5. **Integration Tests**: Complete workflows combining multiple components
6. **Error Path Tests**: More comprehensive error scenarios
7. **Resource Cleanup Tests**: Memory leak detection and proper cleanup
8. **Edge Case Tests**: Boundary conditions and unusual scenarios

---

## Test Organization Strategy

### Principles

1. **Separation of Concerns**: One test file per major component
2. **Logical Grouping**: Related tests grouped together with clear section headers
3. **Test Naming**: Descriptive names following pattern: `component: action - expected result`
4. **Documentation**: Each test group has explanatory comments
5. **Independence**: Tests don't depend on execution order
6. **Cleanup**: Proper resource cleanup with defer/errdefer

### Test Structure

```
tests/
├── connection/                    # Connection layer tests
│   ├── state_machine_tests.zig   # State machine (1.3.1)
│   ├── socket_tests.zig           # Socket structure (1.3.2)
│   ├── lifecycle_tests.zig        # Connection lifecycle (1.3.3)
│   ├── message_sending_tests.zig  # Message sending (1.3.4)
│   ├── message_receiving_tests.zig # Message receiving (1.3.5)
│   └── ref_counter_tests.zig      # Reference generation (1.3.6)
├── integration/
│   └── socket_integration_tests.zig # End-to-end Socket tests
└── unit_tests.zig                 # Test entry point
```

### Test Execution

- Tests can be run individually: `zig build test-connection`
- Or all together: `zig build test`
- Integration tests separate: `zig build test-integration`

---

## Test Categories

### 1. Unit Tests (Component Level)

Test individual functions and methods in isolation.

**Examples**:
- State transition validation
- Reference counter increment
- URL parsing
- Message serialization

**Characteristics**:
- No external dependencies
- Fast execution (<1ms per test)
- Deterministic results
- No threading required (except thread-safety tests)

### 2. Integration Tests (Component Interaction)

Test how components work together.

**Examples**:
- Socket + State Machine
- Socket + Message Sending
- Connection Lifecycle + State Transitions

**Characteristics**:
- Multiple components
- May involve threading
- Slower execution (1-10ms per test)
- Real WebSocket connections (mocked or local server)

### 3. Concurrency Tests (Thread Safety)

Test thread-safe operation under concurrent access.

**Examples**:
- Multiple threads calling nextRef() simultaneously
- Concurrent send() operations
- State changes from multiple threads

**Characteristics**:
- Spawn multiple threads
- Requires synchronization primitives
- Non-deterministic timing
- May need multiple runs to detect race conditions

### 4. Error Path Tests (Failure Scenarios)

Test error handling and recovery.

**Examples**:
- Invalid state transitions
- Connection failures
- Message send errors
- Timeout detection

**Characteristics**:
- Test error conditions
- Verify proper error propagation
- Check resource cleanup on errors
- Validate errdefer works correctly

### 5. Resource Management Tests (Memory Safety)

Test memory allocation and cleanup.

**Examples**:
- No leaks after socket lifecycle
- Proper cleanup on error paths
- Arena allocator usage
- Reference counting

**Characteristics**:
- Use std.testing.allocator (detects leaks)
- Multiple allocation/deallocation cycles
- Verify deinit() completeness
- Check errdefer cleanup

---

## Detailed Test Cases by Subtask

### 1.3.1 State Machine Tests

**File**: `tests/connection/state_machine_tests.zig`

**Existing Coverage**: 21 tests in `src/connection/state.zig`

**Additional Tests Needed**:

#### Basic State Transitions (Already Covered)
- ✅ All valid transitions tested
- ✅ All invalid transitions tested
- ✅ Transition validation
- ✅ Error messages

#### State Callbacks (Needs Expansion)
- **Test**: Multiple callbacks registered
  - Register multiple callbacks, verify all invoked
  - Test callback ordering
- **Test**: Callback throws exception
  - Verify state transition still completes
  - Verify other callbacks still invoked
- **Test**: Callback modifies context
  - Verify context changes visible in subsequent callbacks

#### State Inspection
- **Test**: toString() for all states
  - Verify human-readable names
- **Test**: State equality and comparison
  - Verify enum comparison works correctly

#### Concurrent State Access
- **Test**: Concurrent state reads
  - Multiple threads calling getState()
  - Verify no data races
- **Test**: Concurrent state writes
  - Multiple threads calling setState()
  - Verify serialization (one at a time)
  - Verify no invalid intermediate states

**Total New Tests**: ~8 tests

---

### 1.3.2 Socket Structure Tests

**File**: `tests/connection/socket_tests.zig`

**Existing Coverage**: 11 tests in `src/connection/socket.zig`

**Additional Tests Needed**:

#### Initialization and Configuration
- ✅ Basic initialization
- ✅ Configuration values
- **Test**: Multiple sockets with different configs
  - Create multiple sockets
  - Verify independent configuration
  - Verify independent state
- **Test**: Default configuration values
  - Test default timeout, heartbeat interval
- **Test**: Invalid configuration
  - Negative timeouts
  - Empty URL

#### Reference Counter Integration
- ✅ Numeric ID generation
- ✅ String ID generation
- **Test**: Reference counter overflow
  - Manually set counter near usize max
  - Verify wrapping behavior
- **Test**: Reference uniqueness across socket instances
  - Create multiple sockets
  - Verify refs are unique per socket (not globally)

#### State Management Integration
- ✅ State transition validation
- ✅ Callback invocation
- **Test**: State persistence across operations
  - Perform operations, verify state remains consistent
- **Test**: State after deinit
  - Verify state cleanup

#### WebSocket Client Management
- **Test**: ws_client null when disconnected
  - Verify initially null
  - Verify null after disconnect
- **Test**: ws_client set when connected
  - (Requires actual connection or mock)
- **Test**: ws_client cleanup on deinit
  - Verify client properly freed

#### Memory Management
- **Test**: Socket allocation and deallocation
  - Create and destroy socket
  - Use std.testing.allocator to detect leaks
- **Test**: Multiple socket lifecycle
  - Create, use, destroy multiple sockets
  - Verify no leaks

#### Thread Safety
- **Test**: Concurrent socket creation
  - Multiple threads creating sockets
  - Verify independent instances
- **Test**: Concurrent access to socket fields
  - Multiple threads reading config
  - Verify thread-safe access

**Total New Tests**: ~12 tests

---

### 1.3.3 Connection Lifecycle Tests

**File**: `tests/connection/lifecycle_tests.zig`

**Existing Coverage**: 10 tests (7 URL parsing + 3 lifecycle) in `src/connection/socket.zig`

**Additional Tests Needed**:

#### URL Parsing (Already Well Covered)
- ✅ All URL formats tested
- ✅ Error cases tested

#### Connection Establishment
- **Test**: Successful connection to valid server
  - Requires test server or mock
  - Verify state transitions: DISCONNECTED → CONNECTING → CONNECTED
  - Verify ws_client is set
- **Test**: Connection to invalid host
  - Attempt connection to non-existent host
  - Verify state: DISCONNECTED → CONNECTING → ERROR
  - Verify error returned
- **Test**: Connection timeout
  - Connect to slow/unresponsive server
  - Verify timeout detection
  - Verify error state
- **Test**: Connection with custom headers/params
  - (Future feature, placeholder test)

#### Disconnection
- ✅ Invalid state when DISCONNECTED
- ✅ Valid state when ERROR
- **Test**: Graceful disconnect from CONNECTED
  - Connect, then disconnect
  - Verify state: CONNECTED → CLOSING → DISCONNECTED
  - Verify ws_client cleaned up
- **Test**: Disconnect with pending messages
  - (Phase 2 feature, needs queue implementation)
- **Test**: Disconnect from multiple threads
  - Multiple threads call disconnect()
  - Verify only one succeeds
  - Verify proper cleanup

#### Connection State Transitions
- **Test**: Complete connection-disconnection cycle
  - Connect → verify connected → disconnect → verify disconnected
- **Test**: Multiple connection cycles
  - Connect, disconnect, connect again
  - Verify socket reusable
  - Verify no state corruption
- **Test**: Rapid connect/disconnect
  - Quickly call connect then disconnect
  - Verify race conditions handled

#### Error Handling
- **Test**: Connection error propagation
  - Various connection errors
  - Verify proper error type returned
- **Test**: Disconnect error handling
  - WebSocket close errors
  - Verify cleanup still happens
- **Test**: Resource cleanup on connection error
  - errdefer verification
  - No leaks on error

#### Timeout Detection
- **Test**: Handshake timeout
  - Slow server handshake
  - Verify timeout fires
  - Verify transition to ERROR
- **Test**: Custom timeout values
  - Short timeout (100ms)
  - Long timeout (30s)
  - Verify respected

**Total New Tests**: ~15 tests

**Note**: Many tests require actual WebSocket server or sophisticated mocking. May need test infrastructure from Section 1.6.

---

### 1.3.4 Message Sending Tests

**File**: `tests/connection/message_sending_tests.zig`

**Existing Coverage**: 5 tests in `src/connection/socket.zig`

**Additional Tests Needed**:

#### State Validation
- ✅ Error when DISCONNECTED
- ✅ Error when CONNECTING
- ✅ Error when CLOSING
- ✅ Error when ERROR
- ✅ Error when ws_client null despite CONNECTED

#### Message Validation
- **Test**: Send valid message
  - Create valid Phoenix message
  - Verify send succeeds (with mock/test server)
- **Test**: Send message without ref
  - Non-heartbeat message without ref
  - Verify validation error
- **Test**: Send heartbeat without "phoenix" topic
  - Verify validation error
- **Test**: Send phx_join without join_ref
  - Verify validation error
- **Test**: Send message with primitive payload
  - Verify validation error (must be object)

#### Serialization Integration
- **Test**: Message correctly serialized
  - Send message, capture serialized output
  - Verify JSON format correct
- **Test**: Complex payload serialization
  - Nested objects, arrays, special characters
  - Verify serialization preserves structure
- **Test**: Large message serialization
  - Very large payload
  - Verify buffer handling

#### WebSocket Transmission
- **Test**: Successful transmission
  - Send message, verify received by server
  - (Requires test server)
- **Test**: Transmission with timeout
  - Slow network, verify timeout handling
- **Test**: Transmission error handling
  - Network error during send
  - Verify error propagation

#### Thread Safety
- **Test**: Concurrent send from multiple threads
  - Multiple threads sending different messages
  - Verify all messages sent
  - Verify no data corruption
- **Test**: Send during state transition
  - One thread sending, another disconnecting
  - Verify proper error handling
  - Verify no crashes

#### Memory Management
- **Test**: No leaks on successful send
  - Send message, verify allocations freed
- **Test**: No leaks on failed send
  - Send fails, verify cleanup
- **Test**: Multiple send cycles
  - Send many messages
  - Verify stable memory usage

#### Buffer Management
- **Test**: Mutable buffer allocation
  - Verify buffer created for WebSocket masking
  - Verify original message unchanged
- **Test**: Buffer cleanup on error
  - Send fails after buffer allocation
  - Verify buffer freed

#### Timeout Behavior
- **Test**: Send timeout configuration
  - Set custom timeout
  - Verify used during send
- **Test**: Timeout reset after send
  - Verify timeout reset to 0 after operation
- **Test**: Multiple sends with different timeouts
  - Verify timeout properly updated each time

**Total New Tests**: ~20 tests

---

### 1.3.5 Message Receiving Tests

**File**: `tests/connection/message_receiving_tests.zig`

**Status**: ⚠️ Task 1.3.5 NOT YET IMPLEMENTED

**Planned Tests** (to be implemented with Task 1.3.5):

#### Receive Loop Basics
- **Test**: Receive loop thread spawned
  - Verify thread created on connect
  - Verify thread running
- **Test**: Receive loop terminated on disconnect
  - Disconnect, verify thread exits
  - Verify graceful shutdown
- **Test**: Receive loop handles null client
  - Edge case: client disappears
  - Verify thread exits safely

#### Message Deserialization
- **Test**: Valid message deserialized
  - Receive valid Phoenix message
  - Verify deserialization succeeds
  - Verify message structure correct
- **Test**: Invalid JSON rejected
  - Receive malformed JSON
  - Verify error handling
  - Verify loop continues
- **Test**: Non-array message rejected
  - Receive JSON object (not array)
  - Verify protocol error
- **Test**: Wrong array length rejected
  - Receive array with !=5 elements
  - Verify error handling

#### Message Routing
- **Test**: Heartbeat reply handled
  - Receive heartbeat reply
  - Verify routed to socket (not channel)
- **Test**: Channel message routed
  - Receive message for channel
  - Verify routed to correct channel
- **Test**: Message for unknown channel
  - Receive message for non-existent channel
  - Verify error handling
  - Verify no crash

#### Message Callbacks
- **Test**: Callback invoked for message
  - Register callback
  - Receive message
  - Verify callback called with correct data
- **Test**: Multiple callbacks
  - Register multiple callbacks
  - Verify all invoked
- **Test**: Callback exception handling
  - Callback throws error
  - Verify receive loop continues

#### Connection Error Handling
- **Test**: WebSocket read error
  - Simulate read error
  - Verify transition to ERROR state
  - Verify reconnection triggered (Phase 2)
- **Test**: Connection closed by server
  - Server closes connection
  - Verify detected
  - Verify state transition
- **Test**: Timeout on read
  - No messages for extended period
  - Verify timeout handling

#### Thread Safety
- **Test**: Receive while sending
  - Concurrent receive and send operations
  - Verify no mutex deadlock
  - Verify both succeed
- **Test**: Receive during disconnect
  - Receive loop running, disconnect called
  - Verify graceful shutdown
  - Verify no race conditions
- **Test**: Multiple receivers impossible
  - Only one receive loop per socket
  - Verify enforced

#### Resource Management
- **Test**: Message memory cleanup
  - Receive many messages
  - Verify messages freed after processing
- **Test**: Arena allocator for messages
  - Verify arena used for temp structures
  - Verify arena freed after each message
- **Test**: No leaks during receive loop
  - Long-running receive loop
  - Verify stable memory usage

#### Timeout and Backpressure
- **Test**: Receive timeout handling
  - Configure receive timeout
  - Verify timeout fires
  - Verify loop continues
- **Test**: Fast message rate
  - Receive messages rapidly
  - Verify all processed
  - Verify no buffer overflow
- **Test**: Slow message processing
  - Callback takes time
  - Verify backpressure handling

**Total Planned Tests**: ~30 tests

**Note**: These tests will be implemented as part of Task 1.3.5 implementation.

---

### 1.3.6 Reference Generation Tests

**File**: `tests/connection/ref_counter_tests.zig`

**Existing Coverage**: 4 tests (2 in types.zig, 2 in socket.zig)

**Additional Tests Needed**:

#### Basic Counter Operation
- ✅ Unique reference generation
- ✅ Reset functionality
- **Test**: Counter starts at 0
  - Verify initial value
- **Test**: Counter increments by 1
  - Verify each increment is exactly 1

#### String Conversion
- ✅ Numeric to string conversion
- **Test**: Large number string conversion
  - Counter near usize max
  - Verify string representation correct
- **Test**: String format consistency
  - Verify always decimal format
  - No leading zeros, no formatting

#### Overflow Handling
- **Test**: Counter overflow wraps
  - Set counter to usize max
  - Call next()
  - Verify wraps to 0 (or 1)
- **Test**: String conversion after overflow
  - Verify string conversion works after wrap
- **Test**: Multiple overflow cycles
  - Extremely unlikely but test wrapping behavior

#### Thread Safety
- **Test**: Concurrent reference generation
  - Multiple threads calling next()
  - Verify all references unique
  - Verify no duplicates
  - Verify count matches expected
- **Test**: Concurrent string generation
  - Multiple threads calling nextRefString()
  - Verify all strings unique
  - Verify no memory corruption
- **Test**: Stress test with many threads
  - 100+ threads generating refs
  - Verify correctness under load

#### Socket Integration
- **Test**: Multiple sockets independent counters
  - Create multiple sockets
  - Generate refs from each
  - Verify independence (can have same values)
- **Test**: Socket ref counter lifecycle
  - Socket creation, usage, destruction
  - Verify ref counter properly initialized and cleaned up

#### Memory Management
- **Test**: String reference memory leak detection
  - Generate many string refs
  - Free all
  - Verify no leaks
- **Test**: String ownership
  - Verify caller owns returned string
  - Verify socket doesn't hold references

#### Reset Behavior
- ✅ Reset works
- **Test**: Reset from multiple threads
  - Concurrent reset and next()
  - Verify safe behavior
- **Test**: Reset to specific value
  - (Future feature: reset to arbitrary value)

**Total New Tests**: ~13 tests

---

### Integration Tests (Section 1.3)

**File**: `tests/integration/socket_integration_tests.zig`

These tests verify multiple components working together.

#### Complete Socket Lifecycle
- **Test**: Connect-Send-Receive-Disconnect
  - Full lifecycle with all components
  - Verify each step succeeds
  - Verify proper cleanup
- **Test**: Multiple message roundtrip
  - Send multiple messages
  - Receive all replies
  - Verify ref matching

#### State Machine Integration
- **Test**: State consistency during operations
  - Monitor state during operations
  - Verify correct transitions
  - Verify no invalid states
- **Test**: Callbacks invoked at correct times
  - Register state callbacks
  - Perform operations
  - Verify callback ordering

#### Error Recovery Integration
- **Test**: Recovery from connection error
  - Connection fails
  - Reconnect succeeds
  - Verify state restored
- **Test**: Send error recovery
  - Send fails
  - Retry succeeds
  - Verify message not lost (Phase 2: queuing)

#### Concurrent Operations Integration
- **Test**: Concurrent send and receive
  - Multiple threads sending
  - Receive thread processing
  - Verify no deadlock, all messages processed
- **Test**: Concurrent state changes
  - State callbacks during operations
  - Verify consistency

#### Memory Stability Integration
- **Test**: Long-running socket stability
  - Keep socket alive for extended time
  - Perform periodic operations
  - Verify memory stable
  - Verify no leaks
- **Test**: Many operation cycles
  - Thousands of send/receive cycles
  - Verify performance stable
  - Verify no resource exhaustion

#### Real WebSocket Integration
- **Test**: Connect to real Phoenix server
  - (Requires test server from Section 1.6)
  - Full protocol compliance
  - Verify interoperability

**Total Integration Tests**: ~10 tests

---

## Test File Organization

### Directory Structure

```
tests/
├── connection/
│   ├── state_machine_tests.zig      # 1.3.1 tests (~30 tests)
│   ├── socket_tests.zig              # 1.3.2 tests (~25 tests)
│   ├── lifecycle_tests.zig           # 1.3.3 tests (~25 tests)
│   ├── message_sending_tests.zig     # 1.3.4 tests (~25 tests)
│   ├── message_receiving_tests.zig   # 1.3.5 tests (~30 tests)
│   └── ref_counter_tests.zig         # 1.3.6 tests (~15 tests)
├── integration/
│   └── socket_integration_tests.zig  # Integration tests (~10 tests)
├── test_utils.zig                    # Shared test utilities
└── unit_tests.zig                    # Test entry point
```

### File Template

Each test file follows this structure:

```zig
//! Tests for [Component Name] (Task [Task Number])
//!
//! This file contains comprehensive unit tests for [component description].
//!
//! Test Categories:
//! - [Category 1]
//! - [Category 2]
//! - [Category 3]

const std = @import("std");
const testing = std.testing;
const phoenix = @import("phoenix_channels");

// Import component under test
const [Component] = phoenix.connection.[Component];

// ============================================================================
// Test Utilities
// ============================================================================

// Helper functions for this test file

// ============================================================================
// [Category 1 Name]
// ============================================================================

test "[component]: [action] - [expected result]" {
    const allocator = testing.allocator;

    // Setup

    // Action

    // Assertions

    // Cleanup (via defer/errdefer)
}

// More tests...

// ============================================================================
// [Category 2 Name]
// ============================================================================

// More tests...
```

### Test Utilities

**File**: `tests/test_utils.zig`

Shared utilities for all tests:

```zig
//! Test utilities and helper functions

const std = @import("std");

/// Create a test allocator that detects leaks
pub fn testAllocator() std.mem.Allocator {
    return std.testing.allocator;
}

/// Mock WebSocket server for testing
pub const MockWebSocketServer = struct {
    // Mock implementation
};

/// Mock message for testing
pub fn createTestMessage(allocator: std.mem.Allocator) !PhoenixMessage {
    // Helper to create valid test message
}

/// Wait for condition with timeout
pub fn waitFor(condition: fn() bool, timeout_ms: u32) !void {
    // Utility for async testing
}

/// Spawn test threads
pub fn spawnTestThreads(count: usize, func: fn() void) ![]std.Thread {
    // Utility for concurrency testing
}
```

### Build Configuration

**Add to build.zig**:

```zig
// Individual test targets for each component
const state_tests = b.addTest(.{
    .name = "state-machine-tests",
    .root_source_file = .{ .path = "tests/connection/state_machine_tests.zig" },
    .target = target,
    .optimize = optimize,
});

const socket_tests = b.addTest(.{
    .name = "socket-tests",
    .root_source_file = .{ .path = "tests/connection/socket_tests.zig" },
    .target = target,
    .optimize = optimize,
});

// ... more test targets ...

// Aggregate test step
const test_connection_step = b.step("test-connection", "Run all connection tests");
test_connection_step.dependOn(&state_tests.step);
test_connection_step.dependOn(&socket_tests.step);
test_connection_step.dependOn(&lifecycle_tests.step);
// ... more dependencies ...

// Integration tests (separate, may be slower)
const integration_tests = b.addTest(.{
    .name = "integration-tests",
    .root_source_file = .{ .path = "tests/integration/socket_integration_tests.zig" },
    .target = target,
    .optimize = optimize,
});

const test_integration_step = b.step("test-integration", "Run integration tests");
test_integration_step.dependOn(&integration_tests.step);
```

**Usage**:
```bash
# Run all connection tests
zig build test-connection

# Run specific test file
zig build test --test-filter state_machine_tests

# Run integration tests
zig build test-integration

# Run all tests
zig build test
```

---

## Dependencies and Setup

### Required Components

1. **Implemented Components**:
   - ✅ ConnectionState enum (`src/connection/state.zig`)
   - ✅ PhoenixSocket struct (`src/connection/socket.zig`)
   - ✅ RefCounter (`src/common/types.zig`)
   - ✅ PhoenixMessage (`src/protocol/message.zig`)
   - ✅ Serializer (`src/protocol/serializer.zig`)
   - ✅ Connection lifecycle (connect/disconnect)
   - ✅ Message sending

2. **Pending Components**:
   - ⚠️ Message receiving (Task 1.3.5)
   - ⚠️ Test Phoenix server (Section 1.6)

3. **Test Dependencies**:
   - std.testing module
   - std.testing.allocator (leak detection)
   - std.Thread (for concurrency tests)
   - WebSocket test infrastructure (mock or real server)

### Test Environment Setup

#### Basic Test Execution

No special setup for basic unit tests:

```bash
zig build test
```

#### WebSocket Connection Tests

For tests requiring actual WebSocket connections:

1. **Option A: Mock WebSocket Client**
   - Create mock implementation in test_utils.zig
   - Simulate WebSocket behavior
   - No network required

2. **Option B: Local Test Server**
   - Run test Phoenix server (Section 1.6)
   - Tests connect to localhost:4000
   - More realistic but slower

3. **Option C: Skip Network Tests**
   - Tests requiring network marked with `@setTestName("[network]")`
   - Can be filtered out: `zig build test --test-filter "not network"`

#### Concurrency Test Setup

For reliable concurrency testing:

1. **Sufficient CPU Cores**: Tests spawn multiple threads
2. **Thread Sanitizer**: Optional, helps detect race conditions
3. **Multiple Runs**: Some race conditions only appear occasionally

### Test Data

**Test Messages**: Pre-defined valid/invalid messages in test_utils.zig

**Test URLs**: Standard test WebSocket URLs
- Valid: `ws://localhost:4000/socket/websocket`
- Invalid: `ws://invalid.example.com:9999/socket`
- Timeout: `ws://slow-server.example.com:4000/socket`

**Test Payloads**: Various payload structures
- Empty object: `{}`
- Simple object: `{"key": "value"}`
- Nested object: `{"user": {"id": 123, "name": "test"}}`
- Large payload: 1MB JSON object

---

## Success Criteria

### Quantitative Metrics

1. **Test Count**: Minimum 150 total tests for Section 1.3
   - State Machine: 30 tests
   - Socket Structure: 25 tests
   - Connection Lifecycle: 25 tests
   - Message Sending: 25 tests
   - Message Receiving: 30 tests (when implemented)
   - Reference Generation: 15 tests
   - Integration: 10 tests

2. **Code Coverage**: >90% line coverage for Section 1.3 components
   - ConnectionState: 100%
   - PhoenixSocket: >95%
   - RefCounter: 100%

3. **Test Execution Time**:
   - Unit tests: <5 seconds total
   - Integration tests: <30 seconds total

4. **No Test Failures**: All tests pass on main branch

### Qualitative Criteria

1. **Test Organization**:
   - Tests logically grouped by functionality
   - Clear, descriptive test names
   - Comprehensive documentation

2. **Test Coverage**:
   - Happy path tested
   - Error paths tested
   - Edge cases tested
   - Thread safety tested
   - Resource cleanup tested

3. **Test Reliability**:
   - No flaky tests
   - Deterministic results
   - Reproducible failures

4. **Test Maintainability**:
   - DRY: Common utilities extracted
   - Clear test structure
   - Easy to add new tests
   - Good documentation

### Functional Coverage

#### 1.3.1 State Machine
- ✅ All state transitions tested (valid and invalid)
- ✅ State callbacks tested
- ✅ Thread-safe state access tested
- ⬜ Concurrent state modifications tested
- ⬜ State inspection methods tested

#### 1.3.2 Socket Structure
- ✅ Initialization tested
- ✅ Configuration tested
- ✅ Reference generation tested
- ⬜ Multiple socket instances tested
- ⬜ Memory management tested
- ⬜ Thread safety tested

#### 1.3.3 Connection Lifecycle
- ✅ URL parsing tested (comprehensive)
- ✅ State validation tested
- ⬜ Successful connection tested
- ⬜ Connection errors tested
- ⬜ Connection timeout tested
- ⬜ Graceful disconnect tested
- ⬜ Disconnect errors tested
- ⬜ Multiple cycles tested

#### 1.3.4 Message Sending
- ✅ State validation tested
- ⬜ Message validation tested
- ⬜ Serialization integration tested
- ⬜ WebSocket transmission tested
- ⬜ Thread-safe sending tested
- ⬜ Memory management tested
- ⬜ Timeout behavior tested

#### 1.3.5 Message Receiving (Not Yet Implemented)
- ⬜ Receive loop tested
- ⬜ Deserialization tested
- ⬜ Message routing tested
- ⬜ Callbacks tested
- ⬜ Error handling tested
- ⬜ Thread safety tested

#### 1.3.6 Reference Generation
- ✅ Basic generation tested
- ✅ String conversion tested
- ⬜ Overflow handling tested
- ⬜ Thread safety tested
- ⬜ Multiple instances tested

### Documentation Requirements

1. **Test Documentation**:
   - Each test file has module-level documentation
   - Each test group has explanatory comments
   - Complex tests have inline comments

2. **Summary Documentation**:
   - This planning document
   - Test coverage report
   - Known issues and limitations

3. **Developer Documentation**:
   - How to run tests
   - How to add new tests
   - How to debug failing tests
   - Test architecture and philosophy

---

## Implementation Plan

### Phase 1: Setup and Organization

**Goal**: Establish test infrastructure and organization

**Tasks**:
1. Create test directory structure
2. Set up build.zig test targets
3. Implement test_utils.zig with common utilities
4. Create test file templates

**Duration**: 1-2 hours

**Output**:
- Test directory structure created
- Build system configured
- Test utilities implemented

### Phase 2: Migrate Existing Tests

**Goal**: Move tests from implementation files to dedicated test files

**Tasks**:
1. Extract state machine tests to state_machine_tests.zig
2. Extract socket tests to socket_tests.zig
3. Extract ref counter tests to ref_counter_tests.zig
4. Verify all existing tests still pass
5. Remove tests from implementation files (optional - can keep both)

**Duration**: 2-3 hours

**Output**:
- All existing tests in dedicated files
- All tests passing
- Test coverage maintained

### Phase 3: Expand Socket Structure Tests

**Goal**: Add comprehensive socket structure tests

**Tasks**:
1. Multiple socket instances tests
2. Configuration validation tests
3. Memory management tests
4. Thread safety tests
5. Integration tests

**Duration**: 3-4 hours

**Output**: ~15 new tests for socket structure

### Phase 4: Expand Connection Lifecycle Tests

**Goal**: Add comprehensive connection lifecycle tests

**Tasks**:
1. Implement mock WebSocket or test server integration
2. Connection success tests
3. Connection failure tests
4. Timeout tests
5. Disconnect tests
6. Multiple cycle tests

**Duration**: 4-6 hours

**Output**: ~15 new tests for connection lifecycle

**Note**: May be blocked on test server infrastructure (Section 1.6)

### Phase 5: Expand Message Sending Tests

**Goal**: Add comprehensive message sending tests

**Tasks**:
1. Message validation tests
2. Serialization integration tests
3. Thread safety tests
4. Memory management tests
5. Timeout tests
6. Buffer management tests

**Duration**: 3-4 hours

**Output**: ~20 new tests for message sending

### Phase 6: Expand Reference Generation Tests

**Goal**: Add comprehensive reference generation tests

**Tasks**:
1. Overflow handling tests
2. Thread safety stress tests
3. Multiple instance tests
4. Memory management tests

**Duration**: 2-3 hours

**Output**: ~13 new tests for reference generation

### Phase 7: Integration Tests

**Goal**: Add integration tests combining components

**Tasks**:
1. Complete lifecycle integration tests
2. Concurrent operation tests
3. Memory stability tests
4. Error recovery tests

**Duration**: 3-4 hours

**Output**: ~10 integration tests

### Phase 8: Message Receiving Tests (Future)

**Goal**: Add message receiving tests when Task 1.3.5 implemented

**Tasks**:
1. Implement receive loop tests
2. Deserialization tests
3. Message routing tests
4. Callback tests
5. Thread safety tests

**Duration**: 4-6 hours

**Output**: ~30 tests for message receiving

**Note**: Blocked on Task 1.3.5 implementation

### Phase 9: Documentation and Polish

**Goal**: Complete documentation and improve test quality

**Tasks**:
1. Write comprehensive test documentation
2. Add inline comments to complex tests
3. Review test coverage
4. Fix any flaky tests
5. Optimize slow tests
6. Generate coverage report

**Duration**: 2-3 hours

**Output**:
- Complete documentation
- High-quality test suite
- Coverage report

### Total Estimated Duration

**Phases 1-7** (Current scope): 20-28 hours
**Phase 8** (Future): 4-6 hours
**Phase 9** (Polish): 2-3 hours

**Total**: 26-37 hours for complete implementation

### Phased Delivery

**Minimum Viable Test Suite** (Phases 1-2): Basic organization with existing tests
**Enhanced Test Suite** (Phases 1-6): Comprehensive unit test coverage
**Complete Test Suite** (Phases 1-9): Full integration and documentation

---

## Appendix A: Test Naming Conventions

### Format

```
test "[component]: [action] - [expected result]"
```

### Examples

**Good Names**:
- `test "socket: initialization - creates socket with default state"`
- `test "send: message without ref - returns ValidationError"`
- `test "state: DISCONNECTED to CLOSING transition - returns InvalidStateTransition"`
- `test "refcounter: concurrent access from 100 threads - generates unique references"`

**Bad Names**:
- `test "test1"` - Not descriptive
- `test "socket works"` - Too vague
- `test "creates socket"` - Missing context
- `test "error"` - What kind of error?

### Component Prefixes

- `state:` - ConnectionState tests
- `socket:` - PhoenixSocket tests
- `connect:` - Connection establishment tests
- `disconnect:` - Disconnection tests
- `send:` - Message sending tests
- `receive:` - Message receiving tests
- `refcounter:` - Reference counter tests

---

## Appendix B: Test Utilities Reference

### Helper Functions

```zig
// Memory management
pub fn testAllocator() std.mem.Allocator
pub fn expectNoLeak(allocator: std.mem.Allocator) !void

// Message creation
pub fn createTestMessage(allocator: std.mem.Allocator,
                         topic: []const u8,
                         event: []const u8) !PhoenixMessage
pub fn createJoinMessage(allocator: std.mem.Allocator,
                         topic: []const u8) !PhoenixMessage
pub fn createHeartbeat(allocator: std.mem.Allocator) !PhoenixMessage

// WebSocket mocking
pub const MockWebSocketClient = struct {
    pub fn init(allocator: std.mem.Allocator) !*MockWebSocketClient
    pub fn simulateMessage(self: *MockWebSocketClient, msg: []const u8) !void
    pub fn simulateDisconnect(self: *MockWebSocketClient) void
};

// Thread utilities
pub fn spawnThreads(count: usize, func: anytype, args: anytype) ![]std.Thread
pub fn joinThreads(threads: []std.Thread) void

// Timing utilities
pub fn sleep(ms: u64) void
pub fn waitFor(condition: fn() bool, timeout_ms: u64) !void

// Assertion helpers
pub fn expectState(socket: *PhoenixSocket, expected: ConnectionState) !void
pub fn expectConnected(socket: *PhoenixSocket) !void
pub fn expectDisconnected(socket: *PhoenixSocket) !void
```

### Mock Implementations

```zig
// Mock WebSocket for testing without network
pub const MockWebSocket = struct {
    messages: std.ArrayList([]const u8),
    connected: bool,

    pub fn init(allocator: std.mem.Allocator) MockWebSocket
    pub fn connect(self: *MockWebSocket) !void
    pub fn disconnect(self: *MockWebSocket) void
    pub fn send(self: *MockWebSocket, msg: []const u8) !void
    pub fn receive(self: *MockWebSocket) ![]const u8
};
```

---

## Appendix C: Common Test Patterns

### Pattern 1: Basic Unit Test

```zig
test "component: action - expected result" {
    const allocator = testing.allocator;

    // Setup
    const socket = try PhoenixSocket.init(allocator, config);
    defer socket.deinit();

    // Action
    const result = socket.getState();

    // Assertion
    try testing.expectEqual(ConnectionState.DISCONNECTED, result);
}
```

### Pattern 2: Error Testing

```zig
test "component: invalid action - returns error" {
    const allocator = testing.allocator;

    const socket = try PhoenixSocket.init(allocator, config);
    defer socket.deinit();

    // Action that should fail
    const result = socket.send(&test_msg);

    // Expect error
    try testing.expectError(error.NotConnected, result);
}
```

### Pattern 3: Resource Management Test

```zig
test "component: action - no memory leaks" {
    const allocator = testing.allocator;

    // Action
    const socket = try PhoenixSocket.init(allocator, config);
    defer socket.deinit();

    // ... perform operations ...

    // Cleanup happens via defer
    // testing.allocator will detect leaks
}
```

### Pattern 4: Concurrency Test

```zig
test "component: concurrent action - thread safe" {
    const allocator = testing.allocator;

    const socket = try PhoenixSocket.init(allocator, config);
    defer socket.deinit();

    // Spawn threads
    const threads = try spawnThreads(10, workerFunc, .{socket});
    defer joinThreads(threads);

    // Verify results
    try testing.expectEqual(expected_count, socket.operation_count);
}

fn workerFunc(socket: *PhoenixSocket) void {
    // Thread work
}
```

### Pattern 5: Integration Test

```zig
test "integration: complete workflow - all steps succeed" {
    const allocator = testing.allocator;

    // Setup
    const socket = try PhoenixSocket.init(allocator, config);
    defer socket.deinit();

    // Step 1: Connect
    try socket.connect();
    try testing.expectEqual(ConnectionState.CONNECTED, socket.getState());

    // Step 2: Send message
    try socket.send(&test_msg);

    // Step 3: Receive reply
    // (requires Task 1.3.5)

    // Step 4: Disconnect
    try socket.disconnect();
    try testing.expectEqual(ConnectionState.DISCONNECTED, socket.getState());
}
```

---

## Appendix D: Coverage Goals by Subtask

| Subtask | Component | Current Tests | Target Tests | Current Coverage | Target Coverage |
|---------|-----------|--------------|--------------|------------------|----------------|
| 1.3.1 | State Machine | 21 | 30 | ~85% | 100% |
| 1.3.2 | Socket Structure | 11 | 25 | ~70% | >95% |
| 1.3.3 | Connection Lifecycle | 10 | 25 | ~60% | >90% |
| 1.3.4 | Message Sending | 5 | 25 | ~40% | >90% |
| 1.3.5 | Message Receiving | 0 | 30 | 0% | >90% |
| 1.3.6 | Reference Generation | 4 | 15 | ~70% | 100% |
| Integration | All components | 0 | 10 | N/A | N/A |
| **Total** | **Section 1.3** | **51** | **160** | **~60%** | **>90%** |

---

## Conclusion

This feature planning document provides a comprehensive roadmap for implementing unit tests for Section 1.3 (Socket Component). The plan organizes tests logically, identifies coverage gaps, and provides a clear implementation strategy.

**Key Takeaways**:

1. **Current State**: 51 tests scattered across implementation files
2. **Target State**: 160+ organized tests in dedicated test files
3. **Coverage Gap**: Need ~109 additional tests
4. **Organization**: 7 dedicated test files with clear responsibilities
5. **Timeline**: 26-37 hours for complete implementation
6. **Blockers**: Task 1.3.5 (Message Receiving) not yet implemented

**Next Steps**:

1. Review and approve this planning document
2. Begin Phase 1: Setup and Organization
3. Proceed through implementation phases
4. Track progress and adjust as needed

**Success Metrics**:

- ✅ >90% code coverage
- ✅ 160+ comprehensive tests
- ✅ All tests passing
- ✅ No memory leaks
- ✅ Complete documentation
