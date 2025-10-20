//! Channel State Machine
//!
//! Defines the channel state enum and valid state transitions. The channel
//! state machine operates independently from the socket state machine.
//!
//! State transitions:
//! CLOSED -> JOINING -> JOINED
//!                   -> ERROR -> (automatic rejoin in Phase 2)
//!          JOINED -> LEAVING -> CLOSED
//!                 -> ERROR
//!                 -> CLOSED (on phx_close, no rejoin)

const std = @import("std");

/// Channel state
pub const ChannelState = enum {
    /// Not subscribed to the topic
    CLOSED,

    /// Join request sent, waiting for confirmation
    JOINING,

    /// Successfully subscribed, can send/receive events
    JOINED,

    /// Leave request sent, waiting for confirmation
    LEAVING,

    /// Channel error occurred
    ERROR,

    /// Check if a state transition is valid
    pub fn canTransitionTo(self: ChannelState, target: ChannelState) bool {
        return switch (self) {
            .CLOSED => target == .JOINING,
            .JOINING => target == .JOINED or target == .ERROR or target == .CLOSED,
            .JOINED => target == .LEAVING or target == .ERROR or target == .CLOSED,
            .LEAVING => target == .CLOSED,
            .ERROR => target == .CLOSED or target == .JOINING,
        };
    }

    /// Get human-readable state name
    pub fn toString(self: ChannelState) []const u8 {
        return switch (self) {
            .CLOSED => "CLOSED",
            .JOINING => "JOINING",
            .JOINED => "JOINED",
            .LEAVING => "LEAVING",
            .ERROR => "ERROR",
        };
    }

    /// Check if channel is in joined state (can send/receive)
    pub fn isJoined(self: ChannelState) bool {
        return self == .JOINED;
    }

    /// Check if channel can send messages
    pub fn canSend(self: ChannelState) bool {
        return self == .JOINED;
    }

    /// Check if channel is in transitional state (joining/leaving)
    pub fn isTransitional(self: ChannelState) bool {
        return self == .JOINING or self == .LEAVING;
    }

    /// Check if channel is in error state
    pub fn isError(self: ChannelState) bool {
        return self == .ERROR;
    }

    /// Check if channel is closed
    pub fn isClosed(self: ChannelState) bool {
        return self == .CLOSED;
    }
};

test "valid channel state transitions" {
    try std.testing.expect(ChannelState.CLOSED.canTransitionTo(.JOINING));
    try std.testing.expect(ChannelState.JOINING.canTransitionTo(.JOINED));
    try std.testing.expect(ChannelState.JOINED.canTransitionTo(.LEAVING));
    try std.testing.expect(ChannelState.LEAVING.canTransitionTo(.CLOSED));
}

test "invalid channel state transitions" {
    try std.testing.expect(!ChannelState.CLOSED.canTransitionTo(.JOINED));
    try std.testing.expect(!ChannelState.JOINING.canTransitionTo(.LEAVING));
    try std.testing.expect(!ChannelState.LEAVING.canTransitionTo(.JOINING));
}

test "channel state to string" {
    try std.testing.expectEqualStrings("CLOSED", ChannelState.CLOSED.toString());
    try std.testing.expectEqualStrings("JOINED", ChannelState.JOINED.toString());
}
