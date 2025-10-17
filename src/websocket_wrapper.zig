const std = @import("std");
const websocket = @import("websocket");

/// WebSocket wrapper for Phoenix Channels protocol
/// Provides a clean interface to karlseguin/websocket.zig for Phoenix-specific needs
pub const WebSocketWrapper = struct {
    allocator: std.mem.Allocator,
    client: ?*websocket.Client = null,
    connected: bool = false,

    const Self = @This();

    /// Initialize a new WebSocket wrapper
    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
        };
    }

    /// Clean up resources
    pub fn deinit(self: *Self) void {
        if (self.client) |client| {
            client.deinit();
            self.allocator.destroy(client);
        }
        self.connected = false;
    }

    /// Connect to a WebSocket endpoint
    /// url: The WebSocket URL (e.g., "ws://localhost:4000/socket/websocket")
    pub fn connect(self: *Self, url: []const u8) !void {
        // Parse URL to extract host, port, and path
        const uri = try std.Uri.parse(url);

        // Determine if using TLS based on scheme
        const use_tls = std.mem.eql(u8, uri.scheme, "wss");

        // Extract port from URI or use default
        const port: u16 = uri.port orelse if (use_tls) 443 else 80;

        // Create client
        const client = try self.allocator.create(websocket.Client);
        errdefer self.allocator.destroy(client);

        // Initialize client connection
        client.* = try websocket.Client.init(self.allocator, .{
            .host = uri.host.?,
            .port = port,
            .tls = use_tls,
        });
        errdefer client.deinit();

        // Perform WebSocket handshake
        try client.handshake(uri.path, .{
            .timeout_ms = 5000,
            .headers = "sec-websocket-protocol: phoenix\r\n",
        });

        self.client = client;
        self.connected = true;
    }

    /// Send a text message over the WebSocket
    /// Note: This method modifies the message buffer for masking
    pub fn sendText(self: *Self, message: []u8) !void {
        if (self.client) |client| {
            try client.writeText(message);
        } else {
            return error.NotConnected;
        }
    }

    /// Receive a message from the WebSocket
    /// Caller owns the returned memory and must free it
    pub fn receive(self: *Self) !?[]const u8 {
        if (self.client) |client| {
            const msg = try client.read() orelse return null;
            defer client.done(msg);

            // Only handle text messages for Phoenix protocol
            if (msg.type == .text) {
                const data = try self.allocator.dupe(u8, msg.data);
                return data;
            }
            return null;
        } else {
            return error.NotConnected;
        }
    }

    /// Close the WebSocket connection
    pub fn close(self: *Self) !void {
        if (self.client) |client| {
            try client.close(.{});
            self.connected = false;
        }
    }

    /// Check if currently connected
    pub fn isConnected(self: Self) bool {
        return self.connected and self.client != null;
    }
};

/// Error set for WebSocket operations
pub const WebSocketError = error{
    NotConnected,
    InvalidUrl,
    ConnectionFailed,
    HandshakeFailed,
    SendFailed,
    ReceiveFailed,
};

test "WebSocketWrapper initialization" {
    const allocator = std.testing.allocator;
    var wrapper = WebSocketWrapper.init(allocator);
    defer wrapper.deinit();

    try std.testing.expect(!wrapper.isConnected());
    try std.testing.expect(wrapper.client == null);
}

test "WebSocketWrapper not connected error" {
    const allocator = std.testing.allocator;
    var wrapper = WebSocketWrapper.init(allocator);
    defer wrapper.deinit();

    // Attempting to send on a disconnected wrapper should fail
    const result = wrapper.sendText("test");
    try std.testing.expectError(error.NotConnected, result);
}
