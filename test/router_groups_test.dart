import 'package:endvein/endvein.dart';
import 'package:test/test.dart';

void main() {
  group('EndveinRouter Groups & Scoped Middlewares', () {
    late EndveinRouter router;
    late EndveinTestClient client;

    setUp(() {
      router = EndveinRouter();
      client = EndveinTestClient(router);
    });

    test('Route group prefixes paths correctly', () async {
      router.group('/api/v1', (v1) {
        v1.get('/users', (ctx) => [{'id': 1, 'name': 'Alice'}]);
        v1.get('/users/:id', (ctx) {
          final id = ctx.paramInt('id');
          return {'id': id, 'name': 'User #$id'};
        });
      });

      final listRes = await client.get('/api/v1/users');
      expect(listRes.statusCode, equals(200));
      expect(listRes.bodyJson, equals([{'id': 1, 'name': 'Alice'}]));

      final itemRes = await client.get('/api/v1/users/42');
      expect(itemRes.statusCode, equals(200));
      expect(itemRes.bodyJson, equals({'id': 42, 'name': 'User #42'}));
    });

    test('Nested route groups inherit prefixes recursively', () async {
      router.group('/api', (api) {
        api.group('/v2', (v2) {
          v2.group('/admin', (admin) {
            admin.get('/metrics', (ctx) => {'status': 'ok'});
          });
        });
      });

      final res = await client.get('/api/v2/admin/metrics');
      expect(res.statusCode, equals(200));
      expect(res.bodyJson, equals({'status': 'ok'}));
    });

    test('Group-level middleware protects only routes in that group', () async {
      router.get('/public', (ctx) => 'public content');

      router.group('/protected', (g) {
        g.use((ctx, next) async {
          final auth = ctx.getHeader('authorization');
          if (auth != 'Bearer secret-token') {
            return EndveinResponse.json({'error': 'Unauthorized'}, statusCode: 401);
          }
          return next();
        });

        g.get('/secret', (ctx) => {'secret': 'classified'});
      });

      // Public route works without auth
      final pubRes = await client.get('/public');
      expect(pubRes.statusCode, equals(200));
      expect(pubRes.bodyText, equals('public content'));

      // Protected route fails without header
      final unauthRes = await client.get('/protected/secret');
      expect(unauthRes.statusCode, equals(401));
      expect(unauthRes.bodyJson, equals({'error': 'Unauthorized'}));

      // Protected route succeeds with valid header
      final authRes = await client.get('/protected/secret', headers: {
        'authorization': 'Bearer secret-token',
      });
      expect(authRes.statusCode, equals(200));
      expect(authRes.bodyJson, equals({'secret': 'classified'}));
    });

    test('Route-specific middleware applies only to designated endpoint', () async {
      Future<EndveinResponse?> customMiddleware(
        EndveinContext ctx,
        NextFunction next,
      ) async {
        ctx.store['custom_flag'] = true;
        return next();
      }

      router.get('/no-middleware', (ctx) => {'flag': ctx.store['custom_flag']});
      router.get(
        '/with-middleware',
        (ctx) => {'flag': ctx.store['custom_flag']},
        middlewares: [customMiddleware],
      );

      final noRes = await client.get('/no-middleware');
      expect(noRes.bodyJson, equals({'flag': null}));

      final withRes = await client.get('/with-middleware');
      expect(withRes.bodyJson, equals({'flag': true}));
    });

    test('Type-safe query casting works seamlessly', () async {
      router.get('/search', (ctx) {
        final page = ctx.queryInt('page', defaultValue: 1);
        final limit = ctx.queryInt('limit', defaultValue: 10);
        final active = ctx.queryBool('active', defaultValue: false);
        final query = ctx.queryString('q', defaultValue: 'none');

        return {
          'page': page,
          'limit': limit,
          'active': active,
          'query': query,
        };
      });

      final res = await client.get('/search?page=3&limit=25&active=true&q=dart');
      expect(res.statusCode, equals(200));
      expect(res.bodyJson, equals({
        'page': 3,
        'limit': 25,
        'active': true,
        'query': 'dart',
      }));

      // Test default values when params omitted
      final defaultRes = await client.get('/search');
      expect(defaultRes.statusCode, equals(200));
      expect(defaultRes.bodyJson, equals({
        'page': 1,
        'limit': 10,
        'active': false,
        'query': 'none',
      }));
    });
  });
}
