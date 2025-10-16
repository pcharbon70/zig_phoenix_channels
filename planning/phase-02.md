# Phase 2: Reliability Features

## Overview

This phase transforms the basic Phoenix client from Phase 1 into a production-ready library that handles real-world network conditions reliably. Real networks are unreliable: connections drop, servers restart, network conditions vary. A production client must handle these scenarios automatically without losing messages or requiring manual intervention from the application.

Phase 2 implements three critical reliability features: message queuing (PushBuffer), automatic reconnection with exponential backoff, and heartbeat mechanism with connection health monitoring. Together, these features ensure the client maintains connectivity, detects failures quickly, recovers automatically, and preserves message ordering across disconnections.

This phase builds directly on Phase 1's state machines. The state transitions defined in Phase 1 now trigger recovery actions: ERROR state triggers reconnection, DISCONNECTED state triggers message queuing, missing heartbeats trigger connection health checks. By the end of this phase, the client operates reliably in production environments without constant application babysitting.

This phase represents approximately 2 weeks of work and is essential for any real-world usage of the library.

---

## 2.1 Message Queuing (PushBuffer)

This section implements the PushBuffer component for queuing messages when they cannot be sent immediately. Phoenix clients need two-level queuing: socket-level when disconnected and channel-level when channel not joined. Queuing preserves message ordering and ensures no messages are lost during temporary connectivity issues.

The PushBuffer is a FIFO queue with configurable size limits and overflow handling. When the socket reconnects or channel joins, buffered messages are flushed automatically. The implementation must be thread-safe as multiple threads may queue messages simultaneously. Proper queuing is essential for reliability - without it, messages sent during disconnections are simply lost.

### 2.1.1 PushBuffer Structure

The PushBuffer needs to store messages efficiently while supporting concurrent access. We use a ring buffer or ArrayList-based queue with mutex protection. The structure should support efficient push/pop operations and provide size limit enforcement with configurable overflow behavior.

- 2.1.1.1 Define PushBuffer struct with message queue
- 2.1.1.2 Add capacity limit and current size tracking
- 2.1.1.3 Include mutex for thread-safe access
- 2.1.1.4 Define overflow strategies (drop oldest, drop newest, error)
- 2.1.1.5 Add statistics tracking (dropped messages, max size reached)

### 2.1.2 Queue Operations

Basic queue operations (push, pop, flush) form the PushBuffer API. Push adds messages when send fails, pop retrieves them in FIFO order, flush sends all buffered messages when conditions allow. All operations must be atomic and thread-safe.

- 2.1.2.1 Implement push() for adding messages to buffer
- 2.1.2.2 Implement pop() for retrieving buffered messages
- 2.1.2.3 Implement flush() for sending all buffered messages
- 2.1.2.4 Implement clear() for discarding buffer contents
- 2.1.2.5 Add isEmpty() and isFull() query methods

### 2.1.3 Socket-Level Buffer Integration

Socket-level buffering queues messages when the connection is not CONNECTED. On state transition to CONNECTED, flush the buffer automatically. This ensures messages sent during reconnection are not lost.

- 2.1.3.1 Add PushBuffer field to Socket struct
- 2.1.3.2 Modify Socket.send() to buffer when not CONNECTED
- 2.1.3.3 Implement automatic flush on transition to CONNECTED
- 2.1.3.4 Handle buffer overflow and error reporting
- 2.1.3.5 Add configuration options for buffer size

### 2.1.4 Channel-Level Buffer Integration

Channel-level buffering queues messages when channel state is not JOINED. On transition to JOINED, flush the buffer. This preserves messages pushed before join completes or during rejoin sequences.

- 2.1.4.1 Add PushBuffer field to Channel struct
- 2.1.4.2 Modify Channel.push() to buffer when not JOINED
- 2.1.4.3 Implement automatic flush on transition to JOINED
- 2.1.4.4 Handle buffer overflow and error reporting
- 2.1.4.5 Add configuration options for channel buffer size

### 2.1.5 Buffer Persistence Strategy

During reconnection, decide which messages to preserve and which to discard. Some messages may become stale (e.g., real-time status updates), while others are critical (e.g., chat messages). Implement configurable message TTL and discard strategies.

- 2.1.5.1 Add message timestamp field for age tracking
- 2.1.5.2 Implement TTL-based message expiration
- 2.1.5.3 Add priority levels for messages (high, normal, low)
- 2.1.5.4 Implement priority-based flush ordering
- 2.1.5.5 Add callback for application-specific discard decisions

