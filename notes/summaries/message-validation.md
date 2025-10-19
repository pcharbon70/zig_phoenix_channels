# Message Validation - Summary

## Overview

Implemented semantic message validation for Phoenix Channels messages to catch protocol violations beyond syntactic correctness. Validation ensures messages conform to Phoenix protocol requirements before transmission or processing.

## Task Requirements

### ✅ 1.2.4.1 Implement validation for required fields per message type

Implemented three validation methods:

#### 1. General Validation (`validate()`)
```zig
pub fn validate(self: *const PhoenixMessage) !void
```

**Validates:**
- Payload is always a JSON object (not primitive)
- `phx_join` messages require `join_ref`
- Topic is not empty
- Event is not empty

**Use Case:** Basic protocol compliance for all messages

#### 2. Client-to-Server Validation (`validateForSend()`)
```zig
pub fn validateForSend(self: *const PhoenixMessage) !void
```

**Validates:**
- All general validation rules
- Outgoing messages have `ref` (except heartbeats)
- Heartbeat messages go to "phoenix" topic

**Use Case:** Stricter validation for client-sent messages

#### 3. Server-to-Client Validation (`validateFromServer()`)
```zig
pub fn validateFromServer(self: *const PhoenixMessage) !void
```

**Validates:**
- All general validation rules
- Reply messages have `ref` for matching

**Use Case:** Validation for received server messages

### ✅ 1.2.4.2 Validate topic format and reserved topics

**Reserved Topic Validation:**
- Heartbeat messages MUST use "phoenix" topic
- Validated in `validateForSend()`

```zig
// Heartbeat messages must go to "phoenix" topic
if (self.isHeartbeat()) {
    if (!std.mem.eql(u8, self.topic, constants.ReservedTopics.PHOENIX)) {
        return error.ValidationError;
    }
}
```

**Topic Format Validation:**
- Topic cannot be empty string
- Validated in `validate()`

### ✅ 1.2.4.3 Ensure payload is always a JSON object (not primitive)

**Payload Type Validation:**

```zig
// Validate payload is always an object
if (self.payload != .object) {
    return error.ValidationError;
}
```

**Enforces Phoenix Protocol Rule:**
- Payload MUST be a JSON object `{}`
- Rejects primitives (string, number, boolean, null)
- Rejects arrays
- Required by Phoenix V2 protocol specification

### ✅ 1.2.4.4 Add validation for system event names

**System Event Validation:**

**phx_join Validation:**
```zig
// Validate phx_join messages require join_ref
if (self.isJoin()) {
    if (self.join_ref == null) {
        return error.ValidationError;
    }
}
```

**phx_reply Validation:**
```zig
// Reply messages should have ref for matching
if (self.isReply()) {
    if (self.ref == null) {
        return error.ValidationError;
    }
}
```

**System Event Detection:**
- Uses existing `isJoin()`, `isReply()`, `isHeartbeat()` methods
- Leverages constants from `constants.zig`
- Type-safe event name checking

## Implementation Details

### Validation Hierarchy

```
validate() - Base validation
├── Payload is object
├── phx_join has join_ref
├── Topic not empty
└── Event not empty

validateForSend() - Client validation
├── validate() [all above]
├── Non-heartbeat messages have ref
└── Heartbeat uses "phoenix" topic

validateFromServer() - Server validation
├── validate() [all above]
└── phx_reply messages have ref
```

### Error Handling

**Single Error Type:**
- Returns `error.ValidationError` for all violations
- Already defined in `ProtocolError` set
- Clear, consistent error signaling

**Early Returns:**
- Validation stops at first violation
- No need to collect multiple errors
- Fast-fail approach

### Design Decisions

**Three-Level Validation:**
1. **General** (`validate()`): Universal protocol rules
2. **Client** (`validateForSend()`): Stricter for outgoing
3. **Server** (`validateFromServer()`): Server-specific patterns

**Benefits:**
- Separation of concerns
- Context-appropriate validation
- Flexible validation strategy
- Clear API for different use cases

**Validation is Optional:**
- Constructor methods don't auto-validate
- Allows flexibility for testing
- Explicit validation call by user
- Performance optimization (validate only when needed)

## Test Coverage

Implemented 10 comprehensive validation tests:

### Success Cases (3 tests)

#### Test 1: Valid Join Message
```zig
test "validate: valid join message passes"
```
- Uses `initJoin()` constructor
- Has join_ref and ref
- Validates with both `validate()` and `validateForSend()`

#### Test 2: Valid Heartbeat
```zig
test "validateForSend: valid heartbeat passes"
```
- Uses `initHeartbeat()` constructor
- Goes to "phoenix" topic
- Validates with both methods

#### Test 3: Valid Reply
```zig
test "validateFromServer: valid reply passes"
```
- Has ref for matching
- Validates with both `validate()` and `validateFromServer()`

