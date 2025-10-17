//! Phoenix Socket Implementation
//!
//! This module implements the PhoenixSocket structure which manages the WebSocket
//! connection lifecycle, message routing, heartbeat coordination, and channel registry.
//!
//! The Socket implements a state machine with five states:
//! - DISCONNECTED: No connection established
//! - CONNECTING: Connection in progress
//! - CONNECTED: Active connection
//! - CLOSING: Graceful shutdown in progress
//! - ERROR: Connection error occurred
//!
//! Implementation will be added in Phase 1, Task 1.3 (Socket State Machine)

const std = @import("std");
const State = @import("state.zig").ConnectionState;

/// Phoenix Socket configuration
pub const Config = struct {
    /// WebSocket URL (e.g., "ws://localhost:4000/socket/websocket")
    url: []const u8,

    /// Connection timeout in milliseconds
    timeout_ms: u32 = 10000,

    /// Heartbeat interval in milliseconds
    heartbeat_interval_ms: u32 = 30000,
};

/// Phoenix Socket managing WebSocket connection
pub const PhoenixSocket = struct {
    allocator: std.mem.Allocator,
    config: Config,
    state: State,

    /// Initialize a new Phoenix socket
    pub fn init(allocator: std.mem.Allocator, config: Config) !*PhoenixSocket {
        const socket = try allocator.create(PhoenixSocket);
        socket.* = .{
            .allocator = allocator,
            .config = config,
            .state = .DISCONNECTED,
        };
        return socket;
    }

    /// Clean up resources
    pub fn deinit(self: *PhoenixSocket) void {
        // TODO: Implement cleanup in Task 1.3
        self.allocator.destroy(self);
    }

    /// Connect to the Phoenix server
    pub fn connect(self: *PhoenixSocket) !void {
        _ = self;
        // TODO: Implement in Task 1.3.3 (Connection Lifecycle)
        return error.NotImplemented;
    }

    /// Disconnect from the Phoenix server
    pub fn disconnect(self: *PhoenixSocket) !void {
        _ = self;
        // TODO: Implement in Task 1.3.3 (Connection Lifecycle)
        return error.NotImplemented;
    }

    /// Get current connection state
    pub fn getState(self: *const PhoenixSocket) State {
        return self.state;
    }
};

test "socket initialization" {
    const allocator = std.testing.allocator;

    const config = Config{
        .url = "ws://localhost:4000/socket/websocket",
    };

    const socket = try PhoenixSocket.init(allocator, config);
    defer socket.deinit();

    try std.testing.expect(socket.getState() == .DISCONNECTED);
}
