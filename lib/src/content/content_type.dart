import '../transport/protocol_error.dart';

enum ContentType {
  text,
  chart,
  dashboard,
  image,
  audio,
  reminder,
}

extension ContentTypeX on ContentType {
  String get wireName {
    switch (this) {
      case ContentType.text:
        return 'text';
      case ContentType.chart:
        return 'chart';
      case ContentType.dashboard:
        return 'dashboard';
      case ContentType.image:
        return 'image';
      case ContentType.audio:
        return 'audio';
      case ContentType.reminder:
        return 'reminder';
    }
  }

  static ContentType fromWire(String value) {
    return ContentType.values.firstWhere(
      (ContentType type) => type.wireName == value,
      orElse: () {
        throw ProtocolException(
          code: ProtocolErrorCode.invalidPayload,
          message: 'Unsupported content type',
          details: value,
        );
      },
    );
  }
}
