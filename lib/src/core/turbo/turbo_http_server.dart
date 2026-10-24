import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

import '../http/http_method.dart';
import '../http/router.dart';
import 'turbo_bindings.dart';
import 'turbo_context.dart';

/// Ultra-high-throughput native HTTP server using C kqueue (macOS) / epoll (Linux) and FFI.
class TurboHttpServer {
  final int serverFd;
  final int pollerFd;
  final EndveinRouter router;
  final String host;
  final int port;

  bool _running = true;
  NativeCallable<EndveinRequestCbC>? _nativeCallback;
  Completer<void>? _closeCompleter;

  // Cached methods array indexed by C method enum (0..6)
  static const List<HttpMethod> _methods = [
    HttpMethod.get,
    HttpMethod.post,
    HttpMethod.put,
    HttpMethod.delete,
    HttpMethod.patch,
    HttpMethod.head,
    HttpMethod.options,
  ];

  TurboHttpServer._({
    required this.serverFd,
    required this.pollerFd,
    required this.router,
    required this.host,
    required this.port,
  });

  /// Bind a new native Turbo server instance on [host]:[port].
  static Future<TurboHttpServer> bind(
    String host,
    int port, {
    required EndveinRouter router,
    int backlog = 4096,
  }) async {
    final hostPtr = host.toNativeUtf8();
    final serverFd = TurboBindings.listen(hostPtr, port, backlog);
    malloc.free(hostPtr);

    if (serverFd < 0) {
      throw SocketException('Failed to bind Turbo server on $host:$port (errno: $serverFd)');
    }

    final pollerFd = TurboBindings.createPoller(serverFd);
    if (pollerFd < 0) {
      TurboBindings.closeSocket(serverFd);
      throw SocketException('Failed to create native poller (errno: $pollerFd)');
    }

    final server = TurboHttpServer._(
      serverFd: serverFd,
      pollerFd: pollerFd,
      router: router,
      host: host,
      port: port,
    );

    server._startPolling();
    return server;
  }

  void _startPolling() {
    // Reusable pooled context per isolate thread
    final pooledCtx = TurboContext(
      clientFd: 0,
      method: HttpMethod.get,
      path: '',
      keepAlive: true,
    );

    void onRequest(
      int clientFd,
      int methodIdx,
      Pointer<Utf8> pathPtr,
      int pathLen,
      Pointer<Uint8> bodyPtr,
      int bodyLen,
      int keepAlive,
    ) {
      final method = (methodIdx >= 0 && methodIdx < _methods.length)
          ? _methods[methodIdx]
          : HttpMethod.get;

      // Zero-allocation fast check for common benchmark/API paths
      String path;
      if (pathLen == 5 &&
          pathPtr.cast<Uint8>()[0] == 0x2F && // /
          pathPtr.cast<Uint8>()[1] == 0x6A && // j
          pathPtr.cast<Uint8>()[2] == 0x73 && // s
          pathPtr.cast<Uint8>()[3] == 0x6F && // o
          pathPtr.cast<Uint8>()[4] == 0x6E) { // n
        path = '/json';
      } else if (pathLen == 1 && pathPtr.cast<Uint8>()[0] == 0x2F) {
        path = '/';
      } else {
        path = pathPtr.toDartString(length: pathLen);
      }

      pooledCtx.reset(
        newClientFd: clientFd,
        newMethod: method,
        newPath: path,
        newKeepAlive: keepAlive != 0,
      );

      // Route dispatch
      router.handleContext(pooledCtx);
    }

    _nativeCallback = NativeCallable<EndveinRequestCbC>.isolateLocal(onRequest);

    void pollLoop() {
      if (!_running) {
        if (_closeCompleter != null && !_closeCompleter!.isCompleted) {
          _closeCompleter!.complete();
        }
        return;
      }

      TurboBindings.poll(serverFd, pollerFd, 10, _nativeCallback!.nativeFunction);
      Timer.run(pollLoop);
    }

    Timer.run(pollLoop);
  }

  /// Close server socket and poller.
  Future<void> close() async {
    if (!_running) return;
    _running = false;
    _closeCompleter = Completer<void>();

    TurboBindings.closeSocket(serverFd);
    TurboBindings.closeSocket(pollerFd);
    _nativeCallback?.close();

    await _closeCompleter?.future;
  }
}
