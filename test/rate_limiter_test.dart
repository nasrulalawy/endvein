import 'package:endvein/endvein.dart';
import 'package:test/test.dart';

void main() {
  group('Endvein Rate Limiter Middleware Tests', () {
    test('Allows requests under max limit and sets rate limit headers', () async {
      final router = EndveinRouter();
      router.use(rateLimiter(maxRequests: 3, window: const Duration(seconds: 10)));
      router.get('/ping', (ctx) => 'pong');

      final client = EndveinTestClient(router);

      final res1 = await client.get('/ping', headers: {'x-forwarded-for': '192.168.1.1'});
      expect(res1.statusCode, equals(200));
      expect(res1.headers['x-ratelimit-limit'], equals('3'));
      expect(res1.headers['x-ratelimit-remaining'], equals('2'));

      final res2 = await client.get('/ping', headers: {'x-forwarded-for': '192.168.1.1'});
      expect(res2.statusCode, equals(200));
      expect(res2.headers['x-ratelimit-remaining'], equals('1'));

      final res3 = await client.get('/ping', headers: {'x-forwarded-for': '192.168.1.1'});
      expect(res3.statusCode, equals(200));
      expect(res3.headers['x-ratelimit-remaining'], equals('0'));

      // 4th request exceeds limit -> 429 Too Many Requests
      final res4 = await client.get('/ping', headers: {'x-forwarded-for': '192.168.1.1'});
      expect(res4.statusCode, equals(429));
      expect(res4.bodyJson['error'], equals('Too Many Requests'));
      expect(res4.headers.containsKey('retry-after'), isTrue);

      // Other client IP is unaffected
      final resOther = await client.get('/ping', headers: {'x-forwarded-for': '10.0.0.1'});
      expect(resOther.statusCode, equals(200));
      expect(resOther.headers['x-ratelimit-remaining'], equals('2'));
    });
  });
}
