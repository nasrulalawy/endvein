import 'dart:convert';
import 'dart:math';

import '../context.dart';
import '../middleware.dart';

int _requestCounter = 0;

String _generateRequestId() {
  final now = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final count = (_requestCounter++).toRadixString(36);
  final rand = Random().nextInt(0xFFFFFF).toRadixString(36);
  return 'req-$now-$count-$rand';
}

/// Request Logger and Distributed Tracing Middleware for Endvein.
///
/// Automatically attaches or preserves an `X-Request-Id`, measures handler
/// latency with high-precision [Stopwatch], and prints either colorized CLI logs
/// or structured JSON logs for Datadog / ELK / CloudWatch.
EndveinMiddleware logger({
  bool jsonFormat = false,
  void Function(String logMessage)? printFn,
}) {
  final output = printFn ?? print;

  return (EndveinContext ctx, NextFunction next) async {
    final sw = Stopwatch()..start();

    // Preserve or generate distributed request trace ID
    final reqId = ctx.getHeader('x-request-id') ?? _generateRequestId();
    ctx.setHeader('X-Request-Id', reqId);
    ctx.store['requestId'] = reqId;

    final method = ctx.method?.value ?? 'UNKNOWN';
    final path = ctx.path;

    try {
      final res = await next();
      sw.stop();
      final elapsedMs = (sw.elapsedMicroseconds / 1000.0).toStringAsFixed(2);
      final status = res?.statusCode ?? (ctx.isResponded ? 200 : 200);

      if (jsonFormat) {
        final logMap = {
          'level': 'info',
          'timestamp': DateTime.now().toUtc().toIso8601String(),
          'requestId': reqId,
          'method': method,
          'path': path,
          'statusCode': status,
          'latencyMs': double.tryParse(elapsedMs) ?? 0.0,
        };
        output(jsonEncode(logMap));
      } else {
        output(
          '[${DateTime.now().toIso8601String()}] [$method] $path '
          '-> $status (${elapsedMs}ms) [$reqId]',
        );
      }
      return res;
    } catch (e) {
      sw.stop();
      final elapsedMs = (sw.elapsedMicroseconds / 1000.0).toStringAsFixed(2);
      if (jsonFormat) {
        final logMap = {
          'level': 'error',
          'timestamp': DateTime.now().toUtc().toIso8601String(),
          'requestId': reqId,
          'method': method,
          'path': path,
          'statusCode': 500,
          'latencyMs': double.tryParse(elapsedMs) ?? 0.0,
          'error': e.toString(),
        };
        output(jsonEncode(logMap));
      } else {
        output(
          '[${DateTime.now().toIso8601String()}] [$method] $path '
          '-> ERROR: $e (${elapsedMs}ms) [$reqId]',
        );
      }
      rethrow;
    }
  };
}
