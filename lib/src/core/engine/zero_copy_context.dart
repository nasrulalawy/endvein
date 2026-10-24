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
  RawHttpRequest rawReq;

  Map<String, String>? _params;
  Map<String, Object?>? _store;
  Map<String, String>? _responseHeaders;

  @override
  Map<String, String> get params => _params ??= <String, String>{};

  @override
  Map<String, Object?> get store => _store ??= <String, Object?>{};

  @override
  Map<String, String> get responseHeaders =>
      _responseHeaders ??= <String, String>{};

  bool get hasResponseHeaders =>
      _responseHeaders != null && _responseHeaders!.isNotEmpty;

  bool _responded = false;

  ZeroCopyContext(
    this.socket,
    this.rawReq, {
    Map<String, String>? params,
    Map<String, Object?>? store,
  })  : _params = params,
        _store = store;

  /// Resets context state for the next request on the same Keep-Alive connection.
  void reset(RawHttpRequest newReq) {
    rawReq = newReq;
    _params = null;
    _store = null;
    _responseHeaders = null;
    _responded = false;
  }

  @override
  void setHeader(String name, String value) {
    if (name.contains('\r') || name.contains('\n') || value.contains('\r') || value.contains('\n')) {
      throw ArgumentError(
        'Header name and value must not contain CRLF characters.',
      );
    }
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

    if (!hasResponseHeaders && statusCode == 200) {
      _writeFastResponse(
        rawReq.keepAlive
            ? HttpConstants.json200KeepAlivePrefix
            : HttpConstants.json200ClosePrefix,
        bodyBytes,
      );
      return;
    }

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

    if (!hasResponseHeaders && statusCode == 200) {
      _writeFastResponse(
        rawReq.keepAlive
            ? HttpConstants.text200KeepAlivePrefix
            : HttpConstants.text200ClosePrefix,
        bodyBytes,
      );
      return;
    }

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

    if (!hasResponseHeaders && statusCode == 200) {
      if (contentType == 'application/json; charset=utf-8' ||
          contentType == 'application/json') {
        _writeFastResponse(
          rawReq.keepAlive
              ? HttpConstants.json200KeepAlivePrefix
              : HttpConstants.json200ClosePrefix,
          data,
        );
        return;
      } else if (contentType == 'text/plain; charset=utf-8' ||
          contentType == 'text/plain') {
        _writeFastResponse(
          rawReq.keepAlive
              ? HttpConstants.text200KeepAlivePrefix
              : HttpConstants.text200ClosePrefix,
          data,
        );
        return;
      }
    }

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

    _responseHeaders?.forEach((key, val) {
      headerBuffer.write('$key: $val\r\n');
    });
    response.headers.forEach((key, val) {
      headerBuffer.write('$key: $val\r\n');
    });
    headerBuffer.write('\r\n');

    final headerBytes = ascii.encode(headerBuffer.toString());
    final bodyBytes = response.bodyBytes;
    final totalLen = statusLine.length + headerBytes.length + (bodyBytes?.length ?? 0);
    final out = Uint8List(totalLen);
    out.setRange(0, statusLine.length, statusLine);
    out.setRange(statusLine.length, statusLine.length + headerBytes.length, headerBytes);
    if (bodyBytes != null && bodyBytes.isNotEmpty) {
      out.setRange(statusLine.length + headerBytes.length, totalLen, bodyBytes);
    }

    socket.add(out);

    if (!rawReq.keepAlive) {
      socket.close();
    }
  }

  void _writeFastResponse(Uint8List prefix, Uint8List bodyBytes) {
    final len = bodyBytes.length;
    final cl = len < 1024
        ? HttpConstants.contentLengthCache[len]
        : ascii.encode('Content-Length: $len\r\n\r\n');

    final totalLen = prefix.length + cl.length + len;
    final out = Uint8List(totalLen);

    out.setRange(0, prefix.length, prefix);
    out.setRange(prefix.length, prefix.length + cl.length, cl);
    if (len > 0) {
      out.setRange(prefix.length + cl.length, totalLen, bodyBytes);
    }

    socket.add(out);

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

    _responseHeaders?.forEach((key, val) {
      headerBuffer.write('$key: $val\r\n');
    });
    headerBuffer.write('\r\n');

    final headerBytes = ascii.encode(headerBuffer.toString());
    final totalLen = statusLine.length + headerBytes.length + bodyBytes.length;
    final out = Uint8List(totalLen);
    out.setRange(0, statusLine.length, statusLine);
    out.setRange(statusLine.length, statusLine.length + headerBytes.length, headerBytes);
    if (bodyBytes.isNotEmpty) {
      out.setRange(statusLine.length + headerBytes.length, totalLen, bodyBytes);
    }

    socket.add(out);

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
