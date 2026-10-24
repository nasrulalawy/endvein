import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

// Native typedefs
typedef EndveinTurboListenC = Int32 Function(Pointer<Utf8> host, Int32 port, Int32 backlog);
typedef EndveinTurboListenDart = int Function(Pointer<Utf8> host, int port, int backlog);

typedef EndveinTurboCreatePollerC = Int32 Function(Int32 serverFd);
typedef EndveinTurboCreatePollerDart = int Function(int serverFd);

typedef EndveinRequestCbC = Void Function(
  Int32 clientFd,
  Int32 method,
  Pointer<Utf8> path,
  Int32 pathLen,
  Pointer<Uint8> body,
  Int32 bodyLen,
  Int32 keepAlive,
);

typedef EndveinTurboPollC = Int32 Function(
  Int32 serverFd,
  Int32 pollerFd,
  Int32 timeoutMs,
  Pointer<NativeFunction<EndveinRequestCbC>> cb,
);
typedef EndveinTurboPollDart = int Function(
  int serverFd,
  int pollerFd,
  int timeoutMs,
  Pointer<NativeFunction<EndveinRequestCbC>> cb,
);

typedef EndveinTurboSendJsonC = Int32 Function(
  Int32 clientFd,
  Pointer<Utf8> body,
  Int32 bodyLen,
  Int32 keepAlive,
);
typedef EndveinTurboSendJsonDart = int Function(
  int clientFd,
  Pointer<Utf8> body,
  int bodyLen,
  int keepAlive,
);

typedef EndveinTurboSendTextC = Int32 Function(
  Int32 clientFd,
  Pointer<Utf8> body,
  Int32 bodyLen,
  Int32 keepAlive,
);
typedef EndveinTurboSendTextDart = int Function(
  int clientFd,
  Pointer<Utf8> body,
  int bodyLen,
  int keepAlive,
);

typedef EndveinTurboSendC = Int32 Function(
  Int32 clientFd,
  Pointer<Uint8> data,
  Int32 len,
  Int32 keepAlive,
);
typedef EndveinTurboSendDart = int Function(
  int clientFd,
  Pointer<Uint8> data,
  int len,
  int keepAlive,
);

typedef EndveinTurboCloseC = Void Function(Int32 clientFd);
typedef EndveinTurboCloseDart = void Function(int clientFd);

/// Dynamic bindings to native `libendvein_turbo` (kqueue/epoll C engine).
class TurboBindings {
  static DynamicLibrary? _dylib;

  static DynamicLibrary get dylib {
    if (_dylib != null) return _dylib!;

    final String libName = Platform.isMacOS
        ? 'libendvein_turbo.dylib'
        : 'libendvein_turbo.so';

    // Search order:
    // 1. Current directory / native/
    // 2. Relative to script directory
    // 3. System libraries
    final candidates = [
      'native/$libName',
      './$libName',
      '../native/$libName',
      '/usr/local/lib/$libName',
      libName,
    ];

    for (final path in candidates) {
      if (File(path).existsSync()) {
        try {
          _dylib = DynamicLibrary.open(path);
          return _dylib!;
        } catch (_) {}
      }
    }

    try {
      _dylib = DynamicLibrary.open(libName);
      return _dylib!;
    } catch (e) {
      throw UnsupportedError(
        'Could not load native Endvein Turbo library ($libName). '
        'Please build it with: clang -O3 -flto -shared -fPIC native/endvein_turbo.c -o native/$libName',
      );
    }
  }

  static final EndveinTurboListenDart listen =
      dylib.lookupFunction<EndveinTurboListenC, EndveinTurboListenDart>('endvein_turbo_listen');

  static final EndveinTurboCreatePollerDart createPoller =
      dylib.lookupFunction<EndveinTurboCreatePollerC, EndveinTurboCreatePollerDart>('endvein_turbo_create_poller');

  static final EndveinTurboPollDart poll =
      dylib.lookupFunction<EndveinTurboPollC, EndveinTurboPollDart>('endvein_turbo_poll');

  static final EndveinTurboSendJsonDart sendJson =
      dylib.lookupFunction<EndveinTurboSendJsonC, EndveinTurboSendJsonDart>('endvein_turbo_send_json');

  static final EndveinTurboSendTextDart sendText =
      dylib.lookupFunction<EndveinTurboSendTextC, EndveinTurboSendTextDart>('endvein_turbo_send_text');

  static final EndveinTurboSendDart sendRaw =
      dylib.lookupFunction<EndveinTurboSendC, EndveinTurboSendDart>('endvein_turbo_send');

  static final EndveinTurboCloseDart closeSocket =
      dylib.lookupFunction<EndveinTurboCloseC, EndveinTurboCloseDart>('endvein_turbo_close');
}
