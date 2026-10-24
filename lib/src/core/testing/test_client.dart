import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import '../http/context.dart';
import '../http/http_method.dart';
import '../http/response.dart';
import '../http/router.dart';
import '../http/sse.dart';

class _CaseInsensitiveMap extends MapBase<String, String> {
  final Map<String, String> _inner = {};
  final Map<String, String> _keys = {};

  _CaseInsensitiveMap([Map<String, String>? initial]) {
    if (initial != null) {
      initial.forEach((k, v) => this[k] = v);
    }
  }

  @override
  String? operator [](Object? key) {
    if (key is! String) return null;
    final realKey = _keys[key.toLowerCase()];
    return realKey != null ? _inner[realKey] : null;
  }

  @override
  void operator []=(String key, String value) {
    final lower = key.toLowerCase();
    final existing = _keys[lower];
    if (existing != null) {
      _inner.remove(existing);
    }
    _keys[lower] = key;
    _inner[key] = value;
  }

  @override
  void clear() {
    _inner.clear();
    _keys.clear();
  }

  @override
  Iterable<String> get keys => _inner.keys;

  @override
  String? remove(Object? key) {
    if (key is! String) return null;
    final lower = key.toLowerCase();
    final realKey = _keys.remove(lower);
    return realKey != null ? _inner.remove(realKey) : null;
  }

  @override
  bool containsKey(Object? key) {
    if (key is! String) return false;
    return _keys.containsKey(key.toLowerCase());
  }
}

/// In-memory response returned by [EndveinTestClient].
class TestResponse {
  final int statusCode;
  final Map<String, String> headers;
  final Uint8List? bodyBytes;
  final List<SseEvent> sseEvents;

  TestResponse({
    required this.statusCode,
    required Map<String, String> headers,
    this.bodyBytes,
    this.sseEvents = const [],
  }) : headers = _CaseInsensitiveMap(headers);

  String get bodyText => bodyBytes != null ? utf8.decode(bodyBytes!) : '';

  dynamic get bodyJson {
    final text = bodyText;
    if (text.isEmpty) return null;
    return jsonDecode(text);
  }
}

/// Simulated in-memory context for testing Endvein routers without physical TCP sockets.
class TestContext implements EndveinContext {
  @override
  final String path;

  @override
  final HttpMethod? method;

  @override
  final Map<String, String> params;

  @override
  final Map<String, Object?> store;

  @override
  final Map<String, String> queryParameters;

  final Map<String, String> _headers;
  final Uint8List? _body;

  bool _responded = false;
  int _statusCode = 200;
  final Map<String, String> _responseHeaders = {};
  Uint8List? _responseBytes;

  @override
  Map<String, String> get responseHeaders => _responseHeaders;

  @override
  void setHeader(String name, String value) {
    _responseHeaders[name] = value;
  }

  TestContext({
    required this.path,
    required this.method,
    Map<String, String>? params,
    Map<String, String>? queryParameters,
    Map<String, String>? headers,
    Uint8List? body,
    Map<String, Object?>? store,
  })  : params = params ?? {},
        queryParameters = queryParameters ?? {},
        _headers = headers ?? {},
        _body = body,
        store = store ?? {};

  final List<SseEvent> _sseEvents = [];

  TestResponse toResponse() {
    return TestResponse(
      statusCode: _statusCode,
      headers: _responseHeaders,
      bodyBytes: _responseBytes,
      sseEvents: List.unmodifiable(_sseEvents),
    );
  }

  @override
  String? getHeader(String name) {
    final lower = name.toLowerCase();
    for (final entry in _headers.entries) {
      if (entry.key.toLowerCase() == lower) return entry.value;
    }
    return null;
  }

  @override
  bool get isResponded => _responded;

  @override
  Uint8List? get rawBody => _body;

  @override
  Future<String> bodyText() async {
    final body = _body;
    if (body == null || body.isEmpty) return '';
    return utf8.decode(body);
  }

  @override
  Future<dynamic> bodyJson() async {
    final text = await bodyText();
    if (text.isEmpty) return null;
    return jsonDecode(text);
  }

  @override
  void json(Object? data, {int statusCode = 200}) {
    if (_responded) return;
    _responded = true;
    _statusCode = statusCode;
    _responseHeaders['content-type'] = 'application/json; charset=utf-8';
    if (data != null) {
      _responseBytes = Uint8List.fromList(utf8.encode(jsonEncode(data)));
    } else {
      _responseBytes = Uint8List(0);
    }
    _responseHeaders['content-length'] = _responseBytes!.length.toString();
  }

  @override
  void text(String message, {int statusCode = 200}) {
    if (_responded) return;
    _responded = true;
    _statusCode = statusCode;
    _responseHeaders['content-type'] = 'text/plain; charset=utf-8';
    _responseBytes = Uint8List.fromList(utf8.encode(message));
    _responseHeaders['content-length'] = _responseBytes!.length.toString();
  }

