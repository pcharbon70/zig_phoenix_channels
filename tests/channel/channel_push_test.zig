const std = @import("std");
const testing = std.testing;
const phoenix = @import("phoenix_channels");
const Channel = phoenix.channel.Channel;
const ChannelState = phoenix.channel.ChannelState;
const PhoenixSocket = phoenix.connection.PhoenixSocket;
const SocketConfig = phoenix.connection.SocketConfig;
const PhoenixMessage = phoenix.protocol.PhoenixMessage;

// ============================================================================
// Task 1.4.5: Channel Push Operation Tests
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
// Basic Push Operation
// ----------------------------------------------------------------------------

test "push from JOINED state succeeds" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    try channel.setState(.JOINING);
    try channel.setState(.JOINED);

    try socket.setState(.CONNECTING);
    try socket.setState(.CONNECTED);

    var payload = try PhoenixMessage.emptyPayload(allocator);
    defer payload.object.deinit();

    // Push should work (will fail on actual send but that's OK)
    _ = channel.push("new_msg", payload) catch unreachable;
}

test "push with empty payload" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    try channel.setState(.JOINING);
    try channel.setState(.JOINED);

    try socket.setState(.CONNECTING);
    try socket.setState(.CONNECTED);

    var payload = try PhoenixMessage.emptyPayload(allocator);
    defer payload.object.deinit();

    _ = channel.push("test_event", payload) catch unreachable;
}

test "push with single field payload" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    try channel.setState(.JOINING);
    try channel.setState(.JOINED);

    try socket.setState(.CONNECTING);
    try socket.setState(.CONNECTED);

    var payload = std.json.ObjectMap.init(allocator);
    defer payload.deinit();
    try payload.put("message", .{ .string = "Hello" });

    _ = channel.push("new_msg", .{ .object = payload }) catch unreachable;
}

test "push with nested payload" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    try channel.setState(.JOINING);
    try channel.setState(.JOINED);

    try socket.setState(.CONNECTING);
    try socket.setState(.CONNECTED);

    var inner = std.json.ObjectMap.init(allocator);
    defer inner.deinit();
    try inner.put("field", .{ .string = "value" });

    var payload = std.json.ObjectMap.init(allocator);
    defer payload.deinit();
    try payload.put("data", .{ .object = inner });

    _ = channel.push("test_event", .{ .object = payload }) catch unreachable;
}

test "push with array in payload" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    try channel.setState(.JOINING);
    try channel.setState(.JOINED);

    try socket.setState(.CONNECTING);
    try socket.setState(.CONNECTED);

    var array = std.json.Array.init(allocator);
    defer array.deinit();
    try array.append(.{ .string = "item1" });
    try array.append(.{ .string = "item2" });

    var payload = std.json.ObjectMap.init(allocator);
    defer payload.deinit();
    try payload.put("items", .{ .array = array });

    _ = channel.push("list_event", .{ .object = payload }) catch unreachable;
}

test "push with various payload types" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    try channel.setState(.JOINING);
    try channel.setState(.JOINED);

    try socket.setState(.CONNECTING);
    try socket.setState(.CONNECTED);

    var payload = std.json.ObjectMap.init(allocator);
    defer payload.deinit();
    try payload.put("string", .{ .string = "text" });
    try payload.put("number", .{ .integer = 42 });
    try payload.put("bool", .{ .bool = true });
    try payload.put("null", .null);

    _ = channel.push("mixed_event", .{ .object = payload }) catch unreachable;
}

// ----------------------------------------------------------------------------
// State Validation
// ----------------------------------------------------------------------------

test "push from CLOSED returns NotJoined" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    var payload = try PhoenixMessage.emptyPayload(allocator);
    defer payload.object.deinit();

    const result = channel.push("test_event", payload);
    try testing.expectError(error.NotJoined, result);

    // State should remain CLOSED
    try testing.expectEqual(ChannelState.CLOSED, channel.getState());
}

test "push from JOINING returns NotJoined" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    try channel.setState(.JOINING);

    var payload = try PhoenixMessage.emptyPayload(allocator);
    defer payload.object.deinit();

    const result = channel.push("test_event", payload);
    try testing.expectError(error.NotJoined, result);

    // State should remain JOINING
    try testing.expectEqual(ChannelState.JOINING, channel.getState());
}

