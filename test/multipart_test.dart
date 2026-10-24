import 'dart:convert';
import 'dart:typed_data';
import 'package:endvein/endvein.dart';
import 'package:test/test.dart';

void main() {
  group('Endvein Multipart / Form-Data Parser Tests', () {
    test('Parses form fields and uploaded files accurately', () async {
      final boundary = '----WebKitFormBoundary7MA4YWxkTrZu0gW';
      final payload = StringBuffer()
        ..write('--$boundary\r\n')
        ..write('Content-Disposition: form-data; name="username"\r\n\r\n')
        ..write('nasrulalawy\r\n')
        ..write('--$boundary\r\n')
        ..write('Content-Disposition: form-data; name="avatar"; filename="avatar.png"\r\n')
        ..write('Content-Type: image/png\r\n\r\n')
        ..write('FAKE_PNG_BINARY_CONTENT\r\n')
        ..write('--$boundary--\r\n');

      final bodyBytes = Uint8List.fromList(utf8.encode(payload.toString()));

      final router = EndveinRouter();
      router.post('/upload', (ctx) {
        final form = ctx.multipart();
        if (form == null) return {'error': 'Invalid multipart'};

        final file = form.file('avatar');
        return {
          'username': form.field('username'),
          'filename': file?.filename,
          'fileContentType': file?.contentType,
          'fileSize': file?.size,
          'fileContent': file?.readAsString(),
        };
      });

      final client = EndveinTestClient(router);
      final res = await client.post(
        '/upload',
        headers: {
          'content-type': 'multipart/form-data; boundary=$boundary',
        },
        rawBody: bodyBytes,
      );

      expect(res.statusCode, equals(200));
      expect(res.bodyJson['username'], equals('nasrulalawy'));
      expect(res.bodyJson['filename'], equals('avatar.png'));
      expect(res.bodyJson['fileContentType'], equals('image/png'));
      expect(res.bodyJson['fileContent'], equals('FAKE_PNG_BINARY_CONTENT'));
    });
  });
}
