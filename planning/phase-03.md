# Phase 3: Multiplexing and Polish

## Overview

This phase transforms the library from a functional client into a polished, production-ready tool. Phase 3 focuses on three main areas: robust multiplexing (handling many concurrent channels efficiently), comprehensive error handling (gracefully handling all failure modes), and developer experience (logging, configuration, API ergonomics).

Multiplexing is Phoenix Channels' superpower: one WebSocket connection supports unlimited logical channels. Real applications use multiple channels simultaneously (e.g., user notifications + chat room + presence tracking). This phase implements the complete channel registry and message routing infrastructure to support this efficiently and reliably. The basic registry from Phase 1 is extended with proper lifecycle management, error isolation, and thread-safe operations.

Error handling and observability are critical for production deployments. This phase implements comprehensive error handling that never panics, provides actionable error messages, and gracefully degrades when problems occur. The logging infrastructure gives operators visibility into client behavior without overwhelming them with noise. The configuration system allows customization while maintaining sensible defaults.

This phase represents approximately 2 weeks of work and completes the core library functionality. After this phase, the library is feature-complete for most use cases.

---

## 3.1 Channel Registry and Routing

This section implements robust channel registry and message routing to support many concurrent channels efficiently. The registry maps topics to Channel instances, manages channel lifecycle, and routes incoming messages to the correct channel. The implementation must handle channel creation, destruction, duplicates, and concurrent access correctly.

Message routing is the heart of multiplexing. When a message arrives from the WebSocket, extract the topic field and look up the corresponding channel in the registry. Route the message to that channel's handleMessage() method. If no channel exists for the topic, log and discard the message (but don't crash). Efficient routing is critical for performance with many channels.

### 3.1.1 Registry Structure

The registry needs efficient topic→Channel mapping with thread-safe access. We use a StringHashMap protected by mutex. The registry also tracks channel lifecycle: creating channels on demand, cleaning up closed channels, preventing duplicate subscriptions to the same topic.

- 3.1.1.1 Enhance channel registry with HashMap-based storage
- 3.1.1.2 Add mutex protection for thread-safe registry access
- 3.1.1.3 Implement efficient topic lookup (O(1) hash lookup)
- 3.1.1.4 Add channel lifecycle tracking (created, active, closing, closed)
- 3.1.1.5 Implement statistics collection (channel count, message rates)

### 3.1.2 Channel Lifecycle Management

Channels have a lifecycle: creation (Socket.channel()), active usage, and cleanup (after leave or close). The registry must track this lifecycle and clean up resources at appropriate times. Proper lifecycle management prevents memory leaks from abandoned channels.

- 3.1.2.1 Implement channel creation via Socket.channel(topic)
- 3.1.2.2 Detect duplicate channel creation for same topic
- 3.1.2.3 Handle duplicate channel policy (error, reuse, or replace)
- 3.1.2.4 Implement channel cleanup after phx_close or leave
- 3.1.2.5 Add manual channel removal from registry
- 3.1.2.6 Implement cleanup of all channels on socket disconnect

### 3.1.3 Message Routing Logic

Routing logic extracts the topic from each incoming message and dispatches to the appropriate handler. System messages (topic="phoenix") route to the Socket. Channel messages route to the correct Channel. Unknown topics are logged and discarded.

- 3.1.3.1 Implement topic extraction from incoming messages
- 3.1.3.2 Route "phoenix" topic messages to Socket (heartbeat)
- 3.1.3.3 Lookup channel by topic and route to Channel.handleMessage()
- 3.1.3.4 Handle messages for unknown topics (log and discard)
- 3.1.3.5 Optimize routing performance for many channels
- 3.1.3.6 Add routing statistics and monitoring

### 3.1.4 Concurrent Channel Operations

Multiple threads may operate on channels simultaneously: application thread pushing events, receive thread routing messages, heartbeat thread checking state. The implementation must serialize access correctly without deadlocks.

- 3.1.4.1 Implement thread-safe channel creation
- 3.1.4.2 Implement thread-safe message routing
- 3.1.4.3 Prevent deadlocks between registry and channel locks
- 3.1.4.4 Handle concurrent channel lifecycle operations
- 3.1.4.5 Add lock ordering documentation to prevent deadlocks

