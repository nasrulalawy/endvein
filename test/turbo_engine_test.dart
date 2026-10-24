import 'dart:convert';
import 'dart:io';
import 'package:endvein/endvein.dart';
import 'package:test/test.dart';

void main() {
  group('Endvein Turbo FFI Engine Tests', () {
    test('Binds TurboHttpServer and responds to HTTP requests', () async {
      final router = EndveinRouter();
      router.get('/turbo-ping', (ctx) {
        ctx.json({'status': 'turbo_ok', 'engine': 'ffi_kqueue'});
      });

      router.get('/turbo-text', (ctx) {
        ctx.text('turbo text payload');
      });

      final server = await TurboHttpServer.bind(
        '127.0.0.1',
        9922,
        router: router,
      );

      final client = HttpClient();
      try {
        // Test JSON endpoint
        final req1 = await client.getUrl(Uri.parse('http://127.0.0.1:9922/turbo-ping'));
        final res1 = await req1.close();
        final body1 = await utf8.decoder.bind(res1).join();
        expect(res1.statusCode, equals(200));
        expect(jsonDecode(body1), equals({'status': 'turbo_ok', 'engine': 'ffi_kqueue'}));

        // Test Text endpoint
        final req2 = await client.getUrl(Uri.parse('http://127.0.0.1:9922/turbo-text'));
        final res2 = await req2.close();
        final body2 = await utf8.decoder.bind(res2).join();
        expect(res2.statusCode, equals(200));
        expect(body2, equals('turbo text payload'));
      } finally {
        client.close();
        await server.close();
      }
    });
  });
}
