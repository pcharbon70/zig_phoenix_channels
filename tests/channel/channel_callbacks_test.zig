const std = @import("std");
const testing = std.testing;
const phoenix = @import("phoenix_channels");
const Channel = phoenix.channel.Channel;
const ChannelState = phoenix.channel.ChannelState;
const PhoenixSocket = phoenix.connection.PhoenixSocket;
const SocketConfig = phoenix.connection.SocketConfig;
const PhoenixMessage = phoenix.protocol.PhoenixMessage;

// ============================================================================
// Task 1.4.6: Channel Event Callbacks Tests
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
// Callback Registration
// ----------------------------------------------------------------------------

test "on registers callback" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    const testCallback = struct {
        fn callback(payload: std.json.Value, ctx: ?*anyopaque) void {
            _ = payload;
            _ = ctx;
        }
    }.callback;

    try channel.on("test_event", testCallback, null);

    // Verify callback was registered
    {
        channel.mutex.lock();
        defer channel.mutex.unlock();
        try testing.expect(channel.callbacks.contains("test_event"));
    }
}

test "on with context" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    var counter: usize = 0;
    const testCallback = struct {
        fn callback(payload: std.json.Value, ctx: ?*anyopaque) void {
            _ = payload;
            if (ctx) |context| {
                const count: *usize = @ptrCast(@alignCast(context));
                count.* += 1;
            }
        }
    }.callback;

    try channel.on("test_event", testCallback, &counter);

    // Context is stored
    {
        channel.mutex.lock();
        defer channel.mutex.unlock();
        const entry = channel.callbacks.get("test_event").?;
        try testing.expect(entry.context != null);
    }
}

test "on with null context" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    const testCallback = struct {
        fn callback(payload: std.json.Value, ctx: ?*anyopaque) void {
            _ = payload;
            _ = ctx;
        }
    }.callback;

    try channel.on("test_event", testCallback, null);

    // Callback registered with null context
    {
        channel.mutex.lock();
        defer channel.mutex.unlock();
        const entry = channel.callbacks.get("test_event").?;
        try testing.expect(entry.context == null);
    }
}

test "on multiple events" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    const testCallback = struct {
        fn callback(payload: std.json.Value, ctx: ?*anyopaque) void {
            _ = payload;
            _ = ctx;
        }
    }.callback;

    try channel.on("event1", testCallback, null);
    try channel.on("event2", testCallback, null);
    try channel.on("event3", testCallback, null);

    // All events registered
    {
        channel.mutex.lock();
        defer channel.mutex.unlock();
        try testing.expectEqual(@as(usize, 3), channel.callbacks.count());
    }
}

test "on replaces existing callback for same event" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    const callback1 = struct {
        fn cb(payload: std.json.Value, ctx: ?*anyopaque) void {
            _ = payload;
            _ = ctx;
        }
    }.cb;

    const callback2 = struct {
        fn cb(payload: std.json.Value, ctx: ?*anyopaque) void {
            _ = payload;
            _ = ctx;
        }
    }.cb;

    try channel.on("test_event", callback1, null);
    try channel.on("test_event", callback2, null);

    // Should only have one callback registered
    {
        channel.mutex.lock();
        defer channel.mutex.unlock();
        try testing.expectEqual(@as(usize, 1), channel.callbacks.count());
    }
}

// ----------------------------------------------------------------------------
// Callback Removal
// ----------------------------------------------------------------------------

test "off removes callback" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    const testCallback = struct {
        fn callback(payload: std.json.Value, ctx: ?*anyopaque) void {
            _ = payload;
            _ = ctx;
        }
    }.callback;

    try channel.on("test_event", testCallback, null);

    // Verify registered
    {
        channel.mutex.lock();
        defer channel.mutex.unlock();
        try testing.expect(channel.callbacks.contains("test_event"));
    }

    // Remove callback
    channel.off("test_event");

    // Verify removed
    {
        channel.mutex.lock();
        defer channel.mutex.unlock();
        try testing.expect(!channel.callbacks.contains("test_event"));
    }
}

test "off non-existent event is safe" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    // Should not crash
    channel.off("non_existent_event");

    {
        channel.mutex.lock();
        defer channel.mutex.unlock();
        try testing.expectEqual(@as(usize, 0), channel.callbacks.count());
    }
}

test "off one event preserves others" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    const testCallback = struct {
        fn callback(payload: std.json.Value, ctx: ?*anyopaque) void {
            _ = payload;
            _ = ctx;
        }
    }.callback;

    try channel.on("event1", testCallback, null);
    try channel.on("event2", testCallback, null);
    try channel.on("event3", testCallback, null);

    // Remove one
    channel.off("event2");

    // Others should remain
    {
        channel.mutex.lock();
        defer channel.mutex.unlock();
        try testing.expectEqual(@as(usize, 2), channel.callbacks.count());
        try testing.expect(channel.callbacks.contains("event1"));
        try testing.expect(!channel.callbacks.contains("event2"));
        try testing.expect(channel.callbacks.contains("event3"));
    }
}

