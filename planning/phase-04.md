# Phase 4: Advanced Features

## Overview

This phase extends the core library with advanced Phoenix Channels features that enable sophisticated real-time applications. While the library is functional after Phase 3, these advanced features unlock powerful capabilities: Presence for distributed user tracking, binary messages for efficient data transfer, and push receive hooks for request/response patterns.

Presence is Phoenix's CRDT-based distributed user tracking system. It provides conflict-free presence state synchronization across distributed nodes. Implementing Presence support allows Zig clients to participate in collaborative applications where knowing who's present matters (chat rooms, collaborative editing, multiplayer games).

Performance optimization is critical for production deployments handling high message volumes. This phase profiles the library, identifies bottlenecks, and implements optimizations. We focus on hot paths: message routing, serialization/deserialization, buffer management. The goal is supporting 10K+ messages/second throughput with minimal CPU and memory overhead.

This phase represents approximately 2 weeks of work and distinguishes this library from minimal Phoenix client implementations.

---

## 4.1 Presence Tracking

This section implements support for Phoenix Presence, which provides distributed user tracking with CRDT-based state synchronization. Presence allows tracking who is present in a channel with automatic conflict resolution across distributed nodes. The client must handle presence_state (full state sync) and presence_diff (incremental updates) messages.

Presence state is a map of user IDs to metadata arrays (metas). Each meta contains presence information for one connection. The diff format includes joins and leaves. The client merges diffs into local state, providing applications with an always-current view of who's present without manual synchronization.

### 4.1.1 Presence Data Structures

Define data structures for representing presence state and diffs. State maps user IDs to presence metadata. Diffs contain joins and leaves. The structures must be efficient for updates and queries.

- 4.1.1.1 Define PresenceState struct (user_id → metas map)
- 4.1.1.2 Define PresenceMeta struct (phx_ref, metadata fields)
- 4.1.1.3 Define PresenceDiff struct (joins, leaves)
- 4.1.1.4 Implement efficient storage and lookup
- 4.1.1.5 Add serialization/deserialization for presence messages

### 4.1.2 Presence State Management

Implement presence state management: initializing from presence_state, applying presence_diff updates, querying current state. State management must handle concurrent updates and provide consistent reads.

- 4.1.2.1 Implement initialization from presence_state message
- 4.1.2.2 Implement diff application (merge joins, remove leaves)
- 4.1.2.3 Handle ref-based presence tracking (phx_ref)
- 4.1.2.4 Implement state queries (list users, get user, count)
- 4.1.2.5 Add thread-safe state access

### 4.1.3 Presence Event Handling

Presence uses two system events: presence_state (full state) and presence_diff (incremental updates). Route these events to presence handler, merge into local state, invoke application callbacks.

- 4.1.3.1 Implement presence_state message handling
- 4.1.3.2 Implement presence_diff message handling
- 4.1.3.3 Route presence events from Channel to Presence handler
- 4.1.3.4 Invoke application callbacks on presence changes
- 4.1.3.5 Add callbacks for join, leave, and update events

### 4.1.4 Presence API

Provide high-level API for applications to track presence: list all present users, subscribe to presence changes, query specific users. The API should be ergonomic and hide presence protocol details.

- 4.1.4.1 Implement Channel.trackPresence() to enable tracking
- 4.1.4.2 Add Presence.list() to get all present users
- 4.1.4.3 Add Presence.get(user_id) for specific user query
- 4.1.4.4 Implement presence change callbacks (onJoin, onLeave)
- 4.1.4.5 Add Presence.count() for user count

### 4.1.5 Presence Metadata Handling

Presence metadata is arbitrary JSON. Support custom metadata for application-specific presence information (e.g., user status, typing indicators, cursor position). Provide JSON access while maintaining type safety.

- 4.1.5.1 Support arbitrary JSON metadata in presence
- 4.1.5.2 Provide type-safe metadata accessors
- 4.1.5.3 Handle metadata updates and merging
- 4.1.5.4 Implement metadata change callbacks
- 4.1.5.5 Add metadata convenience methods