### Unit Tests - Section 2.1

- Test PushBuffer push/pop operations
- Test FIFO ordering preservation
- Test buffer size limits and overflow handling
- Test thread-safe concurrent access to buffer
- Test socket-level buffering during disconnection
- Test socket buffer flush on reconnection
- Test channel-level buffering during join
- Test channel buffer flush on successful join
- Test message expiration based on TTL
- Test priority-based message ordering

---

## 2.2 Reconnection Logic

This section implements automatic reconnection with exponential backoff. When the connection enters ERROR state, the client should automatically attempt to reconnect after a delay. The delay increases exponentially with each failed attempt (1s, 5s, 10s, 10s, ...) to avoid overwhelming the server. Jitter is added to prevent thundering herd when many clients reconnect simultaneously.

Reconnection must preserve all client state: channel subscriptions, event handlers, buffered messages. After reconnecting, automatically rejoin all channels that were previously joined. The application should not need to manually recreate state. This seamless recovery is what makes the library production-ready.

### 2.2.1 Backoff Strategy Implementation

The backoff calculator determines delays between reconnection attempts. Phoenix.js uses a simple strategy: [1000ms, 5000ms, 10000ms, 10000ms, ...]. We implement this with configurable multipliers, max delay, and jitter. The implementation should be deterministic for testing but random in production.

- 2.2.1.1 Define ReconnectionBackoff struct with configuration
- 2.2.1.2 Implement delay calculation based on attempt count
- 2.2.1.3 Add configurable max delay ceiling
- 2.2.1.4 Implement jitter addition for thundering herd prevention
- 2.2.1.5 Add reset() method to clear backoff on successful connection

### 2.2.2 Reconnection State Management

Reconnection involves tracking attempts, scheduling retry timers, and managing concurrent reconnection requests. The state must prevent multiple simultaneous reconnection attempts while allowing explicit reconnection requests from the application.

- 2.2.2.1 Add reconnection attempt counter to Socket
- 2.2.2.2 Add reconnection timer/scheduled task tracking
- 2.2.2.3 Implement prevention of duplicate reconnection attempts
- 2.2.2.4 Add configuration for max reconnection attempts (0 = infinite)
- 2.2.2.5 Implement manual reconnection triggering

### 2.2.3 Automatic Reconnection Trigger

When the socket enters ERROR state, automatically schedule reconnection. The trigger detects connection loss (receive loop exit, send failure, heartbeat timeout) and initiates the recovery sequence. Clean separation between detection and recovery makes the code testable.

- 2.2.3.1 Detect connection errors and transition to ERROR state
- 2.2.3.2 Schedule reconnection timer based on backoff calculation
- 2.2.3.3 Implement reconnection attempt execution
- 2.2.3.4 Handle reconnection success (reset backoff, transition to CONNECTED)
- 2.2.3.5 Handle reconnection failure (increment attempts, reschedule)

### 2.2.4 Channel Rejoin Logic

After successful reconnection, all previously joined channels must rejoin automatically. The application should not notice the reconnection except for brief message delivery delays. Track channel state before disconnect and restore it after reconnect.

- 2.2.4.1 Track which channels were JOINED before disconnection
- 2.2.4.2 Automatically trigger rejoin for all tracked channels
- 2.2.4.3 Preserve channel parameters for rejoin
- 2.2.4.4 Handle rejoin failures (retry with backoff per channel)
- 2.2.4.5 Notify application of rejoin completion

### 2.2.5 Reconnection Configuration

Different applications need different reconnection policies. Some need aggressive reconnection for real-time requirements, others prefer conservative backoff to reduce server load. Provide configuration options while maintaining sensible defaults.

- 2.2.5.1 Define reconnection configuration struct
- 2.2.5.2 Add configurable initial delay and max delay
- 2.2.5.3 Add configurable multiplier and jitter factor
- 2.2.5.4 Add max attempts configuration (0 = infinite)
- 2.2.5.5 Add callbacks for reconnection events (attempt, success, failure)

### Unit Tests - Section 2.2

- Test backoff calculation for multiple attempts
- Test jitter addition and variance
- Test backoff reset on successful connection
- Test automatic reconnection trigger on ERROR state
- Test reconnection attempt scheduling and execution
- Test channel rejoin after successful reconnection
- Test max attempts limit enforcement
- Test concurrent reconnection prevention
- Test manual reconnection triggering

---

## 2.3 Heartbeat Mechanism

