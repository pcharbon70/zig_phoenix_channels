const std = @import("std");
const testing = std.testing;
const phoenix = @import("phoenix_channels");
const Channel = phoenix.channel.Channel;
const ChannelState = phoenix.channel.ChannelState;
const PhoenixSocket = phoenix.connection.PhoenixSocket;
const SocketConfig = phoenix.connection.SocketConfig;
const ConnectionState = phoenix.connection.ConnectionState;

// ============================================================================
// Task 1.4.3: Channel Join Operation Tests
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
// Basic Join Operation
// ----------------------------------------------------------------------------

test "join from CLOSED state transitions to JOINING" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    // Set socket to CONNECTED to allow message sending
    try socket.setState(.CONNECTING);
    try socket.setState(.CONNECTED);

    // Note: join will fail because no actual WebSocket connection,
    // but we can test the state transition attempt
    // For this test, we'll catch the error and verify the state changed
    const result = channel.join(null);

    // Join might fail due to NotConnected, but state should have transitioned
    // before the send attempt
    if (result) {
        // Unexpected success - but check state anyway
        try testing.expectEqual(ChannelState.JOINING, channel.getState());
    } else |err| {
        // Expected error - verify it's NotConnected
        try testing.expectEqual(error.NotConnected, err);
        // State should have transitioned to JOINING before send failed
        try testing.expectEqual(ChannelState.JOINING, channel.getState());
    }
}

test "join stores join_ref" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    try socket.setState(.CONNECTING);
    try socket.setState(.CONNECTED);

    // Join will fail, but join_ref should be set
    _ = channel.join(null) catch unreachable;

    // Check join_ref is set
    {
        channel.mutex.lock();
        defer channel.mutex.unlock();
        try testing.expect(channel.join_ref != null);
        try testing.expect(channel.join_ref.?.len > 0);
    }
}

test "join with null params" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    try socket.setState(.CONNECTING);
    try socket.setState(.CONNECTED);

    // Should not crash with null params
    _ = channel.join(null) catch unreachable;
}

test "join with empty payload" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    try socket.setState(.CONNECTING);
    try socket.setState(.CONNECTED);

    var payload = std.json.ObjectMap.init(allocator);
    defer payload.deinit();

    _ = channel.join(.{ .object = payload }) catch unreachable;
}

test "join with params" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    try socket.setState(.CONNECTING);
    try socket.setState(.CONNECTED);

    var payload = std.json.ObjectMap.init(allocator);
    defer payload.deinit();
    try payload.put("token", .{ .string = "auth_token_123" });

    _ = channel.join(.{ .object = payload }) catch unreachable;
}

test "join with nested params" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    try socket.setState(.CONNECTING);
    try socket.setState(.CONNECTED);

    var inner = std.json.ObjectMap.init(allocator);
    defer inner.deinit();
    try inner.put("key", .{ .string = "value" });

    var payload = std.json.ObjectMap.init(allocator);
    defer payload.deinit();
    try payload.put("auth", .{ .object = inner });

    _ = channel.join(.{ .object = payload }) catch unreachable;
}

// ----------------------------------------------------------------------------
// State Validation
// ----------------------------------------------------------------------------

test "join from JOINING fails with InvalidState" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    // Manually set to JOINING
    try channel.setState(.JOINING);

    // Try to join again
    const result = channel.join(null);
    try testing.expectError(error.InvalidState, result);

    // State should remain JOINING
    try testing.expectEqual(ChannelState.JOINING, channel.getState());
}

test "join from JOINED fails with InvalidState" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    // Manually set to JOINED
    try channel.setState(.JOINING);
    try channel.setState(.JOINED);

    // Try to join again
    const result = channel.join(null);
    try testing.expectError(error.InvalidState, result);

    // State should remain JOINED
    try testing.expectEqual(ChannelState.JOINED, channel.getState());
}

test "join from LEAVING fails with InvalidState" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    // Manually set to LEAVING
    try channel.setState(.JOINING);
    try channel.setState(.JOINED);
    try channel.setState(.LEAVING);

    // Try to join
    const result = channel.join(null);
    try testing.expectError(error.InvalidState, result);

    // State should remain LEAVING
    try testing.expectEqual(ChannelState.LEAVING, channel.getState());
}

test "join from ERROR is allowed (rejoin)" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    // Manually set to ERROR
    try channel.setState(.JOINING);
    try channel.setState(.ERROR);

    // First transition to CLOSED as required by state machine
    try channel.setState(.CLOSED);

    try socket.setState(.CONNECTING);
    try socket.setState(.CONNECTED);

    // Join should work from CLOSED (after ERROR)
    _ = channel.join(null) catch unreachable;

    // Should be in JOINING state
    try testing.expectEqual(ChannelState.JOINING, channel.getState());
}

test "join when socket DISCONNECTED returns NotConnected" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    // Socket is DISCONNECTED by default
    const result = channel.join(null);

    // Should fail because socket not connected
    try testing.expectError(error.NotConnected, result);

    // But state should have transitioned to JOINING before send failed
    try testing.expectEqual(ChannelState.JOINING, channel.getState());
}

// ----------------------------------------------------------------------------
// Join Reference Generation
// ----------------------------------------------------------------------------

