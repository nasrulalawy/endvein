import '../context.dart';
import '../middleware.dart';
import '../router.dart';

/// In-memory Prometheus metrics registry for monitoring Endvein services.
///
/// Collects request counts and durations, formatting them in standard
/// Prometheus text exposition format (version 0.0.4) at `/metrics`.
class PrometheusMetrics {
  final Map<String, int> _requestCounts = {};
  final Map<String, double> _requestDurations = {};
  final int _startTime = DateTime.now().millisecondsSinceEpoch;

  /// Middleware that tracks request throughput and latency.
  EndveinMiddleware middleware() {
    return (EndveinContext ctx, NextFunction next) async {
      // Don't count metrics endpoint itself to prevent skew
      if (ctx.path == '/metrics') {
        return await next();
      }

      final sw = Stopwatch()..start();
      final method = ctx.method?.value ?? 'UNKNOWN';

      try {
        final res = await next();
        sw.stop();
        final status = res?.statusCode ?? (ctx.isResponded ? 200 : 200);
        _record(method, status, sw.elapsedMicroseconds / 1000000.0);
        return res;
      } catch (_) {
        sw.stop();
        _record(method, 500, sw.elapsedMicroseconds / 1000000.0);
        rethrow;
      }
    };
  }

  void _record(String method, int status, double durationSeconds) {
    final key = '$method:$status';
    _requestCounts[key] = (_requestCounts[key] ?? 0) + 1;
    _requestDurations[key] = (_requestDurations[key] ?? 0.0) + durationSeconds;
  }

  /// Route handler that exposes collected metrics in Prometheus text format.
  RouteHandler get handler {
    return (EndveinContext ctx) {
      final buffer = StringBuffer();
      final uptimeSeconds = (DateTime.now().millisecondsSinceEpoch - _startTime) / 1000.0;

      buffer.writeln('# HELP endvein_uptime_seconds Process uptime in seconds.');
      buffer.writeln('# TYPE endvein_uptime_seconds gauge');
      buffer.writeln('endvein_uptime_seconds ${uptimeSeconds.toStringAsFixed(2)}');
      buffer.writeln();

      buffer.writeln('# HELP http_requests_total Total number of HTTP requests processed.');
      buffer.writeln('# TYPE http_requests_total counter');
      _requestCounts.forEach((key, count) {
        final parts = key.split(':');
        final method = parts[0];
        final status = parts[1];
        buffer.writeln('http_requests_total{method="$method",status="$status"} $count');
      });
      buffer.writeln();

      buffer.writeln('# HELP http_request_duration_seconds_total Total duration of HTTP requests in seconds.');
      buffer.writeln('# TYPE http_request_duration_seconds_total counter');
      _requestDurations.forEach((key, totalSeconds) {
        final parts = key.split(':');
        final method = parts[0];
        final status = parts[1];
        buffer.writeln(
          'http_request_duration_seconds_total{method="$method",status="$status"} ${totalSeconds.toStringAsFixed(6)}',
        );
      });

      ctx.setHeader('Content-Type', 'text/plain; version=0.0.4; charset=utf-8');
      return buffer.toString();
    };
  }
}
