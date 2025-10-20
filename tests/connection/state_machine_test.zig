const std = @import("std");
const testing = std.testing;
const phoenix = @import("phoenix_channels");
const ConnectionState = phoenix.connection.ConnectionState;

// ============================================================================
// Task 1.3.1: State Machine Tests
// ============================================================================

// ----------------------------------------------------------------------------
// Basic State Transitions
// ----------------------------------------------------------------------------

test "valid transition: DISCONNECTED to CONNECTING" {
    const from = ConnectionState.DISCONNECTED;
    const to = ConnectionState.CONNECTING;
    try testing.expect(from.canTransitionTo(to));
}

test "valid transition: CONNECTING to CONNECTED" {
    const from = ConnectionState.CONNECTING;
    const to = ConnectionState.CONNECTED;
    try testing.expect(from.canTransitionTo(to));
}

test "valid transition: CONNECTING to ERROR" {
    const from = ConnectionState.CONNECTING;
    const to = ConnectionState.ERROR;
    try testing.expect(from.canTransitionTo(to));
}

test "valid transition: CONNECTED to CLOSING" {
    const from = ConnectionState.CONNECTED;
    const to = ConnectionState.CLOSING;
    try testing.expect(from.canTransitionTo(to));
}

test "valid transition: CONNECTED to ERROR" {
    const from = ConnectionState.CONNECTED;
    const to = ConnectionState.ERROR;
    try testing.expect(from.canTransitionTo(to));
}

test "valid transition: CLOSING to DISCONNECTED" {
    const from = ConnectionState.CLOSING;
    const to = ConnectionState.DISCONNECTED;
    try testing.expect(from.canTransitionTo(to));
}

test "valid transition: ERROR to DISCONNECTED" {
    const from = ConnectionState.ERROR;
    const to = ConnectionState.DISCONNECTED;
    try testing.expect(from.canTransitionTo(to));
}

test "valid transition: ERROR to CONNECTING (reconnect)" {
    const from = ConnectionState.ERROR;
    const to = ConnectionState.CONNECTING;
    try testing.expect(from.canTransitionTo(to));
}

test "same state transition returns false (no idempotent transitions)" {
    const from = ConnectionState.DISCONNECTED;
    const to = ConnectionState.DISCONNECTED;
    // State machine doesn't allow idempotent transitions
    try testing.expect(!from.canTransitionTo(to));
}

// ----------------------------------------------------------------------------
// Invalid State Transitions
// ----------------------------------------------------------------------------

test "invalid transition: DISCONNECTED to CONNECTED (skip CONNECTING)" {
    const from = ConnectionState.DISCONNECTED;
    const to = ConnectionState.CONNECTED;
    try testing.expect(!from.canTransitionTo(to));
}

test "invalid transition: DISCONNECTED to CLOSING" {
    const from = ConnectionState.DISCONNECTED;
    const to = ConnectionState.CLOSING;
    try testing.expect(!from.canTransitionTo(to));
}

test "invalid transition: DISCONNECTED to ERROR" {
    const from = ConnectionState.DISCONNECTED;
    const to = ConnectionState.ERROR;
    try testing.expect(!from.canTransitionTo(to));
}

test "invalid transition: CONNECTING to CLOSING" {
    const from = ConnectionState.CONNECTING;
    const to = ConnectionState.CLOSING;
    try testing.expect(!from.canTransitionTo(to));
}

test "valid transition: CONNECTING to DISCONNECTED allowed" {
    const from = ConnectionState.CONNECTING;
    const to = ConnectionState.DISCONNECTED;
    // Implementation allows this transition (connection fails during handshake)
    try testing.expect(from.canTransitionTo(to));
}

test "invalid transition: CONNECTED to CONNECTING" {
    const from = ConnectionState.CONNECTED;
    const to = ConnectionState.CONNECTING;
    try testing.expect(!from.canTransitionTo(to));
}

test "valid transition: CONNECTED to DISCONNECTED allowed" {
    const from = ConnectionState.CONNECTED;
    const to = ConnectionState.DISCONNECTED;
    // Implementation allows direct CONNECTED -> DISCONNECTED
    try testing.expect(from.canTransitionTo(to));
}

test "invalid transition: CLOSING to CONNECTING" {
    const from = ConnectionState.CLOSING;
    const to = ConnectionState.CONNECTING;
    try testing.expect(!from.canTransitionTo(to));
}

test "invalid transition: CLOSING to CONNECTED" {
    const from = ConnectionState.CLOSING;
    const to = ConnectionState.CONNECTED;
    try testing.expect(!from.canTransitionTo(to));
}

test "invalid transition: CLOSING to ERROR" {
    const from = ConnectionState.CLOSING;
    const to = ConnectionState.ERROR;
    try testing.expect(!from.canTransitionTo(to));
}

test "invalid transition: ERROR to CONNECTED" {
    const from = ConnectionState.ERROR;
    const to = ConnectionState.CONNECTED;
    try testing.expect(!from.canTransitionTo(to));
}

test "invalid transition: ERROR to CLOSING" {
    const from = ConnectionState.ERROR;
    const to = ConnectionState.CLOSING;
    try testing.expect(!from.canTransitionTo(to));
}

