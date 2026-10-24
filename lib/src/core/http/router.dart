import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'context.dart';
import 'http_method.dart';
import 'middleware.dart';
import 'response.dart';

typedef RouteHandler = FutureOr<dynamic> Function(EndveinContext ctx);

class _RouteTarget {
  final RouteHandler handler;
  final List<EndveinMiddleware> middlewares;

  _RouteTarget(this.handler, [this.middlewares = const []]);

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

class _DynamicRoute {
  final HttpMethod method;
  final List<String> segments;
  final _RouteTarget target;

  _DynamicRoute({
    required this.method,
    required this.segments,
    required this.target,
  });

  bool matches(List<String> pathSegments, Map<String, String> outParams) {
    if (segments.length != pathSegments.length) return false;

    for (var i = 0; i < segments.length; i++) {
      final seg = segments[i];
      final pathSeg = pathSegments[i];

      if (seg.startsWith(':')) {
        final paramName = seg.substring(1);
        outParams[paramName] = pathSeg;
      } else if (seg != pathSeg) {
        return false;
      }
    }
    return true;
  }
}

/// Ultra-fast HTTP Router supporting static O(1) lookups, dynamic routes, route groups, and scoped middlewares.
class EndveinRouter {
  final String _prefix;
  final List<EndveinMiddleware> _groupMiddlewares;
  final EndveinRouter? _parent;

  // Root storage structures
  final Map<String, _RouteTarget> _staticRoutes;
  final List<_DynamicRoute> _dynamicRoutes;
  final MiddlewarePipeline _pipeline;

  EndveinRouter({String prefix = ''})
      : _prefix = prefix,
        _groupMiddlewares = [],
        _parent = null,
        _staticRoutes = {},
        _dynamicRoutes = [],
        _pipeline = MiddlewarePipeline();

  EndveinRouter._child(
    this._parent,
    this._prefix,
    this._groupMiddlewares,
    this._staticRoutes,
    this._dynamicRoutes,
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
      _dynamicRoutes,
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
    final target = _RouteTarget(handler, allMiddlewares);

    if (cleanPath.contains(':')) {
      final segments = cleanPath.split('/').where((s) => s.isNotEmpty).toList();
      _dynamicRoutes.add(_DynamicRoute(
        method: method,
        segments: segments,
        target: target,
      ));
    } else {
      _staticRoutes['${method.value} $cleanPath'] = target;
    }
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

    // 2. Segment-based Dynamic Route Lookup
    final pathSegments = path.split('/').where((s) => s.isNotEmpty).toList();
    for (final dynamicRoute in _dynamicRoutes) {
      if (dynamicRoute.method != method) continue;

      final params = <String, String>{};
      if (dynamicRoute.matches(pathSegments, params)) {
        ctx.params.addAll(params);
        await dynamicRoute.target.execute(ctx, _handleResult);
        return null;
      }
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
