import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

/// Simulates Dart Frog's core engine stack (Shelf Pipeline, Cascade, and dart:io HttpServer).
void main() async {
  const jsonString = '{"message":"Hello from Dart Frog / Shelf","status":"ok"}';

  Response handler(Request request) {
    if (request.url.path == 'json') {
      return Response.ok(
        jsonString,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }
    return Response.ok('Hello World', headers: {'content-type': 'text/plain'});
  }

  // Standard Dart Frog Shelf pipeline
  final pipeline = const Pipeline().addHandler(handler);

  // Default Dart Frog runner binds on 127.0.0.1
  final server = await shelf_io.serve(pipeline, '127.0.0.1', 8085);
  server.autoCompress = false; // fair comparison without compression overhead

  stdout.writeln('Dart Frog (Shelf) server listening on http://127.0.0.1:8085');
}
