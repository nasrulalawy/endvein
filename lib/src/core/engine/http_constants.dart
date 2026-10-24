import 'dart:convert';
import 'dart:typed_data';

/// ASCII byte codes for HTTP parsing
abstract final class HttpAscii {
  static const int cr = 13; // \r
  static const int lf = 10; // \n
  static const int space = 32; // ' '
  static const int colon = 58; // ':'
  static const int question = 63; // '?'
}

/// Pre-allocated byte constants for ultra-low latency response writing
abstract final class HttpConstants {
  static final Uint8List http11 = ascii.encode('HTTP/1.1 ');
  static final Uint8List crlf = ascii.encode('\r\n');
  static final Uint8List crlfcrlf = ascii.encode('\r\n\r\n');

  // Common Status Lines
  static final Uint8List status200 = ascii.encode('HTTP/1.1 200 OK\r\n');
  static final Uint8List status201 = ascii.encode('HTTP/1.1 201 Created\r\n');
  static final Uint8List status204 = ascii.encode('HTTP/1.1 204 No Content\r\n');
  static final Uint8List status400 = ascii.encode('HTTP/1.1 400 Bad Request\r\n');
  static final Uint8List status401 = ascii.encode('HTTP/1.1 401 Unauthorized\r\n');
  static final Uint8List status403 = ascii.encode('HTTP/1.1 403 Forbidden\r\n');
  static final Uint8List status404 = ascii.encode('HTTP/1.1 404 Not Found\r\n');
  static final Uint8List status405 = ascii.encode('HTTP/1.1 405 Method Not Allowed\r\n');
  static final Uint8List status413 = ascii.encode('HTTP/1.1 413 Payload Too Large\r\n');
  static final Uint8List status422 = ascii.encode('HTTP/1.1 422 Unprocessable Entity\r\n');
  static final Uint8List status431 = ascii.encode('HTTP/1.1 431 Request Header Fields Too Large\r\n');
  static final Uint8List status500 = ascii.encode('HTTP/1.1 500 Internal Server Error\r\n');

  // Common Headers
  static final Uint8List serverHeader = ascii.encode('Server: Endvein\r\n');
  static final Uint8List jsonContentType = ascii.encode('Content-Type: application/json; charset=utf-8\r\n');
  static final Uint8List textContentType = ascii.encode('Content-Type: text/plain; charset=utf-8\r\n');
  static final Uint8List keepAliveHeader = ascii.encode('Connection: keep-alive\r\n');
  static final Uint8List closeHeader = ascii.encode('Connection: close\r\n');

  // Pre-baked Fast-Path Prefixes
  static final Uint8List json200KeepAlivePrefix = ascii.encode(
    'HTTP/1.1 200 OK\r\n'
    'Server: Endvein\r\n'
    'Content-Type: application/json; charset=utf-8\r\n'
    'Connection: keep-alive\r\n',
  );

  static final Uint8List text200KeepAlivePrefix = ascii.encode(
    'HTTP/1.1 200 OK\r\n'
    'Server: Endvein\r\n'
    'Content-Type: text/plain; charset=utf-8\r\n'
    'Connection: keep-alive\r\n',
  );

  static final Uint8List json200ClosePrefix = ascii.encode(
    'HTTP/1.1 200 OK\r\n'
    'Server: Endvein\r\n'
    'Content-Type: application/json; charset=utf-8\r\n'
    'Connection: close\r\n',
  );

  static final Uint8List text200ClosePrefix = ascii.encode(
    'HTTP/1.1 200 OK\r\n'
    'Server: Endvein\r\n'
    'Content-Type: text/plain; charset=utf-8\r\n'
    'Connection: close\r\n',
  );

  /// Pre-computed Content-Length headers including ending \r\n\r\n for lengths 0 to 1023
  static final List<Uint8List> contentLengthCache = List<Uint8List>.generate(
    1024,
    (i) => ascii.encode('Content-Length: $i\r\n\r\n'),
    growable: false,
  );

  static Uint8List getStatusLine(int statusCode) {
    switch (statusCode) {
      case 200:
        return status200;
      case 201:
        return status201;
      case 204:
        return status204;
      case 400:
        return status400;
      case 401:
        return status401;
      case 403:
        return status403;
      case 404:
        return status404;
      case 405:
        return status405;
      case 413:
        return status413;
      case 422:
        return status422;
      case 431:
        return status431;
      case 500:
        return status500;
      default:
        return ascii.encode('HTTP/1.1 $statusCode Custom\r\n');
    }
  }
}

