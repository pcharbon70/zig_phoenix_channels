//! Phoenix Socket Implementation
//!
//! This module implements the PhoenixSocket structure which manages the WebSocket
//! connection lifecycle, message routing, heartbeat coordination, and channel registry.
//!
//! The Socket implements a state machine with five states:
//! - DISCONNECTED: No connection established
//! - CONNECTING: Connection in progress
//! - CONNECTED: Active connection
//! - CLOSING: Graceful shutdown in progress
//! - ERROR: Connection error occurred
//!
//! Thread Safety:
//! The PhoenixSocket struct uses a mutex to protect state access. All public methods
//! that modify state must acquire the lock. The reference counter has its own internal
//! mutex for thread-safe ID generation.

const std = @import("std");
const websocket = @import("websocket");
const State = @import("state.zig");
const types = @import("../common/types.zig");
const message = @import("../protocol/message.zig");
const serializer = @import("../protocol/serializer.zig");

const ConnectionState = State.ConnectionState;
const StateChangeCallback = State.StateChangeCallback;
const RefCounter = types.RefCounter;
const PhoenixMessage = message.PhoenixMessage;

/// Phoenix Socket configuration
pub const Config = struct {
    /// WebSocket URL (e.g., "ws://localhost:4000/socket/websocket")
    url: []const u8,

    /// Connection timeout in milliseconds
    timeout_ms: u32 = 10000,

    /// Heartbeat interval in milliseconds
    heartbeat_interval_ms: u32 = 30000,
};

/// WebSocket URL components
const UrlInfo = struct {
    host: []const u8,
    port: u16,
    path: []const u8,
    tls: bool,
};

/// Parse WebSocket URL into components
/// Supports: ws://host:port/path and wss://host:port/path
fn parseWebSocketUrl(url: []const u8) !UrlInfo {
    var tls = false;
    var rest: []const u8 = undefined;

    // Parse protocol
    if (std.mem.startsWith(u8, url, "wss://")) {
        tls = true;
        rest = url[6..];
    } else if (std.mem.startsWith(u8, url, "ws://")) {
        rest = url[5..];
    } else {
        return error.InvalidUrl;
    }

    // Find first slash (separates host:port from path)
    const path_start = std.mem.indexOf(u8, rest, "/") orelse rest.len;
    const host_port = rest[0..path_start];
    const path = if (path_start < rest.len) rest[path_start..] else "/";

    // Parse host and port
    if (std.mem.indexOf(u8, host_port, ":")) |colon_pos| {
        const host = host_port[0..colon_pos];
        const port_str = host_port[colon_pos + 1 ..];
        const port = std.fmt.parseInt(u16, port_str, 10) catch return error.InvalidUrl;
        return UrlInfo{
            .host = host,
            .port = port,
            .path = path,
            .tls = tls,
        };
    } else {
        // No port specified, use default
        const default_port: u16 = if (tls) 443 else 80;
        return UrlInfo{
            .host = host_port,
            .port = default_port,
            .path = path,
            .tls = tls,
        };
    }
}