  @override
  void bytes(
    Uint8List data, {
    String contentType = 'application/octet-stream',
    int statusCode = 200,
  }) {
    if (_responded) return;
    _responded = true;
    _statusCode = statusCode;
    _responseHeaders['content-type'] = contentType;
    _responseBytes = data;
    _responseHeaders['content-length'] = data.length.toString();
  }

  @override
  void sendResponse(EndveinResponse response) {
    if (_responded) return;
    _responded = true;
    _statusCode = response.statusCode;
    _responseHeaders.addAll(response.headers);
    _responseBytes = response.bodyBytes;
  }

  @override
  Future<void> sse(Future<void> Function(SseSender sender) streamHandler) async {
    if (_responded) return;
    _responded = true;
    _statusCode = 200;
    _responseHeaders['content-type'] = 'text/event-stream; charset=utf-8';
    _responseHeaders['cache-control'] = 'no-cache';

    final builder = BytesBuilder();
    final sender = _TestSseSender(_sseEvents, builder);
    try {
      await streamHandler(sender);
    } finally {
      _responseBytes = builder.takeBytes();
    }
  }
}

class _TestSseSender implements SseSender {
  final List<SseEvent> events;
  final BytesBuilder builder;

  _TestSseSender(this.events, this.builder);

  @override
  void send(SseEvent event) {
    events.add(event);
    builder.add(event.toBytes());
  }

  @override
  void sendData(String data, {String? event, String? id}) {
    send(SseEvent(data: data, event: event, id: id));
  }

  @override
  Future<void> close() async {}
}

/// In-memory HTTP test client for Endvein routers.
class EndveinTestClient {
  final EndveinRouter router;

  EndveinTestClient(this.router);

  Future<TestResponse> request(
    HttpMethod method,
    String path, {
    Map<String, String>? headers,
    Map<String, String>? queryParameters,
    Object? jsonBody,
    String? textBody,
    Uint8List? rawBody,
  }) async {
    Uint8List? bodyBytes = rawBody;
    final mergedHeaders = <String, String>{...?headers};

    if (jsonBody != null) {
      final encoded = utf8.encode(jsonEncode(jsonBody));
      bodyBytes = Uint8List.fromList(encoded);
      mergedHeaders['content-type'] = 'application/json; charset=utf-8';
      mergedHeaders['content-length'] = bodyBytes.length.toString();
    } else if (textBody != null) {
      final encoded = utf8.encode(textBody);
      bodyBytes = Uint8List.fromList(encoded);
      mergedHeaders['content-type'] = 'text/plain; charset=utf-8';
      mergedHeaders['content-length'] = bodyBytes.length.toString();
    }

    // Parse path and query parameters if query string is present in path
    String requestPath = path;
    final queryParams = <String, String>{...?queryParameters};
    final qIdx = path.indexOf('?');
    if (qIdx != -1) {
      requestPath = path.substring(0, qIdx);
      final qStr = path.substring(qIdx + 1);
      final uri = Uri(query: qStr);
      queryParams.addAll(uri.queryParameters);
    }

    final ctx = TestContext(
      path: requestPath,
      method: method,
      queryParameters: queryParams,
      headers: mergedHeaders,
      body: bodyBytes,
    );

    await router.handleContext(ctx);
    return ctx.toResponse();
  }

  Future<TestResponse> get(
    String path, {
    Map<String, String>? headers,
    Map<String, String>? queryParameters,
  }) =>
      request(
        HttpMethod.get,
        path,
        headers: headers,
        queryParameters: queryParameters,
      );

  Future<TestResponse> post(
    String path, {
    Map<String, String>? headers,
    Map<String, String>? queryParameters,
    Object? body,
    Uint8List? rawBody,
    String? textBody,
  }) =>
      request(
        HttpMethod.post,
        path,
        headers: headers,
        queryParameters: queryParameters,
        jsonBody: body,
        rawBody: rawBody,
        textBody: textBody,
      );

  Future<TestResponse> put(
    String path, {
    Map<String, String>? headers,
    Map<String, String>? queryParameters,
    Object? body,
    Uint8List? rawBody,
    String? textBody,
  }) =>
      request(
        HttpMethod.put,
        path,
        headers: headers,
        queryParameters: queryParameters,
        jsonBody: body,
        rawBody: rawBody,
        textBody: textBody,
      );

  Future<TestResponse> delete(
    String path, {
    Map<String, String>? headers,
    Map<String, String>? queryParameters,
  }) =>
      request(
        HttpMethod.delete,
        path,
        headers: headers,
        queryParameters: queryParameters,
      );

  Future<TestResponse> patch(
    String path, {
    Map<String, String>? headers,
    Map<String, String>? queryParameters,
    Object? body,
    Uint8List? rawBody,
    String? textBody,
  }) =>
      request(
        HttpMethod.patch,
        path,
        headers: headers,
        queryParameters: queryParameters,
        jsonBody: body,
        rawBody: rawBody,
        textBody: textBody,
      );

  Future<TestResponse> options(
    String path, {
    Map<String, String>? headers,
  }) =>
      request(HttpMethod.options, path, headers: headers);
}
