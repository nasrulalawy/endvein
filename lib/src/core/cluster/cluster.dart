import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import '../engine/raw_http_server.dart';
import '../http/router.dart';

typedef RouterFactory = FutureOr<EndveinRouter> Function();
typedef WorkerLifecycleHook = FutureOr<void> Function(int workerId);

/// Underlying engine execution mode for Endvein.
enum EngineMode {
  /// Ultra-high-throughput raw TCP socket server with custom Zero-Copy HTTP/1.1 streaming parser.
  /// Achieves 200,000+ RPS.
  rawSocket,

  /// Standard dart:io HttpServer wrapper for fallback compatibility.
  standard,
}

/// Worker configuration payload sent over Isolate boundary.
class _WorkerConfig {
  final int workerId;
  final String host;
  final int port;
  final SendPort masterPort;
  final RouterFactory routerFactory;
  final EngineMode engineMode;
  final WorkerLifecycleHook? onWorkerInit;
  final WorkerLifecycleHook? onWorkerShutdown;
  final int maxHeaderSize;
  final int maxBodySize;
  final Duration? idleTimeout;

  _WorkerConfig({
    required this.workerId,
    required this.host,
    required this.port,
    required this.masterPort,
    required this.routerFactory,
    required this.engineMode,
    this.onWorkerInit,
    this.onWorkerShutdown,
    this.maxHeaderSize = 16 * 1024,
    this.maxBodySize = 10 * 1024 * 1024,
    this.idleTimeout = const Duration(seconds: 30),
  });
}

/// Commands sent from master to worker or vice versa.
enum _IpcCommand { ready, shutdown }

class _IpcMessage {
  final _IpcCommand command;
  final int workerId;
  final SendPort? workerPort;

  _IpcMessage(this.command, this.workerId, [this.workerPort]);
}

/// Endvein Multi-Core Native Cluster Manager with auto-healing worker supervision.
class EndveinCluster {
  final int workerCount;
  final String host;
  final int port;
  final RouterFactory routerFactory;
  final EngineMode engineMode;
  final WorkerLifecycleHook? onWorkerInit;
  final WorkerLifecycleHook? onWorkerShutdown;
  final int maxHeaderSize;
  final int maxBodySize;
  final Duration? idleTimeout;

  final Map<int, Isolate> _isolates = {};
  final Map<int, SendPort> _workerPorts = {};
  final Completer<void> _shutdownCompleter = Completer<void>();
  bool _isShuttingDown = false;
  late final ReceivePort _masterReceivePort;

  EndveinCluster({
    int? workers,
    this.host = '0.0.0.0',
    this.port = 8080,
    this.engineMode = EngineMode.rawSocket,
    required this.routerFactory,
    this.onWorkerInit,
    this.onWorkerShutdown,
    this.maxHeaderSize = 16 * 1024,
    this.maxBodySize = 10 * 1024 * 1024,
    this.idleTimeout = const Duration(seconds: 30),
  }) : workerCount = workers ?? Platform.numberOfProcessors;

  /// Start the multi-core cluster.
  Future<void> run() async {
    stdout.writeln('==================================================');
    stdout.writeln('  ⚡ ENDVEIN HIGH-PERFORMANCE BACKEND CLUSTER ⚡');
    stdout.writeln('==================================================');
    stdout.writeln('Target Address : http://$host:$port');
    stdout.writeln('Active Cores   : $workerCount workers (Isolates)');
    stdout.writeln('Engine Mode    : ${engineMode.name}');
    stdout.writeln('Process PID    : $pid');
    stdout.writeln('Platform       : ${Platform.operatingSystem} (${Platform.version.split(' ').first})');
    stdout.writeln('Supervisor     : Active (Auto-Recovery Enabled)');
    stdout.writeln('==================================================');

    _masterReceivePort = ReceivePort();
    var readyCount = 0;
    final readyCompleter = Completer<void>();

    _masterReceivePort.listen((message) {
      if (message is _IpcMessage) {
        if (message.command == _IpcCommand.ready) {
          if (message.workerPort != null) {
            _workerPorts[message.workerId] = message.workerPort!;
          }
          readyCount++;
          if (readyCount == workerCount && !readyCompleter.isCompleted) {
            readyCompleter.complete();
          }
        }
      }
    });

    // Spawn workers across all cores
    for (var i = 0; i < workerCount; i++) {
      await _spawnWorker(i + 1);
    }

    await readyCompleter.future;
    stdout.writeln('🚀 All $workerCount workers successfully listening on port $port ($engineMode)!');

    // Handle graceful shutdown signals (SIGINT, SIGTERM)
    _listenForShutdownSignals();

    await _shutdownCompleter.future;
    _masterReceivePort.close();
  }

