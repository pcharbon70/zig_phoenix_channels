//! Phoenix Channel Implementation
//!
//! This module implements the Channel structure which represents a logical
//! subscription to a Phoenix topic. Channels have their own state machine
//! independent of the Socket state.
//!
//! Channel states:
//! - CLOSED: Not subscribed to the topic
//! - JOINING: Join request sent, waiting for confirmation
//! - JOINED: Successfully subscribed and can send/receive events
//! - LEAVING: Leave request sent, waiting for confirmation
//! - ERROR: Channel error occurred
//!
//! Implementation will be added in Phase 1, Task 1.4 (Channel State Machine)

const std = @import("std");
const State = @import("state.zig").ChannelState;

/// Channel configuration
pub const Config = struct {
    /// Channel topic (e.g., "room:lobby")
    topic: []const u8,

    /// Join timeout in milliseconds
    timeout_ms: u32 = 10000,
};

/// Phoenix Channel representing a subscription to a topic
pub const Channel = struct {
    allocator: std.mem.Allocator,
    config: Config,
    state: State,
    join_ref: ?[]const u8,

    /// Initialize a new channel
    pub fn init(allocator: std.mem.Allocator, config: Config) !*Channel {
        const channel = try allocator.create(Channel);
        channel.* = .{
            .allocator = allocator,
            .config = config,
            .state = .CLOSED,
            .join_ref = null,
        };
        return channel;
    }

    /// Clean up resources
    pub fn deinit(self: *Channel) void {
        // TODO: Implement cleanup in Task 1.4
        self.allocator.destroy(self);
    }

    /// Join the channel
    pub fn join(self: *Channel) !void {
        _ = self;
        // TODO: Implement in Task 1.4.3 (Join Operation)
        return error.NotImplemented;
    }

    /// Leave the channel
    pub fn leave(self: *Channel) !void {
        _ = self;
        // TODO: Implement in Task 1.4.4 (Leave Operation)
        return error.NotImplemented;
    }

    /// Push an event on the channel
    pub fn push(self: *Channel, event: []const u8, payload: anytype) !void {
        _ = self;
        _ = event;
        _ = payload;
        // TODO: Implement in Task 1.4.5 (Push Operation)
        return error.NotImplemented;
    }

    /// Get current channel state
    pub fn getState(self: *const Channel) State {
        return self.state;
    }
};

test "channel initialization" {
    const allocator = std.testing.allocator;

    const config = Config{
        .topic = "room:lobby",
    };

    const channel = try Channel.init(allocator, config);
    defer channel.deinit();

    try std.testing.expect(channel.getState() == .CLOSED);
    try std.testing.expectEqualStrings("room:lobby", channel.config.topic);
}
