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
