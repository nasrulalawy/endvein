import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:endvein/endvein.dart';
import 'package:test/test.dart';

void main() {
  group('⚔️ Historical Vulnerability Simulations Against Endvein', () {
    late EndveinRouter router;
    late RawHttpServer server;
    late int serverPort;

    setUp(() async {
      router = EndveinRouter();
      router.get('/ping', (ctx) => 'pong');
      router.get('/default.ida', (ctx) => 'iis-simulation');
      router.post('/echo', (ctx) async => await ctx.bodyText());
      router.get('/search', (ctx) => {'query': ctx.queryString('q')});
      router.get('/agent', (ctx) => {'ua': ctx.getHeader('user-agent')});

      server = await RawHttpServer.bind(
        '127.0.0.1',
        0,
        router: router,
        maxHeaderSize: 4096, // 4KB header limit
        maxBodySize: 1024 * 64, // 64KB body limit
        idleTimeout: const Duration(milliseconds: 300),
      );
      serverPort = server.port;
    });

    tearDown(() async {
      await server.close();
    });

    Future<String> sendRaw(String payload) async {
      final socket = await Socket.connect('127.0.0.1', serverPort);
      socket.add(ascii.encode(payload));
      await socket.flush();

      final completer = Completer<String>();
      final buffer = StringBuffer();

      socket.listen(
        (data) => buffer.write(ascii.decode(data, allowInvalid: true)),
        onDone: () {
          if (!completer.isCompleted) completer.complete(buffer.toString());
        },
        onError: (_) {
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

    test('1988 Morris Worm: Giant unbounded request verb fuzzer is rejected', () async {
      // Simulating Morris worm style buffer overflow on request line
      final massiveVerb = 'A' * 2000;
      final payload = '$massiveVerb /ping HTTP/1.1\r\nHost: localhost\r\n\r\n';
      final response = await sendRaw(payload);

      expect(response, contains('400 Bad Request'));
      expect(response, contains('Invalid or unsupported HTTP method'));
    });

    test('1996 Ariane 5: Integer overflow via astronomical Content-Length rejected with 413', () async {
      // Sending a 30-digit astronomical integer that would wrap around 64-bit int
      const payload = 'POST /echo HTTP/1.1\r\n'
          'Host: localhost\r\n'
          'Content-Length: 999999999999999999999999999999\r\n\r\n';
      final response = await sendRaw(payload);

      expect(response, contains('413 Payload Too Large'));
    });

    test('1996 Ariane 5: Negative integer in Content-Length rejected with 400', () async {
      // Sending negative length (-500) to fool signed integer comparisons
      const payload = 'POST /echo HTTP/1.1\r\n'
          'Host: localhost\r\n'
          'Content-Length: -500\r\n\r\n'
          'payload';
      final response = await sendRaw(payload);

      expect(response, contains('400 Bad Request'));
      expect(response, contains('Malformed Content-Length'));
    });

    test('2001 Code Red: Massive 8KB URI buffer overflow rejected with 431', () async {
      // Simulating Code Red worm exploit pattern: GET /default.ida?XXXXXX...
      final giantQuery = 'X' * 8192;
      final payload = 'GET /default.ida?$giantQuery HTTP/1.1\r\nHost: localhost\r\n\r\n';
      final response = await sendRaw(payload);

      expect(response, contains('431 Request Header Fields Too Large'));
    });

    test('2014 Heartbleed: Length over-read attempt does not leak uninitialized memory', () async {
      // Attacker claims 50,000 bytes in body, but only sends 5 bytes ("hello")
      // Heartbleed worked because the server read beyond provided bytes and returned memory.
      // In Endvein, server should wait for the actual declared bytes or timeout, never returning garbage.
      final socket = await Socket.connect('127.0.0.1', serverPort);
      socket.add(ascii.encode('POST /echo HTTP/1.1\r\nHost: localhost\r\nContent-Length: 50000\r\n\r\nhello'));
      await socket.flush();

      final completer = Completer<String>();
      final buffer = StringBuffer();
      socket.listen(
        (data) => buffer.write(ascii.decode(data, allowInvalid: true)),
        onDone: () => completer.complete(buffer.toString()),
        onError: (_) => completer.complete(buffer.toString()),
      );

      // Server will wait for the remaining 49,995 bytes until idle timeout (300ms) fires and destroys socket
      final response = await completer.future.timeout(
        const Duration(milliseconds: 600),
        onTimeout: () => buffer.toString(),
      );

      // Must NOT contain any echoed data or leaked memory
      expect(response, isNot(contains('pong')));
      expect(response, isNot(contains('Server: Endvein')));
    });

    test('2014 Shellshock: Command injection header is treated strictly as inert string', () async {
      // Attacker injects Bash function definitions into User-Agent
      const payload = 'GET /agent HTTP/1.1\r\n'
          'Host: localhost\r\n'
          'User-Agent: () { :;}; /bin/cat /etc/passwd\r\n\r\n';
      final response = await sendRaw(payload);

      expect(response, contains('200 OK'));
      // Verifies string was received safely and literally without executing
      expect(response, contains('() { :;}; /bin/cat /etc/passwd'));
    });

    test('2021 Log4Shell: JNDI injection payload is parsed inertly without evaluation', () async {
      // Attacker tries to trigger JNDI remote lookup via search query
      const payload = 'GET /search?q=%24%7Bjndi%3Aldap%3A%2F%2F127.0.0.1%3A1389%2FExploit%7D HTTP/1.1\r\n'
          'Host: localhost\r\n\r\n';
      final response = await sendRaw(payload);

      expect(response, contains('200 OK'));
      expect(response, contains('\${jndi:ldap://127.0.0.1:1389/Exploit}'));
    });

    test('SQL Injection: Dangerous SQL injection strings handled purely as typed data', () async {
      // Attacker sends classic SQL injection payload
      const payload = 'GET /search?q=%27%20OR%201%3D1%3B%20DROP%20TABLE%20users%3B%20-- HTTP/1.1\r\n'
          'Host: localhost\r\n\r\n';
      final response = await sendRaw(payload);

      expect(response, contains('200 OK'));
      expect(response, contains("' OR 1=1; DROP TABLE users; --"));
    });
  });
}
