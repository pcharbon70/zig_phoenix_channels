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
pub fn serialize(allocator: std.mem.Allocator, msg: *const message.PhoenixMessage) ![]u8 {
    _ = allocator;
    _ = msg;
    // TODO: Implement in Task 1.2.2 (JSON Serialization)
    return error.NotImplemented;
}

/// Deserialize a JSON array to PhoenixMessage
/// Returns a PhoenixMessage with owned string fields that must be freed
///
/// Phoenix message format: [join_ref, ref, topic, event, payload]
/// - join_ref: null or string
/// - ref: null or string
/// - topic: string (required)
/// - event: string (required)
/// - payload: JSON object (required)
///
/// Memory management:
/// - String fields (topic, event, join_ref, ref) are duplicated and owned by the message
/// - Payload is owned by the message
/// - Caller must call deinitOwned() on the returned message to free all memory
pub fn deserialize(allocator: std.mem.Allocator, json: []const u8) !message.PhoenixMessage {
    // Parse JSON
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
    defer parsed.deinit();

    // Validate it's an array
    if (parsed.value != .array) {
        return error.InvalidMessage;
    }

    const array = parsed.value.array;

    // Validate array has exactly 5 elements
    if (array.items.len != 5) {
        return error.InvalidMessage;
    }

    // Parse field 1: join_ref (nullable string)
    const join_ref = if (array.items[0] == .null)
        null
    else if (array.items[0] == .string)
        try allocator.dupe(u8, array.items[0].string)
    else
        return error.InvalidMessage;
    errdefer if (join_ref) |jr| allocator.free(jr);

    // Parse field 2: ref (nullable string)
    const ref = if (array.items[1] == .null)
        null
    else if (array.items[1] == .string)
        try allocator.dupe(u8, array.items[1].string)
    else
        return error.InvalidMessage;
    errdefer if (ref) |r| allocator.free(r);

    // Parse field 3: topic (required string)
    if (array.items[2] != .string) {
        return error.InvalidMessage;
    }
    const topic = try allocator.dupe(u8, array.items[2].string);
    errdefer allocator.free(topic);

    // Parse field 4: event (required string)
    if (array.items[3] != .string) {
        return error.InvalidMessage;
    }
    const event = try allocator.dupe(u8, array.items[3].string);
    errdefer allocator.free(event);

    // Parse field 5: payload (must be object)
    if (array.items[4] != .object) {
        return error.InvalidMessage;
    }

    // Deep copy the payload object
    const payload = try deepCopyValue(allocator, array.items[4]);
    errdefer freeValue(allocator, payload);

    return message.PhoenixMessage{
        .join_ref = join_ref,
        .ref = ref,
        .topic = topic,
        .event = event,
        .payload = payload,
        .allocator = allocator,
    };
}

/// Deep copy a JSON value with a new allocator
fn deepCopyValue(allocator: std.mem.Allocator, value: std.json.Value) !std.json.Value {
    return switch (value) {
        .null => .null,
        .bool => |b| .{ .bool = b },
        .integer => |i| .{ .integer = i },
        .float => |f| .{ .float = f },
        .number_string => |ns| .{ .number_string = try allocator.dupe(u8, ns) },
        .string => |s| .{ .string = try allocator.dupe(u8, s) },
        .array => |arr| {
            var new_array = std.json.Array.init(allocator);
            errdefer new_array.deinit();

            for (arr.items) |item| {
                const copied_item = try deepCopyValue(allocator, item);
                try new_array.append(copied_item);
            }

            return .{ .array = new_array };
        },
        .object => |obj| {
            var new_obj = std.json.ObjectMap.init(allocator);
            errdefer new_obj.deinit();

            var iter = obj.iterator();
            while (iter.next()) |entry| {
                const key = try allocator.dupe(u8, entry.key_ptr.*);
                const value_copy = try deepCopyValue(allocator, entry.value_ptr.*);
                try new_obj.put(key, value_copy);
            }

            return .{ .object = new_obj };
        },
    };
}

/// Free a JSON value and all its contents
fn freeValue(allocator: std.mem.Allocator, value: std.json.Value) void {
    switch (value) {
        .null, .bool, .integer, .float => {},
        .number_string => |ns| allocator.free(ns),
        .string => |s| allocator.free(s),
        .array => |arr| {
            for (arr.items) |item| {
                freeValue(allocator, item);
            }
            arr.deinit();
        },
        .object => |obj| {
            var iter = obj.iterator();
            while (iter.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                freeValue(allocator, entry.value_ptr.*);
            }
            obj.deinit();
        },
    }
}

// ============================================================================
// Tests
// ============================================================================

