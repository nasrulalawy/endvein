import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

import '../http/context.dart';
import '../http/http_method.dart';
import '../http/response.dart';
import '../http/sse.dart';
import 'turbo_bindings.dart';

/// Ultra-High-Performance Context for Native Turbo FFI engine.
class TurboContext implements EndveinContext {
  int clientFd;
  HttpMethod? _method;
  String _path;
  bool keepAlive;
  Uint8List? _rawBody;

  Map<String, String>? _params;
  Map<String, Object?>? _store;
  Map<String, String>? _responseHeaders;
  Map<String, String>? _queryParameters;

  bool _responded = false;

  TurboContext({
    required this.clientFd,
    required HttpMethod? method,
    required String path,
    required this.keepAlive,
    Uint8List? rawBody,
    Map<String, String>? params,
    Map<String, Object?>? store,
  })  : _method = method,
        _path = path,
        _rawBody = rawBody,
        _params = params,
        _store = store;

  /// Reset context for reuse in the same thread.
  void reset({
    required int newClientFd,
    required HttpMethod? newMethod,
    required String newPath,
    required bool newKeepAlive,
    Uint8List? newRawBody,
  }) {
    clientFd = newClientFd;
    _method = newMethod;
    _path = newPath;
    keepAlive = newKeepAlive;
    _rawBody = newRawBody;

    _params = null;
    _store = null;
    _responseHeaders = null;
    _queryParameters = null;
    _responded = false;
  }

  @override
  String get path => _path;

  @override
  HttpMethod? get method => _method;

  @override
  Map<String, String> get params => _params ??= <String, String>{};

  @override
  Map<String, Object?> get store => _store ??= <String, Object?>{};

  @override
  Map<String, String> get responseHeaders => _responseHeaders ??= <String, String>{};

  bool get hasResponseHeaders => _responseHeaders != null && _responseHeaders!.isNotEmpty;

  @override
  Map<String, String> get queryParameters {
    if (_queryParameters != null) return _queryParameters!;
    final queryIdx = _path.indexOf('?');
    if (queryIdx == -1 || queryIdx == _path.length - 1) {
      return _queryParameters = const {};
    }
    return _queryParameters = Uri.splitQueryString(_path.substring(queryIdx + 1));
  }

  @override
  String? getHeader(String name) => null;

  @override
  bool get isResponded => _responded;

  @override
  Uint8List? get rawBody => _rawBody;

  @override
  void setHeader(String name, String value) {
    responseHeaders[name] = value;
  }

  @override
  Future<String> bodyText() async {
    if (_rawBody == null || _rawBody!.isEmpty) return '';
    return utf8.decode(_rawBody!);
  }

  @override
  Future<dynamic> bodyJson() async {
    final text = await bodyText();
    if (text.isEmpty) return null;
    return jsonDecode(text);
  }

  static final Pointer<Uint8> _threadBuffer = malloc<Uint8>(65536);

  @override
  void json(Object? data, {int statusCode = 200}) {
    if (_responded) return;
    _responded = true;

    final jsonBytes = utf8.encode(jsonEncode(data));

    if (!hasResponseHeaders && statusCode == 200 && jsonBytes.length <= 65536) {
      _threadBuffer.asTypedList(jsonBytes.length).setRange(0, jsonBytes.length, jsonBytes);
      TurboBindings.sendJson(
        clientFd,
        _threadBuffer.cast<Utf8>(),
        jsonBytes.length,
        keepAlive ? 1 : 0,
      );
      return;
    }

    _writeFullResponse(
      statusCode: statusCode,
      contentType: 'application/json; charset=utf-8',
      bodyBytes: jsonBytes,
    );
  }

