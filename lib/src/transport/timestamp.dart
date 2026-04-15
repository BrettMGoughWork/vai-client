import 'protocol_error.dart';

DateTime parseIso8601UtcTimestamp(Object? raw) {
  if (raw is! String || raw.isEmpty) {
    throw const ProtocolException(
      code: ProtocolErrorCode.invalidPayload,
      message: 'timestamp must be a non-empty ISO8601 UTC string',
    );
  }

  final DateTime parsed;
  try {
    parsed = DateTime.parse(raw);
  } catch (_) {
    throw ProtocolException(
      code: ProtocolErrorCode.invalidPayload,
      message: 'timestamp is not a valid ISO8601 string',
      details: raw,
    );
  }

  // Accept both 'Z' and '+00:00' as valid UTC indicators (they are equivalent).
  final bool isUtcNotation = raw.endsWith('Z') || raw.endsWith('+00:00');
  if (!isUtcNotation) {
    throw ProtocolException(
      code: ProtocolErrorCode.invalidPayload,
      message: 'timestamp must be UTC (Z or +00:00 suffix)',
      details: raw,
    );
  }

  return parsed;
}

String toIso8601UtcTimestamp(DateTime value) => value.toUtc().toIso8601String();
