import 'package:flutter_test/flutter_test.dart';
import 'package:vai_client/vai_content.dart';
import 'package:vai_client/vai_transport.dart';

void main() {
  group('ContentEnvelope', () {
    test('validates allowed types', () {
      final ContentEnvelope envelope = ContentEnvelope.fromJson(
        <String, Object?>{
          'type': 'reminder',
          'version': '1.0',
          'payload': <String, Object?>{'text': 'wake up'},
        },
      );

      expect(envelope.type, ContentType.reminder);
      expect(envelope.data, isA<ReminderContentData>());
      expect(envelope.payload['text'], 'wake up');
    });

    test('rejects unknown type', () {
      expect(
        () => ContentEnvelope.fromJson(
          <String, Object?>{
            'type': 'video',
            'version': '1.0',
            'payload': <String, Object?>{},
          },
        ),
        throwsA(isA<ProtocolException>()),
      );
    });

    test('coercion fallback to text works', () {
      final ContentEnvelope envelope = ContentEnvelope.coerceFromLegacyPayload(
        <String, Object?>{'message': 'legacy text'},
      );

      expect(envelope.type, ContentType.text);
      expect(envelope.primaryText, 'legacy text');
    });

    test('text parsing works', () {
      final ContentEnvelope envelope = ContentEnvelope.fromJson(
        <String, Object?>{
          'type': 'text',
          'version': '1.0',
          'payload': <String, Object?>{'text': 'hello world'},
        },
      );

      expect(envelope.primaryText, 'hello world');
    });
  });
}
