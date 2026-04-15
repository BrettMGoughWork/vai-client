import 'package:flutter_test/flutter_test.dart';
import 'package:vai_client/vai_transport.dart';

void main() {
  group('TransportMessage.fromJson', () {
    test('accepts a valid transport envelope', () {
      final TransportMessage message = TransportMessage.fromJson(
        <String, Object?>{
          'type': 'intent_started',
          'connection_id': 'conn-1',
          'intent_id': 'intent-1',
          'timestamp': '2026-04-14T10:00:00.000Z',
          'payload': <String, Object?>{'text': 'hello'},
          'protocol_version': '1.0',
          'envelope': 'partial',
        },
      );

      expect(message.type, LegacyMessageType.intentStarted);
      expect(message.connectionId, 'conn-1');
      expect(message.intentId, 'intent-1');
      expect(message.payload['text'], 'hello');
    });

    test('rejects missing required fields', () {
      expect(
        () => TransportMessage.fromJson(<String, Object?>{
          'type': 'intent_started',
          'connection_id': 'conn-1',
          'timestamp': '2026-04-14T10:00:00.000Z',
          'payload': <String, Object?>{'text': 'hello'},
        }),
        throwsA(isA<ProtocolException>()),
      );
    });

    test('rejects non-object payload', () {
      expect(
        () => TransportMessage.fromJson(<String, Object?>{
          'type': 'intent_started',
          'connection_id': 'conn-1',
          'intent_id': 'intent-1',
          'timestamp': '2026-04-14T10:00:00.000Z',
          'payload': 'bad',
        }),
        throwsA(isA<ProtocolException>()),
      );
    });

    test('accepts UTC timestamp with +00:00 offset (server compat)', () {
      final TransportMessage message = TransportMessage.fromJson(
        <String, Object?>{
          'type': 'intent_started',
          'connection_id': 'conn-1',
          'intent_id': 'intent-1',
          'timestamp': '2026-04-14T10:00:00.000000+00:00',
          'payload': <String, Object?>{'text': 'hello'},
          'protocol_version': '1.0',
          'envelope': 'partial',
        },
      );
      expect(message.timestamp.isUtc, isTrue);
    });

    test('rejects non-UTC timestamp (no Z or +00:00)', () {
      expect(
        () => TransportMessage.fromJson(<String, Object?>{
          'type': 'intent_started',
          'connection_id': 'conn-1',
          'intent_id': 'intent-1',
          'timestamp': '2026-04-14T10:00:00',
          'payload': <String, Object?>{'text': 'hello'},
        }),
        throwsA(isA<ProtocolException>()),
      );
    });

    test('rejects non-UTC offset (+01:00)', () {
      expect(
        () => TransportMessage.fromJson(<String, Object?>{
          'type': 'intent_started',
          'connection_id': 'conn-1',
          'intent_id': 'intent-1',
          'timestamp': '2026-04-14T11:00:00+01:00',
          'payload': <String, Object?>{'text': 'hello'},
        }),
        throwsA(isA<ProtocolException>()),
      );
    });
  });
}
