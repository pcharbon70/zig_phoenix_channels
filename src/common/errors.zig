//! Common Error Definitions
//!
//! This module defines all error sets used throughout the library.
//! Errors are organized by category to make error handling more precise.

const std = @import("std");

/// Connection-related errors
pub const ConnectionError = error{
    /// Failed to establish connection
    ConnectionFailed,

    /// Connection timed out
    ConnectionTimeout,

    /// Connection already established
    AlreadyConnected,

    /// Not connected
    NotConnected,

    /// Connection was closed
    ConnectionClosed,

    /// Invalid WebSocket URL
    InvalidUrl,

    /// WebSocket handshake failed
    HandshakeFailed,
};

/// Protocol-related errors
pub const ProtocolError = error{
    /// Invalid message format
    InvalidMessage,

    /// Message serialization failed
    SerializationError,

    /// Message deserialization failed
    DeserializationError,

    /// Invalid protocol state for operation
    InvalidState,

    /// Message validation failed
    ValidationError,
};

/// Channel-related errors
pub const ChannelError = error{
    /// Channel join failed
    JoinFailed,

    /// Channel join timed out
    JoinTimeout,

    /// Channel leave failed
    LeaveFailed,

    /// Channel not joined
    NotJoined,

    /// Channel already joined
    AlreadyJoined,

    /// Push failed
    PushFailed,
};

/// General library errors
pub const PhoenixError = error{
    /// Feature not yet implemented
    NotImplemented,

    /// Invalid configuration
    InvalidConfiguration,

    /// Operation timed out
    Timeout,

    /// Internal error
    InternalError,
};

/// Combined error set for all Phoenix Channels operations
pub const Error = ConnectionError || ProtocolError || ChannelError || PhoenixError || std.mem.Allocator.Error;

test "error sets are defined" {
    // Just verify the error sets compile
    const conn_err: ConnectionError = error.NotConnected;
    _ = conn_err;

    const proto_err: ProtocolError = error.InvalidMessage;
    _ = proto_err;

    const channel_err: ChannelError = error.NotJoined;
    _ = channel_err;

    const phoenix_err: PhoenixError = error.NotImplemented;
    _ = phoenix_err;
}
