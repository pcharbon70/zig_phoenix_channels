# Socket State Machine Implementation (Task 1.3.1)

## Problem Statement

Task 1.3.1 requires implementing the connection state machine for the Phoenix Socket with:
- Explicit state definitions (5 states: DISCONNECTED, CONNECTING, CONNECTED, CLOSING, ERROR)
- Documented valid transitions between states
- Transition validation logic to prevent invalid state changes
- State change callbacks for debugging and monitoring

**Current Status**: Basic implementation exists with enum and canTransitionTo() method, but missing:
- State change callback mechanism
- Transition history/logging
- More comprehensive test coverage
- StateTransition tracking struct

## Solution Overview

Enhance the existing ConnectionState enum with:
1. **StateChangeCallback** - Function pointer type for state change notifications
2. **StateTransition** - Struct to track state changes with timestamps and reasons
3. **Enhanced validation** - Include context and error messages for invalid transitions
4. **Comprehensive tests** - Cover all transitions, error cases, and callback invocation

## Technical Details

**Files**:
- `src/connection/state.zig` - Enhance ConnectionState enum
- Test coverage in the same file

**Key Design Decisions**:
- Use function pointers for callbacks (Zig idiomatic)
- Make callbacks optional (nullable)
- Track transition reasons for debugging
- Keep state machine pure (no allocations in core logic)

## Implementation Plan

### Step 1: Add State Change Callback Type ✅
- Define StateChangeCallback function pointer type
- Include old state, new state, and optional context

### Step 2: Add StateTransition Struct
- Track: from_state, to_state, timestamp, reason
- Provide helper for creating transitions

### Step 3: Enhance Transition Validation
- Add validateTransition() that returns errors with context
- Keep canTransitionTo() for boolean checks
- Add descriptive error messages

### Step 4: Comprehensive Testing
- Test all valid transitions with matrix
- Test all invalid transitions
- Test callback invocation
- Test error messages

### Step 5: Documentation
- Document state machine diagram
- Document callback contract
- Add usage examples
- Update planning document

## Success Criteria

- ✅ All 5 states defined (already exists)
- ✅ Valid transitions documented and tested
- ✅ Transition validation implemented
- ⏳ State change callbacks added
- ⏳ Comprehensive test suite (>20 tests)
- ⏳ Planning document updated

## Current Status

**What Works**:
- Basic ConnectionState enum with 5 states
- canTransitionTo() method for boolean validation
- toString() for debugging
- 3 basic tests

**What's Next**:
- Add callback mechanism
- Add StateTransition tracking
- Expand test coverage
- Update planning docs

**How to Run**:
```bash
zig build test
```
