import 'package:endvein/endvein.dart';
import 'package:test/test.dart';

void main() {
  group('Endvein Radix Tree Router Tests', () {
    test('Resolves nested parameterized routes', () async {
      final router = EndveinRouter();
      router.get('/api/users/:userId/posts/:postId', (ctx) {
        return {
          'userId': ctx.param('userId'),
          'postId': ctx.param('postId'),
        };
      });

      final client = EndveinTestClient(router);
      final res = await client.get('/api/users/123/posts/456');

      expect(res.statusCode, equals(200));
      expect(res.bodyJson['userId'], equals('123'));
      expect(res.bodyJson['postId'], equals('456'));
    });

    test('Static routes take precedence over parameterized routes', () async {
      final router = EndveinRouter();
      router.get('/users/settings', (ctx) => 'settings_hit');
      router.get('/users/:id', (ctx) => 'user_${ctx.param('id')}');

      final client = EndveinTestClient(router);

      final settingsRes = await client.get('/users/settings');
      expect(settingsRes.bodyText, equals('settings_hit'));

      final userRes = await client.get('/users/999');
      expect(userRes.bodyText, equals('user_999'));
    });

    test('Resolves wildcard catch-all routes (*filepath)', () async {
      final router = EndveinRouter();
      router.get('/static/*filepath', (ctx) {
        return {
          'path': ctx.param('filepath'),
        };
      });

      final client = EndveinTestClient(router);
      final res = await client.get('/static/css/themes/dark/main.css');

      expect(res.statusCode, equals(200));
      expect(res.bodyJson['path'], equals('css/themes/dark/main.css'));
    });

    test('Returns 404 for unmatched deep routes', () async {
      final router = EndveinRouter();
      router.get('/products/:id', (ctx) => 'product');

      final client = EndveinTestClient(router);
      final res = await client.get('/products/100/reviews');

      expect(res.statusCode, equals(404));
      expect(res.bodyJson['error'], equals('Not Found'));
    });
  });
}