/// Phoenix Socket managing WebSocket connection
pub const PhoenixSocket = struct {
    /// Memory allocator for dynamic allocations
    allocator: std.mem.Allocator,

    /// Socket configuration
    config: Config,

    /// Current connection state
    state: ConnectionState,

    /// WebSocket client (null when disconnected)
    ws_client: ?*websocket.Client,

    /// Reference counter for generating unique message IDs
    ref_counter: RefCounter,

    /// Mutex for thread-safe state access
    mutex: std.Thread.Mutex,

    /// Optional callback for state change notifications
    state_callback: ?StateChangeCallback,

    /// Optional context for state change callback
    callback_context: ?*anyopaque,

    /// Initialize a new Phoenix socket
    pub fn init(allocator: std.mem.Allocator, config: Config) !*PhoenixSocket {
        const socket = try allocator.create(PhoenixSocket);
        socket.* = .{
            .allocator = allocator,
            .config = config,
            .state = .DISCONNECTED,
            .ws_client = null,
            .ref_counter = RefCounter.init(),
            .mutex = std.Thread.Mutex{},
            .state_callback = null,
            .callback_context = null,
        };
        return socket;
    }

    /// Clean up resources
    pub fn deinit(self: *PhoenixSocket) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Close WebSocket connection if open
        if (self.ws_client) |client| {
            client.close(.{}) catch {};
            client.deinit();
            self.allocator.destroy(client);
        }

        self.allocator.destroy(self);
    }

    /// Connect to the Phoenix server
    /// Establishes WebSocket connection with configured URL and timeout
    /// Transitions: DISCONNECTED -> CONNECTING -> CONNECTED (on success)
    ///              DISCONNECTED -> CONNECTING -> ERROR (on failure)
    pub fn connect(self: *PhoenixSocket) !void {
        // Validate current state
        {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.state != .DISCONNECTED) {
                return error.InvalidState;
            }
        }

        // Transition to CONNECTING
        try self.setState(.CONNECTING);
        errdefer self.setState(.ERROR) catch {};

        // Parse WebSocket URL
        const url_info = try parseWebSocketUrl(self.config.url);

        // Create WebSocket client
        var ws_client = try websocket.Client.init(self.allocator, .{
            .host = url_info.host,
            .port = url_info.port,
            .tls = url_info.tls,
        });
        errdefer ws_client.deinit();

        // Perform WebSocket handshake
        try ws_client.handshake(url_info.path, .{
            .timeout_ms = self.config.timeout_ms,
        });

        // Store WebSocket client and transition to CONNECTED
        {
            self.mutex.lock();
            defer self.mutex.unlock();
            self.ws_client = try self.allocator.create(websocket.Client);
            self.ws_client.?.* = ws_client;
        }

        try self.setState(.CONNECTED);
    }

    /// Disconnect from the Phoenix server
    /// Gracefully closes WebSocket connection
    /// Transitions: CONNECTED -> CLOSING -> DISCONNECTED (on success)
    ///              ERROR -> CLOSING -> DISCONNECTED (cleanup after error)
    pub fn disconnect(self: *PhoenixSocket) !void {
        // Validate current state
        {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.state != .CONNECTED and self.state != .ERROR) {
                return error.InvalidState;
            }
        }

        // Transition to CLOSING
        try self.setState(.CLOSING);

        // Close WebSocket connection if exists
        {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.ws_client) |client| {
                // Send close frame and close connection
                client.close(.{}) catch {};
                client.deinit();
                self.allocator.destroy(client);
                self.ws_client = null;
            }
        }

        // Transition to DISCONNECTED
        try self.setState(.DISCONNECTED);
    }

    /// Send a Phoenix message over the WebSocket connection
    /// Returns error if not connected or if send fails
    /// Thread-safe: can be called from multiple threads
    ///
    /// Phase 1: Returns error.NotConnected if state != CONNECTED (no queuing)
    /// The message buffer is modified by the WebSocket library for masking
    pub fn send(self: *PhoenixSocket, msg: *const PhoenixMessage) !void {
        // Step 1: Check connection state (thread-safe)
        {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.state != .CONNECTED) {
                return error.NotConnected;
            }
        }

        // Step 2: Get WebSocket client (thread-safe, re-check in case of race)
        const client = blk: {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.ws_client) |c| {
                break :blk c;
            } else {
                return error.NotConnected;
            }
        };

        // Step 3: Validate message
        try msg.validateForSend();

        // Step 4: Serialize message to JSON
        const json_bytes = try serializer.serialize(self.allocator, msg);
        defer self.allocator.free(json_bytes);

        // Step 5: Send via WebSocket (requires mutable buffer)
        // Note: websocket.zig modifies the buffer for masking, so we need a mutable copy
        const send_buffer = try self.allocator.dupe(u8, json_bytes);
        defer self.allocator.free(send_buffer);

        // Step 6: Send with timeout (using existing timeout configuration)
        try client.writeTimeout(self.config.timeout_ms);
        defer client.writeTimeout(0) catch {};

        try client.writeText(send_buffer);
    }

    /// Get current connection state (thread-safe)
    pub fn getState(self: *PhoenixSocket) ConnectionState {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.state;
    }

    /// Set connection state with validation and callback notification (thread-safe)
    /// This method validates the state transition and invokes the callback if registered
    pub fn setState(self: *PhoenixSocket, new_state: ConnectionState) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Validate transition
        try self.state.validateTransition(new_state);

        const old_state = self.state;
        self.state = new_state;

        // Invoke callback if registered (outside lock to prevent deadlock)
        if (self.state_callback) |callback| {
            // Release lock temporarily for callback
            self.mutex.unlock();
            callback(old_state, new_state, self.callback_context);
            self.mutex.lock();
        }
    }

    /// Generate next unique message reference
    pub fn nextRef(self: *PhoenixSocket) usize {
        return self.ref_counter.next();
    }

    /// Generate next unique message reference as string
    /// Caller must free the returned string
    pub fn nextRefString(self: *PhoenixSocket) ![]u8 {
        const ref = self.nextRef();
        return std.fmt.allocPrint(self.allocator, "{d}", .{ref});
    }

    /// Set state change callback
    pub fn setStateCallback(
        self: *PhoenixSocket,
        callback: ?StateChangeCallback,
        context: ?*anyopaque,
    ) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.state_callback = callback;
        self.callback_context = context;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "socket initialization" {
    const allocator = std.testing.allocator;

    const config = Config{
        .url = "ws://localhost:4000/socket/websocket",
    };

    const socket = try PhoenixSocket.init(allocator, config);
    defer socket.deinit();

    try std.testing.expect(socket.getState() == .DISCONNECTED);
    try std.testing.expect(socket.ws_client == null);
    try std.testing.expect(socket.state_callback == null);
    try std.testing.expect(socket.callback_context == null);
}

