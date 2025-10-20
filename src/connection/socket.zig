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

const ConnectionState = State.ConnectionState;
const StateChangeCallback = State.StateChangeCallback;
const RefCounter = types.RefCounter;

/// Phoenix Socket configuration
pub const Config = struct {
    /// WebSocket URL (e.g., "ws://localhost:4000/socket/websocket")
    url: []const u8,

    /// Connection timeout in milliseconds
    timeout_ms: u32 = 10000,

    /// Heartbeat interval in milliseconds
    heartbeat_interval_ms: u32 = 30000,
};

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

        // TODO: Close WebSocket connection if open (Task 1.3.3)
        if (self.ws_client) |client| {
            _ = client; // Will implement cleanup in Task 1.3.3
        }

        self.allocator.destroy(self);
    }

    /// Connect to the Phoenix server
    pub fn connect(self: *PhoenixSocket) !void {
        _ = self;
        // TODO: Implement in Task 1.3.3 (Connection Lifecycle)
        return error.NotImplemented;
    }

    /// Disconnect from the Phoenix server
    pub fn disconnect(self: *PhoenixSocket) !void {
        _ = self;
        // TODO: Implement in Task 1.3.3 (Connection Lifecycle)
        return error.NotImplemented;
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
