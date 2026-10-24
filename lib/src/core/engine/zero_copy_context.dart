import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../http/context.dart';
import '../http/http_method.dart';
import '../http/response.dart';
import '../http/sse.dart';
import 'http_constants.dart';
import 'raw_request.dart';

/// Ultra-high-performance context for Raw TCP Sockets.
class ZeroCopyContext implements EndveinContext {
  final Socket socket;
  final RawHttpRequest rawReq;

  @override
  final Map<String, String> params;

  @override
  final Map<String, Object?> store;

  @override
  final Map<String, String> responseHeaders = {};

  bool _responded = false;

  ZeroCopyContext(
    this.socket,
    this.rawReq, {
    Map<String, String>? params,
    Map<String, Object?>? store,
  })  : params = params ?? <String, String>{},
        store = store ?? <String, Object?>{};

  @override
  void setHeader(String name, String value) {
    responseHeaders[name] = value;
  }

  @override
  String get path => rawReq.path;

  @override
  HttpMethod? get method => rawReq.method;

  @override
  Map<String, String> get queryParameters => rawReq.queryParameters;

  @override
  String? getHeader(String name) => rawReq.header(name);

  @override
  bool get isResponded => _responded;

  @override
  Uint8List? get rawBody => rawReq.body;

  @override
  Future<String> bodyText() async {
    return rawReq.bodyText();
  }

  @override
  Future<dynamic> bodyJson() async {
    return rawReq.bodyJson();
  }

  @override
  void json(Object? data, {int statusCode = 200}) {
    if (_responded) return;
    _responded = true;

    final bodyBytes = (data == null)
        ? Uint8List(0)
        : Uint8List.fromList(utf8.encode(jsonEncode(data)));

    _writeResponse(
      statusCode: statusCode,
      contentType: 'application/json; charset=utf-8',
      bodyBytes: bodyBytes,
    );
  }

  @override
  void text(String message, {int statusCode = 200}) {
    if (_responded) return;
    _responded = true;

    final bodyBytes = Uint8List.fromList(utf8.encode(message));
    _writeResponse(
      statusCode: statusCode,
      contentType: 'text/plain; charset=utf-8',
      bodyBytes: bodyBytes,
    );
  }

  @override
  void bytes(
    Uint8List data, {
    String contentType = 'application/octet-stream',
    int statusCode = 200,
  }) {
    if (_responded) return;
    _responded = true;

    _writeResponse(
      statusCode: statusCode,
      contentType: contentType,
      bodyBytes: data,
    );
  }

  @override
  void sendResponse(EndveinResponse response) {
    if (_responded) return;
    _responded = true;

    final statusLine = HttpConstants.getStatusLine(response.statusCode);
    final headerBuffer = StringBuffer();
    headerBuffer.write('Server: Endvein\r\n');

    final len = response.bodyBytes?.length ?? 0;
    headerBuffer.write('Content-Length: $len\r\n');
    headerBuffer.write(
      rawReq.keepAlive ? 'Connection: keep-alive\r\n' : 'Connection: close\r\n',
    );

    responseHeaders.forEach((key, val) {
      headerBuffer.write('$key: $val\r\n');
    });
    response.headers.forEach((key, val) {
      headerBuffer.write('$key: $val\r\n');
    });
    headerBuffer.write('\r\n');

    final headerBytes = ascii.encode(headerBuffer.toString());
    final builder = BytesBuilder(copy: false)
      ..add(statusLine)
      ..add(headerBytes);

    if (response.bodyBytes != null) {
      builder.add(response.bodyBytes!);
    }

    socket.add(builder.takeBytes());

    if (!rawReq.keepAlive) {
      socket.close();
    }
  }

  void _writeResponse({
    required int statusCode,
    required String contentType,
    required Uint8List bodyBytes,
  }) {
    final statusLine = HttpConstants.getStatusLine(statusCode);
    final connHeader =
        rawReq.keepAlive ? 'Connection: keep-alive\r\n' : 'Connection: close\r\n';

    final headerBuffer = StringBuffer();
    headerBuffer.write('Server: Endvein\r\n');
    headerBuffer.write('Content-Type: $contentType\r\n');
    headerBuffer.write('Content-Length: ${bodyBytes.length}\r\n');
    headerBuffer.write(connHeader);

    responseHeaders.forEach((key, val) {
      headerBuffer.write('$key: $val\r\n');
    });
    headerBuffer.write('\r\n');

    final headerBytes = ascii.encode(headerBuffer.toString());
    final builder = BytesBuilder(copy: false)
      ..add(statusLine)
      ..add(headerBytes)
      ..add(bodyBytes);

    socket.add(builder.takeBytes());

    if (!rawReq.keepAlive) {
      socket.close();
    }
  }

  @override
  Future<void> sse(Future<void> Function(SseSender sender) streamHandler) async {
    if (_responded) return;
    _responded = true;

    final headerBuffer = StringBuffer();
    headerBuffer.write('HTTP/1.1 200 OK\r\n');
    headerBuffer.write('Server: Endvein\r\n');
    headerBuffer.write('Content-Type: text/event-stream; charset=utf-8\r\n');
    headerBuffer.write('Cache-Control: no-cache\r\n');
    headerBuffer.write('Connection: keep-alive\r\n');
    headerBuffer.write('X-Accel-Buffering: no\r\n');

    responseHeaders.forEach((key, val) {
      headerBuffer.write('$key: $val\r\n');
    });
    headerBuffer.write('\r\n');

    socket.add(ascii.encode(headerBuffer.toString()));

    final sender = _ZeroCopySseSender(socket);
    try {
      await streamHandler(sender);
    } finally {
      await sender.close();
    }
  }
}

class _ZeroCopySseSender implements SseSender {
  final Socket socket;
  _ZeroCopySseSender(this.socket);

  @override
  void send(SseEvent event) {
    try {
      socket.add(event.toBytes());
    } catch (_) {}
  }

  @override
  void sendData(String data, {String? event, String? id}) {
    send(SseEvent(data: data, event: event, id: id));
  }

  @override
  Future<void> close() async {
    try {
      await socket.flush();
      await socket.close();
    } catch (_) {
      socket.destroy();
    }
  }
}