test "socket configuration" {
    const allocator = std.testing.allocator;

    const config = Config{
        .url = "ws://localhost:4000/socket/websocket",
        .timeout_ms = 5000,
        .heartbeat_interval_ms = 15000,
    };

    const socket = try PhoenixSocket.init(allocator, config);
    defer socket.deinit();

    try std.testing.expectEqualStrings("ws://localhost:4000/socket/websocket", socket.config.url);
    try std.testing.expectEqual(@as(u32, 5000), socket.config.timeout_ms);
    try std.testing.expectEqual(@as(u32, 15000), socket.config.heartbeat_interval_ms);
}

test "reference counter generates unique IDs" {
    const allocator = std.testing.allocator;

    const config = Config{
        .url = "ws://localhost:4000/socket/websocket",
    };

    const socket = try PhoenixSocket.init(allocator, config);
    defer socket.deinit();

    const ref1 = socket.nextRef();
    const ref2 = socket.nextRef();
    const ref3 = socket.nextRef();

    try std.testing.expectEqual(@as(usize, 1), ref1);
    try std.testing.expectEqual(@as(usize, 2), ref2);
    try std.testing.expectEqual(@as(usize, 3), ref3);
}

test "reference counter generates string IDs" {
    const allocator = std.testing.allocator;

    const config = Config{
        .url = "ws://localhost:4000/socket/websocket",
    };

    const socket = try PhoenixSocket.init(allocator, config);
    defer socket.deinit();

    const ref1 = try socket.nextRefString();
    defer allocator.free(ref1);

    const ref2 = try socket.nextRefString();
    defer allocator.free(ref2);

    try std.testing.expectEqualStrings("1", ref1);
    try std.testing.expectEqualStrings("2", ref2);
}

test "state transition validation" {
    const allocator = std.testing.allocator;

    const config = Config{
        .url = "ws://localhost:4000/socket/websocket",
    };

    const socket = try PhoenixSocket.init(allocator, config);
    defer socket.deinit();

    // Valid transition: DISCONNECTED -> CONNECTING
    try socket.setState(.CONNECTING);
    try std.testing.expectEqual(ConnectionState.CONNECTING, socket.getState());

    // Invalid transition: CONNECTING -> CLOSING
    const result = socket.setState(.CLOSING);
    try std.testing.expectError(error.InvalidStateTransition, result);

    // State should remain unchanged after failed transition
    try std.testing.expectEqual(ConnectionState.CONNECTING, socket.getState());
}

