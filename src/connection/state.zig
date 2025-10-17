//! Connection State Machine
//!
//! Defines the connection state enum and valid state transitions for the
//! Phoenix Socket. The state machine ensures that connection operations
//! only happen in valid states.
//!
//! State transitions:
//! DISCONNECTED -> CONNECTING -> CONNECTED
//!                              -> CLOSING -> DISCONNECTED
//!                              -> ERROR -> DISCONNECTED (with reconnection logic)

const std = @import("std");

/// Connection state for Phoenix Socket
pub const ConnectionState = enum {
    /// No connection established
    DISCONNECTED,

    /// Connection attempt in progress
    CONNECTING,

    /// Active WebSocket connection
    CONNECTED,

    /// Graceful shutdown in progress
    CLOSING,

    /// Connection error occurred
    ERROR,

    /// Check if a state transition is valid
    pub fn canTransitionTo(self: ConnectionState, target: ConnectionState) bool {
        return switch (self) {
            .DISCONNECTED => target == .CONNECTING,
            .CONNECTING => target == .CONNECTED or target == .ERROR or target == .DISCONNECTED,
            .CONNECTED => target == .CLOSING or target == .ERROR or target == .DISCONNECTED,
            .CLOSING => target == .DISCONNECTED,
            .ERROR => target == .DISCONNECTED or target == .CONNECTING,
        };
    }

    /// Get human-readable state name
    pub fn toString(self: ConnectionState) []const u8 {
        return switch (self) {
            .DISCONNECTED => "DISCONNECTED",
            .CONNECTING => "CONNECTING",
            .CONNECTED => "CONNECTED",
            .CLOSING => "CLOSING",
            .ERROR => "ERROR",
        };
    }
};

test "valid state transitions" {
    try std.testing.expect(ConnectionState.DISCONNECTED.canTransitionTo(.CONNECTING));
    try std.testing.expect(ConnectionState.CONNECTING.canTransitionTo(.CONNECTED));
    try std.testing.expect(ConnectionState.CONNECTED.canTransitionTo(.CLOSING));
    try std.testing.expect(ConnectionState.CLOSING.canTransitionTo(.DISCONNECTED));
}

test "invalid state transitions" {
    try std.testing.expect(!ConnectionState.DISCONNECTED.canTransitionTo(.CONNECTED));
    try std.testing.expect(!ConnectionState.CONNECTING.canTransitionTo(.CLOSING));
    try std.testing.expect(!ConnectionState.CLOSING.canTransitionTo(.CONNECTING));
}

test "state to string" {
    try std.testing.expectEqualStrings("DISCONNECTED", ConnectionState.DISCONNECTED.toString());
    try std.testing.expectEqualStrings("CONNECTED", ConnectionState.CONNECTED.toString());
}
