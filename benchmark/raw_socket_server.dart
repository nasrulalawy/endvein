import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

// Raw HTTP 1.1 response bytes
final responseBytes = ascii.encode(
  'HTTP/1.1 200 OK\r\n'
  'Content-Type: application/json\r\n'
  'Content-Length: 46\r\n'
  'Connection: keep-alive\r\n\r\n'
  '{"message":"Hello from Endvein","status":"ok"}',
);

void main() async {
  final numCores = Platform.numberOfProcessors;
  print('Testing Raw ServerSocket across $numCores cores on port 8083...');

  for (var i = 0; i < numCores; i++) {
    await Isolate.spawn((_) async {
      final server = await ServerSocket.bind(
        '127.0.0.1',
        8083,
        shared: true,
      );

      server.listen((Socket client) {
        client.listen((Uint8List data) {
          // Send raw response directly into the socket buffer!
          client.add(responseBytes);
        });
      });
    }, i);
  }

  final keepAlive = ReceivePort();
  await keepAlive.first;
}
