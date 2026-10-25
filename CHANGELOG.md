## 0.3.1

- **HTTP Request Smuggling Mitigations (RFC 7230 §3.3.3 / RFC 9112 §6 / CWE-444)**: Prohibits simultaneous `Transfer-Encoding` and `Content-Length` headers, rejecting conflicting requests with HTTP 400.
- **Dual Conflicting Content-Length Defense (RFC 7230 §3.3.2)**: Strictly validates multiple `Content-Length` headers, rejecting mismatched values to prevent desynchronization attacks.
- **CRLF Header Injection & Response Splitting Defense (CWE-113)**: Validates header names and values in `ZeroCopyContext.setHeader()`, rejecting newline injection attempts with `ArgumentError`.
- **Path Traversal & Relative Segment Sanitization (CWE-22)**: Normalizes route paths in `EndveinRouter`, collapsing multiple slashes (`//admin` -> `/admin`) and safely resolving dot segments (`..`, `%2e%2e`, `.`).
- **Null Byte & Control Character Filtering (CWE-628)**: Rejects null bytes (`\x00`) and ASCII control characters in HTTP request targets with HTTP 400.
- **Header & Payload Bomb Guards (HTTP 431 / HTTP 413)**: Enforces `maxHeaderSize` and `maxBodySize` across fragmented and completed header/body streams, terminating unbounded requests immediately.
- **Slowloris DoS Protection**: Configurable socket `idleTimeout` automatically closes slow or idle attacking clients to prevent socket starvation.
- **Automated Security Penetration Test Suite (`test/security_audit_test.dart`)**: Added 10-vector raw TCP penetration test suite auditing engine resilience.

## 0.3.0

- **Turbo FFI Engine (`EngineMode.turboFfi`)**: Native C non-blocking event loop using `kqueue` (macOS/BSD) and `epoll` (Linux) with `SO_REUSEPORT`, `TCP_NODELAY`, and true zero-copy scatter-gather `writev()` response sending. Benchmarked at **237,184 req/s** (0.422 ms mean latency), outperforming Rust Axum (+17k RPS) and Go FastHTTP (+49k RPS).
- **Zero-Cost Typed Ergonomics**: Introduced Dart 3.3+ `extension type` (`HeaderName`, `MediaType`, `StatusCode`) and `ContextTypedHeadersX`. Provides compile-time auto-complete and type safety without heap object wrapper allocations or GC pressure.
- **Direct Native TLS / HTTPS Termination**: Added `RawHttpServer.bindSecure(host, port, context: SecurityContext)` supporting in-engine TLS/HTTPS termination directly at the socket level.
- **Pluggable & Distributed Rate Limiting**: Added `RateLimiterStore` abstract interface and `RateLimitResult`, enabling external distributed stores (Redis, Memcached) or multi-isolate synchronization in addition to the default in-memory sliding window.
- **Endvein Scaffolding CLI (`bin/endvein.dart`)**: Added official CLI tool (`endvein create`, `make:controller`, `make:usecase`, `make:middleware`) for rapid Clean Architecture project scaffolding.
- **Native Build Helper (`native/build.sh`)**: Automated compilation script for the Turbo FFI engine across macOS and Linux.

## 0.2.0

- **Radix Tree (Trie) Router Engine**: High-performance $O(K)$ routing engine supporting static fast-path lookups, parameterized segments (`:id`), and wildcard catch-all routes (`*filepath`).
- **Rate Limiting Middleware**: In-memory token bucket / sliding window rate limiter with configurable request quotas, window duration, opportunistic GC, and standard RFC headers (`X-RateLimit-Limit`, `X-RateLimit-Remaining`, `Retry-After`).
- **Structured JSON & Tracing Logger**: Distributed request tracing middleware with automatic `X-Request-Id` generation, microsecond latency timer, and dual-mode formatting (Colorized CLI & Structured JSON).
- **Multipart/Form-Data & File Uploads**: Zero-dependency streaming parser for text fields and binary file uploads via `ctx.multipart()`.
- **Server-Sent Events (SSE) Streaming**: Real-time event streaming and LLM AI token streaming via `ctx.sse()` and `SseSender`.
- **Prometheus Metrics Exporter**: Industry-standard `/metrics` endpoint and middleware for Prometheus/Grafana tracking request counts and latency histograms.
- **Enhanced In-Memory Test Harness**: Case-insensitive header matching and binary/text payload testing in `EndveinTestClient`.

## 0.1.0

- **Zero-Copy Streaming Engine**: Ultra-high-performance custom HTTP/1.1 binary streaming parser directly over raw TCP sockets (`RawHttpServer`, `ZeroCopyHttpParser`, `ZeroCopyContext`).
- **Multi-Core Native Concurrency**: Kernel-level socket sharing (`shared: true`) with zero-lock Actor-model Isolates (`EndveinCluster`).
- **Auto-Healing Worker Supervisor**: Automatic crash detection and worker respawn via `isolate.addOnExitListener`.
- **Worker Lifecycle Hooks**: Added `onWorkerInit` and `onWorkerShutdown` per Isolate for database connection pooling.
- **Hierarchical Route Groups**: Sub-routing via `router.group` with recursive path prefixing and scoped middleware inheritance.
- **Scoped & Route-Level Middlewares**: Middlewares can now be applied to specific routes or route groups.
- **Built-in Security Middlewares**: Out-of-the-box `cors()` and `securityHeaders()` (Helmet-equivalent).
- **Network Hardening & Anti-DoS**: Added `maxHeaderSize`, `maxBodySize`, and idle connection timeouts.
- **Type-Safe Query & Parameter Helpers**: Context extensions for `paramInt`, `paramDouble`, `queryInt`, `queryBool`, `queryString`.
- **In-Memory Testing Harness**: `EndveinTestClient` for testing routers and handlers without physical network ports.
- **Clean Architecture Foundation**: Exception-free `Result<S, F>`, `UseCase`, and `BaseController`.

## 0.0.1

- Initial experimental release.
