# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Zig implementation of a Phoenix Channels client library. Phoenix Channels is a real-time communication protocol built on WebSockets, used by the Phoenix web framework (Elixir/Erlang).

## Build and Development Commands

Since this is a new project without build configuration yet, standard Zig commands will apply once implemented:

```bash
# Build the project
zig build

# Run tests
zig build test

# Run in debug mode
zig build run

# Clean build artifacts
rm -rf zig-cache zig-out
```

## Architecture Overview

### Core Components

The library architecture follows these main components:

1. **Socket Component**: Manages WebSocket connection lifecycle, heartbeat mechanism, channel registry, and message routing. Implements connection state machine (DISCONNECTED → CONNECTING → CONNECTED → CLOSING/ERROR).

2. **Channel Component**: Represents logical channels on topics. Manages channel state machine (CLOSED → JOINING → JOINED → LEAVING/ERROR), buffers messages when not joined, and handles event callbacks.

3. **Message Component**: Encapsulates Phoenix's 5-field message structure: `[join_ref, message_ref, topic, event, payload]`. All messages must follow this JSON array format.

4. **PushBuffer Component**: Queues outbound messages when connection/channel unavailable. Uses FIFO ordering with configurable size limits.

5. **Timer Component**: Manages heartbeat intervals (default 30s), reconnection backoff, and operation timeouts.

### Phoenix Protocol Specifics

**Message Format** (V2 JSON Serializer):
- Messages are 5-element JSON arrays: `[join_reference, message_reference, topic_name, event_name, payload]`
- `join_reference`: Required for `phx_join` events, null otherwise
- `message_reference`: Unique client-generated ID for matching replies
- `topic_name`: Channel identifier (e.g., "room:lobby")
- `event_name`: Event type (system events: phx_join, phx_leave, phx_reply, phx_error, phx_close, heartbeat)
- `payload`: Must be JSON object (not primitive)

**Key Protocol Behaviors**:
- Heartbeat topic is "phoenix" (no need to join)
- `phx_error` triggers automatic rejoin with exponential backoff
- `phx_close` does NOT trigger automatic rejoin (graceful closure)
- Single WebSocket connection multiplexes multiple channels
- One subscription per unique topic (duplicates close existing channel)

### Reconnection Strategy

Default exponential backoff (Phoenix.js compatible):
- 1st attempt: 1000ms (1 second)
- 2nd attempt: 5000ms (5 seconds)
- 3rd+ attempts: 10000ms (10 seconds)
- Add jitter to prevent thundering herd
- Reset backoff counter on successful connection

### State Machines

**Connection States**: DISCONNECTED, CONNECTING, CONNECTED, CLOSING, ERROR

**Channel States**: CLOSED, JOINING, JOINED, LEAVING, ERROR

Both state machines must be explicitly managed with proper transition handling.

## Zig-Specific Implementation Guidelines

### Concurrency Model

Zig 0.11.0+ removed async/await (being redesigned). Use **thread-based concurrency** with `std.Thread`:
- Main thread for application logic
- Separate thread for heartbeat loop
- Message handler thread spawned by WebSocket client
- Use `std.Thread.Mutex` for shared state protection

### Memory Management Strategy

**Three-tier allocation pattern**:

1. **GeneralPurposeAllocator (GPA)** as base allocator for long-lived structures (Socket, Channel instances)

2. **ArenaAllocator** for message processing cycles:
   ```zig
   var arena = std.heap.ArenaAllocator.init(base_allocator);
   defer arena.deinit(); // Frees all at once
   ```

3. **FixedBufferAllocator** for heartbeats and predictable small messages

**Critical patterns**:
- Always use `defer` for cleanup
- Use `errdefer` for cleanup on error paths
- Always call `.deinit()` on parsed JSON
- Pre-allocate buffers for common message sizes

### WebSocket Library

Use **karlseguin/websocket.zig**:
- Most mature and battle-tested
- Follows Zig master
- Thread-based concurrency model (fits Phoenix well)
- Autobahn test suite compliant

### Error Handling

Define comprehensive error sets covering connection, protocol, and resource errors. Use:
- `try` to propagate errors
- `catch` with `switch` for specific error handling
- `errdefer` for resource cleanup on error paths

Example:
```zig
const conn = try allocator.create(Connection);
errdefer allocator.destroy(conn); // Only runs on error
try conn.init();
errdefer conn.deinit();
```

### JSON Handling

Use `std.json.parseFromSlice` and `std.json.stringify`:
- Parse into structs with proper field types
- Always deinit parsed results
- Use arena allocator for temporary JSON structures
- Handle nullable fields with `?[]const u8`

### Thread Safety

Protect all shared state with `std.Thread.Mutex`:
```zig
self.mutex.lock();
defer self.mutex.unlock();
// Critical section
```

## Key Implementation Requirements

### Message Queuing
- Two-level queuing: socket-level when disconnected, channel-level when not joined
- FIFO ordering preserved
- Configurable size limits (default: socket 1000, channel 100)
- Flush on connection/join state transitions

### Heartbeat Mechanism
- Separate timer thread, not main event loop
- Send every 30 seconds to "phoenix" topic
- Watchdog timer resets on ANY message (not just heartbeat replies)
- Missing heartbeat triggers reconnection

### Error Recovery
- Automatic reconnection on connection errors with exponential backoff
- Automatic channel rejoin on `phx_error` (but NOT on `phx_close`)
- Rejoin all channels after reconnection
- Preserve message buffers across reconnections

## Testing Approach

### Unit Tests
- Message serialization/deserialization with various payloads
- State machine transitions (valid and invalid)
- Reference generation uniqueness
- Backoff delay calculations

### Integration Tests
- Requires a test Phoenix server
- Test join/leave operations
- Multiple simultaneous channels
- Graceful disconnect handling

### Failure Tests
- Simulate network disconnects
- Test reconnection with various scenarios
- Concurrent operations
- Message buffering during disconnect

## References

- Phoenix Channels Guide: https://hexdocs.pm/phoenix/channels.html
- Writing a Channels Client: https://hexdocs.pm/phoenix/writing_a_channels_client.html
- Phoenix.js Source: https://github.com/phoenixframework/phoenix/tree/main/assets/js/phoenix (reference implementation)
- karlseguin/websocket.zig: https://github.com/karlseguin/websocket.zig
- Comprehensive research document: `research/initial_research.md`