  @override
  void text(String message, {int statusCode = 200}) {
    if (_responded) return;
    _responded = true;

    final textBytes = utf8.encode(message);

    if (!hasResponseHeaders && statusCode == 200 && textBytes.length <= 65536) {
      _threadBuffer.asTypedList(textBytes.length).setRange(0, textBytes.length, textBytes);
      TurboBindings.sendText(
        clientFd,
        _threadBuffer.cast<Utf8>(),
        textBytes.length,
        keepAlive ? 1 : 0,
      );
      return;
    }

    _writeFullResponse(
      statusCode: statusCode,
      contentType: 'text/plain; charset=utf-8',
      bodyBytes: textBytes,
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

    if (!hasResponseHeaders && statusCode == 200 && data.length <= 65536) {
      if (contentType.startsWith('application/json')) {
        _threadBuffer.asTypedList(data.length).setRange(0, data.length, data);
        TurboBindings.sendJson(
          clientFd,
          _threadBuffer.cast<Utf8>(),
          data.length,
          keepAlive ? 1 : 0,
        );
        return;
      } else if (contentType.startsWith('text/plain')) {
        _threadBuffer.asTypedList(data.length).setRange(0, data.length, data);
        TurboBindings.sendText(
          clientFd,
          _threadBuffer.cast<Utf8>(),
          data.length,
          keepAlive ? 1 : 0,
        );
        return;
      }
    }

    _writeFullResponse(
      statusCode: statusCode,
      contentType: contentType,
      bodyBytes: data,
    );
  }

  @override
  void sendResponse(EndveinResponse response) {
    if (_responded) return;
    _responded = true;

    _writeFullResponse(
      statusCode: response.statusCode,
      contentType: response.headers['content-type'] ?? 'application/octet-stream',
      bodyBytes: response.bodyBytes ?? Uint8List(0),
      extraHeaders: response.headers,
    );
  }

  void _writeFullResponse({
    required int statusCode,
    required String contentType,
    required List<int> bodyBytes,
    Map<String, String>? extraHeaders,
  }) {
    final statusMsg = _statusCodeMessages[statusCode] ?? 'OK';
    final sb = StringBuffer('HTTP/1.1 $statusCode $statusMsg\r\n');
    sb.write('Server: Endvein-Turbo\r\n');
    sb.write('Content-Type: $contentType\r\n');
    sb.write('Content-Length: ${bodyBytes.length}\r\n');
    sb.write(keepAlive ? 'Connection: keep-alive\r\n' : 'Connection: close\r\n');

    if (extraHeaders != null) {
      extraHeaders.forEach((k, v) {
        sb.write('$k: $v\r\n');
      });
    }
    if (_responseHeaders != null) {
      _responseHeaders!.forEach((k, v) {
        sb.write('$k: $v\r\n');
      });
    }
    sb.write('\r\n');

    final headerBytes = utf8.encode(sb.toString());
    final totalLen = headerBytes.length + bodyBytes.length;

    if (totalLen <= 65536) {
      final byteData = _threadBuffer.asTypedList(totalLen);
      byteData.setRange(0, headerBytes.length, headerBytes);
      byteData.setRange(headerBytes.length, totalLen, bodyBytes);
      TurboBindings.sendRaw(clientFd, _threadBuffer, totalLen, keepAlive ? 1 : 0);
    } else {
      final nativeBuf = malloc<Uint8>(totalLen);
      final byteData = nativeBuf.asTypedList(totalLen);
      byteData.setRange(0, headerBytes.length, headerBytes);
      byteData.setRange(headerBytes.length, totalLen, bodyBytes);
      TurboBindings.sendRaw(clientFd, nativeBuf, totalLen, keepAlive ? 1 : 0);
      malloc.free(nativeBuf);
    }
  }

  @override
  Future<void> sse(Future<void> Function(SseSender sender) streamHandler) async {
    if (_responded) return;
    _responded = true;

    const sseHeaders =
        'HTTP/1.1 200 OK\r\n'
        'Server: Endvein-Turbo\r\n'
        'Content-Type: text/event-stream; charset=utf-8\r\n'
        'Cache-Control: no-cache\r\n'
        'Connection: keep-alive\r\n\r\n';

    final nativeHeaders = sseHeaders.toNativeUtf8();
    TurboBindings.sendRaw(
      clientFd,
      nativeHeaders.cast<Uint8>(),
      nativeHeaders.length,
      1,
    );
    malloc.free(nativeHeaders);

    final sender = _TurboSseSender(clientFd);
    try {
      await streamHandler(sender);
    } finally {
      await sender.close();
    }
  }

  static const Map<int, String> _statusCodeMessages = {
    200: 'OK',
    201: 'Created',
    204: 'No Content',
    400: 'Bad Request',
    401: 'Unauthorized',
    403: 'Forbidden',
    404: 'Not Found',
    405: 'Method Not Allowed',
    500: 'Internal Server Error',
  };
}

class _TurboSseSender implements SseSender {
  final int clientFd;
  _TurboSseSender(this.clientFd);

  @override
  void send(SseEvent event) {
    final bytes = event.toBytes();
    final nativeBuf = malloc<Uint8>(bytes.length);
    nativeBuf.asTypedList(bytes.length).setAll(0, bytes);
    TurboBindings.sendRaw(clientFd, nativeBuf, bytes.length, 1);
    malloc.free(nativeBuf);
  }

  @override
  void sendData(String data, {String? event, String? id}) {
    send(SseEvent(data: data, event: event, id: id));
  }

  @override
  Future<void> close() async {
    TurboBindings.closeSocket(clientFd);
  }
}
