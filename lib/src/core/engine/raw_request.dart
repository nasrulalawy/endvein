import 'dart:convert';
import 'dart:typed_data';
import '../http/http_method.dart';

/// Lightweight, parsed HTTP request from raw TCP socket bytes.
class RawHttpRequest {
  final HttpMethod method;
  final String path;
  final Map<String, String> queryParameters;
  final Map<String, String> headers;
  final Uint8List? body;
  final bool keepAlive;

  const RawHttpRequest({
    required this.method,
    required this.path,
    this.queryParameters = const {},
    this.headers = const {},
    this.body,
    this.keepAlive = true,
  });

  /// Case-insensitive header lookup.
  String? header(String name) {
    final lower = name.toLowerCase();
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == lower) {
        return entry.value;
      }
    }
    return null;
  }

  /// Get body as UTF-8 string.
  String bodyText() {
    if (body == null || body!.isEmpty) return '';
    return utf8.decode(body!);
  }

  /// Get body parsed as JSON.
  dynamic bodyJson() {
    final text = bodyText();
    if (text.isEmpty) return null;
    return jsonDecode(text);
  }
}
