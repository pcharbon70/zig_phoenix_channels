# JSON Serialization - Summary

## Overview

Implemented JSON serialization for Phoenix Channels messages, converting `PhoenixMessage` structs to the Phoenix V2 protocol's 5-element JSON array format: `[join_ref, ref, topic, event, payload]`.

## Task Requirements

### ✅ 1.2.2.1 Implement toArray() method (serialize) for converting to JSON array format

Implemented `serialize()` function that converts `PhoenixMessage` to JSON array format:

```zig
pub fn serialize(allocator: std.mem.Allocator, msg: *const message.PhoenixMessage) ![]u8
```

**Implementation Details:**
- Uses `std.ArrayList(u8)` for dynamic buffer management
- Writes directly to buffer writer for efficiency
- Returns owned slice that caller must free
- Proper error handling with `errdefer` for cleanup on failure

**Output Format:**
```json
[join_ref, ref, topic, event, payload]
```

### ✅ 1.2.2.2 Handle nullable field serialization (null vs absent)

**Nullable Field Handling:**

```zig
// Field 1: join_ref (nullable)
if (msg.join_ref) |join_ref| {
    try std.json.encodeJsonString(join_ref, .{}, writer);
} else {
    try writer.writeAll("null");
}
```

**Implementation:**
- `join_ref` and `ref` serialize as `null` when not present
- Phoenix protocol uses literal `null` (not absent fields)
- Consistent with Phoenix.js behavior
- Proper JSON escaping via `std.json.encodeJsonString`

**Examples:**
- With ref: `["1","1","room:lobby","phx_join",{}]`
- Without ref: `[null,null,"room:lobby","new_msg",{}]`

### ✅ 1.2.2.3 Ensure payload serialization preserves JSON structure

**Payload Serialization:**

```zig
// Field 5: payload (JSON value)
try std.json.stringify(msg.payload, .{}, writer);
```

**Features:**
- Uses `std.json.stringify` for correct JSON output
- Preserves nested object structures
- Handles all JSON value types (object, array, string, number, boolean, null)
- Maintains JSON integrity through the serialization pipeline

**Verified Behaviors:**
- Empty objects: `{}`
- Simple objects: `{"user":"alice","message":"Hello, world!"}`
- Nested objects: `{"nested":{"key":"value"},"count":42}`
- Proper escaping of special characters

### ✅ 1.2.2.4 Add buffer management for serialized output

**Buffer Management Strategy:**

```zig
var buffer = std.ArrayList(u8).init(allocator);
errdefer buffer.deinit();  // Cleanup on error

var writer = buffer.writer();
// ... write operations ...

return buffer.toOwnedSlice();  // Transfer ownership to caller
```

**Key Features:**
- Dynamic buffer allocation via `ArrayList`
- Automatic growth as needed (no fixed size limits)
- `errdefer` ensures cleanup on error paths
- Ownership transfer via `toOwnedSlice()`
- Caller responsible for freeing returned memory

**Memory Safety:**
- No buffer overflows
- Proper cleanup on allocation failures
- Clear ownership semantics
- Testable with `std.testing.allocator` for leak detection

## Test Coverage

Implemented 7 comprehensive tests (267 lines total):

### Test 1: Basic Message with Null References
```zig
test "serialize: basic message with null references"
```
- Tests generic message with no join_ref or ref
- Verifies null serialization
- Expected: `[null,null,"room:lobby","new_msg",{}]`

### Test 2: Join Message with References
```zig
test "serialize: join message with join_ref and ref"
```
- Tests `initJoin()` convenience constructor
- Verifies both join_ref and ref are set
- Expected: `["1","1","room:lobby","phx_join",{}]`

### Test 3: Heartbeat Message
```zig
test "serialize: heartbeat message"
```
- Tests heartbeat on "phoenix" topic
- Verifies null join_ref, present ref
- Expected: `[null,"5","phoenix","heartbeat",{}]`

### Test 4: Message with Payload Data
```zig
test "serialize: message with payload data"
```
- Tests payload with multiple fields
- Parses result to verify structure
- Validates 5-element array format
- Confirms payload object integrity

