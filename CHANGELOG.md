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