### 3.1.5 Channel Iteration and Queries

Applications and internal components need to query the registry: list all channels, find channels by pattern, check if topic is subscribed. Provide safe iteration that doesn't block other operations unnecessarily.

- 3.1.5.1 Implement channel iteration with safe locking
- 3.1.5.2 Add channel queries (getChannel, hasChannel, channelCount)
- 3.1.5.3 Implement channel filtering (by state, by topic pattern)
- 3.1.5.4 Add snapshot functionality for consistent reads
- 3.1.5.5 Optimize queries to minimize lock contention

### Unit Tests - Section 3.1

- Test channel registration and lookup
- Test duplicate topic handling (error, reuse, replace)
- Test message routing to correct channels
- Test routing to unknown topics (discard gracefully)
- Test channel lifecycle (create, active, cleanup)
- Test concurrent channel operations from multiple threads
- Test registry iteration and queries
- Test channel cleanup on socket disconnect
- Test memory cleanup of closed channels

---

## 3.2 Error Handling and Recovery

This section implements comprehensive error handling throughout the library. Every operation that can fail should return an error, never panic. Errors should provide actionable information. Recovery logic should restore the client to a working state when possible. The implementation follows Zig's error handling idioms: error unions, try/catch, and errdefer.

Error categories include: connection errors (network failures), protocol errors (malformed messages), application errors (invalid parameters), and resource errors (out of memory). Each category needs appropriate handling. Connection errors trigger reconnection, protocol errors log and discard the message, application errors return to caller, resource errors propagate but clean up resources.

### 3.2.1 Error Type Hierarchy

Define a comprehensive error set covering all failure modes. Group related errors for easier handling. Document each error type with causes and recommended handling. Well-defined errors make debugging and error handling straightforward.

- 3.2.1.1 Define comprehensive PhoenixError error set
- 3.2.1.2 Group errors by category (connection, protocol, application, resource)
- 3.2.1.3 Document each error type with causes and handling
- 3.2.1.4 Implement error conversion from underlying libraries
- 3.2.1.5 Add error context information (where, why, what)

### 3.2.2 Connection Error Handling

Connection errors occur at various levels: DNS resolution, TCP connection, TLS handshake, WebSocket handshake, send/receive operations. Each level needs appropriate handling. Most connection errors should trigger reconnection logic.

- 3.2.2.1 Handle DNS resolution failures
- 3.2.2.2 Handle TCP connection failures (timeout, refused, unreachable)
- 3.2.2.3 Handle TLS/SSL errors (certificate validation, handshake)
- 3.2.2.4 Handle WebSocket handshake failures
- 3.2.2.5 Handle send/receive errors during operation
- 3.2.2.6 Map all connection errors to reconnection triggers

### 3.2.3 Protocol Error Handling

Protocol errors include malformed messages, unexpected events, invalid state transitions. These typically indicate bugs (client or server side) but shouldn't crash the client. Log the error with full context and continue operation.

- 3.2.3.1 Handle JSON parsing errors gracefully
- 3.2.3.2 Handle invalid message structure (not 5-element array)
- 3.2.3.3 Handle unexpected events for current state
- 3.2.3.4 Handle invalid state transitions
- 3.2.3.5 Log protocol errors with full message context
- 3.2.3.6 Continue operation despite protocol errors

### 3.2.4 Application Error Handling

Application errors come from invalid API usage: joining same channel twice, pushing on closed channel, invalid parameters. These should return clear errors to the caller without affecting other operations.

- 3.2.4.1 Validate API parameters before processing
- 3.2.4.2 Return clear errors for invalid operations
- 3.2.4.3 Prevent invalid state transitions from API calls
- 3.2.4.4 Document error conditions in API documentation
- 3.2.4.5 Provide error context for debugging

### 3.2.5 Resource Error Handling

Resource errors include out of memory, file descriptor exhaustion, thread creation failure. These are serious but should be handled gracefully. Use errdefer for cleanup, return errors to caller, and fail safely.

- 3.2.5.1 Handle out of memory errors gracefully
- 3.2.5.2 Clean up partial allocations with errdefer
- 3.2.5.3 Handle thread creation failures
- 3.2.5.4 Handle resource exhaustion (file descriptors, etc.)
- 3.2.5.5 Implement fallback behaviors where possible