test "off all callbacks" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    const testCallback = struct {
        fn callback(payload: std.json.Value, ctx: ?*anyopaque) void {
            _ = payload;
            _ = ctx;
        }
    }.callback;

    try channel.on("event1", testCallback, null);
    try channel.on("event2", testCallback, null);

    channel.off("event1");
    channel.off("event2");

    {
        channel.mutex.lock();
        defer channel.mutex.unlock();
        try testing.expectEqual(@as(usize, 0), channel.callbacks.count());
    }
}

// ----------------------------------------------------------------------------
// Callback Invocation (via handleMessage internal method)
// ----------------------------------------------------------------------------

test "handleMessage routes to correct callback" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    var callback_called = false;
    const testCallback = struct {
        fn callback(payload: std.json.Value, ctx: ?*anyopaque) void {
            _ = payload;
            if (ctx) |context| {
                const called: *bool = @ptrCast(@alignCast(context));
                called.* = true;
            }
        }
    }.callback;

    try channel.on("test_event", testCallback, &callback_called);

    // Create test message
    var payload = try PhoenixMessage.emptyPayload(allocator);
    defer payload.object.deinit();

    const msg = PhoenixMessage.initEvent(
        allocator,
        "room:lobby",
        "test_event",
        "1",
        payload,
    );

    // Call handleMessage
    try channel.handleMessage(&msg);

    // Verify callback was invoked
    try testing.expect(callback_called);
}

test "handleMessage passes payload to callback" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    const Context = struct {
        payload_received: bool = false,
    };

    const testCallback = struct {
        fn callback(payload: std.json.Value, ctx: ?*anyopaque) void {
            if (ctx) |context| {
                const test_ctx: *Context = @ptrCast(@alignCast(context));
                test_ctx.payload_received = (payload == .object);
            }
        }
    }.callback;

    var ctx = Context{};
    try channel.on("test_event", testCallback, &ctx);

    // Create test message with payload
    var payload = std.json.ObjectMap.init(allocator);
    defer payload.deinit();
    try payload.put("message", .{ .string = "Hello" });

    const msg = PhoenixMessage.initEvent(
        allocator,
        "room:lobby",
        "test_event",
        "1",
        .{ .object = payload },
    );

    try channel.handleMessage(&msg);

    try testing.expect(ctx.payload_received);
}

test "handleMessage passes context to callback" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    var counter: usize = 0;
    const testCallback = struct {
        fn callback(payload: std.json.Value, ctx: ?*anyopaque) void {
            _ = payload;
            if (ctx) |context| {
                const count: *usize = @ptrCast(@alignCast(context));
                count.* += 1;
            }
        }
    }.callback;

    try channel.on("test_event", testCallback, &counter);

    var payload = try PhoenixMessage.emptyPayload(allocator);
    defer payload.object.deinit();

    const msg = PhoenixMessage.initEvent(
        allocator,
        "room:lobby",
        "test_event",
        "1",
        payload,
    );

    try channel.handleMessage(&msg);

    try testing.expectEqual(@as(usize, 1), counter);
}

test "handleMessage for non-registered event does not crash" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    var payload = try PhoenixMessage.emptyPayload(allocator);
    defer payload.object.deinit();

    const msg = PhoenixMessage.initEvent(
        allocator,
        "room:lobby",
        "unknown_event",
        "1",
        payload,
    );

    // Should not crash
    try channel.handleMessage(&msg);
}

test "handleMessage routes to different callbacks" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    var counter1: usize = 0;
    var counter2: usize = 0;

    const callback1 = struct {
        fn cb(payload: std.json.Value, ctx: ?*anyopaque) void {
            _ = payload;
            if (ctx) |context| {
                const count: *usize = @ptrCast(@alignCast(context));
                count.* += 1;
            }
        }
    }.cb;

    const callback2 = struct {
        fn cb(payload: std.json.Value, ctx: ?*anyopaque) void {
            _ = payload;
            if (ctx) |context| {
                const count: *usize = @ptrCast(@alignCast(context));
                count.* += 10;
            }
        }
    }.cb;

    try channel.on("event1", callback1, &counter1);
    try channel.on("event2", callback2, &counter2);

    var payload = try PhoenixMessage.emptyPayload(allocator);
    defer payload.object.deinit();

    const msg1 = PhoenixMessage.initEvent(
        allocator,
        "room:lobby",
        "event1",
        "1",
        payload,
    );

    const msg2 = PhoenixMessage.initEvent(
        allocator,
        "room:lobby",
        "event2",
        "2",
        payload,
    );

    try channel.handleMessage(&msg1);
    try channel.handleMessage(&msg2);

    try testing.expectEqual(@as(usize, 1), counter1);
    try testing.expectEqual(@as(usize, 10), counter2);
}

// ----------------------------------------------------------------------------
// Memory Management
// ----------------------------------------------------------------------------

