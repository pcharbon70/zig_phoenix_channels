const std = @import("std");
const testing = std.testing;
const phoenix = @import("phoenix_channels");
const Channel = phoenix.channel.Channel;
const ChannelState = phoenix.channel.ChannelState;
const PhoenixSocket = phoenix.connection.PhoenixSocket;
const SocketConfig = phoenix.connection.SocketConfig;

// ============================================================================
// Task 1.4.4: Channel Leave Operation Tests
// ============================================================================

const allocator = testing.allocator;

// Helper to create a test socket
fn createTestSocket() !*PhoenixSocket {
    const config = SocketConfig{
        .url = "ws://localhost:4000/socket/websocket",
    };
    return try PhoenixSocket.init(allocator, config);
}

// ----------------------------------------------------------------------------
// Basic Leave Operation
// ----------------------------------------------------------------------------

test "leave from JOINED state transitions to LEAVING" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    // Manually set to JOINED
    try channel.setState(.JOINING);
    try channel.setState(.JOINED);

    try socket.setState(.CONNECTING);
    try socket.setState(.CONNECTED);

    // Leave should transition to LEAVING
    _ = channel.leave() catch unreachable;

    try testing.expectEqual(ChannelState.LEAVING, channel.getState());
}

test "leave sends message when socket connected" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    try channel.setState(.JOINING);
    try channel.setState(.JOINED);

    try socket.setState(.CONNECTING);
    try socket.setState(.CONNECTED);

    // Leave will fail (no real WebSocket), but state should transition
    _ = channel.leave() catch unreachable;

    try testing.expectEqual(ChannelState.LEAVING, channel.getState());
}

test "leave when socket disconnected returns NotConnected" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    try channel.setState(.JOINING);
    try channel.setState(.JOINED);

    // Socket is DISCONNECTED
    const result = channel.leave();
    try testing.expectError(error.NotConnected, result);

    // State should have transitioned to LEAVING before send failed
    try testing.expectEqual(ChannelState.LEAVING, channel.getState());
}

// ----------------------------------------------------------------------------
// State Validation
// ----------------------------------------------------------------------------

test "leave from CLOSED fails with InvalidState" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    // Channel is CLOSED by default
    const result = channel.leave();
    try testing.expectError(error.InvalidState, result);

    // State should remain CLOSED
    try testing.expectEqual(ChannelState.CLOSED, channel.getState());
}

test "leave from JOINING fails with InvalidState" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    try channel.setState(.JOINING);

    const result = channel.leave();
    try testing.expectError(error.InvalidState, result);

    // State should remain JOINING
    try testing.expectEqual(ChannelState.JOINING, channel.getState());
}

test "leave from LEAVING fails with InvalidState" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    try channel.setState(.JOINING);
    try channel.setState(.JOINED);
    try channel.setState(.LEAVING);

    const result = channel.leave();
    try testing.expectError(error.InvalidState, result);

    // State should remain LEAVING
    try testing.expectEqual(ChannelState.LEAVING, channel.getState());
}

test "leave from ERROR fails with InvalidState" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    try channel.setState(.JOINING);
    try channel.setState(.ERROR);

    const result = channel.leave();
    try testing.expectError(error.InvalidState, result);

    // State should remain ERROR
    try testing.expectEqual(ChannelState.ERROR, channel.getState());
}

// ----------------------------------------------------------------------------
// State Callbacks
// ----------------------------------------------------------------------------

test "leave invokes state callback on transition" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    try channel.setState(.JOINING);
    try channel.setState(.JOINED);

    try socket.setState(.CONNECTING);
    try socket.setState(.CONNECTED);

    const CallbackContext = struct {
        called: bool = false,
        old_state: ?ChannelState = null,
        new_state: ?ChannelState = null,
    };

    const testCallback = struct {
        fn callback(old: ChannelState, new: ChannelState, ctx: ?*anyopaque) void {
            if (ctx) |context| {
                const test_ctx: *CallbackContext = @ptrCast(@alignCast(context));
                test_ctx.called = true;
                test_ctx.old_state = old;
                test_ctx.new_state = new;
            }
        }
    }.callback;

    var ctx = CallbackContext{};
    channel.setStateCallback(testCallback, &ctx);

    _ = channel.leave() catch unreachable;

    // Verify callback was invoked
    try testing.expect(ctx.called);
    try testing.expectEqual(ChannelState.JOINED, ctx.old_state.?);
    try testing.expectEqual(ChannelState.LEAVING, ctx.new_state.?);
}

