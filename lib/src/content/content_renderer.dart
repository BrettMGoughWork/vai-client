import 'package:flutter/material.dart';

import 'content_data.dart';
import 'content_envelope.dart';
import 'content_type.dart';

typedef ContentWidgetBuilder = Widget Function(
  BuildContext context,
  ContentEnvelope envelope, {
  required bool isErrored,
});

class ContentRendererRegistry {
  ContentRendererRegistry({Map<ContentType, ContentWidgetBuilder>? builders})
      : _builders = Map<ContentType, ContentWidgetBuilder>.unmodifiable(
          builders ?? _defaultBuilders,
        );

  final Map<ContentType, ContentWidgetBuilder> _builders;

  static final Map<ContentType, ContentWidgetBuilder> _defaultBuilders =
      <ContentType, ContentWidgetBuilder>{
    ContentType.text: _buildTextContent,
    ContentType.reminder: _buildReminderContent,
    ContentType.chart: _buildStructuredContent,
    ContentType.dashboard: _buildStructuredContent,
    ContentType.image: _buildStructuredContent,
    ContentType.audio: _buildStructuredContent,
  };

  Widget build(
    BuildContext context,
    ContentEnvelope envelope, {
    bool isErrored = false,
  }) {
    final ContentWidgetBuilder builder =
        _builders[envelope.type] ?? _buildStructuredContent;
    return builder(context, envelope, isErrored: isErrored);
  }

  ContentRendererRegistry extend(Map<ContentType, ContentWidgetBuilder> builders) {
    return ContentRendererRegistry(
      builders: <ContentType, ContentWidgetBuilder>{
        ..._builders,
        ...builders,
      },
    );
  }

  static Widget _buildTextContent(
    BuildContext context,
    ContentEnvelope envelope, {
    required bool isErrored,
  }) {
    final TextContentData data = envelope.data as TextContentData;
    return Text(
      data.text,
      style: TextStyle(
        color: isErrored ? const Color(0xFFFF8A80) : const Color(0xFFFFFFFF),
        fontSize: 16,
        height: 1.5,
      ),
    );
  }

  static Widget _buildReminderContent(
    BuildContext context,
    ContentEnvelope envelope, {
    required bool isErrored,
  }) {
    final ReminderContentData data = envelope.data as ReminderContentData;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.alarm_rounded,
              color: Color(0xFFE8E8E8),
              size: 13,
            ),
            const SizedBox(width: 5),
            Text(
              data.title ?? 'Reminder',
              style: const TextStyle(
                color: Color(0xFFE8E8E8),
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          data.text,
          style: TextStyle(
            color: isErrored ? const Color(0xFFFF8A80) : const Color(0xFFFFFFFF),
            fontSize: 16,
            height: 1.45,
          ),
        ),
        if (data.when != null) ...<Widget>[
          const SizedBox(height: 6),
          Text(
            data.when!,
            style: const TextStyle(
              color: Color(0xFF9A9A9A),
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ],
      ],
    );
  }

  static Widget _buildStructuredContent(
    BuildContext context,
    ContentEnvelope envelope, {
    required bool isErrored,
  }) {
    final Map<String, Object?> payload = envelope.payload;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF101010),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x22FFFFFF)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              envelope.type.wireName.toUpperCase(),
              style: const TextStyle(
                color: Color(0xFFDFDFDF),
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
              ),
            ),
            if (payload.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              ...payload.entries.map((MapEntry<String, Object?> entry) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: RichText(
                    text: TextSpan(
                      children: <InlineSpan>[
                        TextSpan(
                          text: '${entry.key}: ',
                          style: const TextStyle(
                            color: Color(0xFFBDBDBD),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        TextSpan(
                          text: '${entry.value}',
                          style: TextStyle(
                            color: isErrored
                                ? const Color(0xFFFF8A80)
                                : const Color(0xFFFFFFFF),
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}

final ContentRendererRegistry defaultContentRendererRegistry =
    ContentRendererRegistry();