### Unit Tests - Section 4.1

- Test presence state initialization from presence_state message
- Test presence diff application (joins and leaves)
- Test presence state queries (list, get, count)
- Test presence event routing and callback invocation
- Test metadata handling and access
- Test concurrent presence updates
- Test presence state consistency
- Test phx_ref tracking for multiple connections

---

## 4.2 Binary Message Support

This section adds support for binary message payloads in addition to JSON. Some use cases benefit from binary data transfer: images, audio, video, large data blobs. Phoenix supports binary messages through alternative serializers. This section implements binary message handling while maintaining compatibility with JSON messages.

Binary support requires negotiating serialization format with the server, handling binary frames from WebSocket, and providing APIs for sending/receiving binary data. The implementation must detect binary vs JSON messages and route appropriately. Binary messages still use the 5-field structure but encode it differently.

### 4.2.1 Binary Serialization Format

Phoenix supports multiple serializers. The default is JSON (V2), but servers can support binary formats (MessagePack, custom). Implement detection and handling of binary message formats.

- 4.2.1.1 Define binary message encoding formats supported
- 4.2.1.2 Implement serializer negotiation with server
- 4.2.1.3 Add binary encoding for 5-field message structure
- 4.2.1.4 Implement binary decoding for incoming messages
- 4.2.1.5 Handle binary payload fields (byte arrays)

### 4.2.2 Binary Message Handling

Handle binary messages throughout the pipeline: receiving from WebSocket, deserializing, routing, processing. Binary messages follow same protocol (5 fields) but encode differently. Detect format from WebSocket frame type.

- 4.2.2.1 Detect binary vs text WebSocket frames
- 4.2.2.2 Route binary frames to binary deserializer
- 4.2.2.3 Extract topic from binary messages for routing
- 4.2.2.4 Handle mixed JSON and binary messages
- 4.2.2.5 Implement binary message validation

### 4.2.3 Binary Push API

Provide API for pushing binary payloads. Applications should be able to push binary data efficiently without JSON serialization overhead. Support both pure binary and binary with JSON metadata.

- 4.2.3.1 Add Channel.pushBinary() for binary payloads
- 4.2.3.2 Support binary data with JSON metadata
- 4.2.3.3 Implement efficient binary payload handling
- 4.2.3.4 Add binary data ownership semantics (copy vs reference)
- 4.2.3.5 Handle binary data lifecycle and cleanup

### 4.2.4 Binary Receive Callbacks

Application callbacks should receive binary payloads efficiently. Avoid unnecessary copying. Provide clear ownership semantics: is the application given a reference or ownership?

- 4.2.4.1 Add binary event callbacks to Channel.on()
- 4.2.4.2 Implement efficient binary payload delivery
- 4.2.4.3 Define binary data ownership in callbacks
- 4.2.4.4 Support zero-copy binary delivery where possible
- 4.2.4.5 Handle binary data cleanup after callback

### 4.2.5 Backward Compatibility

Binary support must not break existing JSON-only usage. Applications using only JSON should not be affected by binary support. Detect and route appropriately based on message format.

- 4.2.5.1 Maintain full JSON compatibility
- 4.2.5.2 Default to JSON when format unspecified
- 4.2.5.3 Detect message format automatically
- 4.2.5.4 Test mixed JSON and binary message handling
- 4.2.5.5 Document binary support configuration

### Unit Tests - Section 4.2

- Test binary message serialization and deserialization
- Test binary message routing and delivery
- Test binary push API and payload handling
- Test binary receive callbacks and data ownership
- Test mixed JSON and binary message handling
- Test backward compatibility with JSON-only usage
- Test binary data lifecycle and cleanup
- Test binary payload size limits and handling

---

## 4.3 Push Receive Hooks

This section implements push receive hooks for request/response patterns. Many applications need to know when pushes succeed, fail, or timeout. Receive hooks provide callbacks for these events: ok (success), error (server error), timeout (no response). This enables request/response patterns on top of the message-passing substrate.

