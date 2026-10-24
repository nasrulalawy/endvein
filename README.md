# ⚡ Endvein

[![pub package](https://img.shields.io/pub/v/endvein.svg)](https://pub.dev/packages/endvein)
[![Dart SDK](https://img.shields.io/badge/dart-%3E%3D3.0.0-blue.svg)](https://dart.dev)
[![License: MIT](https://img.shields.io/badge/license-MIT-purple.svg)](https://opensource.org/licenses/MIT)

> **Next-Generation, Ultra-High-Throughput Dart Backend Framework**  
> Engineered for Multi-Core Native Concurrency, Zero-Copy TCP Streaming, and Enterprise-Scale Clean Architecture.

---

## 📖 Overview

**Endvein** was built with a bold mission: **to shatter the misconception that Dart is only for Flutter/mobile** and prove that Dart can match and outperform industry-standard backend runtimes like Go (Golang) in production workloads.

By leveraging kernel-level socket sharing (`SO_REUSEPORT`), an Actor-model concurrency architecture with zero lock contention across CPU cores, and a custom **Zero-Copy streaming HTTP/1.1 parser** directly on raw TCP sockets, Endvein eliminates Garbage Collection (GC) pressure and delivers blistering throughput.

---

## 📊 Head-to-Head Benchmark Results

Tested on identical hardware under **100,000 requests** with **concurrency 150** (Keep-Alive):

* **Machine:** Apple Silicon (10 CPU Cores, macOS `darwin/arm64`)
* **Tool:** ApacheBench (`ab -n 100000 -c 150 -k`)
* **Compilation Mode:** Native Binary AOT (`dart compile exe` vs `go build`)

| Framework / Engine | Throughput (RPS) | Mean Latency | Binary Size |
| :--- | :---: | :---: | :---: |
| **Traditional Dart (Single Isolate)** | ~42,152 req/s | 2.372 ms | 5.7 MB |
| **Go (`net/http` Standard Library)** | 176,675 req/s | 0.849 ms | 7.6 MB |
| **⚡ Endvein (10-Core Native Engine)** | **207,150 req/s** 🚀 | **0.724 ms** | **6.0 MB** |

> **Result:**  
> **Endvein outperforms Go's standard library by +30,475 req/s (~17% faster)** with lower latency (0.724 ms vs 0.849 ms) and a smaller binary footprint.

---

## 🏛️ Core Architectural Pillars

1. **Multi-Isolate Kernel Load Balancing:** Distributes incoming TCP connections across all CPU cores at the OS kernel level via `SO_REUSEPORT` (`shared: true`), requiring no external reverse proxy.
2. **Zero Lock Contention (Actor Model):** Each Isolate runs on its own dedicated memory heap, eliminating mutex locks, race conditions, and CPU cache thrashing.
3. **Zero-Copy Streaming Byte Pipeline:** Directly parses incoming request lines and headers without regex or intermediate heap string allocations on hot paths.
4. **Auto-Healing Worker Supervisor:** Cluster manager continuously supervises worker Isolates. If a worker unexpectedly exits, a replacement is instantly respawned with zero downtime.
5. **Clean Architecture First:** Pre-built `Result<S, F>`, `UseCase`, and `BaseController` contracts provide type-safe, exception-free business logic.
6. **Zero External Core Dependencies:** The engine is built exclusively with pure Dart and `dart:io` primitives to maximize raw performance and security.

---

## 🚀 Quick Start

### 1. Installation

Add Endvein to your `pubspec.yaml`:

```yaml
dependencies:
  endvein: ^0.2.0
```

Or run:

```bash
dart pub add endvein
```

### 2. Minimal Server (`example/main.dart`)

```dart
import 'package:endvein/endvein.dart';

void main() async {
  final cluster = EndveinCluster(
    host: '0.0.0.0',
    port: 8080,
    engineMode: EngineMode.rawSocket, // ⚡ Default: 200,000+ RPS
    routerFactory: () {
      final router = EndveinRouter();

      // Static Route (O(1) lookup)
      router.get('/health', (ctx) => 'OK');

      // JSON Endpoint
      router.get('/', (ctx) => {
        'framework': 'Endvein',
        'status': 'blazing_fast',
      });

      // Dynamic Route with Type-Safe param parsing
      router.get('/users/:id', (ctx) {
        final id = ctx.paramInt('id');
        return {'id': id, 'name': 'User #$id'};
      });

      return router;
    },
  );

  await cluster.run();
}
```

### 3. Running the Server

#### Development Mode (JIT):
```bash
dart run example/main.dart
```

#### Production AOT Compilation (Ultra-High Throughput):
```bash
dart compile exe example/main.dart -o build/endvein_server
./build/endvein_server
```

---

## 📚 Complete Feature Guide

### 1. Hierarchical Route Groups & Prefixing

Organize endpoints cleanly with recursive prefix inheritance:

```dart
final router = EndveinRouter();

// Root level endpoint
router.get('/health', (ctx) => 'OK');

// Grouped API v1
router.group('/api/v1', (v1) {
  v1.get('/users', (ctx) => ['Alice', 'Bob']);

  // Nested Admin Group
  v1.group('/admin', (admin) {
    admin.get('/metrics', (ctx) => {'active_connections': 120});
  });
});
```

---

### 2. Scoped & Route-Level Middlewares

Middlewares can be global, group-level, or applied to specific routes:

```dart
// 1. Global Middleware (applies to all routes)
router.use((ctx, next) async {
  final stopwatch = Stopwatch()..start();
  final response = await next();
  stopwatch.stop();
  ctx.setHeader('X-Response-Time', '${stopwatch.elapsedMicroseconds}us');
  return response;
});

// 2. Group-Level Middleware (applies to /admin/* only)
router.group('/admin', (admin) {
  admin.use((ctx, next) async {
    final token = ctx.getHeader('authorization');
    if (token != 'Bearer secret') {
      return EndveinResponse.json({'error': 'Unauthorized'}, statusCode: 401);
    }
    return next();
  });

  admin.get('/dashboard', (ctx) => {'status': 'admin_access'});
});

// 3. Route-Specific Middleware
router.get(
  '/special',
  (ctx) => {'message': 'special content'},
  middlewares: [myCustomGuard],
);
```

---

### 3. Built-in Security Middlewares

Endvein includes zero-dependency security middlewares:

#### CORS Middleware
```dart
router.use(cors(const CorsOptions(
  allowOrigins: ['https://example.com'],
  allowMethods: ['GET', 'POST', 'PUT', 'DELETE'],
  allowHeaders: ['Authorization', 'Content-Type'],
  allowCredentials: true,
  maxAge: 86400,
)));
```

#### Security Headers (Helmet Equivalent)
```dart
router.use(securityHeaders(
  frameOptions: 'SAMEORIGIN',
  contentTypeOptions: 'nosniff',
  xssProtection: '1; mode=block',
  referrerPolicy: 'no-referrer',
));
```

---

### 4. DoS Protection & Network Hardening

Configurable limits prevent Slowloris attacks and Out-Of-Memory (OOM) issues:

```dart
final cluster = EndveinCluster(
  port: 8080,
  maxHeaderSize: 16 * 1024,        // 16 KB header limit (throws 431 if exceeded)
  maxBodySize: 10 * 1024 * 1024,   // 10 MB payload limit (throws 413 if exceeded)
  idleTimeout: Duration(seconds: 30), // Closes hanging/zombie TCP sockets
  routerFactory: () => appRouter,
);
```

---

### 5. Multi-Core Database Connection Pooling

Each worker Isolate runs in its own memory space. Use `onWorkerInit` and `onWorkerShutdown` to initialize database connection pools (Postgres, SQLite, Redis) cleanly per-isolate:

```dart
final cluster = EndveinCluster(
  onWorkerInit: (workerId) async {
    // Initialized independently for this CPU core / Isolate
    print('Connecting DB pool for worker #$workerId...');
    await Database.initializePool();
  },
  onWorkerShutdown: (workerId) async {
    print('Closing DB pool for worker #$workerId...');
    await Database.closePool();
  },
  routerFactory: () => appRouter,
);
```

---

### 6. Type-Safe Parameter & Query Parsing

Extract and cast query parameters or route tokens without manual parsing:

```dart
router.get('/products/:id', (ctx) {
  // Route Params
  final productId = ctx.paramInt('id'); // returns int?
  
  // Query Params
  final page = ctx.queryInt('page', defaultValue: 1);
  final limit = ctx.queryInt('limit', defaultValue: 20);
  final activeOnly = ctx.queryBool('active', defaultValue: true);
  final search = ctx.queryString('q', defaultValue: '');

  return {
    'product_id': productId,
    'page': page,
    'limit': limit,
    'active': activeOnly,
    'query': search,
  };
});
```

---

### 7. Exception-Free Clean Architecture Pattern

Endvein includes built-in constructs to build enterprise applications without exception-throwing overhead:

```dart
// 1. Pure Domain Use Case
class GetUserUseCase implements UseCase<User, int> {
  final UserRepository repo;
  GetUserUseCase(this.repo);

  @override
  FutureOr<Result<User, Exception>> call(int id) async {
    final user = await repo.findById(id);
    if (user == null) {
      return Failure(Exception('User not found'));
    }
    return Success(user);
  }
}

// 2. Presentation Controller
class UserController extends BaseController {
  final GetUserUseCase getUser;
  UserController(this.getUser);

  @override
  void mount(EndveinRouter router) {
    router.get('/users/:id', (ctx) async {
      final id = ctx.paramInt('id') ?? 0;
      final result = await getUser(id);

      return switch (result) {
        Success(data: final user) => ctx.success(user),
        Failure(error: final err) => ctx.fail(err.toString(), statusCode: 404),
      };
    });
  }
}
```

---

### 8. Fast In-Memory Unit & Integration Testing

Test routes, middleware, and controllers without binding to physical network ports:

```dart
import 'package:endvein/endvein.dart';
import 'package:test/test.dart';

void main() {
  test('User endpoint returns 200 with valid data', () async {
    final router = EndveinRouter();
    router.get('/users/:id', (ctx) => {'id': ctx.paramInt('id')});

    final client = EndveinTestClient(router);
    final response = await client.get('/users/42');

    expect(response.statusCode, equals(200));
    expect(response.bodyJson, equals({'id': 42}));
  });
}
```

---

### 9. Radix Tree (Trie) Routing & Wildcards

Endvein combines **$O(1)$ Hash Map Fast-Path** for static endpoints with a **Radix Tree (Trie)** for parameterized and wildcard routes:

```dart
// Named parameter matching (:id)
router.get('/users/:id', (ctx) => 'User ${ctx.param('id')}');

// Deep wildcard / catch-all matching (*filepath)
router.get('/static/*filepath', (ctx) {
  final path = ctx.param('filepath'); // e.g. "css/themes/dark.css"
  return {'asset': path};
});
```

---

### 10. Rate Limiting Middleware

Protect your APIs from brute-force attacks and scraping with an in-memory sliding window rate limiter:

```dart
router.use(rateLimiter(
  maxRequests: 100,                      // 100 requests
  window: const Duration(minutes: 1),    // per 1 minute per IP
  message: 'Too many requests, slow down.',
));
```

Automatically attaches `X-RateLimit-Limit`, `X-RateLimit-Remaining`, `X-RateLimit-Reset`, and `Retry-After` headers.

---

### 11. Structured JSON Logging & Distributed Tracing

Track requests with automatic correlation IDs and sub-millisecond precision:

```dart
// Dual mode: CLI colorized for development, or Structured JSON for production
router.use(logger(jsonFormat: true));

// Output:
// {"level":"info","timestamp":"2026-10-24T14:30:00Z","requestId":"req-abc-123","method":"GET","path":"/users","statusCode":200,"latencyMs":0.45}
```

---

### 12. Multipart/Form-Data & File Uploads

Upload files and form fields without external libraries:

```dart
router.post('/upload', (ctx) {
  final form = ctx.multipart();
  if (form == null) return {'error': 'Invalid multipart'};

  final avatar = form.file('avatar');
  print('Uploaded: ${avatar?.filename} (${avatar?.size} bytes)');

  return {
    'username': form.field('username'),
    'filename': avatar?.filename,
  };
});
```

---

### 13. Server-Sent Events (SSE) & LLM Token Streaming

Stream live events or AI/LLM tokens to clients using standard W3C `EventSource`:

```dart
router.get('/ai/chat/stream', (ctx) async {
  await ctx.sse((sender) async {
    sender.sendData('Initializing model...', event: 'status');

    for (final token in ['The', ' future', ' of', ' Dart', ' is', ' fast!']) {
      await Future.delayed(const Duration(milliseconds: 50));
      sender.send(SseEvent(event: 'token', data: token));
    }

    sender.sendData('Done', event: 'finish');
  });
});
```

---

### 14. Prometheus Metrics Exporter (`/metrics`)

Expose real-time throughput and latency metrics for Prometheus and Grafana:

```dart
final prom = PrometheusMetrics();
router.use(prom.middleware());

// Expose standard Prometheus exposition endpoint
router.get('/metrics', prom.handler);
```

---

## 🗺️ Roadmap

* ✅ Multi-Isolate Cluster Manager with Kernel Socket Sharing (`shared: true`).
* ✅ Zero-Copy HTTP/1.1 Streaming Parser directly on Raw Sockets.
* ✅ Radix Tree (Trie) Router Engine with Wildcards (`*filepath`) and Parameters (`:id`).
* ✅ Zero-Allocation Byte Pipeline.
* ✅ Clean Architecture Contracts (`Result`, `UseCase`, `Controller`).
* ✅ Network Hardening & Anti-DoS (max header/body size & socket idle timeout).
* ✅ Auto-Healing Worker Supervisor (Isolate crash recovery).
* ✅ Hierarchical Route Groups & Scoped Middlewares.
* ✅ Built-in Security Middlewares (CORS & Security Headers).
* ✅ Rate Limiting & Anti-Spam Middleware.
* ✅ Structured JSON Logging & Distributed Tracing (`X-Request-Id`).
* ✅ Zero-Dependency Multipart/Form-Data & File Upload Parser.
* ✅ Server-Sent Events (SSE) & AI Token Streaming.
* ✅ Prometheus Metrics Exporter (`/metrics`).
* ✅ In-Memory Fast Testing Harness (`EndveinTestClient`).
* ⏳ Isolated DB Pool Adapter (PostgreSQL / SQLite via FFI).
* ⏳ Endvein Scaffolding CLI (`endvein new`, `endvein make:controller`).

---

## 📄 License

MIT License © 2026 Endvein Team & M Nasrul Alawy.

