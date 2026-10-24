import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'http_method.dart';
import 'response.dart';
import 'sse.dart';

/// Unified Context interface for Endvein handlers and middlewares.
abstract interface class EndveinContext {
  String get path;
  HttpMethod? get method;
  Map<String, String> get params;
  Map<String, Object?> get store;
  Map<String, String> get queryParameters;
  String? getHeader(String name);
  bool get isResponded;
  Uint8List? get rawBody;
  Map<String, String> get responseHeaders;
  void setHeader(String name, String value);

  Future<String> bodyText();
  Future<dynamic> bodyJson();

  void json(Object? data, {int statusCode = HttpStatus.ok});
  void text(String message, {int statusCode = HttpStatus.ok});
  void bytes(
    Uint8List data, {
    String contentType = 'application/octet-stream',
    int statusCode = HttpStatus.ok,
  });
  void sendResponse(EndveinResponse response);

  /// Start a Server-Sent Events (SSE) stream for real-time and LLM streaming.
  Future<void> sse(Future<void> Function(SseSender sender) streamHandler);
}

/// Standard implementation wrapping [HttpRequest] and [HttpResponse].
class StandardHttpContext implements EndveinContext {
  final HttpRequest req;

  @override
  final Map<String, String> params;

  @override
  final Map<String, Object?> store;

  @override
  final Map<String, String> responseHeaders = {};

  bool _responded = false;

  StandardHttpContext(
    this.req, {
    Map<String, String>? params,
    Map<String, Object?>? store,
  })  : params = params ?? <String, String>{},
        store = store ?? <String, Object?>{};

  @override
  void setHeader(String name, String value) {
    responseHeaders[name] = value;
  }

  HttpResponse get res => req.response;

  Uri get uri => req.uri;

  @override
  String get path => req.uri.path;

  @override
  HttpMethod? get method => HttpMethod.fromString(req.method);

  @override
  Map<String, String> get queryParameters => req.uri.queryParameters;

  @override
  String? getHeader(String name) => req.headers.value(name);

  @override
  bool get isResponded => _responded;

  @override
  Uint8List? get rawBody => null;

  @override
  Future<String> bodyText() async {
    return await utf8.decoder.bind(req).join();
  }

  @override
  Future<dynamic> bodyJson() async {
    final text = await bodyText();
    if (text.isEmpty) return null;
    return jsonDecode(text);
  }

  void _applyHeaders() {
    responseHeaders.forEach((key, val) {
      res.headers.set(key, val);
    });
  }

  @override
  void json(Object? data, {int statusCode = HttpStatus.ok}) {
    if (_responded) return;
    _responded = true;

    final bytes = utf8.encode(jsonEncode(data));
    res
      ..statusCode = statusCode
      ..headers.contentType = ContentType.json
      ..headers.contentLength = bytes.length;
    _applyHeaders();
    res
      ..add(bytes)
      ..close();
  }

  @override
  void text(String message, {int statusCode = HttpStatus.ok}) {
    if (_responded) return;
    _responded = true;

    final bytes = utf8.encode(message);
    res
      ..statusCode = statusCode
      ..headers.contentType = ContentType.text
      ..headers.contentLength = bytes.length;
    _applyHeaders();
    res
      ..add(bytes)
      ..close();
  }

  @override
  void bytes(
    Uint8List data, {
    String contentType = 'application/octet-stream',
    int statusCode = HttpStatus.ok,
  }) {
    if (_responded) return;
    _responded = true;

    res.statusCode = statusCode;
    final parts = contentType.split('/');
    if (parts.length == 2) {
      res.headers.contentType = ContentType(parts[0], parts[1]);
    }
    res.headers.contentLength = data.length;
    _applyHeaders();
    res.add(data);
    res.close();
  }

  @override
  void sendResponse(EndveinResponse response) {
    if (_responded) return;
    _responded = true;

    res.statusCode = response.statusCode;
    _applyHeaders();
    response.headers.forEach((key, val) {
      res.headers.set(key, val);
    });

    if (response.bodyBytes != null) {
      res.add(response.bodyBytes!);
    }
    res.close();
  }

  @override
  Future<void> sse(Future<void> Function(SseSender sender) streamHandler) async {
    if (_responded) return;
    _responded = true;

    final res = req.response;
    res.headers.set('content-type', 'text/event-stream; charset=utf-8');
    res.headers.set('cache-control', 'no-cache');
    res.headers.set('connection', 'keep-alive');
    _applyHeaders();

    final sender = _StandardHttpSseSender(res);
    try {
      await streamHandler(sender);
    } finally {
      await sender.close();
    }
  }
}

class _StandardHttpSseSender implements SseSender {
  final HttpResponse res;
  _StandardHttpSseSender(this.res);

  @override
  void send(SseEvent event) {
    res.add(event.toBytes());
  }

  @override
  void sendData(String data, {String? event, String? id}) {
    send(SseEvent(data: data, event: event, id: id));
  }

  @override
  Future<void> close() async {
    await res.close();
  }
}

/// Type-safe parsing extensions on [EndveinContext] for params and query parameters.
extension ContextParamQueryX on EndveinContext {
  /// Get route parameter as a String.
  String? param(String name) => params[name];

  /// Get route parameter as an int.
  int? paramInt(String name, {int? defaultValue}) {
    final val = params[name];
    if (val == null) return defaultValue;
    return int.tryParse(val) ?? defaultValue;
  }

  /// Get route parameter as a double.
  double? paramDouble(String name, {double? defaultValue}) {
    final val = params[name];
    if (val == null) return defaultValue;
    return double.tryParse(val) ?? defaultValue;
  }

  /// Get query parameter as an int.
  int? queryInt(String name, {int? defaultValue}) {
    final val = queryParameters[name];
    if (val == null) return defaultValue;
    return int.tryParse(val) ?? defaultValue;
  }

  /// Get query parameter as a double.
  double? queryDouble(String name, {double? defaultValue}) {
    final val = queryParameters[name];
    if (val == null) return defaultValue;
    return double.tryParse(val) ?? defaultValue;
  }

  /// Get query parameter as a bool (handles 'true', '1', 'yes').
  bool queryBool(String name, {bool defaultValue = false}) {
    final val = queryParameters[name]?.toLowerCase();
    if (val == null) return defaultValue;
    return val == 'true' || val == '1' || val == 'yes';
  }

  /// Get query parameter as a String.
  String queryString(String name, {String defaultValue = ''}) {
    return queryParameters[name] ?? defaultValue;
  }
}
