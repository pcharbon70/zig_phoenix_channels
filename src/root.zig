//! Phoenix Channels client library for Zig
//!
//! This library provides a client implementation of the Phoenix Channels
//! protocol for real-time communication with Phoenix servers.
//!
//! ## Architecture
//!
//! The library is organized into four main layers:
//!
//! - **Protocol Layer** (`protocol/`): Message format, serialization, protocol constants
//! - **Connection Layer** (`connection/`): Socket management, WebSocket handling, connection state machine
//! - **Channel Layer** (`channel/`): Channel operations, channel state machine
//! - **Common Layer** (`common/`): Shared utilities, errors, types, configuration
//!
//! ## Usage Example
//!
//! ```zig
//! const phoenix = @import("phoenix_channels");
//!
//! // Create socket configuration
//! const socket_config = phoenix.connection.socket.Config{
//!     .url = "ws://localhost:4000/socket/websocket",
//! };
//!
//! // Initialize socket
//! var socket = try phoenix.connection.socket.PhoenixSocket.init(allocator, socket_config);
//! defer socket.deinit();
//!
//! // Connect and use channels...
//! ```

const std = @import("std");

// Library version
pub const version = "0.1.0";

// ============================================================================
// WebSocket Wrapper (from task 1.1.2)
// ============================================================================

/// WebSocket wrapper for Phoenix protocol
pub const WebSocketWrapper = @import("websocket_wrapper.zig").WebSocketWrapper;

// ============================================================================
// Protocol Layer
// ============================================================================

/// Phoenix protocol message format and serialization
pub const protocol = struct {
    /// Message structure and types
    pub const message = @import("protocol/message.zig");

    /// Protocol constants (system events, reserved topics)
    pub const constants = @import("protocol/constants.zig");

    /// Message serialization/deserialization
    pub const serializer = @import("protocol/serializer.zig");

    // Re-export commonly used types
    pub const PhoenixMessage = message.PhoenixMessage;
    pub const SystemEvents = constants.SystemEvents;
    pub const ReservedTopics = constants.ReservedTopics;
};

// ============================================================================
// Connection Layer
// ============================================================================

/// Socket management and WebSocket connection handling
pub const connection = struct {
    /// Socket implementation
    pub const socket = @import("connection/socket.zig");

    /// Connection state machine
    pub const state = @import("connection/state.zig");

    // Re-export commonly used types
    pub const PhoenixSocket = socket.PhoenixSocket;
    pub const SocketConfig = socket.Config;
    pub const ConnectionState = state.ConnectionState;
};

// ============================================================================
// Channel Layer
// ============================================================================

/// Channel subscriptions and operations
pub const channel = struct {
    /// Channel implementation
    const channel_mod = @import("channel/channel.zig");

    /// Channel state machine
    pub const state = @import("channel/state.zig");

    // Re-export commonly used types
    pub const Channel = channel_mod.Channel;
    pub const ChannelConfig = channel_mod.Config;
    pub const ChannelState = state.ChannelState;
    pub const EventCallback = channel_mod.EventCallback;
    pub const ChannelStateCallback = channel_mod.ChannelStateCallback;
};

// ============================================================================
// Common Layer
// ============================================================================

/// Shared utilities and types
pub const common = struct {
    /// Error definitions
    pub const errors = @import("common/errors.zig");

    /// Common types and type aliases
    pub const types = @import("common/types.zig");

    /// Configuration structures
    pub const config = @import("common/config.zig");

    // Re-export commonly used types
    pub const Error = errors.Error;
    pub const ConnectionError = errors.ConnectionError;
    pub const ProtocolError = errors.ProtocolError;
    pub const ChannelError = errors.ChannelError;
    pub const RefCounter = types.RefCounter;
    pub const PhoenixConfig = config.PhoenixConfig;
};

// ============================================================================
// Tests
// ============================================================================

test "library imports" {
    // Verify all modules can be imported
    _ = protocol;
    _ = connection;
    _ = channel;
    _ = common;
}

test "version is defined" {
    try std.testing.expectEqualStrings("0.1.0", version);
}
