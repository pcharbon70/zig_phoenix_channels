const std = @import("std");
const testing = std.testing;
const phoenix = @import("phoenix_channels");
const PhoenixSocket = phoenix.connection.PhoenixSocket;
const Config = phoenix.connection.SocketConfig;
const PhoenixMessage = phoenix.protocol.PhoenixMessage;
const ConnectionState = phoenix.common.ConnectionState;

// ============================================================================
// Task 1.3.4: Message Sending Tests
// ============================================================================

const allocator = testing.allocator;

// ----------------------------------------------------------------------------
// Error Cases: Invalid States
// ----------------------------------------------------------------------------

test "send: returns error when DISCONNECTED" {
    const config = Config{
        .url = "ws://localhost:4000/socket/websocket",
    };

    const skt = try PhoenixSocket.init(allocator, config);
    defer skt.deinit();

    // Create a valid message
    var payload = std.json.ObjectMap.init(allocator);
    defer payload.deinit();

    const ref = try skt.nextRefString();
    defer allocator.free(ref);

    const msg = PhoenixMessage{
        .allocator = allocator,
        .join_ref = null,
        .ref = ref,
        .topic = "room:lobby",
        .event = "new_msg",
        .payload = .{ .object = payload },
    };

    // Should fail because state is DISCONNECTED
    const result = skt.send(&msg);
    try testing.expectError(error.NotConnected, result);
}

test "send: returns error when CONNECTING" {
    const config = Config{
        .url = "ws://localhost:4000/socket/websocket",
    };

    const skt = try PhoenixSocket.init(allocator, config);
    defer skt.deinit();

    // Set state to CONNECTING
    {
        skt.mutex.lock();
        defer skt.mutex.unlock();
        skt.state = .CONNECTING;
    }

    // Create a valid message
    var payload = std.json.ObjectMap.init(allocator);
    defer payload.deinit();

    const ref = try skt.nextRefString();
    defer allocator.free(ref);

    const msg = PhoenixMessage{
        .allocator = allocator,
        .join_ref = null,
        .ref = ref,
        .topic = "room:lobby",
        .event = "new_msg",
        .payload = .{ .object = payload },
    };

    // Should fail because state is CONNECTING (not yet CONNECTED)
    const result = skt.send(&msg);
    try testing.expectError(error.NotConnected, result);
}

test "send: returns error when CLOSING" {
    const config = Config{
        .url = "ws://localhost:4000/socket/websocket",
    };

    const skt = try PhoenixSocket.init(allocator, config);
    defer skt.deinit();

    // Set state to CLOSING
    {
        skt.mutex.lock();
        defer skt.mutex.unlock();
        skt.state = .CLOSING;
    }

    // Create a valid message
    var payload = std.json.ObjectMap.init(allocator);
    defer payload.deinit();

    const ref = try skt.nextRefString();
    defer allocator.free(ref);

    const msg = PhoenixMessage{
        .allocator = allocator,
        .join_ref = null,
        .ref = ref,
        .topic = "room:lobby",
        .event = "new_msg",
        .payload = .{ .object = payload },
    };

    // Should fail because state is CLOSING
    const result = skt.send(&msg);
    try testing.expectError(error.NotConnected, result);
}

test "send: returns error when ERROR" {
    const config = Config{
        .url = "ws://localhost:4000/socket/websocket",
    };

    const skt = try PhoenixSocket.init(allocator, config);
    defer skt.deinit();

    // Set state to ERROR
    {
        skt.mutex.lock();
        defer skt.mutex.unlock();
        skt.state = .ERROR;
    }

    // Create a valid message
    var payload = std.json.ObjectMap.init(allocator);
    defer payload.deinit();

    const ref = try skt.nextRefString();
    defer allocator.free(ref);

    const msg = PhoenixMessage{
        .allocator = allocator,
        .join_ref = null,
        .ref = ref,
        .topic = "room:lobby",
        .event = "new_msg",
        .payload = .{ .object = payload },
    };

    // Should fail because state is ERROR
    const result = skt.send(&msg);
    try testing.expectError(error.NotConnected, result);
}

