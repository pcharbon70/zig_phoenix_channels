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
//!
//! The state machine supports callbacks for monitoring state changes,
//! which is useful for logging, metrics, and debugging.

const std = @import("std");

/// Callback function type for state change notifications
/// Parameters: old_state, new_state, optional context
pub const StateChangeCallback = *const fn (
    old_state: ConnectionState,
    new_state: ConnectionState,
    context: ?*anyopaque,
) void;

/// Represents a state transition with metadata
pub const StateTransition = struct {
    from: ConnectionState,
    to: ConnectionState,
    reason: ?[]const u8 = null,

    /// Create a new state transition
    pub fn init(from: ConnectionState, to: ConnectionState, reason: ?[]const u8) StateTransition {
        return StateTransition{
            .from = from,
            .to = to,
            .reason = reason,
        };
    }

    /// Check if this transition is valid
    pub fn isValid(self: StateTransition) bool {
        return self.from.canTransitionTo(self.to);
    }
};

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

    /// Get error message for invalid transition
    pub fn getTransitionError(self: ConnectionState, target: ConnectionState) []const u8 {
        if (self.canTransitionTo(target)) {
            return "Valid transition";
        }

        return switch (self) {
            .DISCONNECTED => "DISCONNECTED can only transition to CONNECTING",
            .CONNECTING => "CONNECTING can only transition to CONNECTED, ERROR, or DISCONNECTED",
            .CONNECTED => "CONNECTED can only transition to CLOSING, ERROR, or DISCONNECTED",
            .CLOSING => "CLOSING can only transition to DISCONNECTED",
            .ERROR => "ERROR can only transition to DISCONNECTED or CONNECTING (for retry)",
        };
    }

    /// Validate a transition and return error if invalid
    pub fn validateTransition(self: ConnectionState, target: ConnectionState) !void {
        if (!self.canTransitionTo(target)) {
            return error.InvalidStateTransition;
        }
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
    try std.testing.expectEqualStrings("CONNECTING", ConnectionState.CONNECTING.toString());
    try std.testing.expectEqualStrings("CLOSING", ConnectionState.CLOSING.toString());
    try std.testing.expectEqualStrings("ERROR", ConnectionState.ERROR.toString());
}

// ============================================================================
// StateTransition Tests
// ============================================================================

test "StateTransition: valid transition" {
    const transition = StateTransition.init(.DISCONNECTED, .CONNECTING, "Starting connection");
    try std.testing.expect(transition.isValid());
    try std.testing.expectEqual(ConnectionState.DISCONNECTED, transition.from);
    try std.testing.expectEqual(ConnectionState.CONNECTING, transition.to);
}

test "StateTransition: invalid transition" {
    const transition = StateTransition.init(.DISCONNECTED, .CONNECTED, "Invalid direct connection");
    try std.testing.expect(!transition.isValid());
}

test "StateTransition: with reason" {
    const transition = StateTransition.init(.CONNECTED, .ERROR, "Connection timeout");
    try std.testing.expect(transition.isValid());
    try std.testing.expect(transition.reason != null);
    try std.testing.expectEqualStrings("Connection timeout", transition.reason.?);
}

test "StateTransition: without reason" {
    const transition = StateTransition.init(.CONNECTING, .CONNECTED, null);
    try std.testing.expect(transition.isValid());
    try std.testing.expect(transition.reason == null);
}

// ============================================================================
// Comprehensive Transition Tests
// ============================================================================

test "DISCONNECTED: valid transitions" {
    const state = ConnectionState.DISCONNECTED;
    try std.testing.expect(state.canTransitionTo(.CONNECTING));
    try state.validateTransition(.CONNECTING);
}

test "DISCONNECTED: invalid transitions" {
    const state = ConnectionState.DISCONNECTED;
    try std.testing.expect(!state.canTransitionTo(.CONNECTED));
    try std.testing.expect(!state.canTransitionTo(.CLOSING));
    try std.testing.expect(!state.canTransitionTo(.ERROR));
    try std.testing.expect(!state.canTransitionTo(.DISCONNECTED));

    try std.testing.expectError(error.InvalidStateTransition, state.validateTransition(.CONNECTED));
}

test "CONNECTING: valid transitions" {
    const state = ConnectionState.CONNECTING;
    try std.testing.expect(state.canTransitionTo(.CONNECTED));
    try std.testing.expect(state.canTransitionTo(.ERROR));
    try std.testing.expect(state.canTransitionTo(.DISCONNECTED));

    try state.validateTransition(.CONNECTED);
    try state.validateTransition(.ERROR);
    try state.validateTransition(.DISCONNECTED);
}

