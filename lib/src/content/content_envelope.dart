import '../transport/protocol_error.dart';
import 'content_codec.dart';
import 'content_data.dart';
import 'content_type.dart';

class ContentEnvelope {
  const ContentEnvelope({
    required this.version,
    required this.data,
  });

  final String version;
  final ContentData data;

  ContentType get type => data.type;
  Map<String, Object?> get payload => data.toPayload();
  String? get primaryText => data.primaryText;

  factory ContentEnvelope.fromJson(
    Object? raw, {
    ContentCodec? codec,
  }) {
    final ContentCodec resolvedCodec = codec ?? defaultContentCodec;
    if (raw is! Map<String, Object?>) {
      throw const ProtocolException(
        code: ProtocolErrorCode.invalidPayload,
        message: 'content must be an object',
      );
    }

    final Object? typeRaw = raw['type'];
    final Object? versionRaw = raw['version'];
    final Object? payloadRaw = raw['payload'];

    if (typeRaw is! String || typeRaw.isEmpty) {
      throw const ProtocolException(
        code: ProtocolErrorCode.invalidPayload,
        message: 'content.type must be a non-empty string',
      );
    }
    if (versionRaw is! String || versionRaw.isEmpty) {
      throw const ProtocolException(
        code: ProtocolErrorCode.invalidPayload,
        message: 'content.version must be a non-empty string',
      );
    }
    if (payloadRaw is! Map<String, Object?>) {
      throw const ProtocolException(
        code: ProtocolErrorCode.invalidPayload,
        message: 'content.payload must be an object',
      );
    }

    final ContentType type = ContentTypeX.fromWire(typeRaw);
    return ContentEnvelope(
      version: versionRaw,
      data: resolvedCodec.decode(
        type,
        Map<String, Object?>.unmodifiable(payloadRaw),
      ),
    );
  }

  factory ContentEnvelope.coerceFromLegacyPayload(
    Map<String, Object?> payload, {
    ContentCodec? codec,
  }) {
    final ContentCodec resolvedCodec = codec ?? defaultContentCodec;
    return ContentEnvelope(
      version: '1.0',
      data: resolvedCodec.coerceLegacyPayload(payload),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'type': type.wireName,
      'version': version,
      'payload': payload,
    };
  }
}
