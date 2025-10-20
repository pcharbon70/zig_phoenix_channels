const std = @import("std");
const testing = std.testing;
const phoenix = @import("phoenix_channels");
const PhoenixSocket = phoenix.connection.PhoenixSocket;
const Config = phoenix.connection.SocketConfig;
const ConnectionState = phoenix.connection.ConnectionState;

// ============================================================================
// Task 1.3.2: Socket Structure Tests
// ============================================================================

// Use testing allocator for automatic leak detection
const allocator = testing.allocator;

// ----------------------------------------------------------------------------
// Socket Initialization
// ----------------------------------------------------------------------------

test "socket initialization with default config" {
    const config = Config{
        .url = "ws://localhost:4000/socket/websocket",
    };

    const skt = try PhoenixSocket.init(allocator, config);
    defer skt.deinit();

    try testing.expectEqual(ConnectionState.DISCONNECTED, skt.state);
    try testing.expectEqualStrings("ws://localhost:4000/socket/websocket", skt.config.url);
    try testing.expectEqual(@as(u32, 30000), skt.config.heartbeat_interval_ms);
    try testing.expectEqual(@as(u32, 10000), skt.config.timeout_ms);
}

test "socket initialization with custom config" {
    const config = Config{
        .url = "wss://example.com:8443/socket",
        .heartbeat_interval_ms = 60000,
        .timeout_ms = 5000,
    };

    const skt = try PhoenixSocket.init(allocator, config);
    defer skt.deinit();

    try testing.expectEqual(ConnectionState.DISCONNECTED, skt.state);
    try testing.expectEqualStrings("wss://example.com:8443/socket", skt.config.url);
    try testing.expectEqual(@as(u32, 60000), skt.config.heartbeat_interval_ms);
    try testing.expectEqual(@as(u32, 5000), skt.config.timeout_ms);
}

test "socket initialization sets all required fields" {
    const config = Config{
        .url = "ws://localhost:4000/socket/websocket",
    };

    const skt = try PhoenixSocket.init(allocator, config);
    defer skt.deinit();

    // Verify state
    try testing.expectEqual(ConnectionState.DISCONNECTED, skt.state);

    // Verify null fields
    try testing.expect(skt.ws_client == null);
    try testing.expect(skt.state_callback == null);
    try testing.expect(skt.callback_context == null);
}

test "socket initialization with minimal config" {
    const config = Config{
        .url = "ws://localhost:4000",
    };

    const skt = try PhoenixSocket.init(allocator, config);
    defer skt.deinit();

    try testing.expectEqual(ConnectionState.DISCONNECTED, skt.state);
}

test "multiple socket instances are independent" {
    const config1 = Config{
        .url = "ws://localhost:4000/socket1",
    };
    const config2 = Config{
        .url = "ws://localhost:5000/socket2",
    };

    const skt1 = try PhoenixSocket.init(allocator, config1);
    defer skt1.deinit();

    const skt2 = try PhoenixSocket.init(allocator, config2);
    defer skt2.deinit();

    // Verify they are different instances
    try testing.expect(skt1 != skt2);
    try testing.expectEqualStrings("ws://localhost:4000/socket1", skt1.config.url);
    try testing.expectEqualStrings("ws://localhost:5000/socket2", skt2.config.url);

    // Reference counters are independent
    const ref1 = skt1.nextRef();
    const ref2 = skt2.nextRef();
    try testing.expectEqual(@as(usize, 1), ref1);
    try testing.expectEqual(@as(usize, 1), ref2);
}

// ----------------------------------------------------------------------------
// Reference Counter (Task 1.3.6)
// ----------------------------------------------------------------------------

test "reference counter generates unique numeric IDs" {
    const config = Config{
        .url = "ws://localhost:4000/socket/websocket",
    };

    const skt = try PhoenixSocket.init(allocator, config);
    defer skt.deinit();

    const ref1 = skt.nextRef();
    const ref2 = skt.nextRef();
    const ref3 = skt.nextRef();

    try testing.expectEqual(@as(usize, 1), ref1);
    try testing.expectEqual(@as(usize, 2), ref2);
    try testing.expectEqual(@as(usize, 3), ref3);
}

test "reference counter generates unique string IDs" {
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

    try testing.expectEqualStrings("1", ref1);
    try testing.expectEqualStrings("2", ref2);
    try testing.expectEqualStrings("3", ref3);
}

test "reference counter is monotonically increasing" {
    const config = Config{
        .url = "ws://localhost:4000/socket/websocket",
    };

    const skt = try PhoenixSocket.init(allocator, config);
    defer skt.deinit();

    var prev_ref: usize = 0;
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        const ref = skt.nextRef();
        try testing.expect(ref > prev_ref);
        prev_ref = ref;
    }
}

