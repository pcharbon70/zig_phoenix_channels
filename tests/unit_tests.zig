//! Unit tests for Phoenix Channels library
//!
//! This file serves as the entry point for all unit tests.
//! Module-specific tests are included via comptime test imports.

const std = @import("std");
const testing = std.testing;

// Import test utilities
const test_utils = @import("test_utils.zig");

// Import the library
const phoenix = @import("phoenix_channels");

// ============================================================================
// Module Structure Tests
// ============================================================================

test "protocol layer is accessible" {
    _ = phoenix.protocol;
    _ = phoenix.protocol.message;
    _ = phoenix.protocol.constants;
    _ = phoenix.protocol.serializer;
}

test "connection layer is accessible" {
    _ = phoenix.connection;
    _ = phoenix.connection.socket;
    _ = phoenix.connection.state;
}

test "channel layer is accessible" {
    _ = phoenix.channel;
    _ = phoenix.channel.state;
}

test "common layer is accessible" {
    _ = phoenix.common;
    _ = phoenix.common.errors;
    _ = phoenix.common.types;
    _ = phoenix.common.config;
}

// ============================================================================
// Re-exported Types Tests
// ============================================================================

test "protocol re-exports work" {
    _ = phoenix.protocol.PhoenixMessage;
    _ = phoenix.protocol.SystemEvents;
    _ = phoenix.protocol.ReservedTopics;
}

test "connection re-exports work" {
    _ = phoenix.connection.PhoenixSocket;
    _ = phoenix.connection.SocketConfig;
    _ = phoenix.connection.ConnectionState;
}

test "channel re-exports work" {
    _ = phoenix.channel.Channel;
    _ = phoenix.channel.ChannelConfig;
    _ = phoenix.channel.ChannelState;
}

test "common re-exports work" {
    _ = phoenix.common.Error;
    _ = phoenix.common.ConnectionError;
    _ = phoenix.common.ProtocolError;
    _ = phoenix.common.ChannelError;
    _ = phoenix.common.RefCounter;
    _ = phoenix.common.PhoenixConfig;
}

// ============================================================================
// WebSocket Wrapper Tests (from task 1.1.2)
// ============================================================================

test "WebSocketWrapper can be instantiated" {
    const allocator = testing.allocator;
    var wrapper = phoenix.WebSocketWrapper.init(allocator);
    defer wrapper.deinit();

    try testing.expect(!wrapper.isConnected());
}

test "WebSocketWrapper sendText fails when not connected" {
    const allocator = testing.allocator;
    var wrapper = phoenix.WebSocketWrapper.init(allocator);
    defer wrapper.deinit();

    var message = [_]u8{ 't', 'e', 's', 't' };
    const result = wrapper.sendText(&message);
    try testing.expectError(error.NotConnected, result);
}

test "WebSocketWrapper receive fails when not connected" {
    const allocator = testing.allocator;
    var wrapper = phoenix.WebSocketWrapper.init(allocator);
    defer wrapper.deinit();

    const result = wrapper.receive();
    try testing.expectError(error.NotConnected, result);
}

// ============================================================================
// Module Tests
// ============================================================================

// Individual module tests are included when building the library.
// The phoenix_channels import above brings in all module definitions and their tests.

// ============================================================================
// Section 1.3 Unit Tests (Socket Component)
// ============================================================================

// Import organized unit tests for Section 1.3
test {
    _ = @import("connection/state_machine_test.zig");
    _ = @import("connection/socket_structure_test.zig");
    _ = @import("connection/reference_generation_test.zig");
    _ = @import("connection/connection_lifecycle_test.zig");
    _ = @import("connection/message_sending_test.zig");
}