### 3.2.6 Error Recovery Strategies

Different errors need different recovery strategies. Connection errors trigger reconnection, protocol errors are logged and ignored, application errors return to caller. Implement recovery strategies that match error types.

- 3.2.6.1 Implement automatic recovery for transient errors
- 3.2.6.2 Implement manual recovery for permanent errors
- 3.2.6.3 Add recovery callbacks for application intervention
- 3.2.6.4 Document recovery strategies per error type
- 3.2.6.5 Test recovery strategies with failure injection

### Unit Tests - Section 3.2

- Test error type definitions and hierarchy
- Test connection error handling and recovery
- Test protocol error handling (malformed messages)
- Test application error handling (invalid API usage)
- Test resource error handling (out of memory simulation)
- Test error recovery strategies for each error type
- Test error context preservation and reporting
- Test no panics under any error condition
- Test error handling doesn't leak resources (errdefer works)

---

## 3.3 Logging Infrastructure

This section implements logging infrastructure for observability and debugging. Logging must be configurable, structured, and not impact performance significantly. We use Zig's standard logging but add Phoenix-specific context and structure. Logging is opt-in by default (minimal noise) but can be enabled for debugging.

Structured logging provides context: connection ID, channel topic, message ref, event name. This context makes log correlation straightforward. Log levels (debug, info, warn, error) allow filtering. Performance-sensitive paths use conditional compilation or runtime checks to avoid logging overhead in production.

### 3.3.1 Logging Framework Integration

Integrate with Zig's std.log framework while adding Phoenix-specific structure and context. Define log scopes for different components (socket, channel, protocol). Implement consistent log formatting.

- 3.3.1.1 Integrate with std.log framework
- 3.3.1.2 Define log scopes for components (socket, channel, protocol, etc.)
- 3.3.1.3 Implement structured logging with key-value pairs
- 3.3.1.4 Add log level configuration per scope
- 3.3.1.5 Implement log output formatting (JSON, text)

### 3.3.2 Contextual Logging

Each log message should include relevant context: which socket, which channel, which operation. Implement context passing that doesn't clutter call signatures. Use log scope to carry context implicitly.

- 3.3.2.1 Add connection ID to socket logs
- 3.3.2.2 Add topic to channel logs
- 3.3.2.3 Add message ref to protocol logs
- 3.3.2.4 Add timestamp to all logs
- 3.3.2.5 Implement context propagation through calls

### 3.3.3 Performance-Sensitive Logging

Hot paths (message routing, send/receive) must minimize logging overhead. Use compile-time log level checks, conditional logging, and sampling for high-frequency events. Profile logging overhead and optimize where needed.

- 3.3.3.1 Implement compile-time log level filtering
- 3.3.3.2 Add runtime log level checks before expensive formatting
- 3.3.3.3 Implement log sampling for high-frequency events
- 3.3.3.4 Profile logging overhead in hot paths
- 3.3.3.5 Optimize string formatting for logs

### 3.3.4 Operational Logging

Certain events must always be logged for operational visibility: connection state changes, reconnection attempts, channel state transitions. These logs help operators understand client behavior without overwhelming noise.

- 3.3.4.1 Log connection state changes (connected, disconnected, error)
- 3.3.4.2 Log reconnection attempts with backoff delays
- 3.3.4.3 Log channel state transitions (joining, joined, error, closed)
- 3.3.4.4 Log important errors with full context
- 3.3.4.5 Keep operational logs concise and actionable

### 3.3.5 Debug Logging

Debug logging provides detailed information for troubleshooting: message contents, protocol details, internal state. Debug logging should be disabled by default (performance) but easily enabled when needed.

- 3.3.5.1 Implement detailed protocol logging (message contents)
- 3.3.5.2 Log state machine transitions with state details
- 3.3.5.3 Log message routing decisions
- 3.3.5.4 Log internal state snapshots on errors
- 3.3.5.5 Make debug logging easy to enable/disable

### Unit Tests - Section 3.3

- Test logging framework integration
- Test log scopes and context propagation
- Test log level filtering (compile-time and runtime)
- Test structured log output format
- Test logging doesn't crash on errors
- Test log sampling for high-frequency events
- Test operational logs are present for key events
- Test debug logs are disabled by default
- Test logging performance overhead is acceptable

