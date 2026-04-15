import '../transport/protocol_error.dart';
import 'content_data.dart';
import 'content_type.dart';

typedef ContentDataDecoder = ContentData Function(Map<String, Object?> payload);

class ContentCodec {
  ContentCodec({Map<ContentType, ContentDataDecoder>? decoders})
      : _decoders = Map<ContentType, ContentDataDecoder>.unmodifiable(
          decoders ?? _defaultDecoders,
        );

  final Map<ContentType, ContentDataDecoder> _decoders;

  static final Map<ContentType, ContentDataDecoder> _defaultDecoders =
      <ContentType, ContentDataDecoder>{
    ContentType.text: (Map<String, Object?> payload) {
      final Object? textRaw = payload['text'] ?? payload['message'];
      if (textRaw is! String) {
        throw const ProtocolException(
          code: ProtocolErrorCode.invalidPayload,
          message: 'text content requires a string text field',
        );
      }
      return TextContentData(text: textRaw);
    },
    ContentType.reminder: (Map<String, Object?> payload) {
      final Object? textRaw = payload['text'] ?? payload['message'];
      if (textRaw is! String) {
        throw const ProtocolException(
          code: ProtocolErrorCode.invalidPayload,
          message: 'reminder content requires a string text field',
        );
      }
      return ReminderContentData(
        text: textRaw,
        title: payload['title'] as String?,
        when: payload['when'] as String?,
      );
    },
    ContentType.chart: (Map<String, Object?> payload) =>
        ChartContentData(payload: Map<String, Object?>.unmodifiable(payload)),
    ContentType.dashboard: (Map<String, Object?> payload) => DashboardContentData(
          payload: Map<String, Object?>.unmodifiable(payload),
        ),
    ContentType.image: (Map<String, Object?> payload) =>
        ImageContentData(payload: Map<String, Object?>.unmodifiable(payload)),
    ContentType.audio: (Map<String, Object?> payload) =>
        AudioContentData(payload: Map<String, Object?>.unmodifiable(payload)),
  };

  ContentData decode(ContentType type, Map<String, Object?> payload) {
    final ContentDataDecoder? decoder = _decoders[type];
    if (decoder == null) {
      throw ProtocolException(
        code: ProtocolErrorCode.invalidPayload,
        message: 'No decoder registered for content type ${type.wireName}',
      );
    }
    return decoder(payload);
  }

  ContentCodec extend(Map<ContentType, ContentDataDecoder> decoders) {
    return ContentCodec(
      decoders: <ContentType, ContentDataDecoder>{
        ..._decoders,
        ...decoders,
      },
    );
  }

  ContentData coerceLegacyPayload(Map<String, Object?> payload) {
    return decode(ContentType.text, payload);
  }
}

final ContentCodec defaultContentCodec = ContentCodec();