test "reference counter starts at 1" {
    const config = Config{
        .url = "ws://localhost:4000/socket/websocket",
    };

    const skt = try PhoenixSocket.init(allocator, config);
    defer skt.deinit();

    const first_ref = skt.nextRef();
    try testing.expectEqual(@as(usize, 1), first_ref);
}

test "string references match numeric references" {
    const config = Config{
        .url = "ws://localhost:4000/socket/websocket",
    };

    const skt = try PhoenixSocket.init(allocator, config);
    defer skt.deinit();

    const num_ref = skt.nextRef();
    const str_ref = try skt.nextRefString();
    defer allocator.free(str_ref);

    const expected = try std.fmt.allocPrint(allocator, "{d}", .{num_ref});
    defer allocator.free(expected);

    // String ref should be one ahead since nextRefString() also increments
    const next_expected = try std.fmt.allocPrint(allocator, "{d}", .{num_ref + 1});
    defer allocator.free(next_expected);

    try testing.expectEqualStrings(next_expected, str_ref);
}

// ----------------------------------------------------------------------------
// URL Parsing
// ----------------------------------------------------------------------------

test "URL parsing: ws with port and path" {
    const config = Config{
        .url = "ws://localhost:4000/socket/websocket",
    };

    const skt = try PhoenixSocket.init(allocator, config);
    defer skt.deinit();

    try testing.expectEqualStrings("ws://localhost:4000/socket/websocket", skt.config.url);
}

test "URL parsing: wss with port and path" {
    const config = Config{
        .url = "wss://example.com:443/socket",
    };

    const skt = try PhoenixSocket.init(allocator, config);
    defer skt.deinit();

    try testing.expectEqualStrings("wss://example.com:443/socket", skt.config.url);
}

test "URL parsing: ws without port" {
    const config = Config{
        .url = "ws://localhost/socket",
    };

    const skt = try PhoenixSocket.init(allocator, config);
    defer skt.deinit();

    try testing.expectEqualStrings("ws://localhost/socket", skt.config.url);
}

test "URL parsing: wss without port" {
    const config = Config{
        .url = "wss://example.com/socket",
    };

    const skt = try PhoenixSocket.init(allocator, config);
    defer skt.deinit();

    try testing.expectEqualStrings("wss://example.com/socket", skt.config.url);
}

test "URL parsing: without path" {
    const config = Config{
        .url = "ws://localhost:4000",
    };

    const skt = try PhoenixSocket.init(allocator, config);
    defer skt.deinit();

    try testing.expectEqualStrings("ws://localhost:4000", skt.config.url);
}

test "URL parsing: invalid protocol returns error" {
    const config = Config{
        .url = "http://localhost:4000/socket",
    };

    const result = PhoenixSocket.init(allocator, config);
    try testing.expectError(error.InvalidProtocol, result);
}

test "URL parsing: missing protocol returns error" {
    const config = Config{
        .url = "localhost:4000/socket",
    };

    const result = PhoenixSocket.init(allocator, config);
    try testing.expectError(error.InvalidProtocol, result);
}

// ----------------------------------------------------------------------------
// Configuration Edge Cases
// ----------------------------------------------------------------------------

test "config with zero heartbeat interval" {
    const config = Config{
        .url = "ws://localhost:4000/socket",
        .heartbeat_interval_ms = 0,
    };

    const skt = try PhoenixSocket.init(allocator, config);
    defer skt.deinit();

    try testing.expectEqual(@as(u32, 0), skt.config.heartbeat_interval_ms);
}

test "config with very large timeout" {
    const config = Config{
        .url = "ws://localhost:4000/socket",
        .timeout_ms = 3600000, // 1 hour
    };

    const skt = try PhoenixSocket.init(allocator, config);
    defer skt.deinit();

    try testing.expectEqual(@as(u32, 3600000), skt.config.timeout_ms);
}

test "config with maximum URL length" {
    var url_buffer: [2048]u8 = undefined;
    const url = try std.fmt.bufPrint(&url_buffer, "ws://localhost:4000/{s}", .{"a" ** 2000});

    const config = Config{
        .url = url,
    };

    const skt = try PhoenixSocket.init(allocator, config);
    defer skt.deinit();

    try testing.expect(skt.config.url.len > 2000);
}

// ----------------------------------------------------------------------------
// Memory Management
// ----------------------------------------------------------------------------

test "socket deinit cleans up properly" {
    const config = Config{
        .url = "ws://localhost:4000/socket/websocket",
    };

    const skt = try PhoenixSocket.init(allocator, config);
    skt.deinit(); // Should not leak memory

    // If we reach here without errors, deinit worked correctly
    try testing.expect(true);
}

test "multiple init and deinit cycles" {
    const config = Config{
        .url = "ws://localhost:4000/socket/websocket",
    };

    var i: usize = 0;
    while (i < 10) : (i += 1) {
        const skt = try PhoenixSocket.init(allocator, config);
        skt.deinit();
    }

    // No memory leaks expected
    try testing.expect(true);
}