test "state callback invocation" {
    const allocator = std.testing.allocator;

    const CallbackContext = struct {
        called: bool = false,
        old_state: ?ConnectionState = null,
        new_state: ?ConnectionState = null,
    };

    const testCallback = struct {
        fn callback(old: ConnectionState, new: ConnectionState, ctx: ?*anyopaque) void {
            if (ctx) |context| {
                const test_ctx: *CallbackContext = @ptrCast(@alignCast(context));
                test_ctx.called = true;
                test_ctx.old_state = old;
                test_ctx.new_state = new;
            }
        }
    }.callback;

    const config = Config{
        .url = "ws://localhost:4000/socket/websocket",
    };

    const socket = try PhoenixSocket.init(allocator, config);
    defer socket.deinit();

    var ctx = CallbackContext{};
    socket.setStateCallback(testCallback, &ctx);

    // Trigger state change
    try socket.setState(.CONNECTING);

    // Verify callback was invoked
    try std.testing.expect(ctx.called);
    try std.testing.expectEqual(ConnectionState.DISCONNECTED, ctx.old_state.?);
    try std.testing.expectEqual(ConnectionState.CONNECTING, ctx.new_state.?);
}

test "state callback with null context" {
    const allocator = std.testing.allocator;

    const testCallback = struct {
        fn callback(old: ConnectionState, new: ConnectionState, ctx: ?*anyopaque) void {
            _ = old;
            _ = new;
            _ = ctx;
            // Should not crash with null context
        }
    }.callback;

    const config = Config{
        .url = "ws://localhost:4000/socket/websocket",
    };

    const socket = try PhoenixSocket.init(allocator, config);
    defer socket.deinit();

    socket.setStateCallback(testCallback, null);

    // Should not crash
    try socket.setState(.CONNECTING);
    try std.testing.expectEqual(ConnectionState.CONNECTING, socket.getState());
}

test "remove state callback" {
    const allocator = std.testing.allocator;

    const config = Config{
        .url = "ws://localhost:4000/socket/websocket",
    };

    const socket = try PhoenixSocket.init(allocator, config);
    defer socket.deinit();

    const testCallback = struct {
        fn callback(old: ConnectionState, new: ConnectionState, ctx: ?*anyopaque) void {
            _ = old;
            _ = new;
            _ = ctx;
        }
    }.callback;

    // Set callback
    socket.setStateCallback(testCallback, null);
    try std.testing.expect(socket.state_callback != null);

    // Remove callback
    socket.setStateCallback(null, null);
    try std.testing.expect(socket.state_callback == null);

    // State changes should still work
    try socket.setState(.CONNECTING);
    try std.testing.expectEqual(ConnectionState.CONNECTING, socket.getState());
}

test "thread-safe state access" {
    const allocator = std.testing.allocator;

    const config = Config{
        .url = "ws://localhost:4000/socket/websocket",
    };

    const socket = try PhoenixSocket.init(allocator, config);
    defer socket.deinit();

    // Test that multiple state accesses don't deadlock
    const state1 = socket.getState();
    const state2 = socket.getState();

    try std.testing.expectEqual(state1, state2);
    try std.testing.expectEqual(ConnectionState.DISCONNECTED, state1);
}

test "complete state transition sequence" {
    const allocator = std.testing.allocator;

    const config = Config{
        .url = "ws://localhost:4000/socket/websocket",
    };

    const socket = try PhoenixSocket.init(allocator, config);
    defer socket.deinit();

    // DISCONNECTED -> CONNECTING
    try socket.setState(.CONNECTING);
    try std.testing.expectEqual(ConnectionState.CONNECTING, socket.getState());

    // CONNECTING -> CONNECTED
    try socket.setState(.CONNECTED);
    try std.testing.expectEqual(ConnectionState.CONNECTED, socket.getState());

    // CONNECTED -> CLOSING
    try socket.setState(.CLOSING);
    try std.testing.expectEqual(ConnectionState.CLOSING, socket.getState());

    // CLOSING -> DISCONNECTED
    try socket.setState(.DISCONNECTED);
    try std.testing.expectEqual(ConnectionState.DISCONNECTED, socket.getState());
}

