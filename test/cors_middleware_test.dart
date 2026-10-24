import 'package:endvein/endvein.dart';
import 'package:test/test.dart';

void main() {
  group('Endvein CORS & Security Headers Middleware Tests', () {
    test('CORS handles pre-flight OPTIONS request correctly', () async {
      final router = EndveinRouter();
      router.use(cors(const CorsOptions(
        allowOrigins: ['https://app.example.com'],
        allowMethods: ['GET', 'POST'],
        allowHeaders: ['Authorization', 'Content-Type'],
      )));

      router.get('/api/data', (ctx) => {'status': 'ok'});

      final client = EndveinTestClient(router);
      final optRes = await client.options('/api/data', headers: {
        'origin': 'https://app.example.com',
      });

      expect(optRes.statusCode, equals(204));
      expect(optRes.headers['Access-Control-Allow-Origin'], equals('https://app.example.com'));
      expect(optRes.headers['Access-Control-Allow-Methods'], equals('GET, POST'));
      expect(optRes.headers['Access-Control-Allow-Headers'], equals('Authorization, Content-Type'));
      expect(optRes.headers['Access-Control-Max-Age'], equals('86400'));
    });

    test('CORS attaches headers to regular GET request', () async {
      final router = EndveinRouter();
      router.use(cors());
      router.get('/hello', (ctx) => 'world');

      final client = EndveinTestClient(router);
      final res = await client.get('/hello');

      expect(res.statusCode, equals(200));
      expect(res.bodyText, equals('world'));
      expect(res.headers['Access-Control-Allow-Origin'], equals('*'));
    });

    test('Security headers attaches Helmet-style protective headers', () async {
      final router = EndveinRouter();
      router.use(securityHeaders());
      router.get('/secure', (ctx) => {'secure': true});

      final client = EndveinTestClient(router);
      final res = await client.get('/secure');

      expect(res.statusCode, equals(200));
      expect(res.headers['X-Content-Type-Options'], equals('nosniff'));
      expect(res.headers['X-Frame-Options'], equals('SAMEORIGIN'));
      expect(res.headers['X-XSS-Protection'], equals('1; mode=block'));
      expect(res.headers['Referrer-Policy'], equals('no-referrer'));
    });
  });
}