Receive hooks track pending pushes by reference, match incoming phx_reply messages, and invoke appropriate callbacks. The implementation must handle concurrent pushes, timeout pending pushes, and clean up tracking state appropriately.

### 4.3.1 Push Tracking Infrastructure

Track pending pushes to match replies. Store push metadata: ref, sent time, callbacks, timeout timer. Clean up tracking after reply or timeout.

- 4.3.1.1 Define PendingPush struct for tracking
- 4.3.1.2 Implement push registry (ref → PendingPush map)
- 4.3.1.3 Add thread-safe push registration and lookup
- 4.3.1.4 Implement push cleanup after completion
- 4.3.1.5 Add push statistics (pending count, completed, timed out)

### 4.3.2 Reply Matching Logic

Match incoming phx_reply messages to pending pushes by reference. Extract status (ok, error, timeout) and response payload. Invoke appropriate callback based on status.

- 4.3.2.1 Implement phx_reply message detection
- 4.3.2.2 Extract message ref for pending push lookup
- 4.3.2.3 Parse status field (ok, error, timeout)
- 4.3.2.4 Invoke appropriate callback based on status
- 4.3.2.5 Clean up pending push after callback

### 4.3.3 Callback Registration

Push operations should accept optional callbacks: onOk, onError, onTimeout. Callbacks receive relevant response data. Design callback signature for ergonomic usage.

- 4.3.3.1 Add callback parameters to push() method
- 4.3.3.2 Define callback signatures (onOk, onError, onTimeout)
- 4.3.3.3 Store callbacks in PendingPush
- 4.3.3.4 Support capturing context in callbacks
- 4.3.3.5 Add builder pattern for complex push configurations

### 4.3.4 Timeout Handling

Pushes should timeout if no reply arrives within threshold. On timeout, invoke timeout callback and clean up tracking. Timeout timer must be cancellable when reply arrives.

- 4.3.4.1 Start timeout timer when push is sent
- 4.3.4.2 Cancel timeout timer when reply arrives
- 4.3.4.3 Invoke timeout callback on expiration
- 4.3.4.4 Clean up pending push on timeout
- 4.3.4.5 Make push timeout configurable per operation

### 4.3.5 Push Response API

Provide ergonomic API for synchronous-style push operations. Some applications want to push and wait for response (request/response pattern). Implement await-style API where appropriate.

- 4.3.5.1 Add Channel.pushAndWait() for synchronous-style pushes
- 4.3.5.2 Implement response waiting with timeout
- 4.3.5.3 Return response data or error
- 4.3.5.4 Handle timeout and error responses
- 4.3.5.5 Support cancellation of waiting pushes

### Unit Tests - Section 4.3

- Test push tracking and registration
- Test reply matching by reference
- Test ok callback invocation with response data
- Test error callback invocation with error details
- Test timeout callback invocation
- Test push cleanup after completion
- Test concurrent push tracking
- Test pushAndWait synchronous API
- Test push cancellation

---

## 4.4 Performance Optimization

This section optimizes the library for high-throughput scenarios. Profile the implementation, identify bottlenecks, and optimize hot paths. Focus areas: message routing, serialization/deserialization, buffer management, lock contention. The goal is 10K+ messages/second throughput with minimal overhead.

Performance optimization requires measurement first. Profile CPU usage, memory allocations, lock contention. Identify hot paths and optimization opportunities. Implement optimizations iteratively, measuring impact. Avoid premature optimization - optimize based on profiling data.

### 4.4.1 Performance Profiling Infrastructure

Set up profiling infrastructure to measure performance characteristics. Use Zig's built-in profiling, Linux perf, and custom instrumentation. Establish baseline performance before optimization.

- 4.4.1.1 Set up profiling tools and environment
- 4.4.1.2 Implement custom instrumentation for hot paths
- 4.4.1.3 Add timing measurements for key operations
- 4.4.1.4 Collect baseline performance metrics
- 4.4.1.5 Identify hot paths and bottlenecks

