//! Unit Tests for Project Setup and Dependencies
//!
//! This file contains explicit tests validating:
//! - Build system functionality
//! - Dependency resolution and linking
//! - Project structure and module imports
//! - Core type definitions compilation and instantiation

const std = @import("std");
const testing = std.testing;
const phoenix = @import("phoenix_channels");

// ============================================================================
// Test 1: Build System Compiles Library Target Successfully
// ============================================================================

test "build system: library target compiles" {
    // This test passing proves the library compiles successfully
    // The library module must be accessible
    _ = phoenix;

    // Verify version is accessible (defined in src/root.zig)
    try testing.expectEqualStrings("0.1.0", phoenix.version);
}

test "build system: library exports expected namespaces" {
    // Verify the four-layer architecture is properly exported
    _ = phoenix.protocol;
    _ = phoenix.connection;
    _ = phoenix.channel;
    _ = phoenix.common;

    // Verify WebSocketWrapper is exported
    _ = phoenix.WebSocketWrapper;
}

// ============================================================================
// Test 2: Dependency Resolution and Linking of WebSocket Library
// ============================================================================

test "dependency: websocket library is accessible" {
    // The WebSocketWrapper depends on the websocket library
    // If this compiles and runs, the dependency is properly linked
    const allocator = testing.allocator;
    var wrapper = phoenix.WebSocketWrapper.init(allocator);
    defer wrapper.deinit();

    // Verify the wrapper was initialized
    try testing.expect(!wrapper.isConnected());
}

test "dependency: websocket library types are usable" {
    // Test that we can use websocket-dependent functionality
    const allocator = testing.allocator;
    var wrapper = phoenix.WebSocketWrapper.init(allocator);
    defer wrapper.deinit();

    // Verify operations fail appropriately when not connected
    // (This proves the websocket library is linked and functional)
    var message = [_]u8{ 't', 'e', 's', 't' };
    const result = wrapper.sendText(&message);
    try testing.expectError(error.NotConnected, result);
}

test "dependency: websocket dependency version compatibility" {
    // Ensure the websocket library is compatible with our usage
    // By successfully creating and destroying a wrapper instance
    const allocator = testing.allocator;

    var wrapper1 = phoenix.WebSocketWrapper.init(allocator);
    defer wrapper1.deinit();

    var wrapper2 = phoenix.WebSocketWrapper.init(allocator);
    defer wrapper2.deinit();

    // Both instances should be independent
    try testing.expect(!wrapper1.isConnected());
    try testing.expect(!wrapper2.isConnected());
}

// ============================================================================
// Test 3: Project Structure Allows Proper Module Imports
// ============================================================================

test "project structure: protocol layer modules import correctly" {
    // Verify all protocol layer modules are importable
    _ = phoenix.protocol.message;
    _ = phoenix.protocol.constants;
    _ = phoenix.protocol.serializer;

    // Verify re-exports work
    _ = phoenix.protocol.PhoenixMessage;
    _ = phoenix.protocol.SystemEvents;
    _ = phoenix.protocol.ReservedTopics;
}

test "project structure: connection layer modules import correctly" {
    // Verify all connection layer modules are importable
    _ = phoenix.connection.socket;
    _ = phoenix.connection.state;

    // Verify re-exports work
    _ = phoenix.connection.PhoenixSocket;
    _ = phoenix.connection.SocketConfig;
    _ = phoenix.connection.ConnectionState;
}

test "project structure: channel layer modules import correctly" {
    // Verify all channel layer modules are importable
    _ = phoenix.channel.state;

    // Verify re-exports work
    _ = phoenix.channel.Channel;
    _ = phoenix.channel.ChannelConfig;
    _ = phoenix.channel.ChannelState;
}

test "project structure: common layer modules import correctly" {
    // Verify all common layer modules are importable
    _ = phoenix.common.errors;
    _ = phoenix.common.types;
    _ = phoenix.common.config;

    // Verify re-exports work
    _ = phoenix.common.Error;
    _ = phoenix.common.ConnectionError;
    _ = phoenix.common.ProtocolError;
    _ = phoenix.common.ChannelError;
    _ = phoenix.common.RefCounter;
    _ = phoenix.common.PhoenixConfig;
}

test "project structure: cross-layer dependencies work" {
    // Verify that layers can reference each other properly
    // For example, connection layer uses types from common layer
    const allocator = testing.allocator;

    // RefCounter from common layer should be usable
    var ref_counter = phoenix.common.RefCounter.init();
    const ref1 = ref_counter.next();
    const ref2 = ref_counter.next();

    try testing.expect(ref1 < ref2);
    try testing.expectEqual(@as(usize, 1), ref1);
    try testing.expectEqual(@as(usize, 2), ref2);

    _ = allocator;
}

// ============================================================================
// Test 4: Core Type Definitions Compile and Basic Instantiation Works
// ============================================================================