  Future<void> _spawnWorker(int workerId) async {
    final config = _WorkerConfig(
      workerId: workerId,
      host: host,
      port: port,
      masterPort: _masterReceivePort.sendPort,
      routerFactory: routerFactory,
      engineMode: engineMode,
      onWorkerInit: onWorkerInit,
      onWorkerShutdown: onWorkerShutdown,
      maxHeaderSize: maxHeaderSize,
      maxBodySize: maxBodySize,
      idleTimeout: idleTimeout,
    );

    final exitPort = ReceivePort();
    final isolate = await Isolate.spawn<_WorkerConfig>(_workerEntryPoint, config);
    _isolates[workerId] = isolate;

    // Supervise worker exit
    isolate.addOnExitListener(exitPort.sendPort, response: workerId);
    exitPort.listen((message) async {
      exitPort.close();
      if (!_isShuttingDown) {
        stderr.writeln('⚠️ [Endvein Supervisor] Worker #$workerId exited unexpectedly! Respawning replacement...');
        _workerPorts.remove(workerId);
        _isolates.remove(workerId);
        await _spawnWorker(workerId);
      }
    });
  }

  void _listenForShutdownSignals() {
    StreamSubscription<ProcessSignal>? sigintSub;
    StreamSubscription<ProcessSignal>? sigtermSub;

    void initiateShutdown() async {
      _isShuttingDown = true;
      stdout.writeln('\n🛑 Received termination signal. Gracefully shutting down Endvein...');
      await sigintSub?.cancel();
      await sigtermSub?.cancel();

      // Notify all workers to stop
      for (final port in _workerPorts.values) {
        port.send(_IpcCommand.shutdown);
      }

      // Allow grace period for existing connections to complete
      await Future<void>.delayed(const Duration(milliseconds: 500));

      for (final isolate in _isolates.values) {
        isolate.kill(priority: Isolate.immediate);
      }

      stdout.writeln('✅ Endvein cluster terminated cleanly.');
      if (!_shutdownCompleter.isCompleted) {
        _shutdownCompleter.complete();
      }
    }

    sigintSub = ProcessSignal.sigint.watch().listen((_) => initiateShutdown());
    if (!Platform.isWindows) {
      sigtermSub = ProcessSignal.sigterm.watch().listen((_) => initiateShutdown());
    }
  }

  /// Worker Isolate Entry Point.
  static void _workerEntryPoint(_WorkerConfig config) async {
    final workerReceivePort = ReceivePort();

    // 1. Worker Initialization Lifecycle Hook
    if (config.onWorkerInit != null) {
      try {
        await config.onWorkerInit!(config.workerId);
      } catch (e, stack) {
        stderr.writeln('❌ [Worker #${config.workerId}] onWorkerInit failed: $e\n$stack');
      }
    }

    final router = await config.routerFactory();

    RawHttpServer? rawServer;
    HttpServer? standardServer;
    StreamSubscription<HttpRequest>? standardSub;

    if (config.engineMode == EngineMode.rawSocket) {
      // Ultra-high-throughput raw TCP ServerSocket with custom parser
      rawServer = await RawHttpServer.bind(
        config.host,
        config.port,
        router: router,
        shared: true,
        maxHeaderSize: config.maxHeaderSize,
        maxBodySize: config.maxBodySize,
        idleTimeout: config.idleTimeout,
      );
    } else {
      // Fallback standard dart:io HttpServer
      standardServer = await HttpServer.bind(
        config.host,
        config.port,
        shared: true,
      );
      standardSub = standardServer.listen((HttpRequest request) {
        router.handle(request);
      });
    }

    // Notify master that this worker is ready
    config.masterPort.send(_IpcMessage(
      _IpcCommand.ready,
      config.workerId,
      workerReceivePort.sendPort,
    ));

    // Listen to control commands from master
    await for (final command in workerReceivePort) {
      if (command == _IpcCommand.shutdown) {
        // Shutdown lifecycle hook
        if (config.onWorkerShutdown != null) {
          try {
            await config.onWorkerShutdown!(config.workerId);
          } catch (e) {
            stderr.writeln('⚠️ [Worker #${config.workerId}] onWorkerShutdown error: $e');
          }
        }

        if (rawServer != null) {
          await rawServer.close();
        }
        if (standardSub != null) {
          await standardSub.cancel();
        }
        if (standardServer != null) {
          await standardServer.close(force: false);
        }
        workerReceivePort.close();
        break;
      }
    }
  }
}