test "join generates unique join_ref" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel1 = try Channel.init(allocator, socket, "room:lobby");
    defer channel1.deinit();

    const channel2 = try Channel.init(allocator, socket, "room:private");
    defer channel2.deinit();

    try socket.setState(.CONNECTING);
    try socket.setState(.CONNECTED);

    _ = channel1.join(null) catch unreachable;
    _ = channel2.join(null) catch unreachable;

    // Both should have join_refs
    {
        channel1.mutex.lock();
        defer channel1.mutex.unlock();
        try testing.expect(channel1.join_ref != null);
    }
    {
        channel2.mutex.lock();
        defer channel2.mutex.unlock();
        try testing.expect(channel2.join_ref != null);
    }

    // Refs should be different
    {
        channel1.mutex.lock();
        defer channel1.mutex.unlock();
        channel2.mutex.lock();
        defer channel2.mutex.unlock();

        const ref1 = channel1.join_ref.?;
        const ref2 = channel2.join_ref.?;
        try testing.expect(!std.mem.eql(u8, ref1, ref2));
    }
}

test "join_ref is numeric string" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    try socket.setState(.CONNECTING);
    try socket.setState(.CONNECTED);

    _ = channel.join(null) catch unreachable;

    // Check join_ref is numeric
    {
        channel.mutex.lock();
        defer channel.mutex.unlock();

        const ref = channel.join_ref.?;
        const parsed = std.fmt.parseInt(usize, ref, 10) catch unreachable;
        try testing.expect(parsed > 0);
    }
}

// ----------------------------------------------------------------------------
// State Callbacks
// ----------------------------------------------------------------------------

test "join invokes state callback on transition" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

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

    _ = channel.join(null) catch unreachable;

    // Verify callback was invoked
    try testing.expect(ctx.called);
    try testing.expectEqual(ChannelState.CLOSED, ctx.old_state.?);
    try testing.expectEqual(ChannelState.JOINING, ctx.new_state.?);
}

test "join does not invoke callback on failed state validation" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    // Set to JOINING
    try channel.setState(.JOINING);

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

    // Try to join from JOINING (invalid)
    _ = channel.join(null) catch unreachable;

    // Callback should not be invoked because state validation failed
    try testing.expect(!callback_called);
}

// ----------------------------------------------------------------------------
// Memory Management
// ----------------------------------------------------------------------------

test "join does not leak memory on success" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    try socket.setState(.CONNECTING);
    try socket.setState(.CONNECTED);

    _ = channel.join(null) catch unreachable;
    // Testing allocator will detect leaks
}

test "join does not leak memory on failure" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    // Socket is DISCONNECTED, join will fail
    _ = channel.join(null) catch unreachable;
    // Testing allocator will detect leaks
}

test "join with params does not leak memory" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    try socket.setState(.CONNECTING);
    try socket.setState(.CONNECTED);

    var payload = std.json.ObjectMap.init(allocator);
    defer payload.deinit();
    try payload.put("token", .{ .string = "test" });

    _ = channel.join(.{ .object = payload }) catch unreachable;
    // Testing allocator will detect leaks
}

// ----------------------------------------------------------------------------
// Multiple Join Attempts
// ----------------------------------------------------------------------------

test "consecutive joins from CLOSED are rejected" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    try socket.setState(.CONNECTING);
    try socket.setState(.CONNECTED);

    // First join
    _ = channel.join(null) catch unreachable;
    try testing.expectEqual(ChannelState.JOINING, channel.getState());

    // Second join should fail
    const result = channel.join(null);
    try testing.expectError(error.InvalidState, result);
}

test "join after failed join updates join_ref" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    // First join (will fail - socket disconnected)
    _ = channel.join(null) catch unreachable;

    const first_ref = blk: {
        channel.mutex.lock();
        defer channel.mutex.unlock();
        break :blk try allocator.dupe(u8, channel.join_ref.?);
    };
    defer allocator.free(first_ref);

    // Manually reset to CLOSED
    try channel.setState(.CLOSED);

    try socket.setState(.CONNECTING);
    try socket.setState(.CONNECTED);

    // Second join
    _ = channel.join(null) catch unreachable;

    // join_ref should be different
    {
        channel.mutex.lock();
        defer channel.mutex.unlock();
        const second_ref = channel.join_ref.?;
        try testing.expect(!std.mem.eql(u8, first_ref, second_ref));
    }
}

// ----------------------------------------------------------------------------
// Edge Cases
// ----------------------------------------------------------------------------

test "join preserves topic" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const original_topic = "room:lobby:messages";
    const channel = try Channel.init(allocator, socket, original_topic);
    defer channel.deinit();

    try socket.setState(.CONNECTING);
    try socket.setState(.CONNECTED);

    _ = channel.join(null) catch unreachable;

    // Topic should be unchanged
    try testing.expectEqualStrings(original_topic, channel.topic);
}

test "join from CLOSED with concurrent state access" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    try socket.setState(.CONNECTING);
    try socket.setState(.CONNECTED);

    // Read state while joining
    const state_before = channel.getState();
    _ = channel.join(null) catch unreachable;
    const state_after = channel.getState();

    try testing.expectEqual(ChannelState.CLOSED, state_before);
    try testing.expectEqual(ChannelState.JOINING, state_after);
}
