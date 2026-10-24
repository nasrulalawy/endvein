import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'context.dart';
import 'http_method.dart';
import 'middleware.dart';
import 'response.dart';

import 'trie.dart';

typedef RouteHandler = FutureOr<dynamic> Function(EndveinContext ctx);

/// Represents a route execution target containing handler and scoped middlewares.
class RouteTarget {
  final RouteHandler handler;
  final List<EndveinMiddleware> middlewares;

  RouteTarget(this.handler, [this.middlewares = const []]);

  FutureOr<void> execute(
    EndveinContext ctx,
    void Function(EndveinContext ctx, dynamic result) onResult,
  ) async {
    if (middlewares.isEmpty) {
      final result = await handler(ctx);
      onResult(ctx, result);
      return;
    }

    final pipeline = MiddlewarePipeline();
    for (final m in middlewares) {
      pipeline.use(m);
    }
    final response = await pipeline.execute(ctx, () async {
      final result = await handler(ctx);
      onResult(ctx, result);
      return null;
    });

    if (response != null) {
      onResult(ctx, response);
    }
  }
}

/// Ultra-fast HTTP Router supporting static O(1) lookups, Radix Tree dynamic routes, route groups, and scoped middlewares.
class EndveinRouter {
  final String _prefix;
  final List<EndveinMiddleware> _groupMiddlewares;
  final EndveinRouter? _parent;

  // Root storage structures
  final Map<String, RouteTarget> _staticRoutes;
  final RadixTreeRouter _radixTree;
  final MiddlewarePipeline _pipeline;

  EndveinRouter({String prefix = ''})
      : _prefix = prefix,
        _groupMiddlewares = [],
        _parent = null,
        _staticRoutes = {},
        _radixTree = RadixTreeRouter(),
        _pipeline = MiddlewarePipeline();

  EndveinRouter._child(
    this._parent,
    this._prefix,
    this._groupMiddlewares,
    this._staticRoutes,
    this._radixTree,
    this._pipeline,
  );

  /// Register a middleware for this router or scoped group.
  void use(EndveinMiddleware middleware) {
    if (_parent == null) {
      _pipeline.use(middleware);
    } else {
      _groupMiddlewares.add(middleware);
    }
  }

  /// Create a scoped route group with a path prefix and optional middlewares.
  EndveinRouter group(
    String prefix, [
    void Function(EndveinRouter group)? configure,
    List<EndveinMiddleware>? middlewares,
  ]) {
    final combinedPrefix = _combinePaths(_prefix, prefix);
    final combinedMiddlewares = [
      ..._groupMiddlewares,
      ...?middlewares,
    ];

    final child = EndveinRouter._child(
      this,
      combinedPrefix,
      combinedMiddlewares,
      _staticRoutes,
      _radixTree,
      _pipeline,
    );

    if (configure != null) {
      configure(child);
    }
    return child;
  }

  void add(
    HttpMethod method,
    String path,
    RouteHandler handler, {
    List<EndveinMiddleware>? middlewares,
  }) {
    final fullPath = _combinePaths(_prefix, path);
    final cleanPath = _normalizePath(fullPath);
    final allMiddlewares = [
      ..._groupMiddlewares,
      ...?middlewares,
    ];
    final target = RouteTarget(handler, allMiddlewares);

    if (!cleanPath.contains(':') && !cleanPath.contains('*')) {
      _staticRoutes['${method.value} $cleanPath'] = target;
    }
    _radixTree.insert(method, cleanPath, target);
  }

  void get(String path, RouteHandler handler, {List<EndveinMiddleware>? middlewares}) =>
      add(HttpMethod.get, path, handler, middlewares: middlewares);
  void post(String path, RouteHandler handler, {List<EndveinMiddleware>? middlewares}) =>
      add(HttpMethod.post, path, handler, middlewares: middlewares);
  void put(String path, RouteHandler handler, {List<EndveinMiddleware>? middlewares}) =>
      add(HttpMethod.put, path, handler, middlewares: middlewares);
  void delete(String path, RouteHandler handler, {List<EndveinMiddleware>? middlewares}) =>
      add(HttpMethod.delete, path, handler, middlewares: middlewares);
  void patch(String path, RouteHandler handler, {List<EndveinMiddleware>? middlewares}) =>
      add(HttpMethod.patch, path, handler, middlewares: middlewares);
  void options(String path, RouteHandler handler, {List<EndveinMiddleware>? middlewares}) =>
      add(HttpMethod.options, path, handler, middlewares: middlewares);

  /// Handle a standard [HttpRequest] (for compatibility with dart:io HttpServer)
  Future<void> handle(HttpRequest request) async {
    final ctx = StandardHttpContext(request);
    await handleContext(ctx);
  }

  /// Handle any [EndveinContext] (e.g. ZeroCopyContext, StandardHttpContext, or TestContext)
  Future<void> handleContext(EndveinContext ctx) async {
    try {
      final res = await _pipeline.execute(ctx, () async {
        return await _dispatch(ctx);
      });
      if (res != null && !ctx.isResponded) {
        _handleResult(ctx, res);
      }
    } catch (e, stack) {
      if (!ctx.isResponded) {
        ctx.json({
          'error': 'Internal Server Error',
          'message': e.toString(),
        }, statusCode: HttpStatus.internalServerError);
      }
      stderr.writeln('[Endvein Error] $e\n$stack');
    }
  }

  FutureOr<EndveinResponse?> _dispatch(EndveinContext ctx) async {
    final method = ctx.method;
    if (method == null) {
      ctx.text('Method Not Allowed', statusCode: HttpStatus.methodNotAllowed);
      return null;
    }

    final path = _normalizePath(ctx.path);

    // 1. O(1) Static Route Lookup
    final staticKey = '${method.value} $path';
    final staticTarget = _staticRoutes[staticKey];
    if (staticTarget != null) {
      await staticTarget.execute(ctx, _handleResult);
      return null;
    }

    // 2. High-Performance Radix Tree Lookup (Params :id and Wildcards *filepath)
    final match = _radixTree.search(method, path);
    if (match != null) {
      ctx.params.addAll(match.params);
      await match.target.execute(ctx, _handleResult);
      return null;
    }

    // 3. Fallback 404
    if (!ctx.isResponded) {
      ctx.json({
        'error': 'Not Found',
        'path': ctx.path,
        'method': ctx.method?.value ?? 'UNKNOWN',
      }, statusCode: HttpStatus.notFound);
    }
    return null;
  }

  void _handleResult(EndveinContext ctx, dynamic result) {
    if (ctx.isResponded) return;

    if (result is EndveinResponse) {
      ctx.sendResponse(result);
    } else if (result is Map || result is List) {
      ctx.json(result);
    } else if (result is String) {
      ctx.text(result);
    } else if (result is Uint8List) {
      ctx.bytes(result);
    } else if (result != null) {
      ctx.text(result.toString());
    } else {
      ctx.text('');
    }
  }

  static String _combinePaths(String p1, String p2) {
    var a = p1.trim();
    var b = p2.trim();
    if (a.endsWith('/')) a = a.substring(0, a.length - 1);
    if (!b.startsWith('/')) b = '/$b';
    return '$a$b';
  }

  String _normalizePath(String path) {
    if (path.isEmpty || path == '/') return '/';
    final trimmed = path.trim();
    if (!trimmed.startsWith('/')) return '/$trimmed';
    if (trimmed.endsWith('/') && trimmed.length > 1) {
      return trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }
}
