import 'dart:convert';
import 'dart:io';

/// Simulates Serverpod's core HTTP RPC dispatching & session layer architecture.
class _ServerpodSession {
  final HttpRequest request;
  final String endpoint;
  final String method;
  final DateTime startTime;

  _ServerpodSession({
    required this.request,
    required this.endpoint,
    required this.method,
  }) : startTime = DateTime.now();

  Future<void> close() async {}
}

void main() async {
  final server = await HttpServer.bind('127.0.0.1', 8086);
  server.autoCompress = false;

  stdout.writeln('Serverpod architecture server listening on http://127.0.0.1:8086');

  server.listen((HttpRequest request) async {
    // 1. Serverpod Session Allocation per request
    final session = _ServerpodSession(
      request: request,
      endpoint: 'example',
      method: request.method,
    );

    try {
      if (request.uri.path == '/json') {
        final payload = jsonEncode({
          'message': 'Hello from Serverpod',
          'status': 'ok',
        });
        final bytes = utf8.encode(payload);

        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..headers.contentLength = bytes.length
          ..add(bytes);
        await request.response.close();
      } else {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.text
          ..write('Hello World');
        await request.response.close();
      }
    } finally {
      await session.close();
    }
  });
}
