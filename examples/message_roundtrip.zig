// Example demonstrating complete message functionality:
// Create -> Serialize -> Deserialize -> Validate

const std = @import("std");
const phoenix = @import("phoenix_channels");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n=== Phoenix Channels Message Round-Trip Demo ===\n\n", .{});

    // Example 1: Join Message
    {
        std.debug.print("1. Join Message\n", .{});
        std.debug.print("---------------\n", .{});

        // Create join message
        var payload = try phoenix.protocol.PhoenixMessage.emptyPayload(allocator);
        defer payload.object.deinit();

        var join_msg = phoenix.protocol.PhoenixMessage.initJoin(
            allocator,
            "room:lobby",
            "1",
            payload,
        );
        defer join_msg.deinit();

        std.debug.print("Created: topic={s}, event={s}, ref={s}, join_ref={s}\n", .{
            join_msg.topic,
            join_msg.event,
            join_msg.ref.?,
            join_msg.join_ref.?,
        });

        // Validate before sending
        try join_msg.validateForSend();
        std.debug.print("✓ Validation passed (client-to-server)\n", .{});

        // Serialize
        const json = try phoenix.protocol.serializer.serialize(allocator, &join_msg);
        defer allocator.free(json);
        std.debug.print("Serialized: {s}\n", .{json});

        // Deserialize
        const received_msg = try phoenix.protocol.serializer.deserialize(allocator, json);
        defer phoenix.protocol.serializer.deinitOwned(allocator, received_msg);
        std.debug.print("Deserialized: topic={s}, event={s}\n", .{
            received_msg.topic,
            received_msg.event,
        });

        // Validate received message
        try received_msg.validate();
        std.debug.print("✓ Validation passed (general)\n\n", .{});
    }

    // Example 2: Heartbeat Message
    {
        std.debug.print("2. Heartbeat Message\n", .{});
        std.debug.print("--------------------\n", .{});

        var payload = try phoenix.protocol.PhoenixMessage.emptyPayload(allocator);
        defer payload.object.deinit();

        var hb_msg = phoenix.protocol.PhoenixMessage.initHeartbeat(
            allocator,
            "5",
            payload,
        );
        defer hb_msg.deinit();

        std.debug.print("Created: topic={s}, event={s}, ref={s}\n", .{
            hb_msg.topic,
            hb_msg.event,
            hb_msg.ref.?,
        });

        try hb_msg.validateForSend();
        std.debug.print("✓ Validation passed (heartbeat uses 'phoenix' topic)\n", .{});

        const json = try phoenix.protocol.serializer.serialize(allocator, &hb_msg);
        defer allocator.free(json);
        std.debug.print("Serialized: {s}\n", .{json});

        const received_msg = try phoenix.protocol.serializer.deserialize(allocator, json);
        defer phoenix.protocol.serializer.deinitOwned(allocator, received_msg);
        std.debug.print("Deserialized: {s}\n", .{received_msg.topic});
        std.debug.print("✓ Round-trip successful\n\n", .{});
    }

    // Example 3: Custom Event with Payload
    {
        std.debug.print("3. Custom Event with Payload\n", .{});
        std.debug.print("-----------------------------\n", .{});

        // Create payload with data
        var payload_obj = std.json.ObjectMap.init(allocator);
        defer payload_obj.deinit();

        try payload_obj.put("user", .{ .string = "alice" });
        try payload_obj.put("message", .{ .string = "Hello, Phoenix!" });

        const payload = std.json.Value{ .object = payload_obj };

        var custom_msg = phoenix.protocol.PhoenixMessage.initEvent(
            allocator,
            "room:lobby",
            "new_msg",
            "10",
            payload,
        );
        defer custom_msg.deinit();

        std.debug.print("Created: event={s}, ref={s}\n", .{
            custom_msg.event,
            custom_msg.ref.?,
        });

        try custom_msg.validateForSend();
        std.debug.print("✓ Validation passed\n", .{});

        const json = try phoenix.protocol.serializer.serialize(allocator, &custom_msg);
        defer allocator.free(json);
        std.debug.print("Serialized: {s}\n", .{json});

        const received_msg = try phoenix.protocol.serializer.deserialize(allocator, json);
        defer phoenix.protocol.serializer.deinitOwned(allocator, received_msg);

        // Access payload data
        const user = received_msg.payload.object.get("user");
        const msg_text = received_msg.payload.object.get("message");

        std.debug.print("Deserialized payload: user={s}, message={s}\n", .{
            user.?.string,
            msg_text.?.string,
        });
        std.debug.print("✓ Payload preserved correctly\n\n", .{});
    }

    // Example 4: Validation Error Detection
    {
        std.debug.print("4. Validation Error Detection\n", .{});
        std.debug.print("------------------------------\n", .{});

        var payload = try phoenix.protocol.PhoenixMessage.emptyPayload(allocator);
        defer payload.object.deinit();

        // Create a phx_join without join_ref (invalid!)
        var invalid_msg = phoenix.protocol.PhoenixMessage{
            .join_ref = null, // Missing!
            .ref = "1",
            .topic = "room:lobby",
            .event = "phx_join",
            .payload = payload,
            .allocator = allocator,
        };

        const result = invalid_msg.validate();
        if (result) {
            std.debug.print("✗ Should have failed validation\n", .{});
        } else |err| {
            std.debug.print("✓ Correctly caught validation error: {}\n", .{err});
        }
    }

    std.debug.print("\n=== All Examples Complete ===\n\n", .{});
}