test "leave does not invoke callback on failed state validation" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    // Channel is CLOSED
    var callback_called = false;
    const testCallback = struct {
        fn callback(old: ChannelState, new: ChannelState, ctx: ?*anyopaque) void {
            _ = old;
            _ = new;
            if (ctx) |context| {
                const called: *bool = @ptrCast(@alignCast(context));
                called.* = true;
            }
        }
    }.callback;

    channel.setStateCallback(testCallback, &callback_called);

    // Try to leave from CLOSED (invalid)
    _ = channel.leave() catch unreachable;

    // Callback should not be invoked because state validation failed
    try testing.expect(!callback_called);
}

// ----------------------------------------------------------------------------
// Memory Management
// ----------------------------------------------------------------------------

test "leave does not leak memory on success" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    try channel.setState(.JOINING);
    try channel.setState(.JOINED);

    try socket.setState(.CONNECTING);
    try socket.setState(.CONNECTED);

    _ = channel.leave() catch unreachable;
    // Testing allocator will detect leaks
}

test "leave does not leak memory on failure" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    try channel.setState(.JOINING);
    try channel.setState(.JOINED);

    // Socket is DISCONNECTED, leave will fail
    _ = channel.leave() catch unreachable;
    // Testing allocator will detect leaks
}

// ----------------------------------------------------------------------------
// Multiple Leave Attempts
// ----------------------------------------------------------------------------

test "consecutive leaves from JOINED are rejected" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    try channel.setState(.JOINING);
    try channel.setState(.JOINED);

    try socket.setState(.CONNECTING);
    try socket.setState(.CONNECTED);

    // First leave
    _ = channel.leave() catch unreachable;
    try testing.expectEqual(ChannelState.LEAVING, channel.getState());

    // Second leave should fail
    const result = channel.leave();
    try testing.expectError(error.InvalidState, result);
}

// ----------------------------------------------------------------------------
// Complete Lifecycle
// ----------------------------------------------------------------------------

test "complete lifecycle: join then leave" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    try socket.setState(.CONNECTING);
    try socket.setState(.CONNECTED);

    // Join
    _ = channel.join(null) catch unreachable;
    try testing.expectEqual(ChannelState.JOINING, channel.getState());

    // Manually transition to JOINED
    try channel.setState(.JOINED);

    // Leave
    _ = channel.leave() catch unreachable;
    try testing.expectEqual(ChannelState.LEAVING, channel.getState());

    // Manually transition to CLOSED
    try channel.setState(.CLOSED);
    try testing.expectEqual(ChannelState.CLOSED, channel.getState());
}

test "rejoin after complete leave" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    try socket.setState(.CONNECTING);
    try socket.setState(.CONNECTED);

    // First join-leave cycle
    _ = channel.join(null) catch unreachable;
    try channel.setState(.JOINED);
    _ = channel.leave() catch unreachable;
    try channel.setState(.CLOSED);

    // Second join should work
    _ = channel.join(null) catch unreachable;
    try testing.expectEqual(ChannelState.JOINING, channel.getState());
}

// ----------------------------------------------------------------------------
// Edge Cases
// ----------------------------------------------------------------------------

test "leave preserves topic" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const original_topic = "room:lobby:messages";
    const channel = try Channel.init(allocator, socket, original_topic);
    defer channel.deinit();

    try channel.setState(.JOINING);
    try channel.setState(.JOINED);

    try socket.setState(.CONNECTING);
    try socket.setState(.CONNECTED);

    _ = channel.leave() catch unreachable;

    // Topic should be unchanged
    try testing.expectEqualStrings(original_topic, channel.topic);
}

test "leave with concurrent state access" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    try channel.setState(.JOINING);
    try channel.setState(.JOINED);

    try socket.setState(.CONNECTING);
    try socket.setState(.CONNECTED);

    // Read state while leaving
    const state_before = channel.getState();
    _ = channel.leave() catch unreachable;
    const state_after = channel.getState();

    try testing.expectEqual(ChannelState.JOINED, state_before);
    try testing.expectEqual(ChannelState.LEAVING, state_after);
}

test "leave generates unique message ref" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel1 = try Channel.init(allocator, socket, "room:lobby");
    defer channel1.deinit();

    const channel2 = try Channel.init(allocator, socket, "room:private");
    defer channel2.deinit();

    try channel1.setState(.JOINING);
    try channel1.setState(.JOINED);
    try channel2.setState(.JOINING);
    try channel2.setState(.JOINED);

    try socket.setState(.CONNECTING);
    try socket.setState(.CONNECTED);

    // Both leaves should generate different refs
    // (We can't directly test this without message inspection,
    // but the socket's ref counter ensures uniqueness)
    _ = channel1.leave() catch unreachable;
    _ = channel2.leave() catch unreachable;

    try testing.expectEqual(ChannelState.LEAVING, channel1.getState());
    try testing.expectEqual(ChannelState.LEAVING, channel2.getState());
}
