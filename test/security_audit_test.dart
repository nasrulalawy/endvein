import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:endvein/endvein.dart';
import 'package:test/test.dart';

void main() {
  group('🛡️ Endvein Comprehensive Security & Attack Penetration Audit', () {
    late EndveinRouter router;
    late RawHttpServer server;
    late int serverPort;

    setUp(() async {
      router = EndveinRouter();
      router.get('/ping', (ctx) => 'pong');
      router.get('/admin', (ctx) => 'admin-access');
      router.post('/echo', (ctx) async => await ctx.bodyText());
      router.get('/static/*filepath', (ctx) => {'file': ctx.param('filepath')});

      server = await RawHttpServer.bind(
        '127.0.0.1',
        0, // Bind to random free port
        router: router,
        maxHeaderSize: 2048, // 2KB header limit for test
        maxBodySize: 1024 * 64, // 64KB body limit for test
        idleTimeout: const Duration(milliseconds: 300), // Fast idle timeout for test
      );
      serverPort = server.port;
    });

    tearDown(() async {
      await server.close();
    });

    /// Helper to send raw TCP payload and read raw response
    Future<String> sendRawTcp(String payload) async {
      final socket = await Socket.connect('127.0.0.1', serverPort);
      socket.add(ascii.encode(payload));
      await socket.flush();

      final completer = Completer<String>();
      final buffer = StringBuffer();

      socket.listen(
        (data) {
          buffer.write(ascii.decode(data, allowInvalid: true));
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete(buffer.toString());
        },
        onError: (e) {
          if (!completer.isCompleted) completer.complete(buffer.toString());
        },
      );

      return completer.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          socket.destroy();
          return buffer.toString();
        },
      );
    }

    test('Attack 1: HTTP Request Smuggling (Conflicting CL & TE rejected with 400)', () async {
      // Classic CL.TE Desync exploit vector (RFC 7230 §3.3.3 / CWE-444)
      const payload = 'POST /echo HTTP/1.1\r\n'
          'Host: localhost\r\n'
          'Content-Length: 6\r\n'
          'Transfer-Encoding: chunked\r\n\r\n'
          '0\r\n\r\n'
          'GPOST /evil HTTP/1.1\r\n';

      final response = await sendRawTcp(payload);
      expect(response, contains('400 Bad Request'));
      expect(response, contains('Both Transfer-Encoding and Content-Length present'));
    });

    test('Attack 2: HTTP Request Smuggling (Dual Conflicting Content-Length rejected with 400)', () async {
      // Multiple differing Content-Length headers (RFC 7230 §3.3.2)
      const payload = 'POST /echo HTTP/1.1\r\n'
          'Host: localhost\r\n'
          'Content-Length: 5\r\n'
          'Content-Length: 100\r\n\r\n'
          'hello';

      final response = await sendRawTcp(payload);
      expect(response, contains('400 Bad Request'));
      expect(response, contains('Multiple Conflicting Content-Length Headers'));
    });

    test('Attack 3: CRLF Header Injection / Response Splitting (CWE-113) is prevented', () {
      final dummySocket = _MockSocket();
      final req = RawHttpRequest(method: HttpMethod.get, path: '/test');
      final ctx = ZeroCopyContext(dummySocket, req);

      // Attacker attempts to inject custom response header & fake body via CRLF
      expect(
        () => ctx.setHeader('X-Forwarded', 'user\r\nInjected-Header: evil'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('Attack 4: Path Traversal (Dot-Dot-Slash /.. and %2e%2e/) is sanitized', () async {
      // Attacker attempts to escape directory using ../ or %2e%2e/
      const payload1 = 'GET /static/../../etc/passwd HTTP/1.1\r\nHost: localhost\r\n\r\n';
      final response1 = await sendRawTcp(payload1);

      // Normalization resolves /static/../../etc/passwd -> /etc/passwd
      // which does not match /static/*filepath and returns 404 cleanly
      expect(response1, contains('404 Not Found'));

      // URL-encoded dot-dot-slash (%2e%2e/)
      const payload2 = 'GET /static/%2e%2e/%2e%2e/secret HTTP/1.1\r\nHost: localhost\r\n\r\n';
      final response2 = await sendRawTcp(payload2);
      expect(response2, contains('404 Not Found'));
    });

    test('Attack 5: Double Slash Bypass (//admin) collapses and matches protected route', () async {
      // Attacker uses //admin to bypass proxy ACL matching
      const payload = 'GET //admin HTTP/1.1\r\nHost: localhost\r\n\r\n';
      final response = await sendRawTcp(payload);
      expect(response, contains('200 OK'));
      expect(response, contains('admin-access'));
    });

    test('Attack 6: Null Byte Injection (%00 / \\x00) in request target rejected with 400', () async {
      // Attacker attempts null byte injection to truncate file paths
      final socket = await Socket.connect('127.0.0.1', serverPort);
      socket.add(Uint8List.fromList([
        ...ascii.encode('GET /secret'),
        0, // Null byte \x00
        ...ascii.encode('.png HTTP/1.1\r\nHost: localhost\r\n\r\n'),
      ]));
      await socket.flush();

      final completer = Completer<String>();
      final buffer = StringBuffer();
      socket.listen(
        (data) => buffer.write(ascii.decode(data, allowInvalid: true)),
        onDone: () => completer.complete(buffer.toString()),
        onError: (_) => completer.complete(buffer.toString()),
      );

      final response = await completer.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () => buffer.toString(),
      );

      expect(response, contains('400 Bad Request'));
      expect(response, contains('Invalid control character or null byte'));
    });

    test('Attack 7: Malformed Request Line (Giant method without spaces) rejected with 400', () async {
      // Attacker sends non-standard junk method
      const payload = 'INVALIDMETHODNAMETHATEXCEEDSLIMIT /test HTTP/1.1\r\nHost: localhost\r\n\r\n';
      final response = await sendRawTcp(payload);
      expect(response, contains('400 Bad Request'));
    });

    test('Attack 8: Header Overflow Bomb (DoS rejected with 431)', () async {
      // Attacker sends 5KB of headers when maxHeaderSize is 2KB
      final massiveHeader = 'X-Spam: ${'A' * 4096}\r\n';
      final payload = 'GET /ping HTTP/1.1\r\nHost: localhost\r\n$massiveHeader\r\n';
      final response = await sendRawTcp(payload);
      expect(response, contains('431 Request Header Fields Too Large'));
    });

    test('Attack 9: Payload Overflow Bomb (DoS rejected with 413)', () async {
      // Attacker claims huge Content-Length exceeding maxBodySize (64KB)
      const payload = 'POST /echo HTTP/1.1\r\n'
          'Host: localhost\r\n'
          'Content-Length: 5000000\r\n\r\n'; // 5MB declared
      final response = await sendRawTcp(payload);
      expect(response, contains('413 Payload Too Large'));
    });

    test('Attack 10: Slowloris DoS (Idle socket is terminated by server timer)', () async {
      // Client connects, sends only 10 bytes, and goes silent
      final socket = await Socket.connect('127.0.0.1', serverPort);
      socket.add(ascii.encode('GET /pin'));
      await socket.flush();

      final closedCompleter = Completer<bool>();
      socket.listen(
        (_) {},
        onDone: () {
          if (!closedCompleter.isCompleted) closedCompleter.complete(true);
        },
        onError: (_) {
          if (!closedCompleter.isCompleted) closedCompleter.complete(true);
        },
      );

      // Server idleTimeout is 300ms. Expect socket to be disconnected within 1s.
      final isClosed = await closedCompleter.future.timeout(
        const Duration(seconds: 1),
        onTimeout: () => false,
      );

      expect(isClosed, isTrue);
    });
  });
}

class _MockSocket extends Stream<Uint8List> implements Socket {
  final List<List<int>> written = [];

  @override
  void add(List<int> data) => written.add(data);

  @override
  void destroy() {}

  @override
  Future<void> close() async {}

  @override
  Future<void> get done async {}

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return const Stream<Uint8List>.empty().listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
