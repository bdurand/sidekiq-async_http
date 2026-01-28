# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 1.0.0

### Added

- Async HTTP processor that runs in a dedicated thread with a Fiber-based reactor, allowing hundreds of concurrent HTTP requests without blocking Sidekiq worker threads.
- `Sidekiq::AsyncHttp::Job` mixin providing `async_get`, `async_post`, `async_put`, `async_patch`, and `async_delete` methods for Sidekiq jobs.
- Callback system with `on_completion` and `on_error` blocks for handling HTTP responses and errors.
- Support for custom callback workers with configurable Sidekiq options.
- Automatic integration with Sidekiq's lifecycle (startup, quiet, shutdown signals).
- Graceful shutdown with configurable timeout and automatic re-enqueuing of incomplete requests.
- Crash recovery via Redis-backed inflight request tracking with heartbeats and orphan detection.
- Distributed garbage collection for cleaning up requests from crashed processes.
- Optional Sidekiq Web UI integration for monitoring processor status and statistics.
- Support for `sidekiq-encrypted_args` gem for encrypting sensitive response data.
- ActiveJob compatibility when using Sidekiq as the queue adapter.
- Configurable connection limits, timeouts, response size limits, and heartbeat intervals.