### 4.4.2 Message Routing Optimization

Message routing happens for every incoming message. Optimize topic lookup, channel dispatch, and callback invocation. Reduce allocations, minimize lock hold times, optimize data structures.

- 4.4.2.1 Optimize topic extraction from messages
- 4.4.2.2 Optimize channel lookup in registry (hash function, load factor)
- 4.4.2.3 Minimize lock hold time during routing
- 4.4.2.4 Reduce allocations in routing hot path
- 4.4.2.5 Benchmark routing performance with many channels

### 4.4.3 Serialization Optimization

Serialization and deserialization happen for every message. Optimize JSON parsing, message construction, and buffer management. Consider caching frequently used structures.

- 4.4.3.1 Profile JSON parsing performance
- 4.4.3.2 Optimize message struct construction
- 4.4.3.3 Reduce allocations during serialization
- 4.4.3.4 Implement message caching for repeated patterns
- 4.4.3.5 Benchmark serialization performance

### 4.4.4 Buffer Management Optimization

Buffer allocation and management impacts performance significantly. Optimize buffer reuse, sizing, and copying. Implement buffer pooling for frequently allocated buffers.

- 4.4.4.1 Implement buffer pooling for common sizes
- 4.4.4.2 Optimize buffer growth strategies
- 4.4.4.3 Reduce unnecessary buffer copying
- 4.4.4.4 Tune buffer sizes based on profiling
- 4.4.4.5 Benchmark buffer allocation patterns

### 4.4.5 Lock Contention Reduction

Lock contention can limit scalability. Profile lock usage, identify contention points, reduce lock hold times. Consider lock-free data structures where appropriate.

- 4.4.5.1 Profile lock contention with perf
- 4.4.5.2 Reduce critical section sizes
- 4.4.5.3 Implement finer-grained locking where beneficial
- 4.4.5.4 Consider lock-free structures for hot paths
- 4.4.5.5 Benchmark with concurrent workloads

### 4.4.6 Performance Testing and Validation

Establish performance benchmarks and regression tests. Measure throughput, latency, CPU usage, memory usage. Validate optimizations don't break functionality.

- 4.4.6.1 Create performance benchmark suite
- 4.4.6.2 Measure throughput (messages per second)
- 4.4.6.3 Measure latency distribution (p50, p99, p999)
- 4.4.6.4 Measure CPU and memory usage
- 4.4.6.5 Add regression tests for performance
- 4.4.6.6 Document performance characteristics

### Unit Tests - Section 4.4

- Test performance benchmarks run successfully
- Test throughput meets targets (10K+ msgs/sec)
- Test latency is reasonable (<1ms p99)
- Test CPU usage is efficient
- Test memory usage is stable
- Test optimizations don't break functionality
- Test performance under concurrent load
- Test regression tests detect performance degradation

---

## 4.5 Memory Profiling and Optimization

This section focuses on memory usage: detecting leaks, optimizing allocation patterns, reducing memory footprint. Use GeneralPurposeAllocator's leak detection, profiling tools, and manual analysis. The goal is stable memory usage under prolonged operation.

Memory leaks are unacceptable in long-running clients. This section rigorously tests for leaks in all scenarios: normal operation, error paths, reconnection, channel lifecycle. Fix any detected leaks. Optimize allocation patterns to reduce memory footprint and allocation frequency.

### 4.5.1 Memory Leak Detection

Use GeneralPurposeAllocator's leak detection to find memory leaks. Test all operations: connect, join, push, receive, leave, disconnect, reconnection. Validate cleanup on error paths with errdefer.

- 4.5.1.1 Enable GPA leak detection in all tests
- 4.5.1.2 Test memory cleanup in normal paths
- 4.5.1.3 Test memory cleanup in error paths (errdefer)
- 4.5.1.4 Test memory cleanup during reconnection
- 4.5.1.5 Test memory cleanup with many channels
- 4.5.1.6 Fix all detected memory leaks

### 4.5.2 Memory Profiling

