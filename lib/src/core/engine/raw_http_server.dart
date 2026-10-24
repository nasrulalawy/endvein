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
  final Stream<Socket> _socketStream;
  final Future<void> Function() _onClose;
  final EndveinRouter _router;
  final int maxHeaderSize;
  final int maxBodySize;
  final Duration? idleTimeout;
  StreamSubscription<Socket>? _sub;

  final int port;
  final InternetAddress address;

  RawHttpServer._(
    this._socketStream,
    this._onClose,
    this._router, {
    required this.port,
    required this.address,
    this.maxHeaderSize = 16 * 1024,
    this.maxBodySize = 10 * 1024 * 1024,
    this.idleTimeout = const Duration(seconds: 30),
  });

  static Future<RawHttpServer> bind(
    dynamic host,
    int port, {
    required EndveinRouter router,
    bool shared = true,
    int backlog = 2048,
    int maxHeaderSize = 16 * 1024,
    int maxBodySize = 10 * 1024 * 1024,
    Duration? idleTimeout = const Duration(seconds: 30),
  }) async {
    final serverSocket = await ServerSocket.bind(
      host,
      port,
      shared: shared,
      backlog: backlog,
    );

    final server = RawHttpServer._(
      serverSocket,
      serverSocket.close,
      router,
      port: serverSocket.port,
      address: serverSocket.address,
      maxHeaderSize: maxHeaderSize,
      maxBodySize: maxBodySize,
      idleTimeout: idleTimeout,
    );
    server._listen();
    return server;
  }

  /// Bind a high-performance direct HTTPS server using TLS [SecurityContext].
  static Future<RawHttpServer> bindSecure(
    dynamic host,
    int port, {
    required EndveinRouter router,
    required SecurityContext context,
    bool shared = true,
    int backlog = 2048,
    int maxHeaderSize = 16 * 1024,
    int maxBodySize = 10 * 1024 * 1024,
    Duration? idleTimeout = const Duration(seconds: 30),
  }) async {
    final secureSocket = await SecureServerSocket.bind(
      host,
      port,
      context,
      shared: shared,
      backlog: backlog,
    );

    final server = RawHttpServer._(
      secureSocket,
      secureSocket.close,
      router,
      port: secureSocket.port,
      address: secureSocket.address,
      maxHeaderSize: maxHeaderSize,
      maxBodySize: maxBodySize,
      idleTimeout: idleTimeout,
    );
    server._listen();
    return server;
  }

  void _listen() {
    _sub = _socketStream.listen((Socket client) {
      // Disable Nagle's algorithm for sub-millisecond latency
      try {
        client.setOption(SocketOption.tcpNoDelay, true);
      } catch (_) {}

      Timer? idleTimer;
      void cancelIdleTimer() {
        if (idleTimer != null) {
          idleTimer!.cancel();
          idleTimer = null;
        }
      }

      void armIdleTimer() {
        if (idleTimeout != null && idleTimer == null) {
          idleTimer = Timer(idleTimeout!, () {
            try {
              client.destroy();
            } catch (_) {}
          });
        }
      }

      armIdleTimer();

      final parser = ZeroCopyHttpParser(
        maxHeaderSize: maxHeaderSize,
        maxBodySize: maxBodySize,
      );

      ZeroCopyContext? pooledCtx;

      StreamSubscription<Uint8List>? clientSub;
      clientSub = client.listen(
        (Uint8List chunk) {
          cancelIdleTimer();
          try {
            parser.append(chunk);

            // Drain all available requests (supports Keep-Alive pipelining)
            while (true) {
              final rawReq = parser.parseNext();
              if (rawReq == null) {
                armIdleTimer();
                break;
              }

              if (pooledCtx == null) {
                pooledCtx = ZeroCopyContext(client, rawReq);
              } else {
                pooledCtx!.reset(rawReq);
              }
              _router.handleContext(pooledCtx!);

              if (!rawReq.keepAlive) {
                cancelIdleTimer();
                clientSub?.cancel();
                break;
              }
            }
          } on HttpParserException catch (e) {
            cancelIdleTimer();
            clientSub?.cancel();
            _sendErrorAndClose(client, e.statusCode, e.message);
          } catch (_) {
            cancelIdleTimer();
            clientSub?.cancel();
            client.destroy();
          }
        },
        onError: (Object error) {
          cancelIdleTimer();
          client.destroy();
        },
        onDone: () {
          cancelIdleTimer();
          client.destroy();
        },
        cancelOnError: true,
      );
    });
  }

  void _sendErrorAndClose(Socket client, int statusCode, String message) async {
    try {
      final statusLine = HttpConstants.getStatusLine(statusCode);
      final body = utf8.encode('{"error":"$message"}');
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
      await client.flush();
      await client.close();
    } catch (err, st) {
      stderr.writeln('Error in _sendErrorAndClose: $err\n$st');
      client.destroy();
    }
  }

  Future<void> close() async {
    await _sub?.cancel();
    await _onClose();
  }
}
