//! Phoenix Channel Implementation
//!
//! This module implements the Channel structure which represents a logical
//! subscription to a Phoenix topic. Channels have their own state machine
//! independent of the Socket state.
//!
//! Channel states:
//! - CLOSED: Not subscribed to the topic
//! - JOINING: Join request sent, waiting for confirmation
//! - JOINED: Successfully subscribed and can send/receive events
//! - LEAVING: Leave request sent, waiting for confirmation
//! - ERROR: Channel error occurred
//!
//! Thread Safety:
//! The Channel struct uses a mutex to protect state access. All public methods
//! that modify state must acquire the lock. Event callbacks are invoked outside
//! the mutex to prevent deadlock.

const std = @import("std");
const State = @import("state.zig");
const ChannelState = State.ChannelState;
const PhoenixSocket = @import("../connection/socket.zig").PhoenixSocket;
const PhoenixMessage = @import("../protocol/message.zig").PhoenixMessage;

/// Channel configuration
pub const Config = struct {
    /// Channel topic (e.g., "room:lobby")
    topic: []const u8,

    /// Join timeout in milliseconds
    timeout_ms: u32 = 10000,
};

/// Event callback function signature
/// Receives the payload and optional context pointer
pub const EventCallback = *const fn (payload: std.json.Value, context: ?*anyopaque) void;

/// State change callback function signature
pub const ChannelStateCallback = *const fn (
    old_state: ChannelState,
    new_state: ChannelState,
    context: ?*anyopaque,
) void;

/// Internal callback entry storing callback and context
const CallbackEntry = struct {
    callback: EventCallback,
    context: ?*anyopaque,
};

