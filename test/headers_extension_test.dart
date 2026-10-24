import 'package:endvein/endvein.dart';
import 'package:test/test.dart';

void main() {
  group('Endvein Zero-Cost Typed Extensions Tests', () {
    test('HeaderName, MediaType, and StatusCode behave correctly', () {
      expect(HeaderName.contentType.value, equals('content-type'));
      expect(HeaderName.authorization.value, equals('authorization'));

      expect(MediaType.json.isJson, isTrue);
      expect(MediaType.textPlain.isText, isTrue);
      expect(MediaType.eventStream.isEventStream, isTrue);

      expect(StatusCode.ok.isSuccess, isTrue);
      expect(StatusCode.notFound.isClientError, isTrue);
      expect(StatusCode.internalServerError.isServerError, isTrue);
    });

    test('ContextTypedHeadersX integrates cleanly with EndveinContext', () async {
      final router = EndveinRouter();
      router.get('/typed-test', (ctx) {
        ctx.setHeaderName(HeaderName.contentType, MediaType.json.value);
        ctx.sendJson({'status': 'typed_ok'}, statusCode: StatusCode.ok);
      });

      final client = EndveinTestClient(router);
      final res = await client.get('/typed-test');
      expect(res.statusCode, equals(200));
      expect(res.bodyJson['status'], equals('typed_ok'));
    });
  });
}
