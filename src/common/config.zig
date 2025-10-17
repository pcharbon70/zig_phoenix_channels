//! Common Configuration
//!
//! This module defines configuration structures used throughout the library.

const std = @import("std");

/// Phoenix Channels library configuration
pub const PhoenixConfig = struct {
    /// Enable debug logging
    debug: bool = false,

    /// Maximum message size in bytes
    max_message_size: usize = 65536,

    /// Connection timeout in milliseconds
    connection_timeout_ms: u32 = 10000,

    /// Heartbeat interval in milliseconds
    heartbeat_interval_ms: u32 = 30000,

    /// Join timeout in milliseconds
    join_timeout_ms: u32 = 10000,

    /// Maximum reconnection attempts (0 = infinite)
    max_reconnect_attempts: u32 = 0,

    /// Initial reconnection delay in milliseconds
    reconnect_delay_ms: u32 = 1000,

    /// Maximum reconnection delay in milliseconds
    max_reconnect_delay_ms: u32 = 10000,
};

/// Get default configuration
pub fn defaultConfig() PhoenixConfig {
    return .{};
}

test "default configuration has sensible values" {
    const config = defaultConfig();

    try std.testing.expect(!config.debug);
    try std.testing.expect(config.max_message_size == 65536);
    try std.testing.expect(config.connection_timeout_ms == 10000);
    try std.testing.expect(config.heartbeat_interval_ms == 30000);
}
