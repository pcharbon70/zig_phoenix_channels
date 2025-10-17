//! Basic connection example
//! Demonstrates minimal library usage

const std = @import("std");
const phoenix = @import("phoenix_channels");

pub fn main() !void {
    std.debug.print("Phoenix Channels Library v{s}\n", .{phoenix.version});
    std.debug.print("Build system configuration successful!\n", .{});
}