### Test 5: Special Characters in Topic and Event
```zig
test "serialize: special characters in topic and event"
```
- Tests JSON escaping (quotes, colons)
- Topic: `room:"special"`
- Event: `event:with:colons`
- Verifies proper escaping via round-trip parsing

### Test 6: Nested Payload Structure
```zig
test "serialize: nested payload structure"
```
- Tests complex nested JSON objects
- Verifies nested object preservation
- Tests mixed types (string, integer, object)
- Validates deep structure integrity

### Test 7: Empty Payload Object
```zig
test "serialize: empty payload object"
```
- Tests minimal valid payload `{}`
- Verifies empty object serialization
- Expected: `[null,null,"test:topic","test_event",{}]`

**Test Results**: ✅ All 37 tests passing (30 existing + 7 new serialization tests)

## Phoenix Protocol Compliance

### Message Format
✅ Produces 5-element JSON array: `[join_ref, ref, topic, event, payload]`

### Field Serialization
✅ join_ref: `null` or quoted string
✅ ref: `null` or quoted string
✅ topic: quoted string (required)
✅ event: quoted string (required)
✅ payload: JSON object (preserves structure)

### Special Cases
✅ Null handling for optional fields
✅ JSON escaping for special characters
✅ Nested object preservation
✅ Empty object support `{}`

### Phoenix.js Compatibility
✅ Same null serialization approach
✅ Compatible JSON output format
✅ Handles all message types (join, leave, heartbeat, custom)

## Code Quality

### Documentation
- Clear module-level documentation
- Detailed doc comments on `serialize()` function
- Inline comments explaining each field
- Examples in test names

### Error Handling
- Returns `![]u8` (error union)
- Proper `errdefer` for cleanup
- Clear error propagation with `try`

### Memory Management
- Dynamic buffer allocation
- No memory leaks (verified with testing allocator)
- Clear ownership transfer
- Proper defer/errdefer patterns

### Performance
- Single-pass serialization
- Direct writer usage (no intermediate buffers)
- Efficient string encoding via stdlib

## Integration

Serialization integrates with:
- **message.zig**: Uses PhoenixMessage struct and convenience constructors
- **constants.zig**: Serializes system events correctly
- **Future WebSocket layer**: Will use serialize() for outgoing messages
- **Future serializer tests**: Foundation for round-trip testing

## API Design

```zig
// Simple, clean API
const json = try serialize(allocator, &message);
defer allocator.free(json);

// Works with all message types
var join_msg = PhoenixMessage.initJoin(allocator, "room:lobby", "1", payload);
const join_json = try serialize(allocator, &join_msg);

var heartbeat_msg = PhoenixMessage.initHeartbeat(allocator, "5", payload);
const hb_json = try serialize(allocator, &heartbeat_msg);
```

**Design Principles:**
- Single responsibility (serialization only)
- Clear ownership semantics
- Consistent with Zig conventions
- Easy to use and test

## Files Modified

**Modified**: `src/protocol/serializer.zig` (+232 lines, 267 total)
- Implemented `serialize()` function (40 lines)
- Added 7 comprehensive tests (227 lines)
- Removed placeholder TODO

## Performance Characteristics

### Time Complexity
- O(n) where n is the size of the payload
- Single pass through data
- No backtracking or rewrites

### Space Complexity
- O(n) for output buffer
- Dynamic growth as needed
- No unnecessary copying

### Memory Efficiency
- Direct write to output buffer
- Minimal intermediate allocations
- Proper cleanup on error paths

## Next Steps

With serialization complete, ready to proceed with:
1. **Task 1.2.3**: JSON Deserialization (parse incoming messages)
2. **Task 1.2.4**: Message validation
3. **Round-trip tests**: Serialize → Deserialize → Compare

## Conclusion

JSON serialization is complete and fully tested. The implementation provides:
- ✅ Phoenix V2 protocol compliant output
- ✅ Proper nullable field handling
- ✅ Nested payload structure preservation
- ✅ Efficient buffer management
- ✅ Comprehensive test coverage
- ✅ Memory safe with clear ownership

The serialization foundation is solid for building the WebSocket transmission layer and completing the message format implementation.