test "error state transitions" {
    const allocator = std.testing.allocator;

    const config = Config{
        .url = "ws://localhost:4000/socket/websocket",
    };

    const socket = try PhoenixSocket.init(allocator, config);
    defer socket.deinit();

    // DISCONNECTED -> CONNECTING -> ERROR
    try socket.setState(.CONNECTING);
    try socket.setState(.ERROR);
    try std.testing.expectEqual(ConnectionState.ERROR, socket.getState());

    // ERROR -> DISCONNECTED
    try socket.setState(.DISCONNECTED);
    try std.testing.expectEqual(ConnectionState.DISCONNECTED, socket.getState());

    // ERROR -> CONNECTING (retry)
    try socket.setState(.CONNECTING);
    try socket.setState(.ERROR);
    try socket.setState(.CONNECTING);
    try std.testing.expectEqual(ConnectionState.CONNECTING, socket.getState());
}

// ============================================================================
// Connection Lifecycle Tests
// ============================================================================

test "URL parsing: ws with port and path" {
    const url = "ws://localhost:4000/socket/websocket";
    const info = try parseWebSocketUrl(url);

    try std.testing.expectEqualStrings("localhost", info.host);
    try std.testing.expectEqual(@as(u16, 4000), info.port);
    try std.testing.expectEqualStrings("/socket/websocket", info.path);
    try std.testing.expectEqual(false, info.tls);
}

test "URL parsing: wss with port and path" {
    const url = "wss://example.com:443/socket";
    const info = try parseWebSocketUrl(url);

    try std.testing.expectEqualStrings("example.com", info.host);
    try std.testing.expectEqual(@as(u16, 443), info.port);
    try std.testing.expectEqualStrings("/socket", info.path);
    try std.testing.expectEqual(true, info.tls);
}

test "URL parsing: ws without port" {
    const url = "ws://localhost/socket";
    const info = try parseWebSocketUrl(url);

    try std.testing.expectEqualStrings("localhost", info.host);
    try std.testing.expectEqual(@as(u16, 80), info.port);
    try std.testing.expectEqualStrings("/socket", info.path);
    try std.testing.expectEqual(false, info.tls);
}

test "URL parsing: wss without port" {
    const url = "wss://example.com/socket";
    const info = try parseWebSocketUrl(url);

    try std.testing.expectEqualStrings("example.com", info.host);
    try std.testing.expectEqual(@as(u16, 443), info.port);
    try std.testing.expectEqualStrings("/socket", info.path);
    try std.testing.expectEqual(true, info.tls);
}

test "URL parsing: without path" {
    const url = "ws://localhost:8080";
    const info = try parseWebSocketUrl(url);

    try std.testing.expectEqualStrings("localhost", info.host);
    try std.testing.expectEqual(@as(u16, 8080), info.port);
    try std.testing.expectEqualStrings("/", info.path);
    try std.testing.expectEqual(false, info.tls);
}

test "URL parsing: invalid protocol" {
    const url = "http://localhost:4000/socket";
    const result = parseWebSocketUrl(url);
    try std.testing.expectError(error.InvalidUrl, result);
}

test "URL parsing: invalid port" {
    const url = "ws://localhost:abc/socket";
    const result = parseWebSocketUrl(url);
    try std.testing.expectError(error.InvalidUrl, result);
}

test "connect: invalid state" {
    const allocator = std.testing.allocator;

    const config = Config{
        .url = "ws://localhost:4000/socket/websocket",
    };

    const socket = try PhoenixSocket.init(allocator, config);
    defer socket.deinit();

    // Manually set state to CONNECTING
    try socket.setState(.CONNECTING);

    // Try to connect while already connecting
    const result = socket.connect();
    try std.testing.expectError(error.InvalidState, result);
}

test "disconnect: invalid state when DISCONNECTED" {
    const allocator = std.testing.allocator;

    const config = Config{
        .url = "ws://localhost:4000/socket/websocket",
    };

    const socket = try PhoenixSocket.init(allocator, config);
    defer socket.deinit();

    // Try to disconnect while already disconnected
    const result = socket.disconnect();
    try std.testing.expectError(error.InvalidState, result);
}

test "disconnect: valid state when ERROR" {
    const allocator = std.testing.allocator;

    const config = Config{
        .url = "ws://localhost:4000/socket/websocket",
    };

    const socket = try PhoenixSocket.init(allocator, config);
    defer socket.deinit();

    // Transition to ERROR state
    try socket.setState(.CONNECTING);
    try socket.setState(.ERROR);

    // Should be able to disconnect from ERROR state
    try socket.disconnect();
    try std.testing.expectEqual(ConnectionState.DISCONNECTED, socket.getState());
}

