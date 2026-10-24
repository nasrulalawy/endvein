import 'dart:convert';
import 'dart:typed_data';
import 'package:endvein/endvein.dart';
import 'package:test/test.dart';

void main() {
  group('ZeroCopyHttpParser Tests', () {
    test('Parses standard GET request with query params', () {
      final parser = ZeroCopyHttpParser();
      final raw = ascii.encode(
        'GET /api/v1/users?role=admin&active=true HTTP/1.1\r\n'
        'Host: localhost:8080\r\n'
        'User-Agent: BenchmarkClient\r\n'
        'Accept: application/json\r\n\r\n',
      );

      parser.append(Uint8List.fromList(raw));
      final req = parser.parseNext();

      expect(req, isNotNull);
      expect(req!.method, equals(HttpMethod.get));
      expect(req.path, equals('/api/v1/users'));
      expect(req.queryParameters['role'], equals('admin'));
      expect(req.queryParameters['active'], equals('true'));
      expect(req.header('host'), equals('localhost:8080'));
      expect(req.header('user-agent'), equals('BenchmarkClient'));
      expect(req.keepAlive, isTrue);
    });

    test('Parses POST request with JSON body and Content-Length', () {
      final parser = ZeroCopyHttpParser();
      const bodyJson = '{"name":"Alice","score":100}';
      final bodyBytes = utf8.encode(bodyJson);

      final raw = ascii.encode(
        'POST /api/v1/players HTTP/1.1\r\n'
        'Host: localhost:8080\r\n'
        'Content-Type: application/json\r\n'
        'Content-Length: ${bodyBytes.length}\r\n'
        'Connection: close\r\n\r\n',
      );

      final combined = Uint8List.fromList([...raw, ...bodyBytes]);
      parser.append(combined);

      final req = parser.parseNext();
      expect(req, isNotNull);
      expect(req!.method, equals(HttpMethod.post));
      expect(req.path, equals('/api/v1/players'));
      expect(req.keepAlive, isFalse);
      expect(req.bodyText(), equals(bodyJson));

      final parsedJson = req.bodyJson() as Map<String, dynamic>;
      expect(parsedJson['name'], equals('Alice'));
      expect(parsedJson['score'], equals(100));
    });

    test('Handles TCP packet fragmentation (multi-chunk buffering)', () {
      final parser = ZeroCopyHttpParser();
      const chunk1 = 'GET /stream';
      const chunk2 = 'ing/data HTTP/1.1\r\nHost: loca';
      const chunk3 = 'lhost\r\n\r\n';

      parser.append(Uint8List.fromList(ascii.encode(chunk1)));
      expect(parser.parseNext(), isNull); // Incomplete

      parser.append(Uint8List.fromList(ascii.encode(chunk2)));
      expect(parser.parseNext(), isNull); // Still incomplete

      parser.append(Uint8List.fromList(ascii.encode(chunk3)));
      final req = parser.parseNext(); // Now complete!
      expect(req, isNotNull);
      expect(req!.path, equals('/streaming/data'));
      expect(req.header('host'), equals('localhost'));
    });

    test('Handles HTTP Keep-Alive pipelined requests in sequence', () {
      final parser = ZeroCopyHttpParser();
      final pipelinedRaw = ascii.encode(
        'GET /req1 HTTP/1.1\r\nHost: a\r\n\r\n'
        'GET /req2 HTTP/1.1\r\nHost: b\r\n\r\n',
      );

      parser.append(Uint8List.fromList(pipelinedRaw));

      final req1 = parser.parseNext();
      expect(req1, isNotNull);
      expect(req1!.path, equals('/req1'));
      expect(req1.header('host'), equals('a'));

      final req2 = parser.parseNext();
      expect(req2, isNotNull);
      expect(req2!.path, equals('/req2'));
      expect(req2.header('host'), equals('b'));

      expect(parser.parseNext(), isNull);
    });
  });
}