Profile memory usage patterns: allocation frequency, size distribution, lifetime. Identify opportunities for optimization: buffer reuse, arena allocation, stack allocation.

- 4.5.2.1 Profile memory allocations with tools
- 4.5.2.2 Analyze allocation size distribution
- 4.5.2.3 Analyze allocation lifetime patterns
- 4.5.2.4 Identify high-frequency allocations
- 4.5.2.5 Measure peak memory usage

### 4.5.3 Allocation Pattern Optimization

Optimize allocation patterns based on profiling. Use arena allocators for temporary allocations, stack allocation for small fixed-size data, buffer pooling for frequent allocations.

- 4.5.3.1 Expand arena allocator usage for message processing
- 4.5.3.2 Use stack allocation for small temporary buffers
- 4.5.3.3 Implement object pooling for frequently allocated types
- 4.5.3.4 Reduce allocation frequency in hot paths
- 4.5.3.5 Benchmark allocation pattern improvements

### 4.5.4 Memory Footprint Reduction

Reduce total memory footprint: optimize struct sizes, remove unused fields, pack data structures. Small reductions multiply across many instances (channels, pending pushes, etc.).

- 4.5.4.1 Review and optimize struct sizes
- 4.5.4.2 Remove unused fields from structs
- 4.5.4.3 Pack struct fields for optimal layout
- 4.5.4.4 Measure memory footprint improvements
- 4.5.4.5 Balance footprint vs performance tradeoffs

### 4.5.5 Long-Running Stability

Test memory stability under prolonged operation. Run for hours with continuous activity. Validate memory usage remains stable, no gradual growth, no leaks.

- 4.5.5.1 Create long-running stability tests
- 4.5.5.2 Monitor memory usage over time
- 4.5.5.3 Detect memory growth patterns
- 4.5.5.4 Test with various workloads (high throughput, many channels, etc.)
- 4.5.5.5 Fix any detected stability issues

### Unit Tests - Section 4.5

- Test no memory leaks in all operations
- Test memory cleanup in error paths
- Test memory stability under prolonged operation
- Test peak memory usage is reasonable
- Test allocation patterns are efficient
- Test object pooling works correctly
- Test arena allocator cleanup is complete
- Test memory footprint is optimized

---

## 4.6 Integration Tests

This section provides comprehensive integration testing of Phase 4 advanced features. Test Presence tracking with real server, binary message exchange, push receive hooks with various responses, and performance under realistic loads. These tests validate advanced features work correctly in production-like scenarios.

Integration tests for advanced features require enhanced test infrastructure: Presence-enabled channels, binary message support in test server, high-throughput testing capabilities. These tests prove the library handles advanced use cases reliably.

### 4.6.1 Presence Integration Testing

Test Presence tracking against Phoenix server with Presence enabled. Validate state synchronization, diff application, callbacks, and concurrent presence updates.

- 4.6.1.1 Test presence_state initialization
- 4.6.1.2 Test presence_diff application (joins and leaves)
- 4.6.1.3 Test presence callbacks (onJoin, onLeave)
- 4.6.1.4 Test presence queries (list, get, count)
- 4.6.1.5 Test concurrent presence updates
- 4.6.1.6 Test presence metadata handling

### 4.6.2 Binary Message Testing

Test binary message exchange with server supporting binary format. Validate encoding, decoding, routing, and mixed JSON/binary scenarios.

- 4.6.2.1 Test binary message push to server
- 4.6.2.2 Test binary message receive from server
- 4.6.2.3 Test mixed JSON and binary messages
- 4.6.2.4 Test binary payload correctness
- 4.6.2.5 Test binary data lifecycle and cleanup
- 4.6.2.6 Test binary message performance

### 4.6.3 Push Receive Hook Testing

Test push receive hooks with various server responses. Validate ok callback, error callback, timeout callback, and synchronous pushAndWait API.

