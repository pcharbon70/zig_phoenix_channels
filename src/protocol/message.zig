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
const constants = @import("constants.zig");

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

    /// Create a join message for subscribing to a channel
    /// join_ref and ref are typically the same for join messages
    pub fn initJoin(
        allocator: std.mem.Allocator,
        topic: []const u8,
        join_ref: []const u8,
        payload: std.json.Value,
    ) PhoenixMessage {
        return .{
            .join_ref = join_ref,
            .ref = join_ref,
            .topic = topic,
            .event = constants.SystemEvents.JOIN,
            .payload = payload,
            .allocator = allocator,
        };
    }

    /// Create a leave message for unsubscribing from a channel
    pub fn initLeave(
        allocator: std.mem.Allocator,
        topic: []const u8,
        ref: []const u8,
        payload: std.json.Value,
    ) PhoenixMessage {
        return .{
            .join_ref = null,
            .ref = ref,
            .topic = topic,
            .event = constants.SystemEvents.LEAVE,
            .payload = payload,
            .allocator = allocator,
        };
    }

    /// Create a heartbeat message for connection keepalive
    /// Heartbeat messages go to the "phoenix" topic
    pub fn initHeartbeat(
        allocator: std.mem.Allocator,
        ref: []const u8,
        payload: std.json.Value,
    ) PhoenixMessage {
        return .{
            .join_ref = null,
            .ref = ref,
            .topic = constants.ReservedTopics.PHOENIX,
            .event = constants.SystemEvents.HEARTBEAT,
            .payload = payload,
            .allocator = allocator,
        };
    }

    /// Create a custom event message (user-defined events)
    pub fn initEvent(
        allocator: std.mem.Allocator,
        topic: []const u8,
        event: []const u8,
        ref: []const u8,
        payload: std.json.Value,
    ) PhoenixMessage {
        return .{
            .join_ref = null,
            .ref = ref,
            .topic = topic,
            .event = event,
            .payload = payload,
            .allocator = allocator,
        };
    }

    /// Create an empty payload (empty JSON object)
    pub fn emptyPayload(allocator: std.mem.Allocator) !std.json.Value {
        return std.json.Value{ .object = std.json.ObjectMap.init(allocator) };
    }

    /// Clean up resources
    /// Note: Caller is responsible for cleaning up payload if it owns it
    pub fn deinit(self: *PhoenixMessage) void {
        // The payload cleanup is the caller's responsibility
        // as payload ownership varies (may be shared, borrowed, or owned)
        //
        // If you own the payload, call:
        //   switch (message.payload) {
        //       .object => |obj| obj.deinit(),
        //       else => {},
        //   }
        _ = self;
    }

    /// Check if this message is a system event
    pub fn isSystemEvent(self: *const PhoenixMessage) bool {
        return std.mem.eql(u8, self.event, constants.SystemEvents.JOIN) or
            std.mem.eql(u8, self.event, constants.SystemEvents.LEAVE) or
            std.mem.eql(u8, self.event, constants.SystemEvents.REPLY) or
            std.mem.eql(u8, self.event, constants.SystemEvents.ERROR) or
            std.mem.eql(u8, self.event, constants.SystemEvents.CLOSE) or
            std.mem.eql(u8, self.event, constants.SystemEvents.HEARTBEAT);
    }

    /// Check if this is a join message
    pub fn isJoin(self: *const PhoenixMessage) bool {
        return std.mem.eql(u8, self.event, constants.SystemEvents.JOIN);
    }

    /// Check if this is a leave message
    pub fn isLeave(self: *const PhoenixMessage) bool {
        return std.mem.eql(u8, self.event, constants.SystemEvents.LEAVE);
    }

    /// Check if this is a heartbeat message
    pub fn isHeartbeat(self: *const PhoenixMessage) bool {
        return std.mem.eql(u8, self.event, constants.SystemEvents.HEARTBEAT);
    }

    /// Check if this is a reply message
    pub fn isReply(self: *const PhoenixMessage) bool {
        return std.mem.eql(u8, self.event, constants.SystemEvents.REPLY);
    }
};

// ============================================================================
// Tests
// ============================================================================

