import 'dart:convert';
import 'dart:typed_data';
import '../http/http_method.dart';

/// Lightweight, parsed HTTP request from raw TCP socket bytes with lazy zero-allocation headers.
class RawHttpRequest {
  final HttpMethod method;
  final String path;
  final Map<String, String>? _queryParameters;
  final Uint8List? _headerBytes;
  Map<String, String>? _headers;
  final Uint8List? body;
  final bool keepAlive;

  RawHttpRequest({
    required this.method,
    required this.path,
    Map<String, String>? queryParameters,
    Map<String, String>? headers,
    Uint8List? headerBytes,
    this.body,
    this.keepAlive = true,
  })  : _queryParameters = queryParameters,
        _headers = headers,
        _headerBytes = headerBytes;

  Map<String, String> get queryParameters =>
      _queryParameters ?? const <String, String>{};

  Map<String, String> get headers {
    if (_headers != null) return _headers!;
    return _headers = _parseAllHeaders();
  }

  /// Case-insensitive header lookup with zero-allocation byte scanner.
  String? header(String name) {
    if (_headers != null) {
      final lower = name.toLowerCase();
      for (final entry in _headers!.entries) {
        if (entry.key.toLowerCase() == lower) {
          return entry.value;
        }
      }
      return null;
    }
    final bytes = _headerBytes;
    if (bytes == null || bytes.isEmpty) return null;
    return _scanHeader(name);
  }

  String? _scanHeader(String name) {
    final bytes = _headerBytes;
    if (bytes == null || bytes.isEmpty) return null;

    final target = ascii.encode(name.toLowerCase());
    final targetLen = target.length;
    final totalLen = bytes.length;

    var i = 0;
    while (i < totalLen) {
      var colonIdx = -1;
      var lineEnd = totalLen;
      for (var j = i; j < totalLen - 1; j++) {
        if (colonIdx == -1 && bytes[j] == 58) {
          colonIdx = j;
        }
        if (bytes[j] == 13 && bytes[j + 1] == 10) {
          lineEnd = j;
          break;
        }
      }

      if (colonIdx != -1 && (colonIdx - i) == targetLen) {
        var match = true;
        for (var k = 0; k < targetLen; k++) {
          var b = bytes[i + k];
          if (b >= 65 && b <= 90) b += 32;
          if (b != target[k]) {
            match = false;
            break;
          }
        }
        if (match) {
          var vStart = colonIdx + 1;
          while (vStart < lineEnd && (bytes[vStart] == 32 || bytes[vStart] == 9)) {
            vStart++;
          }
          var vEnd = lineEnd;
          while (vEnd > vStart && (bytes[vEnd - 1] == 32 || bytes[vEnd - 1] == 9)) {
            vEnd--;
          }
          return ascii.decode(Uint8List.sublistView(bytes, vStart, vEnd));
        }
      }

      i = lineEnd + 2;
    }
    return null;
  }

  Map<String, String> _parseAllHeaders() {
    final bytes = _headerBytes;
    if (bytes == null || bytes.isEmpty) return const {};

    final result = <String, String>{};
    final totalLen = bytes.length;
    var i = 0;
    while (i < totalLen) {
      var colonIdx = -1;
      var lineEnd = totalLen;
      for (var j = i; j < totalLen - 1; j++) {
        if (colonIdx == -1 && bytes[j] == 58) {
          colonIdx = j;
        }
        if (bytes[j] == 13 && bytes[j + 1] == 10) {
          lineEnd = j;
          break;
        }
      }

      if (colonIdx != -1 && colonIdx < lineEnd) {
        final keyBytes = Uint8List.sublistView(bytes, i, colonIdx);
        final key = ascii.decode(keyBytes).trim().toLowerCase();

        var vStart = colonIdx + 1;
        while (vStart < lineEnd && (bytes[vStart] == 32 || bytes[vStart] == 9)) {
          vStart++;
        }
        var vEnd = lineEnd;
        while (vEnd > vStart && (bytes[vEnd - 1] == 32 || bytes[vEnd - 1] == 9)) {
          vEnd--;
        }
        final value = ascii.decode(Uint8List.sublistView(bytes, vStart, vEnd));
        result[key] = value;
      }

      i = lineEnd + 2;
    }
    return result;
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
