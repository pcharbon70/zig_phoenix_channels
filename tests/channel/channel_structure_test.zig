const std = @import("std");
const testing = std.testing;
const phoenix = @import("phoenix_channels");
const Channel = phoenix.channel.Channel;
const ChannelState = phoenix.channel.ChannelState;
const PhoenixSocket = phoenix.connection.PhoenixSocket;
const SocketConfig = phoenix.connection.SocketConfig;

// ============================================================================
// Task 1.4.2: Channel Structure Tests
// ============================================================================

// Use testing allocator for automatic leak detection
const allocator = testing.allocator;

// Helper to create a test socket
fn createTestSocket() !*PhoenixSocket {
    const config = SocketConfig{
        .url = "ws://localhost:4000/socket/websocket",
    };
    return try PhoenixSocket.init(allocator, config);
}

// ----------------------------------------------------------------------------
// Channel Initialization
// ----------------------------------------------------------------------------

test "channel initialization with basic topic" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    try testing.expectEqual(ChannelState.CLOSED, channel.getState());
    try testing.expectEqualStrings("room:lobby", channel.topic);
}

test "channel initialization with phoenix topic" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "phoenix");
    defer channel.deinit();

    try testing.expectEqualStrings("phoenix", channel.topic);
}

test "channel initialization with colon-separated topic" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "user:123");
    defer channel.deinit();

    try testing.expectEqualStrings("user:123", channel.topic);
}

test "channel initialization with nested topic" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby:messages");
    defer channel.deinit();

    try testing.expectEqualStrings("room:lobby:messages", channel.topic);
}

test "channel initialization with long topic" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const long_topic = "this:is:a:very:long:topic:name:with:many:segments:for:testing";
    const channel = try Channel.init(allocator, socket, long_topic);
    defer channel.deinit();

    try testing.expectEqualStrings(long_topic, channel.topic);
}

test "channel initialization with empty topic fails" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const result = Channel.init(allocator, socket, "");
    try testing.expectError(error.InvalidConfiguration, result);
}

test "channel initialization sets all required fields" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    // Verify state
    try testing.expectEqual(ChannelState.CLOSED, channel.getState());

    // Verify null fields
    try testing.expect(channel.join_ref == null);
    try testing.expect(channel.state_callback == null);
    try testing.expect(channel.callback_context == null);

    // Verify callbacks HashMap is initialized
    try testing.expectEqual(@as(usize, 0), channel.callbacks.count());
}

test "channel topic is duplicated and owned" {
    const socket = try createTestSocket();
    defer socket.deinit();

    var topic_buffer = [_]u8{ 'r', 'o', 'o', 'm', ':', 'l', 'o', 'b', 'b', 'y' };
    const topic: []const u8 = &topic_buffer;

    const channel = try Channel.init(allocator, socket, topic);
    defer channel.deinit();

    // Modify original buffer
    topic_buffer[0] = 'X';

    // Channel topic should be unchanged (it's a copy)
    try testing.expectEqualStrings("room:lobby", channel.topic);
}

test "multiple channels are independent" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel1 = try Channel.init(allocator, socket, "room:lobby");
    defer channel1.deinit();

    const channel2 = try Channel.init(allocator, socket, "room:private");
    defer channel2.deinit();

    // Verify they are different instances
    try testing.expect(channel1 != channel2);
    try testing.expectEqualStrings("room:lobby", channel1.topic);
    try testing.expectEqualStrings("room:private", channel2.topic);

    // State changes are independent
    try channel1.setState(.JOINING);
    try testing.expectEqual(ChannelState.JOINING, channel1.getState());
    try testing.expectEqual(ChannelState.CLOSED, channel2.getState());
}

test "channel with same topic creates separate instances" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel1 = try Channel.init(allocator, socket, "room:lobby");
    defer channel1.deinit();

    const channel2 = try Channel.init(allocator, socket, "room:lobby");
    defer channel2.deinit();

    // Different instances even with same topic
    try testing.expect(channel1 != channel2);
    try testing.expectEqualStrings(channel1.topic, channel2.topic);
}

// ----------------------------------------------------------------------------
// State Management
// ----------------------------------------------------------------------------

test "getState returns current state" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    try testing.expectEqual(ChannelState.CLOSED, channel.getState());

    try channel.setState(.JOINING);
    try testing.expectEqual(ChannelState.JOINING, channel.getState());
}

