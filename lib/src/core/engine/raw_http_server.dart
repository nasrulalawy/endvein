import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../http/router.dart';
import 'http_constants.dart';
import 'http_parser.dart';
import 'zero_copy_context.dart';

/// Ultra-high-performance HTTP server directly built on raw TCP ServerSocket.
class RawHttpServer {
  final ServerSocket _serverSocket;
  final EndveinRouter _router;
  final int maxHeaderSize;
  final int maxBodySize;
  final Duration? idleTimeout;
  StreamSubscription<Socket>? _sub;

  RawHttpServer._(
    this._serverSocket,
    this._router, {
    this.maxHeaderSize = 16 * 1024,
    this.maxBodySize = 10 * 1024 * 1024,
    this.idleTimeout = const Duration(seconds: 30),
  });

  static Future<RawHttpServer> bind(
    dynamic host,
    int port, {
    required EndveinRouter router,
    bool shared = true,
    int maxHeaderSize = 16 * 1024,
    int maxBodySize = 10 * 1024 * 1024,
    Duration? idleTimeout = const Duration(seconds: 30),
  }) async {
    final serverSocket = await ServerSocket.bind(
      host,
      port,
      shared: shared,
    );

    final server = RawHttpServer._(
      serverSocket,
      router,
      maxHeaderSize: maxHeaderSize,
      maxBodySize: maxBodySize,
      idleTimeout: idleTimeout,
    );
    server._listen();
    return server;
  }

  void _listen() {
    _sub = _serverSocket.listen((Socket client) {
      // Disable Nagle's algorithm for sub-millisecond latency
      try {
        client.setOption(SocketOption.tcpNoDelay, true);
      } catch (_) {}

      Timer? idleTimer;
      void resetTimer() {
        if (idleTimeout != null) {
          idleTimer?.cancel();
          idleTimer = Timer(idleTimeout!, () {
            try {
              client.destroy();
            } catch (_) {}
          });
        }
      }

      resetTimer();

      final parser = ZeroCopyHttpParser(
        maxHeaderSize: maxHeaderSize,
        maxBodySize: maxBodySize,
      );

      StreamSubscription<Uint8List>? clientSub;
      clientSub = client.listen(
        (Uint8List chunk) {
          resetTimer();
          try {
            parser.append(chunk);

            // Drain all available requests (supports Keep-Alive pipelining)
            while (true) {
              final rawReq = parser.parseNext();
              if (rawReq == null) break;

              final ctx = ZeroCopyContext(client, rawReq);
              _router.handleContext(ctx);

              if (!rawReq.keepAlive) {
                idleTimer?.cancel();
                clientSub?.cancel();
                break;
              }
            }
          } on HttpParserException catch (e) {
            idleTimer?.cancel();
            clientSub?.cancel();
            _sendErrorAndClose(client, e.statusCode, e.message);
          } catch (_) {
            idleTimer?.cancel();
            clientSub?.cancel();
            client.destroy();
          }
        },
        onError: (Object error) {
          idleTimer?.cancel();
          client.destroy();
        },
        onDone: () {
          idleTimer?.cancel();
          client.destroy();
        },
        cancelOnError: true,
      );
    });
  }

  void _sendErrorAndClose(Socket client, int statusCode, String message) {
    try {
      final statusLine = HttpConstants.getStatusLine(statusCode);
      final body = ascii.encode('{"error":"$message"}');
      final headerStr = 'Server: Endvein\r\n'
          'Content-Type: application/json; charset=utf-8\r\n'
          'Content-Length: ${body.length}\r\n'
          'Connection: close\r\n\r\n';
      final headerBytes = ascii.encode(headerStr);
      final builder = BytesBuilder(copy: false)
        ..add(statusLine)
        ..add(headerBytes)
        ..add(body);
      client.add(builder.takeBytes());
      client.close();
    } catch (_) {
      client.destroy();
    }
  }

  Future<void> close() async {
    await _sub?.cancel();
    await _serverSocket.close();
  }
}
