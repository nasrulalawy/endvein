import 'package:endvein/endvein.dart';
import 'package:test/test.dart';

void main() {
  group('Endvein Prometheus Metrics Tests', () {
    test('Collects metrics and exposes them in Prometheus exposition format', () async {
      final prom = PrometheusMetrics();
      final router = EndveinRouter();
      router.use(prom.middleware());

      router.get('/ping', (ctx) => 'pong');
      router.post('/users', (ctx) => {'created': true});
      router.get('/metrics', prom.handler);

      final client = EndveinTestClient(router);

      // Fire a couple of requests
      await client.get('/ping');
      await client.get('/ping');
      await client.post('/users', body: {'name': 'Alice'});

      // Fetch /metrics
      final metricsRes = await client.get('/metrics');
      expect(metricsRes.statusCode, equals(200));
      expect(metricsRes.headers['content-type'], contains('text/plain'));

      final body = metricsRes.bodyText;
      expect(body, contains('# TYPE http_requests_total counter'));
      expect(body, contains('http_requests_total{method="GET",status="200"} 2'));
      expect(body, contains('http_requests_total{method="POST",status="200"} 1'));
      expect(body, contains('# TYPE endvein_uptime_seconds gauge'));
    });
  });
}
