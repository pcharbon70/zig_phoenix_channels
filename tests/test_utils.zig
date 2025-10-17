//! Test Utilities
//!
//! Common utilities and helpers for testing the Phoenix Channels library.

const std = @import("std");

/// Test allocator for leak detection
pub const test_allocator = std.testing.allocator;

/// Helper to create a test JSON object
pub fn createTestJsonObject(allocator: std.mem.Allocator) !std.json.ObjectMap {
    var obj = std.json.ObjectMap.init(allocator);
    try obj.put("test_key", std.json.Value{ .string = "test_value" });
    return obj;
}

/// Helper to compare two strings with better error messages
pub fn expectEqualStrings(expected: []const u8, actual: []const u8) !void {
    try std.testing.expectEqualStrings(expected, actual);
}

test "test utilities compile" {
    // Simple test to ensure utilities compile
    try std.testing.expect(true);
}
