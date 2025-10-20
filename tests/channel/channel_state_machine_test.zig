const std = @import("std");
const testing = std.testing;
const phoenix = @import("phoenix_channels");
const ChannelState = phoenix.channel.ChannelState;

// ============================================================================
// Task 1.4.1: Channel State Machine Tests
// ============================================================================

// ----------------------------------------------------------------------------
// Basic State Transitions
// ----------------------------------------------------------------------------

test "valid transition: CLOSED to JOINING" {
    const from = ChannelState.CLOSED;
    const to = ChannelState.JOINING;
    try testing.expect(from.canTransitionTo(to));
}

test "valid transition: JOINING to JOINED" {
    const from = ChannelState.JOINING;
    const to = ChannelState.JOINED;
    try testing.expect(from.canTransitionTo(to));
}

test "valid transition: JOINING to ERROR" {
    const from = ChannelState.JOINING;
    const to = ChannelState.ERROR;
    try testing.expect(from.canTransitionTo(to));
}

test "valid transition: JOINING to CLOSED (join timeout/cancel)" {
    const from = ChannelState.JOINING;
    const to = ChannelState.CLOSED;
    try testing.expect(from.canTransitionTo(to));
}

test "valid transition: JOINED to LEAVING" {
    const from = ChannelState.JOINED;
    const to = ChannelState.LEAVING;
    try testing.expect(from.canTransitionTo(to));
}

test "valid transition: JOINED to ERROR" {
    const from = ChannelState.JOINED;
    const to = ChannelState.ERROR;
    try testing.expect(from.canTransitionTo(to));
}

test "valid transition: JOINED to CLOSED (phx_close)" {
    const from = ChannelState.JOINED;
    const to = ChannelState.CLOSED;
    try testing.expect(from.canTransitionTo(to));
}

test "valid transition: LEAVING to CLOSED" {
    const from = ChannelState.LEAVING;
    const to = ChannelState.CLOSED;
    try testing.expect(from.canTransitionTo(to));
}

test "valid transition: ERROR to CLOSED" {
    const from = ChannelState.ERROR;
    const to = ChannelState.CLOSED;
    try testing.expect(from.canTransitionTo(to));
}

test "valid transition: ERROR to JOINING (rejoin)" {
    const from = ChannelState.ERROR;
    const to = ChannelState.JOINING;
    try testing.expect(from.canTransitionTo(to));
}

// ----------------------------------------------------------------------------
// Invalid State Transitions
// ----------------------------------------------------------------------------

test "invalid transition: CLOSED to JOINED (skip JOINING)" {
    const from = ChannelState.CLOSED;
    const to = ChannelState.JOINED;
    try testing.expect(!from.canTransitionTo(to));
}

test "invalid transition: CLOSED to LEAVING" {
    const from = ChannelState.CLOSED;
    const to = ChannelState.LEAVING;
    try testing.expect(!from.canTransitionTo(to));
}

test "invalid transition: CLOSED to ERROR" {
    const from = ChannelState.CLOSED;
    const to = ChannelState.ERROR;
    try testing.expect(!from.canTransitionTo(to));
}

test "invalid transition: JOINING to LEAVING" {
    const from = ChannelState.JOINING;
    const to = ChannelState.LEAVING;
    try testing.expect(!from.canTransitionTo(to));
}

test "invalid transition: JOINED to JOINING" {
    const from = ChannelState.JOINED;
    const to = ChannelState.JOINING;
    try testing.expect(!from.canTransitionTo(to));
}

test "invalid transition: LEAVING to JOINING" {
    const from = ChannelState.LEAVING;
    const to = ChannelState.JOINING;
    try testing.expect(!from.canTransitionTo(to));
}

test "invalid transition: LEAVING to JOINED" {
    const from = ChannelState.LEAVING;
    const to = ChannelState.JOINED;
    try testing.expect(!from.canTransitionTo(to));
}

test "invalid transition: LEAVING to ERROR" {
    const from = ChannelState.LEAVING;
    const to = ChannelState.ERROR;
    try testing.expect(!from.canTransitionTo(to));
}

test "invalid transition: ERROR to JOINED" {
    const from = ChannelState.ERROR;
    const to = ChannelState.JOINED;
    try testing.expect(!from.canTransitionTo(to));
}

test "invalid transition: ERROR to LEAVING" {
    const from = ChannelState.ERROR;
    const to = ChannelState.LEAVING;
    try testing.expect(!from.canTransitionTo(to));
}

// ----------------------------------------------------------------------------
// State Properties
// ----------------------------------------------------------------------------

test "CLOSED is closed" {
    try testing.expect(ChannelState.CLOSED.isClosed());
}

test "JOINING is not closed" {
    try testing.expect(!ChannelState.JOINING.isClosed());
}

test "CLOSED is not joined" {
    try testing.expect(!ChannelState.CLOSED.isJoined());
}

test "JOINING is not joined" {
    try testing.expect(!ChannelState.JOINING.isJoined());
}

test "JOINED is joined" {
    try testing.expect(ChannelState.JOINED.isJoined());
}

test "LEAVING is not joined" {
    try testing.expect(!ChannelState.LEAVING.isJoined());
}

test "ERROR is not joined" {
    try testing.expect(!ChannelState.ERROR.isJoined());
}

test "CLOSED cannot send" {
    try testing.expect(!ChannelState.CLOSED.canSend());
}

test "JOINING cannot send" {
    try testing.expect(!ChannelState.JOINING.canSend());
}

test "JOINED can send" {
    try testing.expect(ChannelState.JOINED.canSend());
}

test "LEAVING cannot send" {
    try testing.expect(!ChannelState.LEAVING.canSend());
}

test "ERROR cannot send" {
    try testing.expect(!ChannelState.ERROR.canSend());
}