/// Phoenix Channel representing a subscription to a topic
pub const Channel = struct {
    /// Memory allocator for dynamic allocations
    allocator: std.mem.Allocator,

    /// Back-reference to parent socket (not owned)
    socket: *PhoenixSocket,

    /// Channel topic (owned, duplicated from config)
    topic: []u8,

    /// Current channel state
    state: ChannelState,

    /// Join reference (owned, null when not joining/joined)
    join_ref: ?[]u8,

    /// Event callback registry: event_name -> callback entry
    callbacks: std.StringHashMap(CallbackEntry),

    /// Mutex for thread-safe state access
    mutex: std.Thread.Mutex,

    /// Optional state change callback
    state_callback: ?ChannelStateCallback,

    /// Optional context for state change callback
    callback_context: ?*anyopaque,

    /// Initialize a new channel
    /// The topic string is duplicated and owned by the channel
    pub fn init(allocator: std.mem.Allocator, socket: *PhoenixSocket, topic: []const u8) !*Channel {
        // Validate topic is not empty
        if (topic.len == 0) {
            return error.InvalidConfiguration;
        }

        const channel = try allocator.create(Channel);
        errdefer allocator.destroy(channel);

        // Duplicate topic string
        const topic_copy = try allocator.dupe(u8, topic);
        errdefer allocator.free(topic_copy);

        channel.* = .{
            .allocator = allocator,
            .socket = socket,
            .topic = topic_copy,
            .state = .CLOSED,
            .join_ref = null,
            .callbacks = std.StringHashMap(CallbackEntry).init(allocator),
            .mutex = std.Thread.Mutex{},
            .state_callback = null,
            .callback_context = null,
        };

        return channel;
    }

    /// Clean up resources
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

    /// Join the channel with optional parameters
    /// Transitions: CLOSED -> JOINING
    /// Sends phx_join message to server
    pub fn join(self: *Channel, params: ?std.json.Value) !void {
        // Step 1: Validate current state (thread-safe)
        {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.state != .CLOSED) {
                return error.InvalidState;
            }
        }

        // Step 2: Generate join reference
        const join_ref = try self.socket.nextRefString();
        errdefer self.socket.allocator.free(join_ref);

        // Step 3: Transition to JOINING and store join_ref
        {
            self.mutex.lock();
            defer self.mutex.unlock();

            // Double-check state hasn't changed
            if (self.state != .CLOSED) {
                self.socket.allocator.free(join_ref);
                return error.InvalidState;
            }

            // Store join_ref (transfer ownership from socket allocator to channel allocator)
            const join_ref_copy = try self.allocator.dupe(u8, join_ref);
            self.join_ref = join_ref_copy;

            // Transition state
            const old_state = self.state;
            self.state = .JOINING;

            // Invoke state callback if registered
            if (self.state_callback) |callback| {
                const ctx = self.callback_context;
                self.mutex.unlock();
                callback(old_state, .JOINING, ctx);
                self.mutex.lock();
            }
        }

        // Step 4: Build and send join message (no lock held)
        const payload = params orelse try PhoenixMessage.emptyPayload(self.allocator);
        defer if (params == null) {
            var mutable_payload = payload;
            if (mutable_payload == .object) mutable_payload.object.deinit();
        };

        const msg = PhoenixMessage.initJoin(
            self.allocator,
            self.topic,
            join_ref,
            payload,
        );

        // Send message (may fail if socket not connected)
        try self.socket.send(&msg);

        // Clean up temporary join_ref from socket allocator
        self.socket.allocator.free(join_ref);
    }

    /// Leave the channel
    /// Transitions: JOINED -> LEAVING
    /// Sends phx_leave message to server
    pub fn leave(self: *Channel) !void {
        // Step 1: Validate current state (thread-safe)
        {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.state != .JOINED) {
                return error.InvalidState;
            }
        }

        // Step 2: Generate message reference
        const ref = try self.socket.nextRefString();
        defer self.socket.allocator.free(ref);

        // Step 3: Transition to LEAVING
        try self.transitionTo(.LEAVING);

        // Step 4: Build and send leave message (no lock held)
        var payload = try PhoenixMessage.emptyPayload(self.allocator);
        defer payload.object.deinit();

        const msg = PhoenixMessage.initLeave(
            self.allocator,
            self.topic,
            ref,
            payload,
        );

        // Send message (may fail if socket not connected)
        try self.socket.send(&msg);
    }

    /// Push an event on the channel
    /// Only works when channel is JOINED
    pub fn push(self: *Channel, event: []const u8, payload: std.json.Value) !void {
        // Step 1: Validate current state (thread-safe)
        {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.state != .JOINED) {
                return error.NotJoined;
            }
        }

        // Step 2: Generate message reference
        const ref = try self.socket.nextRefString();
        defer self.socket.allocator.free(ref);

        // Step 3: Build and send message (no lock held)
        const msg = PhoenixMessage.initEvent(
            self.allocator,
            self.topic,
            event,
            ref,
            payload,
        );

        // Send message (may fail if socket not connected)
        try self.socket.send(&msg);
    }

    /// Register an event callback
    /// The event name is duplicated and owned by the channel
    /// The callback and context pointers are not owned (caller responsibility)
    pub fn on(self: *Channel, event: []const u8, callback: EventCallback, context: ?*anyopaque) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Duplicate event name for HashMap key
        const event_copy = try self.allocator.dupe(u8, event);
        errdefer self.allocator.free(event_copy);

        const entry = CallbackEntry{
            .callback = callback,
            .context = context,
        };

        // Check if event already has a callback
        if (self.callbacks.get(event)) |_| {
            // Free the old key and replace
            var old_key: []u8 = undefined;
            _ = self.callbacks.fetchRemove(event);
            if (self.callbacks.getKey(event)) |key| {
                old_key = @constCast(key);
                self.allocator.free(old_key);
            }
        }

        try self.callbacks.put(event_copy, entry);
    }

    /// Unregister an event callback
    pub fn off(self: *Channel, event: []const u8) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Remove callback and free the key
        if (self.callbacks.fetchRemove(event)) |kv| {
            self.allocator.free(kv.key);
        }
    }

    /// Get current channel state (thread-safe)
    pub fn getState(self: *const Channel) ChannelState {
        // Use @constCast to acquire lock on const self
        // This is safe because the lock doesn't modify the logical state
        const mutable_self = @constCast(self);
        mutable_self.mutex.lock();
        defer mutable_self.mutex.unlock();
        return self.state;
    }

    /// Set channel state with validation (thread-safe, internal use)
    /// This is primarily for testing; normal operation uses transitionTo
    pub fn setState(self: *Channel, new_state: ChannelState) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Validate transition
        if (!self.state.canTransitionTo(new_state)) {
            return error.InvalidStateTransition;
        }

        const old_state = self.state;
        self.state = new_state;

        // Invoke callback if registered (release lock temporarily)
        if (self.state_callback) |callback| {
            const ctx = self.callback_context;
            self.mutex.unlock();
            callback(old_state, new_state, ctx);
            self.mutex.lock();
        }
    }

    /// Set state change callback
    pub fn setStateCallback(
        self: *Channel,
        callback: ?ChannelStateCallback,
        context: ?*anyopaque,
    ) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.state_callback = callback;
        self.callback_context = context;
    }

    /// Add a state change callback (alias for setStateCallback for consistency)
    pub fn addStateCallback(
        self: *Channel,
        callback: ChannelStateCallback,
        context: ?*anyopaque,
    ) void {
        self.setStateCallback(callback, context);
    }

    /// Remove the state change callback
    pub fn removeStateCallback(self: *Channel) void {
        self.setStateCallback(null, null);
    }

    // ========================================================================
    // Internal Methods (Not part of public API)
    // ========================================================================

    /// Transition to a new state with validation and callback invocation
    /// Internal use only
    fn transitionTo(self: *Channel, new_state: ChannelState) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Validate transition
        if (!self.state.canTransitionTo(new_state)) {
            return error.InvalidStateTransition;
        }

        const old_state = self.state;
        self.state = new_state;

        // Invoke callback if registered (release lock temporarily)
        if (self.state_callback) |callback| {
            const ctx = self.callback_context;
            self.mutex.unlock();
            callback(old_state, new_state, ctx);
            self.mutex.lock();
        }
    }

    /// Handle incoming message from server (internal use, will be implemented in Phase 2)
    /// Routes messages to registered callbacks based on event name
    /// Made public for testing purposes
    pub fn handleMessage(self: *Channel, msg: *const PhoenixMessage) !void {
        // Get the callback entry (thread-safe)
        const entry: ?CallbackEntry = blk: {
            self.mutex.lock();
            defer self.mutex.unlock();
            break :blk self.callbacks.get(msg.event);
        };

        // Invoke callback outside lock if found
        if (entry) |e| {
            e.callback(msg.payload, e.context);
        }
    }
};

