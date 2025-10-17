//! Phoenix Channels Protocol Constants
//!
//! This module defines all protocol-level constants used throughout the library,
//! including system event names, reserved topics, and protocol configuration.

/// System event names defined by the Phoenix protocol
pub const SystemEvents = struct {
    /// Join event - subscribe to a channel
    pub const JOIN = "phx_join";

    /// Leave event - unsubscribe from a channel
    pub const LEAVE = "phx_leave";

    /// Reply event - server response to client messages
    pub const REPLY = "phx_reply";

    /// Error event - channel error (triggers automatic rejoin)
    pub const ERROR = "phx_error";

    /// Close event - graceful channel closure (no rejoin)
    pub const CLOSE = "phx_close";

    /// Heartbeat event - connection keepalive
    pub const HEARTBEAT = "heartbeat";
};

/// Reserved topic names with special meaning
pub const ReservedTopics = struct {
    /// Phoenix system topic for heartbeats
    /// This topic doesn't require joining
    pub const PHOENIX = "phoenix";
};

/// Protocol configuration defaults
pub const Defaults = struct {
    /// Default heartbeat interval in milliseconds
    pub const HEARTBEAT_INTERVAL_MS: u32 = 30000;

    /// Default timeout for operations in milliseconds
    pub const TIMEOUT_MS: u32 = 10000;

    /// Default WebSocket subprotocol header
    pub const WEBSOCKET_SUBPROTOCOL = "sec-websocket-protocol: phoenix";
};

/// Reply status values
pub const ReplyStatus = struct {
    /// Successful operation
    pub const OK = "ok";

    /// Failed operation
    pub const ERROR = "error";

    /// Timeout occurred
    pub const TIMEOUT = "timeout";
};

test "system event constants are defined" {
    const std = @import("std");
    try std.testing.expectEqualStrings("phx_join", SystemEvents.JOIN);
    try std.testing.expectEqualStrings("phx_leave", SystemEvents.LEAVE);
    try std.testing.expectEqualStrings("phx_reply", SystemEvents.REPLY);
    try std.testing.expectEqualStrings("phx_error", SystemEvents.ERROR);
    try std.testing.expectEqualStrings("phx_close", SystemEvents.CLOSE);
    try std.testing.expectEqualStrings("heartbeat", SystemEvents.HEARTBEAT);
}

test "reserved topics are defined" {
    const std = @import("std");
    try std.testing.expectEqualStrings("phoenix", ReservedTopics.PHOENIX);
}

test "default values are reasonable" {
    const std = @import("std");
    try std.testing.expect(Defaults.HEARTBEAT_INTERVAL_MS == 30000);
    try std.testing.expect(Defaults.TIMEOUT_MS == 10000);
}