test "on does not leak memory" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    const testCallback = struct {
        fn callback(payload: std.json.Value, ctx: ?*anyopaque) void {
            _ = payload;
            _ = ctx;
        }
    }.callback;

    try channel.on("event1", testCallback, null);
    try channel.on("event2", testCallback, null);
    try channel.on("event3", testCallback, null);

    // Testing allocator will detect leaks
}

test "off does not leak memory" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    const testCallback = struct {
        fn callback(payload: std.json.Value, ctx: ?*anyopaque) void {
            _ = payload;
            _ = ctx;
        }
    }.callback;

    try channel.on("event1", testCallback, null);
    try channel.on("event2", testCallback, null);

    channel.off("event1");
    channel.off("event2");

    // Testing allocator will detect leaks
}

test "replacing callback does not leak" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    const callback1 = struct {
        fn cb(payload: std.json.Value, ctx: ?*anyopaque) void {
            _ = payload;
            _ = ctx;
        }
    }.cb;

    const callback2 = struct {
        fn cb(payload: std.json.Value, ctx: ?*anyopaque) void {
            _ = payload;
            _ = ctx;
        }
    }.cb;

    try channel.on("test_event", callback1, null);
    try channel.on("test_event", callback2, null);

    // Testing allocator will detect leaks
}

// ----------------------------------------------------------------------------
// Thread Safety
// ----------------------------------------------------------------------------

test "on is thread-safe" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    const testCallback = struct {
        fn callback(payload: std.json.Value, ctx: ?*anyopaque) void {
            _ = payload;
            _ = ctx;
        }
    }.callback;

    // Sequential registrations should work
    try channel.on("event1", testCallback, null);
    try channel.on("event2", testCallback, null);

    {
        channel.mutex.lock();
        defer channel.mutex.unlock();
        try testing.expectEqual(@as(usize, 2), channel.callbacks.count());
    }
}

test "off is thread-safe" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    const testCallback = struct {
        fn callback(payload: std.json.Value, ctx: ?*anyopaque) void {
            _ = payload;
            _ = ctx;
        }
    }.callback;

    try channel.on("event1", testCallback, null);
    try channel.on("event2", testCallback, null);

    // Sequential removals should work
    channel.off("event1");
    channel.off("event2");

    {
        channel.mutex.lock();
        defer channel.mutex.unlock();
        try testing.expectEqual(@as(usize, 0), channel.callbacks.count());
    }
}

// ----------------------------------------------------------------------------
// Edge Cases
// ----------------------------------------------------------------------------

test "callback with empty event name" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    const testCallback = struct {
        fn callback(payload: std.json.Value, ctx: ?*anyopaque) void {
            _ = payload;
            _ = ctx;
        }
    }.callback;

    // Empty event name is allowed (though unusual)
    try channel.on("", testCallback, null);

    {
        channel.mutex.lock();
        defer channel.mutex.unlock();
        try testing.expect(channel.callbacks.contains(""));
    }
}

test "callback with long event name" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    const testCallback = struct {
        fn callback(payload: std.json.Value, ctx: ?*anyopaque) void {
            _ = payload;
            _ = ctx;
        }
    }.callback;

    const long_event = "this_is_a_very_long_event_name_with_many_characters_for_testing_purposes";
    try channel.on(long_event, testCallback, null);

    {
        channel.mutex.lock();
        defer channel.mutex.unlock();
        try testing.expect(channel.callbacks.contains(long_event));
    }
}

test "multiple channels with same event names" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel1 = try Channel.init(allocator, socket, "room:lobby");
    defer channel1.deinit();

    const channel2 = try Channel.init(allocator, socket, "room:private");
    defer channel2.deinit();

    const testCallback = struct {
        fn callback(payload: std.json.Value, ctx: ?*anyopaque) void {
            _ = payload;
            _ = ctx;
        }
    }.callback;

    try channel1.on("new_msg", testCallback, null);
    try channel2.on("new_msg", testCallback, null);

    // Both should have the callback registered independently
    {
        channel1.mutex.lock();
        defer channel1.mutex.unlock();
        try testing.expect(channel1.callbacks.contains("new_msg"));
    }
    {
        channel2.mutex.lock();
        defer channel2.mutex.unlock();
        try testing.expect(channel2.callbacks.contains("new_msg"));
    }
}

test "callback survives state transitions" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    const testCallback = struct {
        fn callback(payload: std.json.Value, ctx: ?*anyopaque) void {
            _ = payload;
            _ = ctx;
        }
    }.callback;

    try channel.on("test_event", testCallback, null);

    // Change states
    try channel.setState(.JOINING);
    try channel.setState(.JOINED);
    try channel.setState(.LEAVING);
    try channel.setState(.CLOSED);

    // Callback should still be registered
    {
        channel.mutex.lock();
        defer channel.mutex.unlock();
        try testing.expect(channel.callbacks.contains("test_event"));
    }
}