// ============================================================================
// Message Sending Tests
// ============================================================================

test "send: returns error when DISCONNECTED" {
    const allocator = std.testing.allocator;

    const config = Config{
        .url = "ws://localhost:4000/socket/websocket",
    };

    const socket = try PhoenixSocket.init(allocator, config);
    defer socket.deinit();

    // Create a test message
    const test_msg = PhoenixMessage{
        .join_ref = null,
        .ref = "1",
        .topic = "room:lobby",
        .event = "test_event",
        .payload = .{ .object = std.json.ObjectMap.init(allocator) },
    };
    defer if (test_msg.payload == .object) test_msg.payload.object.deinit();

    // Try to send while DISCONNECTED
    const result = socket.send(&test_msg);
    try std.testing.expectError(error.NotConnected, result);
}

test "send: returns error when CONNECTING" {
    const allocator = std.testing.allocator;

    const config = Config{
        .url = "ws://localhost:4000/socket/websocket",
    };

    const socket = try PhoenixSocket.init(allocator, config);
    defer socket.deinit();

    // Transition to CONNECTING
    try socket.setState(.CONNECTING);

    // Create a test message
    const test_msg = PhoenixMessage{
        .join_ref = null,
        .ref = "1",
        .topic = "room:lobby",
        .event = "test_event",
        .payload = .{ .object = std.json.ObjectMap.init(allocator) },
    };
    defer if (test_msg.payload == .object) test_msg.payload.object.deinit();

    // Try to send while CONNECTING
    const result = socket.send(&test_msg);
    try std.testing.expectError(error.NotConnected, result);
}

test "send: returns error when CLOSING" {
    const allocator = std.testing.allocator;

    const config = Config{
        .url = "ws://localhost:4000/socket/websocket",
    };

    const socket = try PhoenixSocket.init(allocator, config);
    defer socket.deinit();

    // Transition to CONNECTED then CLOSING
    try socket.setState(.CONNECTING);
    try socket.setState(.CONNECTED);
    try socket.setState(.CLOSING);

    // Create a test message
    const test_msg = PhoenixMessage{
        .join_ref = null,
        .ref = "1",
        .topic = "room:lobby",
        .event = "test_event",
        .payload = .{ .object = std.json.ObjectMap.init(allocator) },
    };
    defer if (test_msg.payload == .object) test_msg.payload.object.deinit();

    // Try to send while CLOSING
    const result = socket.send(&test_msg);
    try std.testing.expectError(error.NotConnected, result);
}

test "send: returns error when ERROR" {
    const allocator = std.testing.allocator;

    const config = Config{
        .url = "ws://localhost:4000/socket/websocket",
    };

    const socket = try PhoenixSocket.init(allocator, config);
    defer socket.deinit();

    // Transition to ERROR
    try socket.setState(.CONNECTING);
    try socket.setState(.ERROR);

    // Create a test message
    const test_msg = PhoenixMessage{
        .join_ref = null,
        .ref = "1",
        .topic = "room:lobby",
        .event = "test_event",
        .payload = .{ .object = std.json.ObjectMap.init(allocator) },
    };
    defer if (test_msg.payload == .object) test_msg.payload.object.deinit();

    // Try to send while ERROR
    const result = socket.send(&test_msg);
    try std.testing.expectError(error.NotConnected, result);
}

test "send: returns error when ws_client is null despite CONNECTED state" {
    const allocator = std.testing.allocator;

    const config = Config{
        .url = "ws://localhost:4000/socket/websocket",
    };

    const socket = try PhoenixSocket.init(allocator, config);
    defer socket.deinit();

    // Manually set state to CONNECTED without actually connecting
    // (This simulates a race condition)
    try socket.setState(.CONNECTING);
    try socket.setState(.CONNECTED);

    // Create a test message
    const test_msg = PhoenixMessage{
        .join_ref = null,
        .ref = "1",
        .topic = "room:lobby",
        .event = "test_event",
        .payload = .{ .object = std.json.ObjectMap.init(allocator) },
    };
    defer if (test_msg.payload == .object) test_msg.payload.object.deinit();

    // Try to send - should fail because ws_client is null
    const result = socket.send(&test_msg);
    try std.testing.expectError(error.NotConnected, result);
}
