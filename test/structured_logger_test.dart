import 'package:flutter_test/flutter_test.dart';
import 'package:vai_client/src/diagnostics/structured_logger.dart';

void main() {
  test('StructuredLogger emits structured entries with sequence and fields', () {
    final List<StructuredLogEntry> entries = <StructuredLogEntry>[];
    final StructuredLogger logger = StructuredLogger(
      sink: entries.add,
      clock: () => DateTime.utc(2026, 4, 14, 12, 30, 0),
    );

    logger.info('transport', 'handshake_ack_received', <String, Object?>{
      'connection_id': 'conn-1',
      'intent_id': 'handshake',
      'protocol_version': 1,
    });
    logger.warning('ux', 'prompt_submitted', <String, Object?>{
      'intent_id': 'intent-1',
      'prompt_length': 19,
    });

    expect(entries, hasLength(2));
    expect(entries.first.sequence, 1);
    expect(entries.first.subsystem, 'transport');
    expect(entries.first.event, 'handshake_ack_received');
    expect(entries.first.fields['connection_id'], 'conn-1');
    expect(entries.last.sequence, 2);
    expect(entries.last.level, StructuredLogLevel.warning);
    expect(entries.last.toJson()['fields'], containsPair('intent_id', 'intent-1'));
  });
}