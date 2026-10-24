import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

void main() async {
  final numCores = Platform.numberOfProcessors;
  final jsonBytes = Uint8List.fromList(
    utf8.encode('{"message":"Hello from Endvein","status":"ok"}'),
  );

  final masterPort = ReceivePort();
  final workerCounts = List<int>.filled(numCores, 0);

  masterPort.listen((msg) {
    if (msg is Map) {
      final id = msg['id'] as int;
      final count = msg['count'] as int;
      workerCounts[id] = count;
      print('>>> STATS: Worker #$id handled $count requests (Total: ${workerCounts.reduce((a, b) => a + b)})');
    }
  });

  for (var i = 0; i < numCores; i++) {
    await Isolate.spawn((Map<String, dynamic> args) async {
      final id = args['id'] as int;
      final sendPort = args['sendPort'] as SendPort;

      final server = await HttpServer.bind(
        '127.0.0.1',
        8080,
        shared: true,
      );

      var count = 0;
      server.listen((req) {
        count++;
        if (count % 2000 == 0) {
          sendPort.send({'id': id, 'count': count});
        }
        req.response
          ..headers.contentType = ContentType.json
          ..headers.contentLength = jsonBytes.length
          ..add(jsonBytes)
          ..close();
      });
    }, {'id': i, 'sendPort': masterPort.sendPort});
  }

  print('All $numCores workers spawned. Waiting for traffic...');
  await Completer<void>().future;
}
