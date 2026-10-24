import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

void main() async {
  final server = await HttpServer.bind('127.0.0.1', 8081);
  final jsonBytes = Uint8List.fromList(
    utf8.encode('{"message":"Hello from Single Isolate","status":"ok"}'),
  );

  stdout.writeln('Single Isolate server listening on http://127.0.0.1:8081');

  server.listen((HttpRequest request) {
    if (request.uri.path == '/json') {
      request.response
        ..headers.contentType = ContentType.json
        ..headers.contentLength = jsonBytes.length
        ..add(jsonBytes)
        ..close();
    } else {
      request.response
        ..headers.contentType = ContentType.text
        ..write('Hello World')
        ..close();
    }
  });
}
