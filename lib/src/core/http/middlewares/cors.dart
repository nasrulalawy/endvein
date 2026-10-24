import '../context.dart';
import '../http_method.dart';
import '../middleware.dart';
import '../response.dart';

/// Endvein CORS Middleware configuration options.
class CorsOptions {
  final List<String> allowOrigins;
  final List<String> allowMethods;
  final List<String> allowHeaders;
  final List<String> exposeHeaders;
  final bool allowCredentials;
  final int maxAge;

  const CorsOptions({
    this.allowOrigins = const ['*'],
    this.allowMethods = const [
      'GET',
      'HEAD',
      'PUT',
      'PATCH',
      'POST',
      'DELETE',
      'OPTIONS',
    ],
    this.allowHeaders = const ['*'],
    this.exposeHeaders = const [],
    this.allowCredentials = false,
    this.maxAge = 86400, // 24 hours
  });
}

/// Creates a standard, high-performance CORS middleware for Endvein.
EndveinMiddleware cors([CorsOptions options = const CorsOptions()]) {
  final originsStr = options.allowOrigins.join(', ');
  final methodsStr = options.allowMethods.join(', ');
  final headersStr = options.allowHeaders.join(', ');
  final exposeHeadersStr = options.exposeHeaders.isNotEmpty
      ? options.exposeHeaders.join(', ')
      : null;

  return (EndveinContext ctx, NextFunction next) async {
    final requestOrigin = ctx.getHeader('origin');
    final allowOrigin = options.allowOrigins.contains('*')
        ? '*'
        : (requestOrigin != null && options.allowOrigins.contains(requestOrigin)
            ? requestOrigin
            : originsStr);

    ctx.setHeader('Access-Control-Allow-Origin', allowOrigin);
    if (options.allowCredentials) {
      ctx.setHeader('Access-Control-Allow-Credentials', 'true');
    }
    if (exposeHeadersStr != null) {
      ctx.setHeader('Access-Control-Expose-Headers', exposeHeadersStr);
    }

    // Handle pre-flight OPTIONS request
    if (ctx.method == HttpMethod.options) {
      ctx.setHeader('Access-Control-Allow-Methods', methodsStr);
      ctx.setHeader('Access-Control-Allow-Headers', headersStr);
      ctx.setHeader('Access-Control-Max-Age', options.maxAge.toString());
      return EndveinResponse.empty(statusCode: 204);
    }

    return await next();
  };
}