test "send: returns error when ws_client is null despite CONNECTED state" {
    const config = Config{
        .url = "ws://localhost:4000/socket/websocket",
    };

    const skt = try PhoenixSocket.init(allocator, config);
    defer skt.deinit();

    // Manually set state to CONNECTED without actual connection
    // This simulates a race condition
    {
        skt.mutex.lock();
        defer skt.mutex.unlock();
        skt.state = .CONNECTED;
        // ws_client remains null
    }

    // Create a valid message
    var payload = std.json.ObjectMap.init(allocator);
    defer payload.deinit();

    const ref = try skt.nextRefString();
    defer allocator.free(ref);

    const msg = PhoenixMessage{
        .allocator = allocator,
        .join_ref = null,
        .ref = ref,
        .topic = "room:lobby",
        .event = "new_msg",
        .payload = .{ .object = payload },
    };

    // Should fail because ws_client is null
    const result = skt.send(&msg);
    try testing.expectError(error.NotConnected, result);
}

// ----------------------------------------------------------------------------
// Message Validation
// ----------------------------------------------------------------------------

test "send: validates message before sending" {
    const config = Config{
        .url = "ws://localhost:4000/socket/websocket",
    };

    const skt = try PhoenixSocket.init(allocator, config);
    defer skt.deinit();

    // Set state to CONNECTED
    {
        skt.mutex.lock();
        defer skt.mutex.unlock();
        skt.state = .CONNECTED;
    }

    // Create invalid message (missing ref)
    var payload = std.json.ObjectMap.init(allocator);
    defer payload.deinit();

    const invalid_msg = PhoenixMessage{
        .allocator = allocator,
        .join_ref = null,
        .ref = null, // Invalid: missing ref
        .topic = "room:lobby",
        .event = "new_msg",
        .payload = .{ .object = payload },
    };

    // Should fail validation
    const result = skt.send(&invalid_msg);
    try testing.expectError(error.ValidationError, result);
}

test "send: requires object payload" {
    const config = Config{
        .url = "ws://localhost:4000/socket/websocket",
    };

    const skt = try PhoenixSocket.init(allocator, config);
    defer skt.deinit();

    // Set state to CONNECTED
    {
        skt.mutex.lock();
        defer skt.mutex.unlock();
        skt.state = .CONNECTED;
    }

    const ref = try skt.nextRefString();
    defer allocator.free(ref);

    // Create message with primitive payload (invalid)
    const invalid_msg = PhoenixMessage{
        .allocator = allocator,
        .join_ref = null,
        .ref = ref,
        .topic = "room:lobby",
        .event = "new_msg",
        .payload = .{ .string = "invalid" }, // Should be object
    };

    // Should fail validation
    const result = skt.send(&invalid_msg);
    try testing.expectError(error.ValidationError, result);
}

test "send: validates topic is not empty" {
    const config = Config{
        .url = "ws://localhost:4000/socket/websocket",
    };

    const skt = try PhoenixSocket.init(allocator, config);
    defer skt.deinit();

    // Set state to CONNECTED
    {
        skt.mutex.lock();
        defer skt.mutex.unlock();
        skt.state = .CONNECTED;
    }

    var payload = std.json.ObjectMap.init(allocator);
    defer payload.deinit();

    const ref = try skt.nextRefString();
    defer allocator.free(ref);

    const invalid_msg = PhoenixMessage{
        .allocator = allocator,
        .join_ref = null,
        .ref = ref,
        .topic = "", // Empty topic
        .event = "new_msg",
        .payload = .{ .object = payload },
    };

    // Should fail validation
    const result = skt.send(&invalid_msg);
    try testing.expectError(error.ValidationError, result);
}

test "send: validates event is not empty" {
    const config = Config{
        .url = "ws://localhost:4000/socket/websocket",
    };

    const skt = try PhoenixSocket.init(allocator, config);
    defer skt.deinit();

    // Set state to CONNECTED
    {
        skt.mutex.lock();
        defer skt.mutex.unlock();
        skt.state = .CONNECTED;
    }

    var payload = std.json.ObjectMap.init(allocator);
    defer payload.deinit();

    const ref = try skt.nextRefString();
    defer allocator.free(ref);

    const invalid_msg = PhoenixMessage{
        .allocator = allocator,
        .join_ref = null,
        .ref = ref,
        .topic = "room:lobby",
        .event = "", // Empty event
        .payload = .{ .object = payload },
    };

    // Should fail validation
    const result = skt.send(&invalid_msg);
    try testing.expectError(error.ValidationError, result);
}

