const std = @import("std");
const testing = std.testing;
const phoenix = @import("phoenix_channels");
const RefCounter = phoenix.common.RefCounter;
const PhoenixSocket = phoenix.connection.PhoenixSocket;
const Config = phoenix.connection.SocketConfig;

// ============================================================================
// Task 1.3.6: Reference Generation Tests
// ============================================================================

const allocator = testing.allocator;

// ----------------------------------------------------------------------------
// Basic RefCounter Tests
// ----------------------------------------------------------------------------

test "RefCounter generates unique references" {
    var counter = RefCounter.init();

    const ref1 = counter.next();
    const ref2 = counter.next();
    const ref3 = counter.next();

    try testing.expect(ref1 < ref2);
    try testing.expect(ref2 < ref3);
    try testing.expectEqual(@as(usize, 1), ref1);
    try testing.expectEqual(@as(usize, 2), ref2);
    try testing.expectEqual(@as(usize, 3), ref3);
}

test "RefCounter reset works" {
    var counter = RefCounter.init();

    _ = counter.next();
    _ = counter.next();
    _ = counter.next();

    counter.reset();

    const ref = counter.next();
    try testing.expectEqual(@as(usize, 1), ref);
}

test "RefCounter starts at 0 and first next() returns 1" {
    var counter = RefCounter.init();
    try testing.expectEqual(@as(usize, 0), counter.counter);

    const first = counter.next();
    try testing.expectEqual(@as(usize, 1), first);
}

test "RefCounter is monotonically increasing" {
    var counter = RefCounter.init();

    var prev: usize = 0;
    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        const current = counter.next();
        try testing.expect(current > prev);
        try testing.expectEqual(prev + 1, current);
        prev = current;
    }
}

test "RefCounter wrapping add handles overflow" {
    var counter = RefCounter.init();
    counter.counter = std.math.maxInt(usize);

    const ref = counter.next();
    try testing.expectEqual(@as(usize, 0), ref); // Wraps to 0
}

test "RefCounter consecutive values have gap of 1" {
    var counter = RefCounter.init();

    var i: usize = 0;
    while (i < 100) : (i += 1) {
        const ref1 = counter.next();
        const ref2 = counter.next();
        try testing.expectEqual(ref1 + 1, ref2);
    }
}

// ----------------------------------------------------------------------------
// Socket Integration Tests
// ----------------------------------------------------------------------------

test "socket nextRef generates sequential IDs" {
    const config = Config{
        .url = "ws://localhost:4000/socket/websocket",
    };

    const skt = try PhoenixSocket.init(allocator, config);
    defer skt.deinit();

    const refs = [_]usize{
        skt.nextRef(),
        skt.nextRef(),
        skt.nextRef(),
        skt.nextRef(),
        skt.nextRef(),
    };

    for (refs, 0..) |ref, i| {
        try testing.expectEqual(@as(usize, i + 1), ref);
    }
}

test "socket nextRefString formats correctly" {
    const config = Config{
        .url = "ws://localhost:4000/socket/websocket",
    };

    const skt = try PhoenixSocket.init(allocator, config);
    defer skt.deinit();

    const ref_str = try skt.nextRefString();
    defer allocator.free(ref_str);

    try testing.expectEqualStrings("1", ref_str);
}

test "socket nextRefString generates sequential string IDs" {
    const config = Config{
        .url = "ws://localhost:4000/socket/websocket",
    };

    const skt = try PhoenixSocket.init(allocator, config);
    defer skt.deinit();

    const ref1 = try skt.nextRefString();
    defer allocator.free(ref1);
    const ref2 = try skt.nextRefString();
    defer allocator.free(ref2);
    const ref3 = try skt.nextRefString();
    defer allocator.free(ref3);

    try testing.expectEqualStrings("1", ref1);
    try testing.expectEqualStrings("2", ref2);
    try testing.expectEqualStrings("3", ref3);
}

test "socket nextRefString memory is caller-owned" {
    const config = Config{
        .url = "ws://localhost:4000/socket/websocket",
    };

    const skt = try PhoenixSocket.init(allocator, config);
    defer skt.deinit();

    const ref1 = try skt.nextRefString();
    const ref2 = try skt.nextRefString();

    // Both strings should remain valid and independent
    try testing.expectEqualStrings("1", ref1);
    try testing.expectEqualStrings("2", ref2);

    allocator.free(ref1);
    allocator.free(ref2);
}

test "mixing nextRef and nextRefString maintains sequence" {
    const config = Config{
        .url = "ws://localhost:4000/socket/websocket",
    };

    const skt = try PhoenixSocket.init(allocator, config);
    defer skt.deinit();

    const num1 = skt.nextRef(); // 1
    const str1 = try skt.nextRefString(); // 2
    defer allocator.free(str1);
    const num2 = skt.nextRef(); // 3
    const str2 = try skt.nextRefString(); // 4
    defer allocator.free(str2);

    try testing.expectEqual(@as(usize, 1), num1);
    try testing.expectEqualStrings("2", str1);
    try testing.expectEqual(@as(usize, 3), num2);
    try testing.expectEqualStrings("4", str2);
}

// ----------------------------------------------------------------------------
// Thread Safety Tests
// ----------------------------------------------------------------------------

const ThreadTestContext = struct {
    socket: *PhoenixSocket,
    refs: []usize,
    start_index: usize,
    count: usize,
};