// ----------------------------------------------------------------------------
// State Properties
// ----------------------------------------------------------------------------

test "DISCONNECTED is not connected" {
    try testing.expect(!ConnectionState.DISCONNECTED.isConnected());
}

test "CONNECTING is not connected" {
    try testing.expect(!ConnectionState.CONNECTING.isConnected());
}

test "CONNECTED is connected" {
    try testing.expect(ConnectionState.CONNECTED.isConnected());
}

test "CLOSING is not connected" {
    try testing.expect(!ConnectionState.CLOSING.isConnected());
}

test "ERROR is not connected" {
    try testing.expect(!ConnectionState.ERROR.isConnected());
}

// ----------------------------------------------------------------------------
// State Sequences
// ----------------------------------------------------------------------------

test "complete connection sequence: DISCONNECTED -> CONNECTING -> CONNECTED" {
    var state = ConnectionState.DISCONNECTED;

    // DISCONNECTED -> CONNECTING
    try testing.expect(state.canTransitionTo(.CONNECTING));
    state = .CONNECTING;

    // CONNECTING -> CONNECTED
    try testing.expect(state.canTransitionTo(.CONNECTED));
    state = .CONNECTED;

    try testing.expect(state.isConnected());
}

test "graceful disconnection sequence: CONNECTED -> CLOSING -> DISCONNECTED" {
    var state = ConnectionState.CONNECTED;

    // CONNECTED -> CLOSING
    try testing.expect(state.canTransitionTo(.CLOSING));
    state = .CLOSING;

    // CLOSING -> DISCONNECTED
    try testing.expect(state.canTransitionTo(.DISCONNECTED));
    state = .DISCONNECTED;

    try testing.expect(!state.isConnected());
}

test "error sequence: CONNECTING -> ERROR -> DISCONNECTED" {
    var state = ConnectionState.CONNECTING;

    // CONNECTING -> ERROR
    try testing.expect(state.canTransitionTo(.ERROR));
    state = .ERROR;

    // ERROR -> DISCONNECTED
    try testing.expect(state.canTransitionTo(.DISCONNECTED));
    state = .DISCONNECTED;

    try testing.expect(!state.isConnected());
}

test "reconnection sequence: ERROR -> CONNECTING -> CONNECTED" {
    var state = ConnectionState.ERROR;

    // ERROR -> CONNECTING (reconnect)
    try testing.expect(state.canTransitionTo(.CONNECTING));
    state = .CONNECTING;

    // CONNECTING -> CONNECTED
    try testing.expect(state.canTransitionTo(.CONNECTED));
    state = .CONNECTED;

    try testing.expect(state.isConnected());
}

test "error during connection: CONNECTED -> ERROR -> CONNECTING -> CONNECTED" {
    var state = ConnectionState.CONNECTED;

    // CONNECTED -> ERROR
    try testing.expect(state.canTransitionTo(.ERROR));
    state = .ERROR;

    // ERROR -> CONNECTING (reconnect)
    try testing.expect(state.canTransitionTo(.CONNECTING));
    state = .CONNECTING;

    // CONNECTING -> CONNECTED
    try testing.expect(state.canTransitionTo(.CONNECTED));
    state = .CONNECTED;

    try testing.expect(state.isConnected());
}

// ----------------------------------------------------------------------------
// Edge Cases
// ----------------------------------------------------------------------------

test "idempotent transitions are not allowed" {
    // State machine doesn't support idempotent transitions
    try testing.expect(!ConnectionState.DISCONNECTED.canTransitionTo(.DISCONNECTED));
    try testing.expect(!ConnectionState.CONNECTING.canTransitionTo(.CONNECTING));
    try testing.expect(!ConnectionState.CONNECTED.canTransitionTo(.CONNECTED));
    try testing.expect(!ConnectionState.CLOSING.canTransitionTo(.CLOSING));
    try testing.expect(!ConnectionState.ERROR.canTransitionTo(.ERROR));
}

test "no state can transition to itself" {
    const states = [_]ConnectionState{
        .DISCONNECTED,
        .CONNECTING,
        .CONNECTED,
        .CLOSING,
        .ERROR,
    };

    // State machine doesn't allow idempotent transitions
    for (states) |state| {
        try testing.expect(!state.canTransitionTo(state));
    }
}

test "ERROR state can only transition to DISCONNECTED or CONNECTING" {
    const from = ConnectionState.ERROR;

    try testing.expect(!from.canTransitionTo(.ERROR)); // no idempotent
    try testing.expect(from.canTransitionTo(.DISCONNECTED));
    try testing.expect(from.canTransitionTo(.CONNECTING));
    try testing.expect(!from.canTransitionTo(.CONNECTED));
    try testing.expect(!from.canTransitionTo(.CLOSING));
}

test "CLOSING state can only transition to DISCONNECTED" {
    const from = ConnectionState.CLOSING;

    try testing.expect(!from.canTransitionTo(.CLOSING)); // no idempotent
    try testing.expect(from.canTransitionTo(.DISCONNECTED));
    try testing.expect(!from.canTransitionTo(.CONNECTING));
    try testing.expect(!from.canTransitionTo(.CONNECTED));
    try testing.expect(!from.canTransitionTo(.ERROR));
}