test "send: validates phx_join requires join_ref" {
    const config = Config{
        .url = "ws://localhost:4000/socket/websocket",
    };

    const skt = try PhoenixSocket.init(allocator, config);
    defer skt.deinit();

    // Set state to CONNECTED
    {
        skt.mutex.lock();
        defer skt.mutex.unlock();
        skt.state = .CONNECTED;
    }

    var payload = std.json.ObjectMap.init(allocator);
    defer payload.deinit();

    const ref = try skt.nextRefString();
    defer allocator.free(ref);

    const invalid_msg = PhoenixMessage{
        .allocator = allocator,
        .join_ref = null, // Missing join_ref for phx_join
        .ref = ref,
        .topic = "room:lobby",
        .event = "phx_join",
        .payload = .{ .object = payload },
    };

    // Should fail validation
    const result = skt.send(&invalid_msg);
    try testing.expectError(error.ValidationError, result);
}

// ----------------------------------------------------------------------------
// Valid Message Construction
// ----------------------------------------------------------------------------

test "valid message: regular channel message" {
    var payload = std.json.ObjectMap.init(allocator);
    defer payload.deinit();

    try payload.put("user_id", .{ .string = "123" });
    try payload.put("text", .{ .string = "Hello" });

    const config = Config{
        .url = "ws://localhost:4000/socket/websocket",
    };

    const skt = try PhoenixSocket.init(allocator, config);
    defer skt.deinit();

    const ref = try skt.nextRefString();
    defer allocator.free(ref);

    const msg = PhoenixMessage{
        .allocator = allocator,
        .join_ref = null,
        .ref = ref,
        .topic = "room:lobby",
        .event = "new_msg",
        .payload = .{ .object = payload },
    };

    // Message should be valid (validation happens in send())
    try msg.validateForSend();
}

test "valid message: phx_join with join_ref" {
    var payload = std.json.ObjectMap.init(allocator);
    defer payload.deinit();

    const config = Config{
        .url = "ws://localhost:4000/socket/websocket",
    };

    const skt = try PhoenixSocket.init(allocator, config);
    defer skt.deinit();

    const join_ref = try skt.nextRefString();
    defer allocator.free(join_ref);

    const ref = try skt.nextRefString();
    defer allocator.free(ref);

    const msg = PhoenixMessage{
        .allocator = allocator,
        .join_ref = join_ref,
        .ref = ref,
        .topic = "room:lobby",
        .event = "phx_join",
        .payload = .{ .object = payload },
    };

    // Message should be valid
    try msg.validateForSend();
}

test "valid message: heartbeat" {
    var payload = std.json.ObjectMap.init(allocator);
    defer payload.deinit();

    const config = Config{
        .url = "ws://localhost:4000/socket/websocket",
    };

    const skt = try PhoenixSocket.init(allocator, config);
    defer skt.deinit();

    const ref = try skt.nextRefString();
    defer allocator.free(ref);

    const msg = PhoenixMessage{
        .allocator = allocator,
        .join_ref = null,
        .ref = ref,
        .topic = "phoenix",
        .event = "heartbeat",
        .payload = .{ .object = payload },
    };

    // Message should be valid
    try msg.validateForSend();
}

test "valid message: phx_leave" {
    var payload = std.json.ObjectMap.init(allocator);
    defer payload.deinit();

    const config = Config{
        .url = "ws://localhost:4000/socket/websocket",
    };

    const skt = try PhoenixSocket.init(allocator, config);
    defer skt.deinit();

    const ref = try skt.nextRefString();
    defer allocator.free(ref);

    const msg = PhoenixMessage{
        .allocator = allocator,
        .join_ref = null,
        .ref = ref,
        .topic = "room:lobby",
        .event = "phx_leave",
        .payload = .{ .object = payload },
    };

    // Message should be valid
    try msg.validateForSend();
}

