//! Unit tests for Phoenix Channels library

const std = @import("std");
const testing = std.testing;
const websocket = @import("websocket");
const phoenix_channels = @import("phoenix_channels");

test "placeholder unit test" {
    try testing.expect(true);
}

test "websocket dependency is available" {
    // Verify that we can access the websocket module
    _ = websocket;
}

test "websocket types are accessible" {
    // Verify we can reference websocket types
    _ = websocket.Client;
}

test "phoenix_channels library is accessible" {
    // Verify we can access the phoenix_channels module
    _ = phoenix_channels;
}

test "WebSocketWrapper can be instantiated" {
    const allocator = testing.allocator;
    var wrapper = phoenix_channels.WebSocketWrapper.init(allocator);
    defer wrapper.deinit();

    try testing.expect(!wrapper.isConnected());
}

test "WebSocketWrapper sendText fails when not connected" {
    const allocator = testing.allocator;
    var wrapper = phoenix_channels.WebSocketWrapper.init(allocator);
    defer wrapper.deinit();

    var message = [_]u8{ 't', 'e', 's', 't' };
    const result = wrapper.sendText(&message);
    try testing.expectError(error.NotConnected, result);
}

test "WebSocketWrapper receive fails when not connected" {
    const allocator = testing.allocator;
    var wrapper = phoenix_channels.WebSocketWrapper.init(allocator);
    defer wrapper.deinit();

    const result = wrapper.receive();
    try testing.expectError(error.NotConnected, result);
}