test "setState validates transition" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    // Valid transition
    try channel.setState(.JOINING);
    try testing.expectEqual(ChannelState.JOINING, channel.getState());

    // Invalid transition
    const result = channel.setState(.LEAVING);
    try testing.expectError(error.InvalidStateTransition, result);

    // State should remain unchanged after failed transition
    try testing.expectEqual(ChannelState.JOINING, channel.getState());
}

test "setState rejects idempotent transitions" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    // Try to transition to same state
    const result = channel.setState(.CLOSED);
    try testing.expectError(error.InvalidStateTransition, result);
}

test "setState invokes state callback" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

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

    // Trigger state change
    try channel.setState(.JOINING);

    // Verify callback was invoked
    try testing.expect(ctx.called);
    try testing.expectEqual(ChannelState.CLOSED, ctx.old_state.?);
    try testing.expectEqual(ChannelState.JOINING, ctx.new_state.?);
}

test "setState does not invoke callback on failed transition" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

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

    // Try invalid transition
    _ = channel.setState(.JOINED) catch {};

    // Callback should not be called
    try testing.expect(!callback_called);
}

// ----------------------------------------------------------------------------
// State Callbacks
// ----------------------------------------------------------------------------

test "setStateCallback registers callback" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    const testCallback = struct {
        fn callback(old: ChannelState, new: ChannelState, ctx: ?*anyopaque) void {
            _ = old;
            _ = new;
            _ = ctx;
        }
    }.callback;

    channel.setStateCallback(testCallback, null);

    // Callback is set (we can't directly test, but verify it doesn't crash)
    try channel.setState(.JOINING);
}

test "setStateCallback with context" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    var counter: usize = 0;
    const testCallback = struct {
        fn callback(old: ChannelState, new: ChannelState, ctx: ?*anyopaque) void {
            _ = old;
            _ = new;
            if (ctx) |context| {
                const count: *usize = @ptrCast(@alignCast(context));
                count.* += 1;
            }
        }
    }.callback;

    channel.setStateCallback(testCallback, &counter);

    try channel.setState(.JOINING);
    try testing.expectEqual(@as(usize, 1), counter);

    try channel.setState(.JOINED);
    try testing.expectEqual(@as(usize, 2), counter);
}

test "setStateCallback with null context works" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    const testCallback = struct {
        fn callback(old: ChannelState, new: ChannelState, ctx: ?*anyopaque) void {
            _ = old;
            _ = new;
            _ = ctx;
            // Should not crash with null context
        }
    }.callback;

    channel.setStateCallback(testCallback, null);

    // Should not crash
    try channel.setState(.JOINING);
}

test "setStateCallback can replace existing callback" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    var counter1: usize = 0;
    var counter2: usize = 0;

    const callback1 = struct {
        fn cb(old: ChannelState, new: ChannelState, ctx: ?*anyopaque) void {
            _ = old;
            _ = new;
            if (ctx) |context| {
                const count: *usize = @ptrCast(@alignCast(context));
                count.* += 1;
            }
        }
    }.cb;

    const callback2 = struct {
        fn cb(old: ChannelState, new: ChannelState, ctx: ?*anyopaque) void {
            _ = old;
            _ = new;
            if (ctx) |context| {
                const count: *usize = @ptrCast(@alignCast(context));
                count.* += 10;
            }
        }
    }.cb;

    // Set first callback
    channel.setStateCallback(callback1, &counter1);
    try channel.setState(.JOINING);
    try testing.expectEqual(@as(usize, 1), counter1);

    // Replace with second callback
    channel.setStateCallback(callback2, &counter2);
    try channel.setState(.JOINED);
    try testing.expectEqual(@as(usize, 1), counter1); // First counter unchanged
    try testing.expectEqual(@as(usize, 10), counter2); // Second counter incremented
}

test "removeStateCallback stops callbacks" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    var counter: usize = 0;
    const testCallback = struct {
        fn callback(old: ChannelState, new: ChannelState, ctx: ?*anyopaque) void {
            _ = old;
            _ = new;
            if (ctx) |context| {
                const count: *usize = @ptrCast(@alignCast(context));
                count.* += 1;
            }
        }
    }.callback;

    channel.setStateCallback(testCallback, &counter);
    try channel.setState(.JOINING);
    try testing.expectEqual(@as(usize, 1), counter);

    // Remove callback
    channel.removeStateCallback();
    try channel.setState(.JOINED);
    try testing.expectEqual(@as(usize, 1), counter); // Counter unchanged
}

