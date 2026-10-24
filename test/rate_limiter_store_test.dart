import 'package:endvein/endvein.dart';
import 'package:test/test.dart';

class MockDistributedStore implements RateLimiterStore {
  int callCount = 0;

  @override
  RateLimitResult recordRequest(String key, Duration window) {
    callCount++;
    return RateLimitResult(
      count: callCount,
      resetTime: DateTime.now().add(window),
    );
  }
}

void main() {
  group('RateLimiterStore Custom Pluggable Store Tests', () {
    test('Uses custom store for rate evaluation', () async {
      final customStore = MockDistributedStore();
      final router = EndveinRouter();
      router.use(rateLimiter(
        maxRequests: 2,
        store: customStore,
      ));

      router.get('/ping', (ctx) => 'pong');

      final client = EndveinTestClient(router);

      final res1 = await client.get('/ping');
      expect(res1.statusCode, equals(200));
      expect(customStore.callCount, equals(1));

      final res2 = await client.get('/ping');
      expect(res2.statusCode, equals(200));
      expect(customStore.callCount, equals(2));

      // Third request should be blocked by custom store counter (3 > 2)
      final res3 = await client.get('/ping');
      expect(res3.statusCode, equals(429));
      expect(customStore.callCount, equals(3));
    });
  });
}