test "CLOSED is not transitional" {
    try testing.expect(!ChannelState.CLOSED.isTransitional());
}

test "JOINING is transitional" {
    try testing.expect(ChannelState.JOINING.isTransitional());
}

test "JOINED is not transitional" {
    try testing.expect(!ChannelState.JOINED.isTransitional());
}

test "LEAVING is transitional" {
    try testing.expect(ChannelState.LEAVING.isTransitional());
}

test "ERROR is not transitional" {
    try testing.expect(!ChannelState.ERROR.isTransitional());
}

test "only ERROR is error state" {
    try testing.expect(!ChannelState.CLOSED.isError());
    try testing.expect(!ChannelState.JOINING.isError());
    try testing.expect(!ChannelState.JOINED.isError());
    try testing.expect(!ChannelState.LEAVING.isError());
    try testing.expect(ChannelState.ERROR.isError());
}

// ----------------------------------------------------------------------------
// State Sequences
// ----------------------------------------------------------------------------

test "complete join sequence: CLOSED -> JOINING -> JOINED" {
    var state = ChannelState.CLOSED;

    // CLOSED -> JOINING
    try testing.expect(state.canTransitionTo(.JOINING));
    state = .JOINING;

    // JOINING -> JOINED
    try testing.expect(state.canTransitionTo(.JOINED));
    state = .JOINED;

    try testing.expect(state.isJoined());
    try testing.expect(state.canSend());
}

test "graceful leave sequence: JOINED -> LEAVING -> CLOSED" {
    var state = ChannelState.JOINED;

    // JOINED -> LEAVING
    try testing.expect(state.canTransitionTo(.LEAVING));
    state = .LEAVING;

    // LEAVING -> CLOSED
    try testing.expect(state.canTransitionTo(.CLOSED));
    state = .CLOSED;

    try testing.expect(!state.isJoined());
    try testing.expect(!state.canSend());
}

test "error during join: JOINING -> ERROR -> CLOSED" {
    var state = ChannelState.JOINING;

    // JOINING -> ERROR
    try testing.expect(state.canTransitionTo(.ERROR));
    state = .ERROR;

    // ERROR -> CLOSED
    try testing.expect(state.canTransitionTo(.CLOSED));
    state = .CLOSED;

    try testing.expect(state.isClosed());
}

test "error during joined: JOINED -> ERROR -> JOINING -> JOINED (rejoin)" {
    var state = ChannelState.JOINED;

    // JOINED -> ERROR
    try testing.expect(state.canTransitionTo(.ERROR));
    state = .ERROR;

    // ERROR -> JOINING (rejoin)
    try testing.expect(state.canTransitionTo(.JOINING));
    state = .JOINING;

    // JOINING -> JOINED
    try testing.expect(state.canTransitionTo(.JOINED));
    state = .JOINED;

    try testing.expect(state.isJoined());
}

test "phx_close sequence: JOINED -> CLOSED (direct)" {
    var state = ChannelState.JOINED;

    // JOINED -> CLOSED (on phx_close, no LEAVING)
    try testing.expect(state.canTransitionTo(.CLOSED));
    state = .CLOSED;

    try testing.expect(state.isClosed());
}

test "join timeout: JOINING -> CLOSED" {
    var state = ChannelState.JOINING;

    // JOINING -> CLOSED (timeout)
    try testing.expect(state.canTransitionTo(.CLOSED));
    state = .CLOSED;

    try testing.expect(state.isClosed());
}

// ----------------------------------------------------------------------------
// toString Method
// ----------------------------------------------------------------------------

test "toString returns correct state names" {
    try testing.expectEqualStrings("CLOSED", ChannelState.CLOSED.toString());
    try testing.expectEqualStrings("JOINING", ChannelState.JOINING.toString());
    try testing.expectEqualStrings("JOINED", ChannelState.JOINED.toString());
    try testing.expectEqualStrings("LEAVING", ChannelState.LEAVING.toString());
    try testing.expectEqualStrings("ERROR", ChannelState.ERROR.toString());
}

// ----------------------------------------------------------------------------
// Edge Cases
// ----------------------------------------------------------------------------

test "no state can transition to itself (no idempotent transitions)" {
    const states = [_]ChannelState{
        .CLOSED,
        .JOINING,
        .JOINED,
        .LEAVING,
        .ERROR,
    };

    for (states) |state| {
        try testing.expect(!state.canTransitionTo(state));
    }
}

test "LEAVING can only transition to CLOSED" {
    const from = ChannelState.LEAVING;

    try testing.expect(from.canTransitionTo(.CLOSED));
    try testing.expect(!from.canTransitionTo(.JOINING));
    try testing.expect(!from.canTransitionTo(.JOINED));
    try testing.expect(!from.canTransitionTo(.LEAVING));
    try testing.expect(!from.canTransitionTo(.ERROR));
}

test "ERROR can only transition to CLOSED or JOINING" {
    const from = ChannelState.ERROR;

    try testing.expect(from.canTransitionTo(.CLOSED));
    try testing.expect(from.canTransitionTo(.JOINING));
    try testing.expect(!from.canTransitionTo(.JOINED));
    try testing.expect(!from.canTransitionTo(.LEAVING));
    try testing.expect(!from.canTransitionTo(.ERROR));
}

test "CLOSED can only transition to JOINING" {
    const from = ChannelState.CLOSED;

    try testing.expect(from.canTransitionTo(.JOINING));
    try testing.expect(!from.canTransitionTo(.CLOSED));
    try testing.expect(!from.canTransitionTo(.JOINED));
    try testing.expect(!from.canTransitionTo(.LEAVING));
    try testing.expect(!from.canTransitionTo(.ERROR));
}
