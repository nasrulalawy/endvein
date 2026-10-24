import 'dart:convert';
import 'dart:typed_data';

import '../http/context.dart';
import '../http/http_method.dart';
import '../http/response.dart';
import '../http/router.dart';

/// In-memory response returned by [EndveinTestClient].
class TestResponse {
  final int statusCode;
  final Map<String, String> headers;
  final Uint8List? bodyBytes;

  const TestResponse({
    required this.statusCode,
    required this.headers,
    this.bodyBytes,
  });

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

  TestResponse toResponse() {
    return TestResponse(
      statusCode: _statusCode,
      headers: _responseHeaders,
      bodyBytes: _responseBytes,
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
    if (_body == null || _body!.isEmpty) return '';
    return utf8.decode(_body!);
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
  }) =>
      request(
        HttpMethod.post,
        path,
        headers: headers,
        queryParameters: queryParameters,
        jsonBody: body,
      );

  Future<TestResponse> put(
    String path, {
    Map<String, String>? headers,
    Map<String, String>? queryParameters,
    Object? body,
  }) =>
      request(
        HttpMethod.put,
        path,
        headers: headers,
        queryParameters: queryParameters,
        jsonBody: body,
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
  }) =>
      request(
        HttpMethod.patch,
        path,
        headers: headers,
        queryParameters: queryParameters,
        jsonBody: body,
      );

  Future<TestResponse> options(
    String path, {
    Map<String, String>? headers,
  }) =>
      request(HttpMethod.options, path, headers: headers);
}