---

## 3.4 Configuration System

This section implements a comprehensive configuration system for customizing client behavior. Configuration should support multiple sources (code, files, environment), provide validation, and have sensible defaults. The configuration covers all aspects: connection, channels, reconnection, heartbeat, buffers, timeouts, logging.

A good configuration system makes the library flexible without complexity. Most users should use defaults. Advanced users can tune every parameter. Configuration should be type-safe (compile-time checks where possible), validated (catch invalid values early), and documented (every option explained with use cases).

### 3.4.1 Configuration Structure

Define configuration structures for each component: SocketConfig, ChannelConfig, ReconnectionConfig, HeartbeatConfig, etc. Use Zig structs with default values. Allow partial configuration (override only specific fields).

- 3.4.1.1 Define SocketConfig struct with all socket options
- 3.4.1.2 Define ChannelConfig struct with channel options
- 3.4.1.3 Define ReconnectionConfig for reconnection policy
- 3.4.1.4 Define HeartbeatConfig for heartbeat settings
- 3.4.1.5 Define BufferConfig for buffer sizes and policies
- 3.4.1.6 Define LogConfig for logging options

### 3.4.2 Configuration Defaults

Establish sensible defaults matching Phoenix.js behavior. Defaults should work for 90% of use cases. Document the reasoning behind each default value. Allow complete customization for the other 10%.

- 3.4.2.1 Set default connection timeout (10s)
- 3.4.2.2 Set default heartbeat interval (30s) and timeout (60s)
- 3.4.2.3 Set default reconnection backoff (1s, 5s, 10s, 10s...)
- 3.4.2.4 Set default buffer sizes (socket: 1000, channel: 100)
- 3.4.2.5 Set default timeout values (join: 10s, push: 10s, leave: 5s)
- 3.4.2.6 Document all default values and rationale

### 3.4.3 Configuration Validation

Validate configuration values at initialization. Catch nonsensical values (negative timeouts, timeout < interval, etc.) early. Provide clear error messages when validation fails. Validation prevents hard-to-debug runtime issues.

- 3.4.3.1 Implement validation for all configuration values
- 3.4.3.2 Check constraints (timeout > interval, positive values, etc.)
- 3.4.3.3 Return clear errors for invalid configuration
- 3.4.3.4 Add validation tests for boundary conditions
- 3.4.3.5 Document validation rules for each option

### 3.4.4 Configuration Sources

Support multiple configuration sources: inline code (struct initialization), configuration files (JSON/TOML), environment variables. Establish precedence order: code overrides files, files override environment, environment overrides defaults.

- 3.4.4.1 Support inline configuration via struct initialization
- 3.4.4.2 Implement configuration file loading (JSON format)
- 3.4.4.3 Implement environment variable reading for common options
- 3.4.4.4 Establish configuration precedence order
- 3.4.4.5 Add configuration merging logic

### 3.4.5 Runtime Configuration Updates

Some configuration can be updated at runtime (logging levels, reconnection policy), others cannot (connection URL). Distinguish mutable from immutable configuration. Provide safe update methods for mutable configuration.

- 3.4.5.1 Identify mutable vs immutable configuration
- 3.4.5.2 Implement safe updates for mutable configuration
- 3.4.5.3 Prevent updates to immutable configuration
- 3.4.5.4 Add callbacks for configuration change notifications
- 3.4.5.5 Document which configuration is mutable

### Unit Tests - Section 3.4

- Test configuration structure initialization
- Test default values are sensible
- Test configuration validation catches invalid values
- Test configuration from multiple sources (code, file, env)
- Test configuration precedence order
- Test runtime configuration updates (mutable options)
- Test immutable configuration cannot be changed
- Test configuration merging logic
- Test configuration documentation completeness

---

## 3.5 API Polish and Ergonomics

This section focuses on making the public API intuitive, consistent, and ergonomic. Good API design reduces friction for library users. This includes: consistent naming, clear ownership semantics, builder patterns where appropriate, comprehensive documentation, and usage examples.

API ergonomics matter. A powerful library with poor API won't be adopted. This section reviews all public APIs and improves usability. We add convenience methods, improve error messages, provide builder patterns for complex configuration, and ensure consistent patterns across the API surface.