test "core types: error sets are defined and usable" {
    // Test ConnectionError
    const conn_err: phoenix.common.ConnectionError = error.NotConnected;
    try testing.expectEqual(error.NotConnected, conn_err);

    // Test ProtocolError
    const proto_err: phoenix.common.ProtocolError = error.InvalidMessage;
    try testing.expectEqual(error.InvalidMessage, proto_err);

    // Test ChannelError
    const channel_err: phoenix.common.ChannelError = error.NotJoined;
    try testing.expectEqual(error.NotJoined, channel_err);

    // Test PhoenixError
    const phoenix_err = error.NotImplemented;
    try testing.expectEqual(error.NotImplemented, phoenix_err);

    // Test combined Error type
    const combined_err: phoenix.common.Error = error.NotConnected;
    try testing.expectEqual(error.NotConnected, combined_err);
}

test "core types: RefCounter instantiates and works" {
    var counter = phoenix.common.RefCounter.init();

    // Test reference generation
    const ref1 = counter.next();
    const ref2 = counter.next();
    const ref3 = counter.next();

    try testing.expect(ref1 < ref2);
    try testing.expect(ref2 < ref3);
    try testing.expectEqual(@as(usize, 1), ref1);
    try testing.expectEqual(@as(usize, 2), ref2);
    try testing.expectEqual(@as(usize, 3), ref3);
}

test "core types: RefCounter reset works" {
    var counter = phoenix.common.RefCounter.init();

    _ = counter.next();
    _ = counter.next();

    counter.reset();

    const ref = counter.next();
    try testing.expectEqual(@as(usize, 1), ref);
}

test "core types: PhoenixConfig instantiates with defaults" {
    const config = phoenix.common.config.defaultConfig();

    // Verify default values
    try testing.expect(!config.debug);
    try testing.expectEqual(@as(usize, 65536), config.max_message_size);
    try testing.expectEqual(@as(u32, 10000), config.connection_timeout_ms);
    try testing.expectEqual(@as(u32, 30000), config.heartbeat_interval_ms);
    try testing.expectEqual(@as(u32, 10000), config.join_timeout_ms);
    try testing.expectEqual(@as(u32, 0), config.max_reconnect_attempts);
    try testing.expectEqual(@as(u32, 1000), config.reconnect_delay_ms);
    try testing.expectEqual(@as(u32, 10000), config.max_reconnect_delay_ms);
}

test "core types: PhoenixConfig can be customized" {
    const custom_config = phoenix.common.config.PhoenixConfig{
        .debug = true,
        .max_message_size = 32768,
        .connection_timeout_ms = 5000,
        .heartbeat_interval_ms = 15000,
    };

    try testing.expect(custom_config.debug);
    try testing.expectEqual(@as(usize, 32768), custom_config.max_message_size);
    try testing.expectEqual(@as(u32, 5000), custom_config.connection_timeout_ms);
    try testing.expectEqual(@as(u32, 15000), custom_config.heartbeat_interval_ms);
}

test "core types: Allocator type alias works" {
    // Verify the Allocator type alias is usable
    const AllocatorType = phoenix.common.types.Allocator;
    const allocator: AllocatorType = testing.allocator;

    // Test basic allocation
    const bytes = try allocator.alloc(u8, 10);
    defer allocator.free(bytes);

    try testing.expectEqual(@as(usize, 10), bytes.len);
}

test "core types: callback types are defined" {
    // Verify EventCallback type is defined
    _ = phoenix.common.types.EventCallback;

    // Verify StateChangeCallback type is defined
    _ = phoenix.common.types.StateChangeCallback;
}

// ============================================================================
// Integration Test: All Components Work Together
// ============================================================================

test "project setup integration: full stack is operational" {
    // This test verifies that all project setup components work together:
    // - Build system (compiles this test)
    // - Dependencies (websocket library)
    // - Project structure (all layers accessible)
    // - Core types (instantiable and usable)

    const allocator = testing.allocator;

    // 1. Core types work
    var ref_counter = phoenix.common.RefCounter.init();
    const ref = ref_counter.next();
    try testing.expectEqual(@as(usize, 1), ref);

    // 2. Configuration works
    const config = phoenix.common.config.defaultConfig();
    try testing.expect(!config.debug);

    // 3. Dependency (websocket) works
    var wrapper = phoenix.WebSocketWrapper.init(allocator);
    defer wrapper.deinit();
    try testing.expect(!wrapper.isConnected());

    // 4. Project structure allows cross-layer access
    _ = phoenix.protocol;
    _ = phoenix.connection;
    _ = phoenix.channel;
    _ = phoenix.common;

    // 5. Error handling works
    const err: phoenix.common.ConnectionError = error.NotConnected;
    try testing.expectEqual(error.NotConnected, err);
}
