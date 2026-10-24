import 'dart:convert';
import 'dart:typed_data';

/// Represents a single Server-Sent Event (SSE) message according to the W3C EventSource standard.
class SseEvent {
  /// The event payload.
  final String data;

  /// Optional event type name (defaults to 'message').
  final String? event;

  /// Optional event identifier for client reconnection (`Last-Event-ID`).
  final String? id;

  /// Optional reconnection time in milliseconds.
  final int? retry;

  const SseEvent({
    required this.data,
    this.event,
    this.id,
    this.retry,
  });

  /// Formats the SSE event as standard wire bytes.
  Uint8List toBytes() {
    final buffer = StringBuffer();
    if (event != null) buffer.write('event: $event\n');
    if (id != null) buffer.write('id: $id\n');
    if (retry != null) buffer.write('retry: $retry\n');
    for (final line in data.split('\n')) {
      buffer.write('data: $line\n');
    }
    buffer.write('\n');
    return Uint8List.fromList(utf8.encode(buffer.toString()));
  }
}

/// Interface for sending real-time streaming events to a connected client.
abstract interface class SseSender {
  /// Send a structured [SseEvent].
  void send(SseEvent event);

  /// Send plain event data with optional event type and id.
  void sendData(String data, {String? event, String? id});

  /// Close the SSE stream and terminate connection.
  Future<void> close();
}