- 4.6.3.1 Test ok callback on successful push reply
- 4.6.3.2 Test error callback on error reply
- 4.6.3.3 Test timeout callback when no reply
- 4.6.3.4 Test pushAndWait synchronous API
- 4.6.3.5 Test concurrent pushes with callbacks
- 4.6.3.6 Test push cancellation

### 4.6.4 Performance Integration Testing

Test performance under realistic loads: high message rates, many channels, concurrent operations. Validate throughput and latency targets are met.

- 4.6.4.1 Test high message throughput (10K+ msgs/sec)
- 4.6.4.2 Test latency under load (p99 < 1ms)
- 4.6.4.3 Test with many active channels (100+)
- 4.6.4.4 Test concurrent operations from multiple threads
- 4.6.4.5 Test sustained performance over time
- 4.6.4.6 Test performance doesn't degrade over time

### 4.6.5 Memory Stability Testing

Test memory stability under realistic loads. Run prolonged tests with continuous activity. Validate no memory leaks, stable memory usage, efficient allocation patterns.

- 4.6.5.1 Test memory stability over hours of operation
- 4.6.5.2 Test with various workload patterns
- 4.6.5.3 Test no memory leaks under realistic scenarios
- 4.6.5.4 Test peak memory usage is reasonable
- 4.6.5.5 Test memory usage doesn't grow over time

### 4.6.6 Advanced Feature Combinations

Test combinations of advanced features: Presence + binary messages, push hooks + high throughput, etc. Validate features don't interfere with each other.

- 4.6.6.1 Test Presence with binary messages
- 4.6.6.2 Test push hooks with high message volume
- 4.6.6.3 Test binary messages with push callbacks
- 4.6.6.4 Test all features simultaneously
- 4.6.6.5 Test feature interactions don't cause issues

---

## Success Criteria

This phase is complete when:

1. **Presence Support**: Full Phoenix Presence implementation with state, diffs, and callbacks
2. **Binary Messages**: Binary message support working with efficient payload handling
3. **Push Hooks**: Push receive hooks implemented with ok, error, and timeout callbacks
4. **Performance**: Throughput ≥10K msgs/sec, latency p99 <1ms
5. **Memory Stability**: No leaks, stable memory usage under prolonged operation
6. **Integration Tests**: All advanced features tested against real Phoenix server
7. **Benchmarks**: Comprehensive performance benchmarks documented
8. **Optimization**: Hot paths optimized based on profiling data

## Provides Foundation For

This phase completes advanced features, enabling:
- **Phase 5**: Production readiness builds on optimized, feature-complete library
- **Real-world Applications**: Advanced features support sophisticated use cases
- **Performance-Critical Usage**: Optimization enables high-throughput scenarios
- **Competitive Positioning**: Advanced features distinguish library from alternatives

## Key Outputs

1. **Implemented Features**:
   - Phoenix Presence tracking with full protocol support
   - Binary message support for efficient data transfer
   - Push receive hooks for request/response patterns
   - Optimized performance for high-throughput scenarios

2. **Performance Improvements**:
   - Optimized message routing and serialization
   - Reduced memory allocations in hot paths
   - Efficient buffer management and pooling
   - Reduced lock contention

3. **Memory Optimizations**:
   - No memory leaks in any scenario
   - Optimized allocation patterns
   - Reduced memory footprint
   - Stable memory usage under prolonged operation

4. **Testing Infrastructure**:
   - Presence integration tests
   - Binary message tests
   - Performance benchmarks
   - Memory stability tests
   - Advanced feature combination tests

5. **Documentation**:
   - Presence API documentation
   - Binary message usage guide
   - Push hooks examples
   - Performance characteristics documentation
   - Optimization guide

## Next Phase Preview

Phase 5 completes the library for production release:
- Comprehensive test suite covering all scenarios
- Failure scenario testing (network issues, server failures)
- Load testing for production validation
- Complete API documentation
- Example applications demonstrating all features
- Migration guides and tutorials
- Release preparation and versioning

With advanced features complete and optimized, Phase 5 focuses on validation, documentation, and release preparation for production deployments.