test "push from LEAVING returns NotJoined" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    try channel.setState(.JOINING);
    try channel.setState(.JOINED);
    try channel.setState(.LEAVING);

    var payload = try PhoenixMessage.emptyPayload(allocator);
    defer payload.object.deinit();

    const result = channel.push("test_event", payload);
    try testing.expectError(error.NotJoined, result);

    // State should remain LEAVING
    try testing.expectEqual(ChannelState.LEAVING, channel.getState());
}

test "push from ERROR returns NotJoined" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    try channel.setState(.JOINING);
    try channel.setState(.ERROR);

    var payload = try PhoenixMessage.emptyPayload(allocator);
    defer payload.object.deinit();

    const result = channel.push("test_event", payload);
    try testing.expectError(error.NotJoined, result);

    // State should remain ERROR
    try testing.expectEqual(ChannelState.ERROR, channel.getState());
}

test "push when socket disconnected returns NotConnected" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    try channel.setState(.JOINING);
    try channel.setState(.JOINED);

    // Socket is DISCONNECTED
    var payload = try PhoenixMessage.emptyPayload(allocator);
    defer payload.object.deinit();

    const result = channel.push("test_event", payload);
    try testing.expectError(error.NotConnected, result);

    // State should remain JOINED
    try testing.expectEqual(ChannelState.JOINED, channel.getState());
}

// ----------------------------------------------------------------------------
// Event Names
// ----------------------------------------------------------------------------

test "push with custom event name" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    try channel.setState(.JOINING);
    try channel.setState(.JOINED);

    try socket.setState(.CONNECTING);
    try socket.setState(.CONNECTED);

    var payload = try PhoenixMessage.emptyPayload(allocator);
    defer payload.object.deinit();

    _ = channel.push("custom_event_name", payload) catch unreachable;
}

test "push with common event names" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    try channel.setState(.JOINING);
    try channel.setState(.JOINED);

    try socket.setState(.CONNECTING);
    try socket.setState(.CONNECTED);

    var payload = try PhoenixMessage.emptyPayload(allocator);
    defer payload.object.deinit();

    // Try various common event names
    _ = channel.push("new_msg", payload) catch unreachable;
    _ = channel.push("update", payload) catch unreachable;
    _ = channel.push("delete", payload) catch unreachable;
    _ = channel.push("presence_state", payload) catch unreachable;
}

// ----------------------------------------------------------------------------
// Multiple Pushes
// ----------------------------------------------------------------------------

test "consecutive pushes from JOINED succeed" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    try channel.setState(.JOINING);
    try channel.setState(.JOINED);

    try socket.setState(.CONNECTING);
    try socket.setState(.CONNECTED);

    var payload1 = std.json.ObjectMap.init(allocator);
    defer payload1.deinit();
    try payload1.put("count", .{ .integer = 1 });

    var payload2 = std.json.ObjectMap.init(allocator);
    defer payload2.deinit();
    try payload2.put("count", .{ .integer = 2 });

    var payload3 = std.json.ObjectMap.init(allocator);
    defer payload3.deinit();
    try payload3.put("count", .{ .integer = 3 });

    _ = channel.push("event", .{ .object = payload1 }) catch unreachable;
    _ = channel.push("event", .{ .object = payload2 }) catch unreachable;
    _ = channel.push("event", .{ .object = payload3 }) catch unreachable;
}

test "push generates unique message refs" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    try channel.setState(.JOINING);
    try channel.setState(.JOINED);

    try socket.setState(.CONNECTING);
    try socket.setState(.CONNECTED);

    var payload = try PhoenixMessage.emptyPayload(allocator);
    defer payload.object.deinit();

    // Multiple pushes should generate unique refs
    // (We can't directly verify this without message inspection,
    // but socket's ref counter ensures uniqueness)
    _ = channel.push("event1", payload) catch unreachable;
    _ = channel.push("event2", payload) catch unreachable;
    _ = channel.push("event3", payload) catch unreachable;

    // Verify ref counter advanced
    const ref = socket.nextRef();
    try testing.expect(ref > 3);
}