test "PhoenixMessage initialization" {
    const allocator = std.testing.allocator;

    var payload = try PhoenixMessage.emptyPayload(allocator);
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

test "PhoenixMessage initJoin creates proper join message" {
    const allocator = std.testing.allocator;

    var payload = try PhoenixMessage.emptyPayload(allocator);
    defer payload.object.deinit();

    var message = PhoenixMessage.initJoin(
        allocator,
        "room:lobby",
        "1",
        payload,
    );
    defer message.deinit();

    try std.testing.expectEqualStrings("room:lobby", message.topic);
    try std.testing.expectEqualStrings(constants.SystemEvents.JOIN, message.event);
    try std.testing.expectEqualStrings("1", message.join_ref.?);
    try std.testing.expectEqualStrings("1", message.ref.?);
    try std.testing.expect(message.isJoin());
    try std.testing.expect(message.isSystemEvent());
}

test "PhoenixMessage initLeave creates proper leave message" {
    const allocator = std.testing.allocator;

    var payload = try PhoenixMessage.emptyPayload(allocator);
    defer payload.object.deinit();

    var message = PhoenixMessage.initLeave(
        allocator,
        "room:lobby",
        "2",
        payload,
    );
    defer message.deinit();

    try std.testing.expectEqualStrings("room:lobby", message.topic);
    try std.testing.expectEqualStrings(constants.SystemEvents.LEAVE, message.event);
    try std.testing.expect(message.join_ref == null);
    try std.testing.expectEqualStrings("2", message.ref.?);
    try std.testing.expect(message.isLeave());
    try std.testing.expect(message.isSystemEvent());
}

test "PhoenixMessage initHeartbeat creates proper heartbeat message" {
    const allocator = std.testing.allocator;

    var payload = try PhoenixMessage.emptyPayload(allocator);
    defer payload.object.deinit();

    var message = PhoenixMessage.initHeartbeat(
        allocator,
        "3",
        payload,
    );
    defer message.deinit();

    try std.testing.expectEqualStrings(constants.ReservedTopics.PHOENIX, message.topic);
    try std.testing.expectEqualStrings(constants.SystemEvents.HEARTBEAT, message.event);
    try std.testing.expect(message.join_ref == null);
    try std.testing.expectEqualStrings("3", message.ref.?);
    try std.testing.expect(message.isHeartbeat());
    try std.testing.expect(message.isSystemEvent());
}

test "PhoenixMessage initEvent creates proper custom event message" {
    const allocator = std.testing.allocator;

    var payload = try PhoenixMessage.emptyPayload(allocator);
    defer payload.object.deinit();

    var message = PhoenixMessage.initEvent(
        allocator,
        "room:lobby",
        "new_message",
        "4",
        payload,
    );
    defer message.deinit();

    try std.testing.expectEqualStrings("room:lobby", message.topic);
    try std.testing.expectEqualStrings("new_message", message.event);
    try std.testing.expect(message.join_ref == null);
    try std.testing.expectEqualStrings("4", message.ref.?);
    try std.testing.expect(!message.isSystemEvent());
}

test "PhoenixMessage emptyPayload creates valid empty object" {
    const allocator = std.testing.allocator;

    var payload = try PhoenixMessage.emptyPayload(allocator);
    defer payload.object.deinit();

    try std.testing.expect(payload == .object);
    try std.testing.expectEqual(@as(usize, 0), payload.object.count());
}

test "PhoenixMessage system event detection" {
    const allocator = std.testing.allocator;

    var payload = try PhoenixMessage.emptyPayload(allocator);
    defer payload.object.deinit();

    // Test join
    var join_msg = PhoenixMessage.initJoin(allocator, "room:lobby", "1", payload);
    try std.testing.expect(join_msg.isJoin());
    try std.testing.expect(!join_msg.isLeave());
    try std.testing.expect(!join_msg.isHeartbeat());
    try std.testing.expect(!join_msg.isReply());

    // Test leave
    var leave_msg = PhoenixMessage.initLeave(allocator, "room:lobby", "2", payload);
    try std.testing.expect(!leave_msg.isJoin());
    try std.testing.expect(leave_msg.isLeave());
    try std.testing.expect(!leave_msg.isHeartbeat());
    try std.testing.expect(!leave_msg.isReply());

    // Test heartbeat
    var hb_msg = PhoenixMessage.initHeartbeat(allocator, "3", payload);
    try std.testing.expect(!hb_msg.isJoin());
    try std.testing.expect(!hb_msg.isLeave());
    try std.testing.expect(hb_msg.isHeartbeat());
    try std.testing.expect(!hb_msg.isReply());

    // Test custom event
    var custom_msg = PhoenixMessage.initEvent(allocator, "room:lobby", "custom", "4", payload);
    try std.testing.expect(!custom_msg.isJoin());
    try std.testing.expect(!custom_msg.isLeave());
    try std.testing.expect(!custom_msg.isHeartbeat());
    try std.testing.expect(!custom_msg.isReply());
    try std.testing.expect(!custom_msg.isSystemEvent());
}
