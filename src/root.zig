//! Phoenix Channels client library for Zig
//!
//! This library provides a client implementation of the Phoenix Channels
//! protocol for real-time communication with Phoenix servers.

const std = @import("std");

// Library version
pub const version = "0.1.0";

// WebSocket wrapper for Phoenix protocol
pub const WebSocketWrapper = @import("websocket_wrapper.zig").WebSocketWrapper;

// This is the library entry point. Components will be exported here
// as they are implemented in subsequent phases.

test "library imports std" {
    _ = std;
}