// ============================================================================
// Tests
// ============================================================================

test "channel initialization with valid topic" {
    const allocator = std.testing.allocator;

    const socket_config = @import("../connection/socket.zig").Config{
        .url = "ws://localhost:4000/socket/websocket",
    };
    const socket = try PhoenixSocket.init(allocator, socket_config);
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    try std.testing.expectEqual(ChannelState.CLOSED, channel.getState());
    try std.testing.expectEqualStrings("room:lobby", channel.topic);
    try std.testing.expect(channel.join_ref == null);
    try std.testing.expect(channel.state_callback == null);
}

test "channel initialization with empty topic fails" {
    const allocator = std.testing.allocator;

    const socket_config = @import("../connection/socket.zig").Config{
        .url = "ws://localhost:4000/socket/websocket",
    };
    const socket = try PhoenixSocket.init(allocator, socket_config);
    defer socket.deinit();

    const result = Channel.init(allocator, socket, "");
    try std.testing.expectError(error.InvalidConfiguration, result);
}

test "multiple channels are independent" {
    const allocator = std.testing.allocator;

    const socket_config = @import("../connection/socket.zig").Config{
        .url = "ws://localhost:4000/socket/websocket",
    };
    const socket = try PhoenixSocket.init(allocator, socket_config);
    defer socket.deinit();

    const channel1 = try Channel.init(allocator, socket, "room:lobby");
    defer channel1.deinit();

    const channel2 = try Channel.init(allocator, socket, "room:private");
    defer channel2.deinit();

    try std.testing.expect(channel1 != channel2);
    try std.testing.expectEqualStrings("room:lobby", channel1.topic);
    try std.testing.expectEqualStrings("room:private", channel2.topic);
}
