/// Endvein - Next-Generation, Ultra-High-Throughput Dart Backend Framework.
library endvein;

// HTTP & Context Abstractions
export 'src/core/http/http_method.dart';
export 'src/core/http/context.dart';
export 'src/core/http/headers.dart';
export 'src/core/http/response.dart';
export 'src/core/http/middleware.dart';
export 'src/core/http/router.dart';
export 'src/core/http/trie.dart';
export 'src/core/http/multipart.dart';
export 'src/core/http/sse.dart';

// Built-in Middlewares
export 'src/core/http/middlewares/cors.dart';
export 'src/core/http/middlewares/security_headers.dart';
export 'src/core/http/middlewares/rate_limiter.dart';
export 'src/core/http/middlewares/logger.dart';
export 'src/core/http/middlewares/prometheus.dart';

// Multi-Core Cluster
export 'src/core/cluster/cluster.dart';

// Zero-Copy Streaming Engine
export 'src/core/engine/http_constants.dart';
export 'src/core/engine/raw_request.dart';
export 'src/core/engine/http_parser.dart';
export 'src/core/engine/zero_copy_context.dart';
export 'src/core/engine/raw_http_server.dart';

// Turbo FFI Native Engine (kqueue/epoll)
export 'src/core/turbo/turbo_bindings.dart';
export 'src/core/turbo/turbo_context.dart';
export 'src/core/turbo/turbo_http_server.dart';

// In-Memory Testing Harness
export 'src/core/testing/test_client.dart';

// Clean Architecture Core
export 'src/architecture/result.dart';
export 'src/architecture/use_case.dart';
export 'src/architecture/controller.dart';
