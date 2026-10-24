import 'dart:async';
import 'dart:io';

import '../context.dart';
import '../middleware.dart';
import '../response.dart';

/// Result returned by [RateLimiterStore] for rate evaluation.
class RateLimitResult {
  final int count;
  final DateTime resetTime;

  const RateLimitResult({required this.count, required this.resetTime});
}

/// Abstract storage engine interface for rate limiting.
/// Allows pluggable backends (In-Memory, Shared Memory, Redis, PostgreSQL).
abstract interface class RateLimiterStore {
  /// Record a request for [key] within [window] and return current state.
  FutureOr<RateLimitResult> recordRequest(String key, Duration window);
}

class _RateLimitEntry {
  int count;
  DateTime resetTime;

  _RateLimitEntry({required this.count, required this.resetTime});
}

/// In-memory storage engine for rate limiting.
class InMemoryRateLimiterStore implements RateLimiterStore {
  final Map<String, _RateLimitEntry> _storage = {};
  DateTime _lastCleanup = DateTime.now();

  @override
  RateLimitResult recordRequest(String key, Duration window) {
    final now = DateTime.now();

    // Opportunistic garbage collection of expired entries every 30 seconds
    if (now.difference(_lastCleanup) > const Duration(seconds: 30)) {
      _storage.removeWhere((_, entry) => now.isAfter(entry.resetTime));
      _lastCleanup = now;
    }

    final entry = _storage[key];
    if (entry == null || now.isAfter(entry.resetTime)) {
      final resetTime = now.add(window);
      _storage[key] = _RateLimitEntry(count: 1, resetTime: resetTime);
      return RateLimitResult(count: 1, resetTime: resetTime);
    }

    entry.count++;
    return RateLimitResult(count: entry.count, resetTime: entry.resetTime);
  }
}

/// Rate Limiting middleware protecting Endvein routes from abuse.
/// Supports in-memory storage or pluggable distributed stores (e.g. Redis).
EndveinMiddleware rateLimiter({
  int maxRequests = 100,
  Duration window = const Duration(minutes: 1),
  String message = 'Too many requests, please try again later.',
  RateLimiterStore? store,
  String Function(EndveinContext ctx)? keyGenerator,
}) {
  final activeStore = store ?? InMemoryRateLimiterStore();

  return (EndveinContext ctx, NextFunction next) async {
    final now = DateTime.now();

    // Determine client identifier key
    final clientKey = keyGenerator != null
        ? keyGenerator(ctx)
        : (ctx.getHeader('x-forwarded-for')?.split(',').first.trim() ??
            ctx.getHeader('x-real-ip') ??
            'unknown_client');

    final state = await activeStore.recordRequest(clientKey, window);
    final resetSecs = (state.resetTime.millisecondsSinceEpoch / 1000).ceil();

    if (state.count > maxRequests) {
      // Rate limit exceeded
      final retryAfter = state.resetTime.difference(now).inSeconds.clamp(1, window.inSeconds);

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

    final remaining = (maxRequests - state.count).clamp(0, maxRequests);

    ctx.setHeader('X-RateLimit-Limit', maxRequests.toString());
    ctx.setHeader('X-RateLimit-Remaining', remaining.toString());
    ctx.setHeader('X-RateLimit-Reset', resetSecs.toString());

    return await next();
  };
}