test "deserialize: basic message with null references" {
    const allocator = std.testing.allocator;

    const json = "[null,null,\"room:lobby\",\"new_msg\",{}]";
    const msg = try deserialize(allocator, json);
    defer deinitOwned(allocator, msg);

    try std.testing.expect(msg.join_ref == null);
    try std.testing.expect(msg.ref == null);
    try std.testing.expectEqualStrings("room:lobby", msg.topic);
    try std.testing.expectEqualStrings("new_msg", msg.event);
    try std.testing.expect(msg.payload == .object);
}

test "deserialize: join message with join_ref and ref" {
    const allocator = std.testing.allocator;

    const json = "[\"1\",\"1\",\"room:lobby\",\"phx_join\",{}]";
    const msg = try deserialize(allocator, json);
    defer deinitOwned(allocator, msg);

    try std.testing.expectEqualStrings("1", msg.join_ref.?);
    try std.testing.expectEqualStrings("1", msg.ref.?);
    try std.testing.expectEqualStrings("room:lobby", msg.topic);
    try std.testing.expectEqualStrings("phx_join", msg.event);
}

test "deserialize: heartbeat message" {
    const allocator = std.testing.allocator;

    const json = "[null,\"5\",\"phoenix\",\"heartbeat\",{}]";
    const msg = try deserialize(allocator, json);
    defer deinitOwned(allocator, msg);

    try std.testing.expect(msg.join_ref == null);
    try std.testing.expectEqualStrings("5", msg.ref.?);
    try std.testing.expectEqualStrings("phoenix", msg.topic);
    try std.testing.expectEqualStrings("heartbeat", msg.event);
}

test "deserialize: message with payload data" {
    const allocator = std.testing.allocator;

    const json = "[null,\"10\",\"room:lobby\",\"new_msg\",{\"user\":\"alice\",\"message\":\"Hello\"}]";
    const msg = try deserialize(allocator, json);
    defer deinitOwned(allocator, msg);

    try std.testing.expectEqualStrings("room:lobby", msg.topic);
    try std.testing.expect(msg.payload == .object);

    const user = msg.payload.object.get("user");
    try std.testing.expect(user != null);
    try std.testing.expectEqualStrings("alice", user.?.string);

    const msg_text = msg.payload.object.get("message");
    try std.testing.expect(msg_text != null);
    try std.testing.expectEqualStrings("Hello", msg_text.?.string);
}

test "deserialize: nested payload structure" {
    const allocator = std.testing.allocator;

    const json = "[null,null,\"test\",\"event\",{\"nested\":{\"key\":\"value\"},\"count\":42}]";
    const msg = try deserialize(allocator, json);
    defer deinitOwned(allocator, msg);

    const nested = msg.payload.object.get("nested");
    try std.testing.expect(nested != null);
    try std.testing.expect(nested.? == .object);

    const key = nested.?.object.get("key");
    try std.testing.expect(key != null);
    try std.testing.expectEqualStrings("value", key.?.string);

    const count = msg.payload.object.get("count");
    try std.testing.expect(count != null);
    try std.testing.expectEqual(@as(i64, 42), count.?.integer);
}

test "deserialize: error on wrong array length" {
    const allocator = std.testing.allocator;

    const json = "[null,null,\"topic\"]"; // Only 3 elements
    const result = deserialize(allocator, json);
    try std.testing.expectError(error.InvalidMessage, result);
}

test "deserialize: error on non-array" {
    const allocator = std.testing.allocator;

    const json = "{\"not\":\"an array\"}";
    const result = deserialize(allocator, json);
    try std.testing.expectError(error.InvalidMessage, result);
}

test "deserialize: error on missing topic" {
    const allocator = std.testing.allocator;

    const json = "[null,null,null,\"event\",{}]"; // topic is null
    const result = deserialize(allocator, json);
    try std.testing.expectError(error.InvalidMessage, result);
}

test "deserialize: error on missing event" {
    const allocator = std.testing.allocator;

    const json = "[null,null,\"topic\",null,{}]"; // event is null
    const result = deserialize(allocator, json);
    try std.testing.expectError(error.InvalidMessage, result);
}

test "deserialize: error on non-object payload" {
    const allocator = std.testing.allocator;

    const json = "[null,null,\"topic\",\"event\",\"not an object\"]";
    const result = deserialize(allocator, json);
    try std.testing.expectError(error.InvalidMessage, result);
}

/// Free all owned memory in a deserialized message
/// Call this instead of deinit() for messages from deserialize()
pub fn deinitOwned(allocator: std.mem.Allocator, msg: message.PhoenixMessage) void {
    if (msg.join_ref) |jr| allocator.free(jr);
    if (msg.ref) |r| allocator.free(r);
    allocator.free(msg.topic);
    allocator.free(msg.event);
    freeValue(allocator, msg.payload);
}
