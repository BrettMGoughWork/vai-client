import '../content/content_envelope.dart';

class ChatTurn {
  const ChatTurn({
    required this.intentId,
    required this.prompt,
    this.ephemeralLines = const <String>[],
    this.partialText,
    this.finalContent,
    this.isErrored = false,
    this.errorMessage,
  });

  final String intentId;
  final String prompt;
  final List<String> ephemeralLines;
  final String? partialText;
  final ContentEnvelope? finalContent;
  final bool isErrored;
  final String? errorMessage;

  ChatTurn copyWith({
    List<String>? ephemeralLines,
    String? partialText,
    bool clearPartialText = false,
    ContentEnvelope? finalContent,
    bool clearFinalContent = false,
    bool? isErrored,
    String? errorMessage,
  }) {
    return ChatTurn(
      intentId: intentId,
      prompt: prompt,
      ephemeralLines: ephemeralLines ?? this.ephemeralLines,
      partialText: clearPartialText ? null : (partialText ?? this.partialText),
      finalContent: clearFinalContent ? null : (finalContent ?? this.finalContent),
      isErrored: isErrored ?? this.isErrored,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}
