//! Phoenix Message Serialization and Deserialization
//!
//! This module provides functions for converting PhoenixMessage structures to/from
//! the JSON array format used by the Phoenix V2 protocol.
//!
//! Message format: [join_ref, ref, topic, event, payload]

const std = @import("std");
const message = @import("message.zig");

/// Serialize a PhoenixMessage to JSON array format
/// Returns owned memory that must be freed by the caller
///
/// Phoenix message format: [join_ref, ref, topic, event, payload]
/// - join_ref: null or string
/// - ref: null or string
/// - topic: string (required)
/// - event: string (required)
/// - payload: JSON object (required)
pub fn serialize(allocator: std.mem.Allocator, msg: *const message.PhoenixMessage) ![]u8 {
    var buffer = std.ArrayList(u8).init(allocator);
    errdefer buffer.deinit();

    var writer = buffer.writer();

    // Start array
    try writer.writeByte('[');

    // Field 1: join_ref (nullable)
    if (msg.join_ref) |join_ref| {
        try std.json.encodeJsonString(join_ref, .{}, writer);
    } else {
        try writer.writeAll("null");
    }
    try writer.writeByte(',');

    // Field 2: ref (nullable)
    if (msg.ref) |ref| {
        try std.json.encodeJsonString(ref, .{}, writer);
    } else {
        try writer.writeAll("null");
    }
    try writer.writeByte(',');

    // Field 3: topic (required)
    try std.json.encodeJsonString(msg.topic, .{}, writer);
    try writer.writeByte(',');

    // Field 4: event (required)
    try std.json.encodeJsonString(msg.event, .{}, writer);
    try writer.writeByte(',');

    // Field 5: payload (JSON value)
    try std.json.stringify(msg.payload, .{}, writer);

    // End array
    try writer.writeByte(']');

    return buffer.toOwnedSlice();
}

/// Deserialize a JSON array to PhoenixMessage
/// Returns owned PhoenixMessage that must be freed by the caller
pub fn deserialize(allocator: std.mem.Allocator, json: []const u8) !message.PhoenixMessage {
    _ = allocator;
    _ = json;
    // TODO: Implement in Task 1.2.3 (JSON Deserialization)
    return error.NotImplemented;
}

// ============================================================================
// Tests
// ============================================================================

test "serialize: basic message with null references" {
    const allocator = std.testing.allocator;

    var payload = try message.PhoenixMessage.emptyPayload(allocator);
    defer payload.object.deinit();

    var msg = message.PhoenixMessage.init(
        allocator,
        "room:lobby",
        "new_msg",
        payload,
    );
    defer msg.deinit();

    const json = try serialize(allocator, &msg);
    defer allocator.free(json);

    try std.testing.expectEqualStrings(
        "[null,null,\"room:lobby\",\"new_msg\",{}]",
        json,
    );
}

test "serialize: join message with join_ref and ref" {
    const allocator = std.testing.allocator;

    var payload = try message.PhoenixMessage.emptyPayload(allocator);
    defer payload.object.deinit();

    var msg = message.PhoenixMessage.initJoin(
        allocator,
        "room:lobby",
        "1",
        payload,
    );
    defer msg.deinit();

    const json = try serialize(allocator, &msg);
    defer allocator.free(json);

    try std.testing.expectEqualStrings(
        "[\"1\",\"1\",\"room:lobby\",\"phx_join\",{}]",
        json,
    );
}

test "serialize: heartbeat message" {
    const allocator = std.testing.allocator;

    var payload = try message.PhoenixMessage.emptyPayload(allocator);
    defer payload.object.deinit();

    var msg = message.PhoenixMessage.initHeartbeat(
        allocator,
        "5",
        payload,
    );
    defer msg.deinit();

    const json = try serialize(allocator, &msg);
    defer allocator.free(json);

    try std.testing.expectEqualStrings(
        "[null,\"5\",\"phoenix\",\"heartbeat\",{}]",
        json,
    );
}

test "serialize: message with payload data" {
    const allocator = std.testing.allocator;

    // Create payload with some data
    var payload_obj = std.json.ObjectMap.init(allocator);
    defer payload_obj.deinit();

    try payload_obj.put("user", .{ .string = "alice" });
    try payload_obj.put("message", .{ .string = "Hello, world!" });

    const payload = std.json.Value{ .object = payload_obj };

    var msg = message.PhoenixMessage.initEvent(
        allocator,
        "room:lobby",
        "new_msg",
        "10",
        payload,
    );
    defer msg.deinit();

    const json = try serialize(allocator, &msg);
    defer allocator.free(json);

    // Parse the JSON to verify structure
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
    defer parsed.deinit();

    try std.testing.expect(parsed.value == .array);
    try std.testing.expectEqual(@as(usize, 5), parsed.value.array.items.len);

    // Verify array elements
    try std.testing.expect(parsed.value.array.items[0] == .null);
    try std.testing.expectEqualStrings("10", parsed.value.array.items[1].string);
    try std.testing.expectEqualStrings("room:lobby", parsed.value.array.items[2].string);
    try std.testing.expectEqualStrings("new_msg", parsed.value.array.items[3].string);
    try std.testing.expect(parsed.value.array.items[4] == .object);
}

test "serialize: special characters in topic and event" {
    const allocator = std.testing.allocator;

    var payload = try message.PhoenixMessage.emptyPayload(allocator);
    defer payload.object.deinit();

    var msg = message.PhoenixMessage.initEvent(
        allocator,
        "room:\"special\"",
        "event:with:colons",
        "1",
        payload,
    );
    defer msg.deinit();

    const json = try serialize(allocator, &msg);
    defer allocator.free(json);

    // Verify JSON is properly escaped
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
    defer parsed.deinit();

    try std.testing.expectEqualStrings("room:\"special\"", parsed.value.array.items[2].string);
    try std.testing.expectEqualStrings("event:with:colons", parsed.value.array.items[3].string);
}

test "serialize: nested payload structure" {
    const allocator = std.testing.allocator;

    // Create nested payload
    var inner_obj = std.json.ObjectMap.init(allocator);
    try inner_obj.put("key", .{ .string = "value" });

    var payload_obj = std.json.ObjectMap.init(allocator);
    defer payload_obj.deinit();
    defer inner_obj.deinit();

    try payload_obj.put("nested", .{ .object = inner_obj });
    try payload_obj.put("count", .{ .integer = 42 });

    const payload = std.json.Value{ .object = payload_obj };

    var msg = message.PhoenixMessage.init(
        allocator,
        "room:lobby",
        "complex",
        payload,
    );
    defer msg.deinit();

    const json = try serialize(allocator, &msg);
    defer allocator.free(json);

    // Verify nested structure is preserved
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
    defer parsed.deinit();

    const payload_value = parsed.value.array.items[4];
    try std.testing.expect(payload_value == .object);
    try std.testing.expect(payload_value.object.get("nested").? == .object);
    try std.testing.expectEqual(@as(i64, 42), payload_value.object.get("count").?.integer);
}

test "serialize: empty payload object" {
    const allocator = std.testing.allocator;

    var payload = try message.PhoenixMessage.emptyPayload(allocator);
    defer payload.object.deinit();

    var msg = message.PhoenixMessage.init(
        allocator,
        "test:topic",
        "test_event",
        payload,
    );
    defer msg.deinit();

    const json = try serialize(allocator, &msg);
    defer allocator.free(json);

    try std.testing.expectEqualStrings(
        "[null,null,\"test:topic\",\"test_event\",{}]",
        json,
    );
}