test "CONNECTING: invalid transitions" {
    const state = ConnectionState.CONNECTING;
    try std.testing.expect(!state.canTransitionTo(.CLOSING));
    try std.testing.expect(!state.canTransitionTo(.CONNECTING));

    try std.testing.expectError(error.InvalidStateTransition, state.validateTransition(.CLOSING));
}

test "CONNECTED: valid transitions" {
    const state = ConnectionState.CONNECTED;
    try std.testing.expect(state.canTransitionTo(.CLOSING));
    try std.testing.expect(state.canTransitionTo(.ERROR));
    try std.testing.expect(state.canTransitionTo(.DISCONNECTED));

    try state.validateTransition(.CLOSING);
    try state.validateTransition(.ERROR);
    try state.validateTransition(.DISCONNECTED);
}

test "CONNECTED: invalid transitions" {
    const state = ConnectionState.CONNECTED;
    try std.testing.expect(!state.canTransitionTo(.CONNECTING));
    try std.testing.expect(!state.canTransitionTo(.CONNECTED));

    try std.testing.expectError(error.InvalidStateTransition, state.validateTransition(.CONNECTING));
}

test "CLOSING: valid transitions" {
    const state = ConnectionState.CLOSING;
    try std.testing.expect(state.canTransitionTo(.DISCONNECTED));
    try state.validateTransition(.DISCONNECTED);
}

test "CLOSING: invalid transitions" {
    const state = ConnectionState.CLOSING;
    try std.testing.expect(!state.canTransitionTo(.CONNECTING));
    try std.testing.expect(!state.canTransitionTo(.CONNECTED));
    try std.testing.expect(!state.canTransitionTo(.ERROR));
    try std.testing.expect(!state.canTransitionTo(.CLOSING));

    try std.testing.expectError(error.InvalidStateTransition, state.validateTransition(.CONNECTING));
    try std.testing.expectError(error.InvalidStateTransition, state.validateTransition(.CONNECTED));
}

test "ERROR: valid transitions" {
    const state = ConnectionState.ERROR;
    try std.testing.expect(state.canTransitionTo(.DISCONNECTED));
    try std.testing.expect(state.canTransitionTo(.CONNECTING));

    try state.validateTransition(.DISCONNECTED);
    try state.validateTransition(.CONNECTING);
}

test "ERROR: invalid transitions" {
    const state = ConnectionState.ERROR;
    try std.testing.expect(!state.canTransitionTo(.CONNECTED));
    try std.testing.expect(!state.canTransitionTo(.CLOSING));
    try std.testing.expect(!state.canTransitionTo(.ERROR));

    try std.testing.expectError(error.InvalidStateTransition, state.validateTransition(.CONNECTED));
}

// ============================================================================
// Transition Error Messages Tests
// ============================================================================

test "getTransitionError: valid transition" {
    const msg = ConnectionState.DISCONNECTED.getTransitionError(.CONNECTING);
    try std.testing.expectEqualStrings("Valid transition", msg);
}

test "getTransitionError: invalid transitions have messages" {
    const msg1 = ConnectionState.DISCONNECTED.getTransitionError(.CONNECTED);
    try std.testing.expect(msg1.len > 0);

    const msg2 = ConnectionState.CONNECTING.getTransitionError(.CLOSING);
    try std.testing.expect(msg2.len > 0);

    const msg3 = ConnectionState.CONNECTED.getTransitionError(.CONNECTING);
    try std.testing.expect(msg3.len > 0);
}

// ============================================================================
// State Change Callback Tests
// ============================================================================

const TestCallbackContext = struct {
    called: bool = false,
    old_state: ?ConnectionState = null,
    new_state: ?ConnectionState = null,
};

fn testCallback(old_state: ConnectionState, new_state: ConnectionState, context: ?*anyopaque) void {
    if (context) |ctx| {
        const test_ctx: *TestCallbackContext = @ptrCast(@alignCast(ctx));
        test_ctx.called = true;
        test_ctx.old_state = old_state;
        test_ctx.new_state = new_state;
    }
}

test "StateChangeCallback: invocation" {
    var ctx = TestCallbackContext{};
    const callback: StateChangeCallback = testCallback;

    callback(.DISCONNECTED, .CONNECTING, &ctx);

    try std.testing.expect(ctx.called);
    try std.testing.expectEqual(ConnectionState.DISCONNECTED, ctx.old_state.?);
    try std.testing.expectEqual(ConnectionState.CONNECTING, ctx.new_state.?);
}

test "StateChangeCallback: with null context" {
    const callback: StateChangeCallback = testCallback;

    // Should not crash with null context
    callback(.CONNECTING, .CONNECTED, null);
}