fn generateRefsThread(ctx: *ThreadTestContext) void {
    var i: usize = 0;
    while (i < ctx.count) : (i += 1) {
        ctx.refs[ctx.start_index + i] = ctx.socket.nextRef();
    }
}

test "RefCounter thread safety: concurrent access" {
    const config = Config{
        .url = "ws://localhost:4000/socket/websocket",
    };

    const skt = try PhoenixSocket.init(allocator, config);
    defer skt.deinit();

    const num_threads = 4;
    const refs_per_thread = 100;
    const total_refs = num_threads * refs_per_thread;

    const refs = try allocator.alloc(usize, total_refs);
    defer allocator.free(refs);

    var threads: [num_threads]std.Thread = undefined;
    var contexts: [num_threads]ThreadTestContext = undefined;

    // Spawn threads
    for (0..num_threads) |i| {
        contexts[i] = ThreadTestContext{
            .socket = skt,
            .refs = refs,
            .start_index = i * refs_per_thread,
            .count = refs_per_thread,
        };
        threads[i] = try std.Thread.spawn(.{}, generateRefsThread, .{&contexts[i]});
    }

    // Wait for all threads
    for (threads) |thread| {
        thread.join();
    }

    // Verify all references are unique
    var seen = std.AutoHashMap(usize, void).init(allocator);
    defer seen.deinit();

    for (refs) |ref| {
        const result = try seen.getOrPut(ref);
        try testing.expect(!result.found_existing); // Should be unique
    }

    // Should have exactly total_refs unique values
    try testing.expectEqual(total_refs, seen.count());
}

test "RefCounter thread safety: no duplicate refs" {
    var counter = RefCounter.init();

    const num_threads = 8;
    const refs_per_thread = 50;

    const ThreadContext = struct {
        counter: *RefCounter,
        refs: []usize,

        fn worker(ctx: *@This()) void {
            for (ctx.refs) |*ref| {
                ref.* = ctx.counter.next();
            }
        }
    };

    var all_refs = try allocator.alloc(usize, num_threads * refs_per_thread);
    defer allocator.free(all_refs);

    var threads: [num_threads]std.Thread = undefined;
    var thread_contexts: [num_threads]ThreadContext = undefined;

    // Spawn worker threads
    for (0..num_threads) |i| {
        const start = i * refs_per_thread;
        const end = start + refs_per_thread;
        thread_contexts[i] = ThreadContext{
            .counter = &counter,
            .refs = all_refs[start..end],
        };
        threads[i] = try std.Thread.spawn(.{}, ThreadContext.worker, .{&thread_contexts[i]});
    }

    // Join all threads
    for (threads) |t| {
        t.join();
    }

    // Verify uniqueness
    var seen = std.AutoHashMap(usize, void).init(allocator);
    defer seen.deinit();

    for (all_refs) |ref| {
        const result = try seen.getOrPut(ref);
        try testing.expect(!result.found_existing);
    }

    try testing.expectEqual(num_threads * refs_per_thread, seen.count());
}

// ----------------------------------------------------------------------------
// Edge Cases
// ----------------------------------------------------------------------------

test "large reference values format correctly" {
    var counter = RefCounter.init();
    counter.counter = 999999999;

    const config = Config{
        .url = "ws://localhost:4000/socket/websocket",
    };

    const skt = try PhoenixSocket.init(allocator, config);
    defer skt.deinit();

    // Manually set counter to large value
    skt.ref_counter.counter = 999999999;

    const ref_str = try skt.nextRefString();
    defer allocator.free(ref_str);

    try testing.expectEqualStrings("1000000000", ref_str);
}

test "reference generation after many operations" {
    const config = Config{
        .url = "ws://localhost:4000/socket/websocket",
    };

    const skt = try PhoenixSocket.init(allocator, config);
    defer skt.deinit();

    // Generate many references
    var i: usize = 0;
    while (i < 10000) : (i += 1) {
        _ = skt.nextRef();
    }

    const final_ref = skt.nextRef();
    try testing.expectEqual(@as(usize, 10001), final_ref);
}

test "nextRefString allocates new memory each time" {
    const config = Config{
        .url = "ws://localhost:4000/socket/websocket",
    };

    const skt = try PhoenixSocket.init(allocator, config);
    defer skt.deinit();

    const ref1 = try skt.nextRefString();
    const ref2 = try skt.nextRefString();

    // Should be different memory locations
    try testing.expect(ref1.ptr != ref2.ptr);

    allocator.free(ref1);
    allocator.free(ref2);
}

test "reference uniqueness across multiple sockets" {
    const config1 = Config{
        .url = "ws://localhost:4000/socket1",
    };
    const config2 = Config{
        .url = "ws://localhost:5000/socket2",
    };

    const skt1 = try PhoenixSocket.init(allocator, config1);
    defer skt1.deinit();

    const skt2 = try PhoenixSocket.init(allocator, config2);
    defer skt2.deinit();

    // Each socket has its own reference counter
    // They can generate the same numeric values independently
    const ref1_from_skt1 = skt1.nextRef();
    const ref1_from_skt2 = skt2.nextRef();

    // Both should be 1 (not globally unique, but unique per socket)
    try testing.expectEqual(@as(usize, 1), ref1_from_skt1);
    try testing.expectEqual(@as(usize, 1), ref1_from_skt2);
}

test "zero is never returned as a reference" {
    var counter = RefCounter.init();

    // Generate many references
    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        const ref = counter.next();
        try testing.expect(ref != 0); // Should never be 0
    }
}
