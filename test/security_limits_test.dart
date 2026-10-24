import 'dart:convert';
import 'dart:typed_data';

import 'package:endvein/endvein.dart';
import 'package:test/test.dart';

void main() {
  group('ZeroCopyHttpParser Security Limits & DoS Protection', () {
    test('Throws HttpParserException(431) when headers exceed maxHeaderSize', () {
      final parser = ZeroCopyHttpParser(maxHeaderSize: 128); // 128 byte limit

      // Send 200 bytes of headers without \r\n\r\n
      final garbageHeader = 'GET / HTTP/1.1\r\nX-Spam: ${'A' * 180}\r\n';
      parser.append(Uint8List.fromList(ascii.encode(garbageHeader)));

      expect(
        () => parser.parseNext(),
        throwsA(
          isA<HttpParserException>().having(
            (e) => e.statusCode,
            'statusCode',
            equals(431),
          ),
        ),
      );
    });

    test('Throws HttpParserException(413) when Content-Length exceeds maxBodySize', () {
      final parser = ZeroCopyHttpParser(maxBodySize: 1024); // 1 KB limit

      final oversizedReq = 'POST /upload HTTP/1.1\r\n'
          'Host: localhost\r\n'
          'Content-Length: 5000000\r\n\r\n'; // 5MB payload declared
      parser.append(Uint8List.fromList(ascii.encode(oversizedReq)));

      expect(
        () => parser.parseNext(),
        throwsA(
          isA<HttpParserException>().having(
            (e) => e.statusCode,
            'statusCode',
            equals(413),
          ),
        ),
      );
    });
  });
}
