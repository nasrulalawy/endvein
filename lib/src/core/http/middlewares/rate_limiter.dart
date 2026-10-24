import 'dart:io';

import '../context.dart';
import '../middleware.dart';
import '../response.dart';

class _RateLimitEntry {
  int count;
  DateTime resetTime;

  _RateLimitEntry({required this.count, required this.resetTime});
}

/// In-memory Rate Limiting middleware protecting Endvein routes from abuse.
///
/// Returns HTTP `429 Too Many Requests` when limits are exceeded, attaching
/// standard `X-RateLimit-Limit`, `X-RateLimit-Remaining`, and `Retry-After` headers.
EndveinMiddleware rateLimiter({
  int maxRequests = 100,
  Duration window = const Duration(minutes: 1),
  String message = 'Too many requests, please try again later.',
  String Function(EndveinContext ctx)? keyGenerator,
}) {
  final storage = <String, _RateLimitEntry>{};
  var lastCleanup = DateTime.now();

  return (EndveinContext ctx, NextFunction next) async {
    final now = DateTime.now();

    // Opportunistic garbage collection of expired entries every 30 seconds
    if (now.difference(lastCleanup) > const Duration(seconds: 30)) {
      storage.removeWhere((_, entry) => now.isAfter(entry.resetTime));
      lastCleanup = now;
    }

    // Determine client identifier key
    final clientKey = keyGenerator != null
        ? keyGenerator(ctx)
        : (ctx.getHeader('x-forwarded-for')?.split(',').first.trim() ??
            ctx.getHeader('x-real-ip') ??
            'unknown_client');

    final entry = storage[clientKey];

    if (entry == null || now.isAfter(entry.resetTime)) {
      // First request or window expired
      final resetTime = now.add(window);
      storage[clientKey] = _RateLimitEntry(count: 1, resetTime: resetTime);

      final resetSecs = (resetTime.millisecondsSinceEpoch / 1000).ceil();
      ctx.setHeader('X-RateLimit-Limit', maxRequests.toString());
      ctx.setHeader('X-RateLimit-Remaining', (maxRequests - 1).toString());
      ctx.setHeader('X-RateLimit-Reset', resetSecs.toString());

      return await next();
    }

    if (entry.count >= maxRequests) {
      // Rate limit exceeded
      final retryAfter = entry.resetTime.difference(now).inSeconds.clamp(1, window.inSeconds);
      final resetSecs = (entry.resetTime.millisecondsSinceEpoch / 1000).ceil();

      ctx.setHeader('Retry-After', retryAfter.toString());
      ctx.setHeader('X-RateLimit-Limit', maxRequests.toString());
      ctx.setHeader('X-RateLimit-Remaining', '0');
      ctx.setHeader('X-RateLimit-Reset', resetSecs.toString());

      return EndveinResponse.json({
        'error': 'Too Many Requests',
        'message': message,
        'retryAfter': retryAfter,
      }, statusCode: HttpStatus.tooManyRequests);
    }

    // Increment count within active window
    entry.count++;
    final remaining = maxRequests - entry.count;
    final resetSecs = (entry.resetTime.millisecondsSinceEpoch / 1000).ceil();

    ctx.setHeader('X-RateLimit-Limit', maxRequests.toString());
    ctx.setHeader('X-RateLimit-Remaining', remaining.toString());
    ctx.setHeader('X-RateLimit-Reset', resetSecs.toString());

    return await next();
  };
}