This section implements the heartbeat mechanism for keeping connections alive and detecting connection failures. The client sends heartbeat messages every 30 seconds (configurable) to the "phoenix" topic. The server responds with phx_reply. If no response arrives within a timeout (e.g., 60s), assume the connection is dead and trigger reconnection.

The heartbeat must run independently of application activity. A separate thread sends heartbeats periodically regardless of whether application messages are flowing. A watchdog timer monitors all incoming messages (not just heartbeat replies) and triggers reconnection if no messages arrive within the timeout window. This detects network failures quickly even if the socket API doesn't report an error.

### 2.3.1 Heartbeat Structure

The heartbeat system needs configuration (interval, timeout), state tracking (pending heartbeat, last received message time), and synchronization primitives. The implementation must coordinate between the heartbeat thread and receive loop without deadlocks.

- 2.3.1.1 Define heartbeat configuration (interval, timeout)
- 2.3.1.2 Add heartbeat state to Socket (last send time, last receive time)
- 2.3.1.3 Add pending heartbeat tracking (ref, sent time)
- 2.3.1.4 Include synchronization for thread-safe state access
- 2.3.1.5 Add configuration for heartbeat enable/disable

### 2.3.2 Heartbeat Thread

The heartbeat thread runs continuously while connected, sleeping for the interval duration then sending a heartbeat. The thread must handle connection state changes gracefully: stop when disconnected, restart when reconnected, handle clean shutdown.

- 2.3.2.1 Implement heartbeat thread function
- 2.3.2.2 Add interval-based sleep between heartbeats
- 2.3.2.3 Send heartbeat message to "phoenix" topic
- 2.3.2.4 Handle connection state changes (pause when disconnected)
- 2.3.2.5 Implement graceful thread shutdown

### 2.3.3 Heartbeat Message Handling

Heartbeat messages are special: they use the "phoenix" topic (not a joinable channel) and expect phx_reply responses. The Socket must route heartbeat replies specially rather than to a Channel. Track pending heartbeats by ref to match replies.

- 2.3.3.1 Construct heartbeat message with proper format
- 2.3.3.2 Send to "phoenix" topic without channel join
- 2.3.3.3 Handle heartbeat reply messages specially in receive loop
- 2.3.3.4 Track pending heartbeats by reference
- 2.3.3.5 Update last-received time on any message (not just heartbeat reply)

### 2.3.4 Watchdog Timer

The watchdog detects connection failures by monitoring message receipt. If no messages arrive within the timeout period, assume the connection is dead and trigger reconnection. The watchdog resets on ANY message receipt, not just heartbeat replies, because any message proves the connection is alive.

- 2.3.4.1 Implement watchdog timer in separate thread
- 2.3.4.2 Check last-received time against timeout threshold
- 2.3.4.3 Reset watchdog on any message receipt
- 2.3.4.4 Trigger reconnection when timeout exceeded
- 2.3.4.5 Handle watchdog lifecycle (start/stop with connection)

### 2.3.5 Heartbeat Configuration

Different network conditions and application requirements need different heartbeat settings. Real-time applications may want aggressive heartbeats (every 10s) while background sync clients can use longer intervals (every 60s). Provide configuration while maintaining protocol-compliant defaults (30s).

- 2.3.5.1 Define heartbeat configuration options
- 2.3.5.2 Add configurable interval (default 30000ms)
- 2.3.5.3 Add configurable timeout (default 60000ms)
- 2.3.5.4 Add enable/disable flag for testing
- 2.3.5.5 Validate configuration (timeout > interval)

### Unit Tests - Section 2.3

- Test heartbeat message construction and format
- Test heartbeat sending at configured interval
- Test heartbeat reply handling
- Test watchdog timeout detection
- Test watchdog reset on message receipt
- Test reconnection trigger on heartbeat timeout
- Test heartbeat thread lifecycle (start/stop/restart)
- Test heartbeat configuration validation
- Test heartbeat with various network conditions (simulated)

---

## 2.4 Timeout Management

This section implements comprehensive timeout handling for various operations. Timeouts prevent indefinite waiting and enable proper error handling. We need timeouts for: connection establishment, channel join, push replies, and channel leave operations. Each timeout must trigger appropriate error handling and state transitions.

