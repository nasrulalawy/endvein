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

  Uint8List _buffer;
  int _bufferLength = 0;

  ZeroCopyHttpParser({
    this.maxHeaderSize = 16 * 1024,
    this.maxBodySize = 10 * 1024 * 1024,
    int initialBufferSize = 4096,
  }) : _buffer = Uint8List(initialBufferSize);

  void append(Uint8List chunk) {
    if (_bufferLength + chunk.length > _buffer.length) {
      final newCapacity = (_buffer.isEmpty)
          ? 4096
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

    if (headerEnd > maxHeaderSize) {
      throw const HttpParserException(
        431,
        'Request Header Fields Too Large',
      );
    }

    // 2. Direct byte-scanning of Request Line & Headers (Zero string splits)
    HttpMethod method = HttpMethod.get;
    int pathStart = 4;
    final b0 = _buffer[0];
    if (b0 == 71 && _buffer[1] == 69 && _buffer[2] == 84 && _buffer[3] == 32) {
      method = HttpMethod.get;
      pathStart = 4;
    } else if (b0 == 80 && _buffer[1] == 79 && _buffer[2] == 83 && _buffer[3] == 84 && _buffer[4] == 32) {
      method = HttpMethod.post;
      pathStart = 5;
    } else if (b0 == 80 && _buffer[1] == 85 && _buffer[2] == 84 && _buffer[3] == 32) {
      method = HttpMethod.put;
      pathStart = 4;
    } else if (b0 == 68 && _buffer[1] == 69 && _buffer[2] == 76 && _buffer[3] == 69 && _buffer[4] == 84 && _buffer[5] == 69 && _buffer[6] == 32) {
      method = HttpMethod.delete;
      pathStart = 7;
    } else {
      int spaceIdx = -1;
      for (var i = 0; i < 16 && i < headerEnd; i++) {
        if (_buffer[i] == 32) {
          spaceIdx = i;
          break;
        }
      }
      if (spaceIdx == -1) {
        throw const HttpParserException(
          400,
          'Bad Request: Invalid or unsupported HTTP method',
        );
      }
      final mStr = ascii.decode(Uint8List.sublistView(_buffer, 0, spaceIdx));
      final parsed = HttpMethod.fromString(mStr);
      if (parsed == null) {
        throw const HttpParserException(400, 'Bad Request: Unknown HTTP method');
      }
      method = parsed;
      pathStart = spaceIdx + 1;
    }

    // Locate end of path and optional query delimiter '?'
    int pathEnd = -1;
    int questionIdx = -1;
    for (var i = pathStart; i < headerEnd; i++) {
      final b = _buffer[i];
      if (b == 0 || (b < 32 && b != 9) || b == 127) {
        throw const HttpParserException(
          400,
          'Bad Request: Invalid control character or null byte in path',
        );
      }
      if (b == 32) {
        pathEnd = i;
        break;
      } else if (b == 63 && questionIdx == -1) {
        questionIdx = i;
      }
    }
    if (pathEnd == -1) {
      throw const HttpParserException(
        400,
        'Bad Request: Missing HTTP version in request line',
      );
    }

    final targetEnd = questionIdx != -1 ? questionIdx : pathEnd;
    final pathLen = targetEnd - pathStart;

    // Zero-allocation path lookup for standard endpoints
    String path;
    if (pathLen == 5 &&
        _buffer[pathStart] == 47 &&
        _buffer[pathStart + 1] == 106 &&
        _buffer[pathStart + 2] == 115 &&
        _buffer[pathStart + 3] == 111 &&
        _buffer[pathStart + 4] == 110) {
      path = '/json';
    } else if (pathLen == 10 &&
        _buffer[pathStart] == 47 &&
        _buffer[pathStart + 1] == 112 &&
        _buffer[pathStart + 2] == 108 &&
        _buffer[pathStart + 3] == 97 &&
        _buffer[pathStart + 4] == 105 &&
        _buffer[pathStart + 5] == 110 &&
        _buffer[pathStart + 6] == 116 &&
        _buffer[pathStart + 7] == 101 &&
        _buffer[pathStart + 8] == 120 &&
        _buffer[pathStart + 9] == 116) {
      path = '/plaintext';
    } else if (pathLen == 1 && _buffer[pathStart] == 47) {
      path = '/';
    } else {
      path = ascii.decode(Uint8List.sublistView(_buffer, pathStart, targetEnd));
    }

    // Parse query parameters if present
    Map<String, String>? queryParams;
    if (questionIdx != -1) {
      queryParams = <String, String>{};
      final qBytes = Uint8List.sublistView(_buffer, questionIdx + 1, pathEnd);
      final queryString = ascii.decode(qBytes);
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

    // Find end of request line (\r\n)
    int lineStart = -1;
    for (var i = pathEnd; i <= headerEnd - 2; i++) {
      if (_buffer[i] == 13 && _buffer[i + 1] == 10) {
        lineStart = i + 2;
        break;
      }
    }
    if (lineStart == -1) return null;

    final headerStart = lineStart;
    int? parsedContentLength;
    var keepAlive = true;
    var hasTransferEncoding = false;

    while (lineStart < headerEnd) {
      int nextCrlf = -1;
      int colonIdx = -1;

      for (var i = lineStart; i <= headerEnd; i++) {
        if (colonIdx == -1 && _buffer[i] == 58) {
          colonIdx = i;
        }
        if (_buffer[i] == 13 && _buffer[i + 1] == 10) {
          nextCrlf = i;
          break;
        }
      }
      if (nextCrlf == -1) break;

      if (colonIdx != -1 && colonIdx < nextCrlf) {
        final keyLen = colonIdx - lineStart;
        final firstByte = _buffer[lineStart];

        // Check for Transfer-Encoding (17 chars)
        if ((firstByte == 116 || firstByte == 84) && keyLen == 17) {
          final keyBytes = Uint8List.sublistView(_buffer, lineStart, colonIdx);
          final keyStr = ascii.decode(keyBytes).toLowerCase();
          if (keyStr == 'transfer-encoding') {
            hasTransferEncoding = true;
            if (parsedContentLength != null) {
              throw const HttpParserException(
                400,
                'Bad Request: Both Transfer-Encoding and Content-Length present (RFC 7230 §3.3.3)',
              );
            }
          }
        }

        // Fast parsing of 'content-length' and 'connection'
        if (firstByte == 99 || firstByte == 67) {
          if (keyLen == 14) {
            final keyBytes = Uint8List.sublistView(_buffer, lineStart, colonIdx);
            final keyStr = ascii.decode(keyBytes).toLowerCase();
            if (keyStr == 'content-length') {
              if (hasTransferEncoding) {
                throw const HttpParserException(
                  400,
                  'Bad Request: Both Transfer-Encoding and Content-Length present (RFC 7230 §3.3.3)',
                );
              }
              var val = 0;
              var digitsFound = false;
              for (var j = colonIdx + 1; j < nextCrlf; j++) {
                final b = _buffer[j];
                if (b >= 48 && b <= 57) {
                  val = val * 10 + (b - 48);
                  digitsFound = true;
                } else if (digitsFound && b != 32 && b != 9) {
                  throw const HttpParserException(
                    400,
                    'Bad Request: Malformed Content-Length header',
                  );
                }
              }
              if (val > maxBodySize) {
                throw const HttpParserException(413, 'Payload Too Large');
              }
              if (parsedContentLength != null && parsedContentLength != val) {
                throw const HttpParserException(
                  400,
                  'Bad Request: Multiple Conflicting Content-Length Headers (RFC 7230 §3.3.2)',
                );
              }
              parsedContentLength = val;
            }
          } else if (keyLen == 10) {
            for (var j = colonIdx + 1; j <= nextCrlf - 5; j++) {
              if ((_buffer[j] == 99 || _buffer[j] == 67) &&
                  (_buffer[j + 1] == 108 || _buffer[j + 1] == 76) &&
                  (_buffer[j + 2] == 111 || _buffer[j + 2] == 79) &&
                  (_buffer[j + 3] == 115 || _buffer[j + 3] == 83) &&
                  (_buffer[j + 4] == 101 || _buffer[j + 4] == 69)) {
                keepAlive = false;
                break;
              }
            }
          }
        }
      }

      lineStart = nextCrlf + 2;
    }

    if (hasTransferEncoding && parsedContentLength == null) {
      throw const HttpParserException(
        501,
        'Not Implemented: Chunked Transfer-Encoding is not supported',
      );
    }

    final contentLength = parsedContentLength ?? 0;

    final bodyStart = headerEnd + 4;
    final totalRequired = bodyStart + contentLength;

    // 3. Check if body is fully available
    if (_bufferLength < totalRequired) {
      return null; // Need more data for full body
    }

    final unconsumedLength = _bufferLength - totalRequired;

    final Uint8List? headerBytes = headerEnd > headerStart
        ? (unconsumedLength > 0
            ? Uint8List.fromList(Uint8List.sublistView(_buffer, headerStart, headerEnd))
            : Uint8List.sublistView(_buffer, headerStart, headerEnd))
        : null;

    Uint8List? body;
    if (contentLength > 0) {
      body = Uint8List.fromList(
        Uint8List.sublistView(_buffer, bodyStart, totalRequired),
      );
    }

    // 4. Compact the buffer for remaining data (pipelined requests)
    if (unconsumedLength > 0) {
      for (var i = 0; i < unconsumedLength; i++) {
        _buffer[i] = _buffer[totalRequired + i];
      }
      _bufferLength = unconsumedLength;
    } else {
      _bufferLength = 0;
    }

    return RawHttpRequest(
      method: method,
      path: path,
      queryParameters: queryParams,
      headerBytes: headerBytes,
      body: body,
      keepAlive: keepAlive,
    );
  }

  void reset() {
    _bufferLength = 0;
  }
}
