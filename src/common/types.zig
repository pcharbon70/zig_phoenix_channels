//! Common Type Definitions
//!
//! This module defines common types and type aliases used throughout the library.

const std = @import("std");

/// Allocator type alias for convenience
pub const Allocator = std.mem.Allocator;

/// Callback function type for event handlers
/// Parameters: event name, payload (as JSON string)
pub const EventCallback = *const fn (event: []const u8, payload: []const u8) void;

/// Callback function type for state change notifications
/// Parameters: old state, new state
pub const StateChangeCallback = *const fn (old_state: anytype, new_state: anytype) void;

/// Reference counter for generating unique message references
pub const RefCounter = struct {
    counter: usize,
    mutex: std.Thread.Mutex,

    /// Initialize a new reference counter
    pub fn init() RefCounter {
        return .{
            .counter = 0,
            .mutex = std.Thread.Mutex{},
        };
    }

    /// Generate the next unique reference
    /// Returns the reference as a number that can be converted to string
    pub fn next(self: *RefCounter) usize {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.counter +%= 1; // Wrapping add to handle overflow
        return self.counter;
    }

    /// Reset the counter (primarily for testing)
    pub fn reset(self: *RefCounter) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.counter = 0;
    }
};

test "RefCounter generates unique references" {
    var counter = RefCounter.init();

    const ref1 = counter.next();
    const ref2 = counter.next();
    const ref3 = counter.next();

    try std.testing.expect(ref1 < ref2);
    try std.testing.expect(ref2 < ref3);
    try std.testing.expectEqual(@as(usize, 1), ref1);
    try std.testing.expectEqual(@as(usize, 2), ref2);
    try std.testing.expectEqual(@as(usize, 3), ref3);
}

test "RefCounter reset works" {
    var counter = RefCounter.init();

    _ = counter.next();
    _ = counter.next();

    counter.reset();

    const ref = counter.next();
    try std.testing.expectEqual(@as(usize, 1), ref);
}