Timeout management requires timer infrastructure that can schedule, cancel, and execute timeout callbacks. The implementation should be efficient (don't create threads per timeout) and accurate (fire callbacks at appropriate times). Timeouts enable the client to fail fast rather than hang indefinitely.

### 2.4.1 Timer Infrastructure

A timer system manages multiple concurrent timeouts efficiently. We need to schedule timeouts, cancel them when operations complete, and execute callbacks when timeouts fire. The implementation could use a timer thread with a priority queue of scheduled timeouts.

- 2.4.1.1 Implement timer system for scheduling timeouts
- 2.4.1.2 Add timeout registration with callback support
- 2.4.1.3 Implement timeout cancellation when operations complete
- 2.4.1.4 Add efficient timer execution (don't create thread per timeout)
- 2.4.1.5 Handle timer lifecycle and cleanup

### 2.4.2 Connection Timeout

Connection establishment should not hang indefinitely. If the WebSocket handshake doesn't complete within a timeout (default 10s), abort the connection attempt and return an error or trigger reconnection logic.

- 2.4.2.1 Add connection timeout to Socket.connect()
- 2.4.2.2 Implement timeout detection during WebSocket handshake
- 2.4.2.3 Clean up resources on connection timeout
- 2.4.2.4 Transition to ERROR state on timeout
- 2.4.2.5 Make connection timeout configurable

### 2.4.3 Join Timeout

Channel join operations should timeout if no phx_reply arrives within a threshold (default 10s). On timeout, transition channel to ERROR state, invoke error callback, and optionally schedule rejoin (with backoff).

- 2.4.3.1 Start timeout timer when sending phx_join
- 2.4.3.2 Cancel timeout on phx_reply receipt
- 2.4.3.3 Transition to ERROR state on join timeout
- 2.4.3.4 Invoke join error callback with timeout reason
- 2.4.3.5 Make join timeout configurable per channel

### 2.4.4 Push Reply Timeout

Push operations may expect replies (ok, error callbacks). If no phx_reply arrives within the timeout, invoke the timeout callback. This allows applications to handle slow responses gracefully rather than waiting indefinitely.

- 2.4.4.1 Add optional timeout to push() operations
- 2.4.4.2 Track pending pushes by reference
- 2.4.4.3 Implement timeout callback invocation
- 2.4.4.4 Clean up pending push tracking on timeout
- 2.4.4.5 Make push timeout configurable per operation

### 2.4.5 Leave Timeout

Channel leave operations should timeout if no confirmation arrives. On timeout, forcefully transition to CLOSED state and clean up channel resources. Leave timeouts are less critical than join timeouts but still important for resource cleanup.

- 2.4.5.1 Start timeout timer when sending phx_leave
- 2.4.5.2 Cancel timeout on phx_reply receipt
- 2.4.5.3 Force transition to CLOSED on leave timeout
- 2.4.5.4 Clean up channel resources on timeout
- 2.4.5.5 Make leave timeout configurable per channel

### Unit Tests - Section 2.4

- Test timer system scheduling and execution
- Test timeout cancellation when operations complete
- Test connection timeout triggers error handling
- Test join timeout transitions channel to ERROR
- Test push timeout invokes timeout callback
- Test leave timeout forces channel closure
- Test timeout configuration and defaults
- Test concurrent timeouts don't interfere
- Test timer cleanup prevents resource leaks

---

## 2.5 Integration Tests

This section provides comprehensive integration testing of reliability features against a real Phoenix server. These tests validate that reconnection, buffering, and heartbeat work correctly in realistic scenarios. We test failure conditions that are difficult to simulate in unit tests: network disconnections, server restarts, slow responses.

Integration tests for reliability require careful setup: ability to disconnect/reconnect network, simulate server failures, inject delays. We extend the Phoenix test server from Phase 1 with additional failure injection capabilities. These tests prove the library handles production conditions reliably.

### 2.5.1 Test Infrastructure Enhancement

Enhance the test server to support reliability testing scenarios. Add endpoints to simulate failures, inject delays, and control server behavior. This allows reproducible testing of failure conditions.

- 2.5.1.1 Add test server endpoints for failure injection
- 2.5.1.2 Implement network disconnect simulation
- 2.5.1.3 Add configurable response delays
- 2.5.1.4 Implement server restart simulation
- 2.5.1.5 Add heartbeat ignore mode for timeout testing

### 2.5.2 Reconnection Scenario Testing

Test the complete reconnection flow: connection loss detection, backoff delays, automatic reconnection, channel rejoin. Validate that messages queued during disconnection are delivered after reconnection and that state is fully restored.

- 2.5.2.1 Test automatic reconnection after network failure
- 2.5.2.2 Test exponential backoff timing accuracy
- 2.5.2.3 Test automatic channel rejoin after reconnection
- 2.5.2.4 Test message buffer flush after reconnection
- 2.5.2.5 Test max reconnection attempts limit
- 2.5.2.6 Test manual reconnection triggering

### 2.5.3 Message Queuing Validation

Test that messages sent during disconnection or before channel join are queued correctly and delivered when conditions allow. Validate FIFO ordering, buffer limits, and overflow handling work as specified.

- 2.5.3.1 Test socket-level buffering during disconnection
- 2.5.3.2 Test channel-level buffering before join completes
- 2.5.3.3 Test buffer overflow handling strategies
- 2.5.3.4 Test message ordering preservation after reconnection
- 2.5.3.5 Test TTL-based message expiration
- 2.5.3.6 Test buffer flush on successful reconnection/rejoin

### 2.5.4 Heartbeat and Connection Health

Test heartbeat mechanism and connection health monitoring. Validate that heartbeats keep connections alive, timeouts detect dead connections, and watchdog triggers reconnection appropriately.

- 2.5.4.1 Test heartbeat exchange with server
- 2.5.4.2 Test connection timeout detection when server stops responding
- 2.5.4.3 Test watchdog timer reset on message receipt
- 2.5.4.4 Test reconnection trigger on heartbeat timeout
- 2.5.4.5 Test heartbeat configuration (interval, timeout)
- 2.5.4.6 Test heartbeat thread lifecycle across disconnections

### 2.5.5 Timeout Scenario Testing

Test all timeout scenarios: connection timeout, join timeout, push timeout, leave timeout. Validate that timeouts fire at appropriate times, invoke correct callbacks, and trigger appropriate state transitions.

- 2.5.5.1 Test connection timeout with unresponsive server
- 2.5.5.2 Test join timeout when server doesn't respond
- 2.5.5.3 Test push timeout for unacknowledged messages
- 2.5.5.4 Test leave timeout when server doesn't confirm
- 2.5.5.5 Test timeout cancellation when operations complete
- 2.5.5.6 Test timeout configuration and customization

### 2.5.6 Stress Testing

Test reliability under stress conditions: rapid connection/disconnection cycles, many concurrent channels, high message volume, continuous failures. Stress testing reveals race conditions and resource leaks that normal testing misses.

- 2.5.6.1 Test rapid connect/disconnect cycles
- 2.5.6.2 Test many channels with concurrent failures
- 2.5.6.3 Test high message volume during reconnections
- 2.5.6.4 Test continuous failure conditions (server unavailable)
- 2.5.6.5 Test memory stability under prolonged stress
- 2.5.6.6 Test no resource leaks during stress conditions

---

## Success Criteria

This phase is complete when:

1. **Message Queuing**: PushBuffer implemented and integrated at socket and channel levels
2. **Reconnection**: Automatic reconnection with exponential backoff working reliably
3. **Heartbeat**: Heartbeat mechanism keeping connections alive and detecting failures
4. **Timeouts**: All operations have appropriate timeouts with error handling
5. **State Preservation**: Reconnection preserves all channel subscriptions and state
6. **Integration Tests**: All reliability scenarios tested against real Phoenix server
7. **Memory Stability**: No memory leaks under prolonged operation with failures
8. **Configuration**: All reliability features are configurable with sensible defaults

## Provides Foundation For

This phase establishes reliability that enables:
- **Phase 3**: Multiplexing and error handling assume reliable connectivity
- **Phase 4**: Advanced features require reliable message delivery
- **Phase 5**: Production deployment relies on automatic recovery
- **Real-world Usage**: Applications can trust the client to handle network issues

## Key Outputs

1. **Implemented Components**:
   - PushBuffer for two-level message queuing
   - Automatic reconnection with exponential backoff
   - Heartbeat mechanism with watchdog
   - Comprehensive timeout management

2. **Reliability Infrastructure**:
   - Timer system for scheduling timeouts
   - Backoff calculator for reconnection delays
   - Channel rejoin logic for state preservation

3. **Testing Infrastructure**:
   - Enhanced test server with failure injection
   - Integration tests for all failure scenarios
   - Stress tests for reliability validation

4. **Configuration System**:
   - Reconnection policy configuration
   - Heartbeat configuration
   - Timeout configuration
   - Buffer size and overflow configuration

## Next Phase Preview

Phase 3 builds on this reliable foundation by adding:
- Full channel registry and message routing
- Support for unlimited simultaneous channels
- Comprehensive error handling and recovery
- Logging infrastructure for observability
- Configuration system for customization
- Developer documentation and examples

With reliability established, Phase 3 focuses on making the library production-ready through polish, observability, and comprehensive error handling.
