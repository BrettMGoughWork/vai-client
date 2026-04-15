import 'content_type.dart';

sealed class ContentData {
  const ContentData();

  ContentType get type;
  Map<String, Object?> toPayload();
  String? get primaryText;
}

class TextContentData extends ContentData {
  const TextContentData({required this.text});

  final String text;

  @override
  ContentType get type => ContentType.text;

  @override
  String get primaryText => text;

  @override
  Map<String, Object?> toPayload() => <String, Object?>{'text': text};
}

class ReminderContentData extends ContentData {
  const ReminderContentData({
    required this.text,
    this.title,
    this.when,
  });

  final String text;
  final String? title;
  final String? when;

  @override
  ContentType get type => ContentType.reminder;

  @override
  String get primaryText => text;

  @override
  Map<String, Object?> toPayload() {
    return <String, Object?>{
      'text': text,
      if (title != null) 'title': title,
      if (when != null) 'when': when,
    };
  }
}

class ChartContentData extends ContentData {
  const ChartContentData({required this.payload});

  final Map<String, Object?> payload;

  @override
  ContentType get type => ContentType.chart;

  @override
  String? get primaryText => payload['title'] as String?;

  @override
  Map<String, Object?> toPayload() => payload;
}

class DashboardContentData extends ContentData {
  const DashboardContentData({required this.payload});

  final Map<String, Object?> payload;

  @override
  ContentType get type => ContentType.dashboard;

  @override
  String? get primaryText => payload['title'] as String?;

  @override
  Map<String, Object?> toPayload() => payload;
}

class ImageContentData extends ContentData {
  const ImageContentData({required this.payload});

  final Map<String, Object?> payload;

  @override
  ContentType get type => ContentType.image;

  @override
  String? get primaryText => payload['alt'] as String? ?? payload['title'] as String?;

  @override
  Map<String, Object?> toPayload() => payload;
}

class AudioContentData extends ContentData {
  const AudioContentData({required this.payload});

  final Map<String, Object?> payload;

  @override
  ContentType get type => ContentType.audio;

  @override
  String? get primaryText => payload['title'] as String?;

  @override
  Map<String, Object?> toPayload() => payload;
}
