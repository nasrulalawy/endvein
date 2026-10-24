import 'package:endvein/endvein.dart';
import 'package:test/test.dart';

void main() {
  group('Endvein Server-Sent Events (SSE) Tests', () {
    test('Streams real-time events with standard W3C formatting', () async {
      final router = EndveinRouter();
      router.get('/events', (ctx) async {
        await ctx.sse((sender) async {
          sender.sendData('Starting token generation', event: 'status');
          sender.send(const SseEvent(
            event: 'token',
            data: 'Hello',
            id: '1',
          ));
          sender.send(const SseEvent(
            event: 'token',
            data: 'World!',
            id: '2',
          ));
          sender.sendData('Generation completed', event: 'done');
        });
      });

      final client = EndveinTestClient(router);
      final res = await client.get('/events');

      expect(res.statusCode, equals(200));
      expect(res.headers['content-type'], contains('text/event-stream'));
      expect(res.headers['cache-control'], equals('no-cache'));

      expect(res.sseEvents.length, equals(4));
      expect(res.sseEvents[0].event, equals('status'));
      expect(res.sseEvents[0].data, equals('Starting token generation'));

      expect(res.sseEvents[1].event, equals('token'));
      expect(res.sseEvents[1].data, equals('Hello'));
      expect(res.sseEvents[1].id, equals('1'));

      expect(res.sseEvents[2].event, equals('token'));
      expect(res.sseEvents[2].data, equals('World!'));
      expect(res.sseEvents[2].id, equals('2'));

      expect(res.sseEvents[3].event, equals('done'));

      expect(res.bodyText, contains('event: status\ndata: Starting token generation\n\n'));
      expect(res.bodyText, contains('event: token\nid: 1\ndata: Hello\n\n'));
      expect(res.bodyText, contains('event: token\nid: 2\ndata: World!\n\n'));
    });
  });
}