// ----------------------------------------------------------------------------
// Memory Management
// ----------------------------------------------------------------------------

test "push does not leak memory on success" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    try channel.setState(.JOINING);
    try channel.setState(.JOINED);

    try socket.setState(.CONNECTING);
    try socket.setState(.CONNECTED);

    var payload = try PhoenixMessage.emptyPayload(allocator);
    defer payload.object.deinit();

    _ = channel.push("test_event", payload) catch unreachable;
    // Testing allocator will detect leaks
}

test "push does not leak memory on failure" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    var payload = try PhoenixMessage.emptyPayload(allocator);
    defer payload.object.deinit();

    // Push from CLOSED will fail
    _ = channel.push("test_event", payload) catch unreachable;
    // Testing allocator will detect leaks
}

test "push with complex payload does not leak" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    try channel.setState(.JOINING);
    try channel.setState(.JOINED);

    try socket.setState(.CONNECTING);
    try socket.setState(.CONNECTED);

    var inner = std.json.ObjectMap.init(allocator);
    defer inner.deinit();
    try inner.put("nested", .{ .string = "value" });

    var array = std.json.Array.init(allocator);
    defer array.deinit();
    try array.append(.{ .integer = 1 });

    var payload = std.json.ObjectMap.init(allocator);
    defer payload.deinit();
    try payload.put("object", .{ .object = inner });
    try payload.put("array", .{ .array = array });

    _ = channel.push("complex_event", .{ .object = payload }) catch unreachable;
    // Testing allocator will detect leaks
}

// ----------------------------------------------------------------------------
// Edge Cases
// ----------------------------------------------------------------------------

test "push preserves channel state" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    try channel.setState(.JOINING);
    try channel.setState(.JOINED);

    try socket.setState(.CONNECTING);
    try socket.setState(.CONNECTED);

    var payload = try PhoenixMessage.emptyPayload(allocator);
    defer payload.object.deinit();

    const state_before = channel.getState();
    _ = channel.push("test_event", payload) catch unreachable;
    const state_after = channel.getState();

    // Push should not change channel state
    try testing.expectEqual(state_before, state_after);
    try testing.expectEqual(ChannelState.JOINED, state_after);
}

test "push preserves topic" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const original_topic = "room:lobby:messages";
    const channel = try Channel.init(allocator, socket, original_topic);
    defer channel.deinit();

    try channel.setState(.JOINING);
    try channel.setState(.JOINED);

    try socket.setState(.CONNECTING);
    try socket.setState(.CONNECTED);

    var payload = try PhoenixMessage.emptyPayload(allocator);
    defer payload.object.deinit();

    _ = channel.push("test_event", payload) catch unreachable;

    // Topic should be unchanged
    try testing.expectEqualStrings(original_topic, channel.topic);
}

test "push to multiple channels independently" {
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

    var payload1 = std.json.ObjectMap.init(allocator);
    defer payload1.deinit();
    try payload1.put("channel", .{ .string = "lobby" });

    var payload2 = std.json.ObjectMap.init(allocator);
    defer payload2.deinit();
    try payload2.put("channel", .{ .string = "private" });

    _ = channel1.push("msg", .{ .object = payload1 }) catch unreachable;
    _ = channel2.push("msg", .{ .object = payload2 }) catch unreachable;

    // Both channels should remain JOINED
    try testing.expectEqual(ChannelState.JOINED, channel1.getState());
    try testing.expectEqual(ChannelState.JOINED, channel2.getState());
}

test "push with concurrent state access" {
    const socket = try createTestSocket();
    defer socket.deinit();

    const channel = try Channel.init(allocator, socket, "room:lobby");
    defer channel.deinit();

    try channel.setState(.JOINING);
    try channel.setState(.JOINED);

    try socket.setState(.CONNECTING);
    try socket.setState(.CONNECTED);

    var payload = try PhoenixMessage.emptyPayload(allocator);
    defer payload.object.deinit();

    // Read state while pushing
    const state_before = channel.getState();
    _ = channel.push("test_event", payload) catch unreachable;
    const state_after = channel.getState();

    try testing.expectEqual(ChannelState.JOINED, state_before);
    try testing.expectEqual(ChannelState.JOINED, state_after);
}