// ----------------------------------------------------------------------------
// Reference Generation Integration
// ----------------------------------------------------------------------------

test "send: uses unique references for each message" {
    const config = Config{
        .url = "ws://localhost:4000/socket/websocket",
    };

    const skt = try PhoenixSocket.init(allocator, config);
    defer skt.deinit();

    const ref1 = try skt.nextRefString();
    defer allocator.free(ref1);

    const ref2 = try skt.nextRefString();
    defer allocator.free(ref2);

    const ref3 = try skt.nextRefString();
    defer allocator.free(ref3);

    // All refs should be unique
    try testing.expect(!std.mem.eql(u8, ref1, ref2));
    try testing.expect(!std.mem.eql(u8, ref2, ref3));
    try testing.expect(!std.mem.eql(u8, ref1, ref3));

    try testing.expectEqualStrings("1", ref1);
    try testing.expectEqualStrings("2", ref2);
    try testing.expectEqualStrings("3", ref3);
}

test "send: references are sequential" {
    const config = Config{
        .url = "ws://localhost:4000/socket/websocket",
    };

    const skt = try PhoenixSocket.init(allocator, config);
    defer skt.deinit();

    var refs: [10][]u8 = undefined;
    for (&refs) |*ref| {
        ref.* = try skt.nextRefString();
    }
    defer for (refs) |ref| allocator.free(ref);

    // Verify sequence
    for (refs, 0..) |ref, i| {
        const expected = try std.fmt.allocPrint(allocator, "{d}", .{i + 1});
        defer allocator.free(expected);
        try testing.expectEqualStrings(expected, ref);
    }
}

// ----------------------------------------------------------------------------
// Edge Cases
// ----------------------------------------------------------------------------

test "send: empty payload object is valid" {
    var payload = std.json.ObjectMap.init(allocator);
    defer payload.deinit();

    const config = Config{
        .url = "ws://localhost:4000/socket/websocket",
    };

    const skt = try PhoenixSocket.init(allocator, config);
    defer skt.deinit();

    const ref = try skt.nextRefString();
    defer allocator.free(ref);

    const msg = PhoenixMessage{
        .allocator = allocator,
        .join_ref = null,
        .ref = ref,
        .topic = "room:lobby",
        .event = "ping",
        .payload = .{ .object = payload },
    };

    // Empty payload object should be valid
    try msg.validateForSend();
}

test "send: large payload" {
    var payload = std.json.ObjectMap.init(allocator);
    defer payload.deinit();

    // Add many fields
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        const key = try std.fmt.allocPrint(allocator, "field_{d}", .{i});
        defer allocator.free(key);

        const value = try std.fmt.allocPrint(allocator, "value_{d}", .{i});
        defer allocator.free(value);

        const owned_key = try allocator.dupe(u8, key);
        errdefer allocator.free(owned_key);

        const owned_value = try allocator.dupe(u8, value);
        errdefer allocator.free(owned_value);

        try payload.put(owned_key, .{ .string = owned_value });
    }

    const config = Config{
        .url = "ws://localhost:4000/socket/websocket",
    };

    const skt = try PhoenixSocket.init(allocator, config);
    defer skt.deinit();

    const ref = try skt.nextRefString();
    defer allocator.free(ref);

    const msg = PhoenixMessage{
        .allocator = allocator,
        .join_ref = null,
        .ref = ref,
        .topic = "room:lobby",
        .event = "bulk_data",
        .payload = .{ .object = payload },
    };

    // Large payload should still be valid
    try msg.validateForSend();
}

test "send: topic with special characters" {
    var payload = std.json.ObjectMap.init(allocator);
    defer payload.deinit();

    const config = Config{
        .url = "ws://localhost:4000/socket/websocket",
    };

    const skt = try PhoenixSocket.init(allocator, config);
    defer skt.deinit();

    const ref = try skt.nextRefString();
    defer allocator.free(ref);

    const msg = PhoenixMessage{
        .allocator = allocator,
        .join_ref = null,
        .ref = ref,
        .topic = "room:lobby:123:sub-topic",
        .event = "msg",
        .payload = .{ .object = payload },
    };

    // Should be valid
    try msg.validateForSend();
}