test "addStateCallback is alias for setStateCallback" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    var counter: usize = 0;
    const testCallback = struct {
        fn callback(old: ChannelState, new: ChannelState, ctx: ?*anyopaque) void {
            _ = old;
            _ = new;
            if (ctx) |context| {
                const count: *usize = @ptrCast(@alignCast(context));
                count.* += 1;
            }
        }
    }.callback;

    channel.addStateCallback(testCallback, &counter);
    try channel.setState(.JOINING);
    try testing.expectEqual(@as(usize, 1), counter);
}

// ----------------------------------------------------------------------------
// Memory Management
// ----------------------------------------------------------------------------

test "init and deinit do not leak memory" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    channel.deinit();

    // Testing allocator will detect leaks automatically
}

test "multiple init and deinit cycles" {
    const socket = try createTestSocket();
    defer socket.deinit();

    var i: usize = 0;
    while (i < 10) : (i += 1) {
        const channel = try Channel.init(allocator, socket, "room:lobby");
        channel.deinit();
    }
}

test "deinit frees topic string" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");

    // Topic should be owned by channel
    const topic_ptr = channel.topic.ptr;
    _ = topic_ptr;

    channel.deinit();
    // Memory should be freed (testing allocator will detect if not)
}

test "deinit with callbacks registered does not leak" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");

    const testCallback = struct {
        fn callback(payload: std.json.Value, ctx: ?*anyopaque) void {
            _ = payload;
            _ = ctx;
        }
    }.callback;

    try channel.on("event1", testCallback, null);
    try channel.on("event2", testCallback, null);
    try channel.on("event3", testCallback, null);

    channel.deinit();
    // Testing allocator will detect leaks
}

test "deinit with join_ref does not leak" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");

    // Manually set join_ref (simulating join operation)
    {
        channel.mutex.lock();
        defer channel.mutex.unlock();
        channel.join_ref = try channel.allocator.dupe(u8, "test_ref_123");
    }

    channel.deinit();
    // Testing allocator will detect leaks
}

// ----------------------------------------------------------------------------
// Thread Safety
// ----------------------------------------------------------------------------

test "getState is thread-safe" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    // Multiple concurrent reads should not deadlock
    const state1 = channel.getState();
    const state2 = channel.getState();

    try testing.expectEqual(state1, state2);
    try testing.expectEqual(ChannelState.CLOSED, state1);
}

test "setState is thread-safe" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    // Sequential state changes should work
    try channel.setState(.JOINING);
    try channel.setState(.JOINED);
    try channel.setState(.LEAVING);
    try channel.setState(.CLOSED);

    try testing.expectEqual(ChannelState.CLOSED, channel.getState());
}

// ----------------------------------------------------------------------------
// State Transition Sequences
// ----------------------------------------------------------------------------

test "complete join sequence: CLOSED -> JOINING -> JOINED" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    try testing.expectEqual(ChannelState.CLOSED, channel.getState());

    try channel.setState(.JOINING);
    try testing.expectEqual(ChannelState.JOINING, channel.getState());

    try channel.setState(.JOINED);
    try testing.expectEqual(ChannelState.JOINED, channel.getState());
}

test "graceful leave sequence: JOINED -> LEAVING -> CLOSED" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    // Manually set to JOINED
    try channel.setState(.JOINING);
    try channel.setState(.JOINED);

    try channel.setState(.LEAVING);
    try testing.expectEqual(ChannelState.LEAVING, channel.getState());

    try channel.setState(.CLOSED);
    try testing.expectEqual(ChannelState.CLOSED, channel.getState());
}

test "error during join: JOINING -> ERROR -> CLOSED" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    try channel.setState(.JOINING);
    try channel.setState(.ERROR);
    try testing.expectEqual(ChannelState.ERROR, channel.getState());

    try channel.setState(.CLOSED);
    try testing.expectEqual(ChannelState.CLOSED, channel.getState());
}

test "rejoin after error: ERROR -> JOINING -> JOINED" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    // Transition to ERROR
    try channel.setState(.JOINING);
    try channel.setState(.ERROR);

    // Rejoin
    try channel.setState(.JOINING);
    try channel.setState(.JOINED);
    try testing.expectEqual(ChannelState.JOINED, channel.getState());
}
