import 'dart:convert';
import 'dart:typed_data';
import 'package:endvein/endvein.dart';

void main(List<String> args) async {
  int? workers;
  for (final arg in args) {
    if (arg.startsWith('--workers=')) {
      workers = int.tryParse(arg.substring(10));
    } else {
      workers = int.tryParse(arg);
    }
  }

  final jsonBytes = Uint8List.fromList(
    utf8.encode('{"message":"Hello from Endvein","status":"ok"}'),
  );

  final cluster = EndveinCluster(
    workers: workers,
    host: '127.0.0.1',
    port: 8084,
    engineMode: EngineMode.rawSocket,
    routerFactory: () {
      final router = EndveinRouter();

      router.get('/json', (ctx) {
        ctx.bytes(
          jsonBytes,
          contentType: 'application/json; charset=utf-8',
          statusCode: 200,
        );
      });

      router.get('/plaintext', (ctx) {
        ctx.text('Hello World');
      });

      return router;
    },
  );

  await cluster.run();
}