### 3.5.1 API Consistency Review

Review all public APIs for consistency in naming, parameter order, error handling, and return types. Establish and document naming conventions. Apply conventions consistently across all APIs.

- 3.5.1.1 Review and standardize naming conventions (snake_case)
- 3.5.1.2 Standardize parameter ordering (allocator first, options last)
- 3.5.1.3 Ensure consistent error handling patterns (error unions)
- 3.5.1.4 Standardize return types across similar operations
- 3.5.1.5 Document API conventions in style guide

### 3.5.2 Builder Patterns

For complex object creation (Socket, Channel with many options), provide builder patterns. Builders make optional parameters ergonomic without function overloading. Implement fluent interfaces where appropriate.

- 3.5.2.1 Implement SocketBuilder for socket creation
- 3.5.2.2 Implement ChannelBuilder for channel creation with options
- 3.5.2.3 Add fluent interface methods (chainable)
- 3.5.2.4 Validate builder state before build()
- 3.5.2.5 Provide examples using builder pattern

### 3.5.3 Convenience Methods

Add convenience methods for common operations: connecting with URL string, joining channel with inline parameters, pushing simple events. Convenience methods don't add functionality but improve ergonomics.

- 3.5.3.1 Add Socket.connectUrl() for URL string connection
- 3.5.3.2 Add Channel.joinWith() for inline parameter passing
- 3.5.3.3 Add Channel.pushEvent() for simple event sending
- 3.5.3.4 Add Socket.channelJoin() for create+join in one call
- 3.5.3.5 Add error convenience methods (isConnectionError, etc.)

### 3.5.4 Memory Ownership Clarity

Clarify memory ownership for all APIs: who allocates, who frees, when. Use naming conventions (Owned, Ref) to indicate ownership. Document ownership in API comments. Prevent common memory management bugs through clear API design.

- 3.5.4.1 Document ownership for all returned pointers
- 3.5.4.2 Use naming conventions for ownership clarity
- 3.5.4.3 Add Owned types for transferred ownership
- 3.5.4.4 Add Ref types for borrowed references
- 3.5.4.5 Implement lifetime validation where possible

### 3.5.5 API Documentation

Comprehensive API documentation is essential. Every public function, struct, and constant should have doc comments. Include parameters, return values, errors, examples, and cross-references. Generate documentation with zig-autodoc.

- 3.5.5.1 Add doc comments to all public APIs
- 3.5.5.2 Document parameters, return values, and errors
- 3.5.5.3 Include usage examples in doc comments
- 3.5.5.4 Add cross-references between related APIs
- 3.5.5.5 Generate and review API documentation output

### Unit Tests - Section 3.5

- Test builder pattern creation and validation
- Test convenience methods work correctly
- Test ownership semantics prevent leaks
- Test API consistency across components
- Test documentation completeness (all public APIs documented)
- Test examples in documentation compile and work
- Test error messages are clear and actionable

---

## 3.6 Integration Tests

This section provides comprehensive integration testing of the complete library with all Phase 3 features. Test multiplexing with many concurrent channels, error handling under various failure conditions, configuration customization, and logging output. These tests validate the library is production-ready.

Integration tests for Phase 3 focus on complexity: many channels, concurrent operations, various error conditions, configuration variations. These tests stress the library in ways that approach real production usage. They catch issues with resource management, race conditions, and edge cases.

### 3.6.1 Multi-Channel Scenarios

Test the library with many simultaneous channels to validate multiplexing performance and correctness. Test channel creation, independent operation, message routing, and cleanup.

- 3.6.1.1 Test creating many channels (100+) simultaneously
- 3.6.1.2 Test independent operation of multiple channels
- 3.6.1.3 Test message routing correctness with many channels
- 3.6.1.4 Test channel cleanup after closing many channels
- 3.6.1.5 Test memory usage with many active channels
- 3.6.1.6 Test performance of routing with many channels

### 3.6.2 Error Handling Validation

Test error handling throughout the library. Inject errors at various points and validate graceful handling. Ensure no panics, no resource leaks, and appropriate recovery.

