//! Phoenix Channels Protocol Message Implementation
//!
//! This module defines the PhoenixMessage structure and provides serialization/
//! deserialization functionality for the Phoenix V2 protocol message format.
//!
//! Phoenix messages are 5-element JSON arrays:
//! [join_ref, ref, topic, event, payload]
//!
//! Field descriptions:
//! - join_ref: Reference for the channel join (required for phx_join, null otherwise)
//! - ref: Unique message reference for matching replies
//! - topic: Channel topic (e.g., "room:lobby", "phoenix" for heartbeat)
//! - event: Event name (e.g., "phx_join", "phx_reply", custom events)
//! - payload: JSON object containing event data

const std = @import("std");

/// Phoenix protocol message structure
/// Represents the 5-field message format: [join_ref, ref, topic, event, payload]
pub const PhoenixMessage = struct {
    /// Join reference (required for phx_join events, null otherwise)
    join_ref: ?[]const u8,

    /// Message reference for matching replies (should be unique per socket)
    ref: ?[]const u8,

    /// Channel topic (e.g., "room:lobby", "phoenix")
    topic: []const u8,

    /// Event name (e.g., "phx_join", "phx_reply", custom events)
    event: []const u8,

    /// Event payload as JSON object
    /// Note: Phoenix requires this to be an object, not a primitive
    payload: std.json.Value,

    /// Allocator used for memory management
    allocator: std.mem.Allocator,

    /// Initialize a new Phoenix message
    pub fn init(
        allocator: std.mem.Allocator,
        topic: []const u8,
        event: []const u8,
        payload: std.json.Value,
    ) PhoenixMessage {
        return .{
            .join_ref = null,
            .ref = null,
            .topic = topic,
            .event = event,
            .payload = payload,
            .allocator = allocator,
        };
    }

    /// Clean up resources
    pub fn deinit(self: *PhoenixMessage) void {
        // Payload cleanup will be handled by the caller
        // as it may be shared or have external ownership
        _ = self;
    }
};

test "PhoenixMessage initialization" {
    const allocator = std.testing.allocator;

    const payload = std.json.Value{ .object = std.json.ObjectMap.init(allocator) };
    defer payload.object.deinit();

    var message = PhoenixMessage.init(
        allocator,
        "room:lobby",
        "test_event",
        payload,
    );
    defer message.deinit();

    try std.testing.expectEqualStrings("room:lobby", message.topic);
    try std.testing.expectEqualStrings("test_event", message.event);
    try std.testing.expect(message.join_ref == null);
    try std.testing.expect(message.ref == null);
}
