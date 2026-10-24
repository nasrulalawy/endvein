import 'dart:convert';
import 'dart:typed_data';

/// Represents an HTTP Response produced by Endvein handlers or middlewares.
class EndveinResponse {
  final int statusCode;
  final Map<String, String> headers;
  final Uint8List? bodyBytes;

  const EndveinResponse({
    this.statusCode = 200,
    this.headers = const {},
    this.bodyBytes,
  });

  factory EndveinResponse.json(
    Object? data, {
    int statusCode = 200,
    Map<String, String>? headers,
  }) {
    final bytes = utf8.encode(jsonEncode(data));
    final mergedHeaders = <String, String>{
      'content-type': 'application/json; charset=utf-8',
      'content-length': bytes.length.toString(),
      ...?headers,
    };

    return EndveinResponse(
      statusCode: statusCode,
      headers: mergedHeaders,
      bodyBytes: Uint8List.fromList(bytes),
    );
  }

  factory EndveinResponse.text(
    String text, {
    int statusCode = 200,
    Map<String, String>? headers,
  }) {
    final bytes = utf8.encode(text);
    final mergedHeaders = <String, String>{
      'content-type': 'text/plain; charset=utf-8',
      'content-length': bytes.length.toString(),
      ...?headers,
    };

    return EndveinResponse(
      statusCode: statusCode,
      headers: mergedHeaders,
      bodyBytes: Uint8List.fromList(bytes),
    );
  }

  factory EndveinResponse.empty({
    int statusCode = 204,
    Map<String, String>? headers,
  }) {
    return EndveinResponse(
      statusCode: statusCode,
      headers: headers ?? const {},
      bodyBytes: null,
    );
  }
}
