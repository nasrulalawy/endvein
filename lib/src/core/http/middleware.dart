import 'dart:async';

import 'context.dart';
import 'response.dart';

/// Next function signature in the middleware pipeline.
typedef NextFunction = FutureOr<EndveinResponse?> Function();

/// Endvein Middleware function definition.
typedef EndveinMiddleware = FutureOr<EndveinResponse?> Function(
  EndveinContext ctx,
  NextFunction next,
);

/// Composes a list of middlewares into a single executable pipeline.
class MiddlewarePipeline {
  final List<EndveinMiddleware> _middlewares = [];

  void use(EndveinMiddleware middleware) {
    _middlewares.add(middleware);
  }

  bool get hasMiddlewares => _middlewares.isNotEmpty;

  FutureOr<EndveinResponse?> execute(
    EndveinContext ctx,
    FutureOr<EndveinResponse?> Function() finalHandler,
  ) {
    if (_middlewares.isEmpty) {
      return finalHandler();
    }

    int index = -1;

    FutureOr<EndveinResponse?> dispatch(int i) {
      if (i <= index) {
        throw StateError('next() called multiple times');
      }
      index = i;

      if (i < _middlewares.length) {
        final middleware = _middlewares[i];
        return middleware(ctx, () => dispatch(i + 1));
      } else {
        return finalHandler();
      }
    }

    return dispatch(0);
  }
}
