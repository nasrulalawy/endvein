import 'dart:convert';
import 'dart:typed_data';
import '../http/http_method.dart';
import 'http_constants.dart';
import 'raw_request.dart';

/// Exception thrown when HTTP request violates parser constraints.
class HttpParserException implements Exception {
  final int statusCode;
  final String message;

  const HttpParserException(this.statusCode, this.message);

  @override
  String toString() => 'HttpParserException($statusCode, $message)';
}

/// Zero-allocation, high-throughput streaming HTTP/1.1 parser.
class ZeroCopyHttpParser {
  /// Maximum allowed header size in bytes (defaults to 16KB).
  final int maxHeaderSize;

  /// Maximum allowed body size in bytes (defaults to 10MB).
  final int maxBodySize;

  Uint8List _buffer = Uint8List(0);
  int _bufferLength = 0;

  ZeroCopyHttpParser({
    this.maxHeaderSize = 16 * 1024,
    this.maxBodySize = 10 * 1024 * 1024,
  });

  void append(Uint8List chunk) {
    if (_bufferLength + chunk.length > _buffer.length) {
      final newCapacity = (_buffer.isEmpty)
          ? chunk.length * 2
          : (_bufferLength + chunk.length) * 2;
      final newBuffer = Uint8List(newCapacity);
      if (_bufferLength > 0) {
        newBuffer.setRange(0, _bufferLength, _buffer);
      }
      _buffer = newBuffer;
    }

    _buffer.setRange(_bufferLength, _bufferLength + chunk.length, chunk);
    _bufferLength += chunk.length;
  }

  /// Attempts to parse the next HTTP request from the current buffer.
  /// Returns `null` if more chunks are needed.
  /// Throws [HttpParserException] if header or body size exceeds configured limits.
  RawHttpRequest? parseNext() {
    if (_bufferLength < 4) return null;

    // 1. Search for \r\n\r\n delimiter (header boundary)
    int headerEnd = -1;
    for (var i = 0; i <= _bufferLength - 4; i++) {
      if (_buffer[i] == HttpAscii.cr &&
          _buffer[i + 1] == HttpAscii.lf &&
          _buffer[i + 2] == HttpAscii.cr &&
          _buffer[i + 3] == HttpAscii.lf) {
        headerEnd = i;
        break;
      }
    }

    if (headerEnd == -1) {
      if (_bufferLength > maxHeaderSize) {
        throw const HttpParserException(
          431,
          'Request Header Fields Too Large',
        );
      }
      return null; // Incomplete headers, wait for more data
    }

    // 2. Parse Request Line and Headers
    final headerBytes = Uint8List.sublistView(_buffer, 0, headerEnd);
    final headerText = ascii.decode(headerBytes);
    final lines = headerText.split('\r\n');

    if (lines.isEmpty) return null;

    final requestLine = lines[0];
    final parts = requestLine.split(' ');
    if (parts.length < 2) return null;

    final methodStr = parts[0];
    final target = parts[1];
    final method = HttpMethod.fromString(methodStr) ?? HttpMethod.get;

    // Parse path and query parameters
    String path = target;
    final queryParams = <String, String>{};
    final questionIdx = target.indexOf('?');
    if (questionIdx != -1) {
      path = target.substring(0, questionIdx);
      final queryString = target.substring(questionIdx + 1);
      final queryPairs = queryString.split('&');
      for (final pair in queryPairs) {
        final eqIdx = pair.indexOf('=');
        if (eqIdx != -1) {
          queryParams[Uri.decodeQueryComponent(pair.substring(0, eqIdx))] =
              Uri.decodeQueryComponent(pair.substring(eqIdx + 1));
        } else if (pair.isNotEmpty) {
          queryParams[Uri.decodeQueryComponent(pair)] = '';
        }
      }
    }

    // Parse headers
    final headers = <String, String>{};
    var contentLength = 0;
    var keepAlive = true; // HTTP/1.1 default

    for (var i = 1; i < lines.length; i++) {
      final line = lines[i];
      final colonIdx = line.indexOf(':');
      if (colonIdx != -1) {
        final key = line.substring(0, colonIdx).trim().toLowerCase();
        final value = line.substring(colonIdx + 1).trim();
        headers[key] = value;

        if (key == 'content-length') {
          contentLength = int.tryParse(value) ?? 0;
          if (contentLength > maxBodySize) {
            throw const HttpParserException(
              413,
              'Payload Too Large',
            );
          }
        } else if (key == 'connection') {
          if (value.toLowerCase() == 'close') {
            keepAlive = false;
          }
        }
      }
    }

    final bodyStart = headerEnd + 4;
    final totalRequired = bodyStart + contentLength;

    // 3. Check if body is fully available
    if (_bufferLength < totalRequired) {
      return null; // Need more data for full body
    }

    Uint8List? body;
    if (contentLength > 0) {
      body = Uint8List.fromList(
        Uint8List.sublistView(_buffer, bodyStart, totalRequired),
      );
    }

    // 4. Compact the buffer for remaining data (pipelined requests)
    final unconsumedLength = _bufferLength - totalRequired;
    if (unconsumedLength > 0) {
      _buffer.setRange(
        0,
        unconsumedLength,
        _buffer.sublist(totalRequired, _bufferLength),
      );
      _bufferLength = unconsumedLength;
    } else {
      _bufferLength = 0;
    }

    return RawHttpRequest(
      method: method,
      path: path,
      queryParameters: queryParams,
      headers: headers,
      body: body,
      keepAlive: keepAlive,
    );
  }

  void reset() {
    _bufferLength = 0;
  }
}