- 3.6.2.1 Test connection error handling and recovery
- 3.6.2.2 Test protocol error handling (malformed messages)
- 3.6.2.3 Test application error handling (invalid API usage)
- 3.6.2.4 Test resource error handling (simulated OOM)
- 3.6.2.5 Test error recovery strategies work correctly
- 3.6.2.6 Test no panics under any error condition

### 3.6.3 Configuration Testing

Test the configuration system with various configurations. Validate defaults work, custom configurations apply correctly, and validation catches errors.

- 3.6.3.1 Test default configuration works for common scenarios
- 3.6.3.2 Test custom configuration from code
- 3.6.3.3 Test configuration file loading and parsing
- 3.6.3.4 Test environment variable configuration
- 3.6.3.5 Test configuration validation catches invalid values
- 3.6.3.6 Test configuration precedence order

### 3.6.4 Logging Validation

Test logging infrastructure produces expected output at various log levels. Validate log context, structured format, and performance.

- 3.6.4.1 Test operational logs appear for key events
- 3.6.4.2 Test debug logging provides detailed information
- 3.6.4.3 Test log level filtering works correctly
- 3.6.4.4 Test structured log output format
- 3.6.4.5 Test logging context includes relevant information
- 3.6.4.6 Test logging performance overhead is acceptable

### 3.6.5 Concurrent Operations

Test concurrent access from multiple threads: multiple threads creating channels, pushing events, receiving messages. Validate thread safety and absence of race conditions.

- 3.6.5.1 Test concurrent channel creation from multiple threads
- 3.6.5.2 Test concurrent push operations on different channels
- 3.6.5.3 Test concurrent access to same channel
- 3.6.5.4 Test concurrent reconnection attempts
- 3.6.5.5 Test no race conditions under concurrent access
- 3.6.5.6 Test thread safety validation (ThreadSanitizer)

### 3.6.6 Load Testing

Test the library under sustained load: high message rates, many channels, prolonged operation. Validate memory stability, performance consistency, and resource cleanup.

- 3.6.6.1 Test sustained high message rate (10K+ msgs/sec)
- 3.6.6.2 Test prolonged operation (hours)
- 3.6.6.3 Test memory stability under load
- 3.6.6.4 Test performance consistency over time
- 3.6.6.5 Test resource cleanup prevents leaks
- 3.6.6.6 Test CPU usage is reasonable under load

---

## Success Criteria

This phase is complete when:

1. **Multiplexing**: Channel registry supports unlimited concurrent channels efficiently
2. **Error Handling**: All error paths handled gracefully, no panics under any condition
3. **Logging**: Comprehensive logging infrastructure with configurable levels
4. **Configuration**: Flexible configuration system with sensible defaults
5. **API Polish**: Consistent, ergonomic APIs with comprehensive documentation
6. **Integration Tests**: All complex scenarios tested successfully
7. **Performance**: Routing performance scales with channel count (O(1) lookup)
8. **Resource Management**: No memory leaks under prolonged operation with many channels

## Provides Foundation For

This phase completes the core library, enabling:
- **Phase 4**: Advanced features build on stable foundation
- **Phase 5**: Production deployment relies on polish and reliability
- **Real-world Adoption**: Production-ready quality encourages adoption
- **Maintenance**: Good logging and error handling simplify maintenance

## Key Outputs

1. **Implemented Components**:
   - Robust channel registry with lifecycle management
   - Comprehensive error handling throughout library
   - Structured logging infrastructure
   - Flexible configuration system
   - Polished public APIs with documentation

2. **Developer Experience**:
   - Builder patterns for complex configuration
   - Convenience methods for common operations
   - Clear error messages and handling
   - Comprehensive API documentation

3. **Testing Infrastructure**:
   - Multi-channel integration tests
   - Error injection and recovery tests
   - Load tests for performance validation
   - Thread safety validation

4. **Documentation**:
   - API documentation for all public functions
   - Configuration guide with all options documented
   - Error handling guide
   - Logging guide

## Next Phase Preview

Phase 4 adds advanced features that enhance the library's capabilities:
- Presence tracking for distributed user tracking
- Binary message support for efficient data transfer
- Push receive hooks for request/response patterns
- Performance optimization for high-throughput scenarios
- Memory profiling and optimization

With the core library solid and polished from Phase 3, Phase 4 focuses on advanced features that distinguish the library from basic implementations.
