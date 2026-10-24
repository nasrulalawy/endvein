import 'dart:convert';
import 'package:endvein/endvein.dart';
import 'package:test/test.dart';

void main() {
  group('Endvein Logger Middleware Tests', () {
    test('Logs in human-readable format and injects X-Request-Id', () async {
      final logs = <String>[];
      final router = EndveinRouter();
      router.use(logger(printFn: (msg) => logs.add(msg)));
      router.get('/hello', (ctx) => 'world');

      final client = EndveinTestClient(router);
      final res = await client.get('/hello');

      expect(res.statusCode, equals(200));
      expect(res.headers.containsKey('x-request-id'), isTrue);
      expect(logs.length, equals(1));
      expect(logs[0], contains('[GET] /hello -> 200'));
    });

    test('Logs in structured JSON format', () async {
      final logs = <String>[];
      final router = EndveinRouter();
      router.use(logger(jsonFormat: true, printFn: (msg) => logs.add(msg)));
      router.get('/api/users', (ctx) => {'status': 'ok'});

      final client = EndveinTestClient(router);
      final res = await client.get('/api/users', headers: {'x-request-id': 'custom-trace-id'});

      expect(res.statusCode, equals(200));
      expect(res.headers['x-request-id'], equals('custom-trace-id'));
      expect(logs.length, equals(1));

      final parsed = jsonDecode(logs[0]) as Map<String, dynamic>;
      expect(parsed['level'], equals('info'));
      expect(parsed['requestId'], equals('custom-trace-id'));
      expect(parsed['method'], equals('GET'));
      expect(parsed['path'], equals('/api/users'));
      expect(parsed['statusCode'], equals(200));
      expect(parsed.containsKey('latencyMs'), isTrue);
    });
  });
}