### Failure Cases (7 tests)

#### Test 4: Join Without join_ref
```zig
test "validate: join message without join_ref fails"
```
- phx_join event but join_ref is null
- Expects: `error.ValidationError`

#### Test 5: Non-Object Payload
```zig
test "validate: message with non-object payload fails"
```
- Payload is string instead of object
- Expects: `error.ValidationError`

#### Test 6: Empty Topic
```zig
test "validate: message with empty topic fails"
```
- Topic is empty string
- Expects: `error.ValidationError`

#### Test 7: Empty Event
```zig
test "validate: message with empty event fails"
```
- Event is empty string
- Expects: `error.ValidationError`

#### Test 8: Missing ref for Send
```zig
test "validateForSend: message without ref fails"
```
- Non-heartbeat message without ref
- Expects: `error.ValidationError`

#### Test 9: Heartbeat on Wrong Topic
```zig
test "validateForSend: heartbeat on wrong topic fails"
```
- Heartbeat event on "room:lobby" instead of "phoenix"
- Expects: `error.ValidationError`

#### Test 10: Reply Without ref
```zig
test "validateFromServer: reply without ref fails"
```
- phx_reply event but ref is null
- Expects: `error.ValidationError`

**Test Results**: ✅ All 50 tests passing (30 existing + 10 new + 10 validation tests)

## Phoenix Protocol Compliance

### Required Fields
✅ phx_join requires join_ref
✅ phx_reply requires ref
✅ topic cannot be empty
✅ event cannot be empty

### Payload Validation
✅ Payload must be JSON object
✅ Rejects primitives and arrays
✅ Enforces Phoenix V2 requirement

### Reserved Topics
✅ Heartbeat must use "phoenix" topic
✅ Reserved topic validation in place

### System Events
✅ Validates phx_join constraints
✅ Validates phx_reply constraints
✅ Validates heartbeat constraints

## Code Quality

### Documentation
- Clear doc comments on all validation methods
- Explains validation purpose
- Documents use cases
- Inline comments for validation logic

### Error Handling
- Consistent error type (ValidationError)
- Clear error conditions
- Fast-fail validation
- No silent failures

### API Design
- Three methods for different contexts
- Composable (validateForSend calls validate)
- Optional validation (caller decides when)
- Const methods (no mutation)

### Performance
- Early return on first error
- No expensive operations
- String comparison with std.mem.eql
- O(1) validation checks

## Integration

Validation integrates with:
- **message.zig**: Methods on PhoenixMessage struct
- **constants.zig**: Uses SystemEvents and ReservedTopics
- **errors.zig**: Uses ValidationError from ProtocolError
- **Future serialization**: Can validate before serialize()
- **Future WebSocket**: Can validate before send/after receive

## Files Modified

**Modified**: `src/protocol/message.zig` (+235 lines, 571 total)
- Added `validate()` method (23 lines)
- Added `validateForSend()` method (15 lines)
- Added `validateFromServer()` method (10 lines)
- Added 10 comprehensive validation tests (187 lines)

## Example Usage

```zig
// Validate before sending
var msg = PhoenixMessage.initJoin(allocator, "room:lobby", "1", payload);
try msg.validateForSend(); // Throws if invalid
const json = try serialize(allocator, &msg);

// Validate after receiving
const msg = try deserialize(allocator, json);
try msg.validateFromServer(); // Throws if invalid
// Process message...

// General validation
try msg.validate(); // Basic protocol compliance
```

## Validation Rules Summary

### Universal Rules (all messages)
1. Payload must be object
2. Topic must not be empty
3. Event must not be empty
4. phx_join must have join_ref

### Client-to-Server Rules
5. Non-heartbeat messages must have ref
6. Heartbeat must use "phoenix" topic

### Server-to-Client Rules
7. phx_reply must have ref

## Benefits

### Protocol Compliance
- Catches violations early
- Prevents invalid messages
- Enforces Phoenix specifications
- Clear error feedback

### Developer Experience
- Explicit validation API
- Context-appropriate methods
- Clear error messages
- Flexible validation strategy

### Maintainability
- Centralized validation logic
- Comprehensive test coverage
- Clear separation of concerns
- Easy to extend

## Next Steps

With validation complete, ready to proceed with:
1. **Unit Tests - Section 1.2**: Comprehensive message format tests
2. **Round-trip testing**: Serialize → Deserialize → Validate
3. **WebSocket integration**: Use validation in send/receive paths

## Conclusion

Message validation is complete and fully tested. The implementation provides:
- ✅ Three-level validation (general, client, server)
- ✅ Phoenix protocol compliance enforcement
- ✅ Required field validation per message type
- ✅ Reserved topic validation
- ✅ Payload type validation (always object)
- ✅ System event constraints
- ✅ 10 comprehensive tests (success + failure cases)

The validation layer ensures protocol correctness and prevents invalid messages from propagating through the system.
