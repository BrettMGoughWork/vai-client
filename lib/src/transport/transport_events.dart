import '../content/content_envelope.dart';
import 'lifecycle.dart';
import 'protocol_error.dart';

sealed class VaiTransportEvent {
  const VaiTransportEvent();
}

class ConnectionStateChangedEvent extends VaiTransportEvent {
  const ConnectionStateChangedEvent({required this.from, required this.to});

  final ConnectionPhase from;
  final ConnectionPhase to;
}

class IntentStateChangedEvent extends VaiTransportEvent {
  const IntentStateChangedEvent({
    required this.intentId,
    required this.from,
    required this.to,
  });

  final String intentId;
  final IntentPhase? from;
  final IntentPhase to;
}

class ProtocolErrorEvent extends VaiTransportEvent {
  const ProtocolErrorEvent(this.error);

  final ProtocolException error;
}

class IntentInterruptedEvent extends VaiTransportEvent {
  const IntentInterruptedEvent(this.intentId);

  final String intentId;
}

class StreamStartedEvent extends VaiTransportEvent {
  const StreamStartedEvent(this.intentId);

  final String intentId;
}

class StreamChunkEvent extends VaiTransportEvent {
  const StreamChunkEvent({
    required this.intentId,
    required this.index,
    required this.delta,
    required this.assembledPreview,
  });

  final String intentId;
  final int index;
  final String delta;
  final String assembledPreview;
}

class StreamOutOfOrderBufferedEvent extends VaiTransportEvent {
  const StreamOutOfOrderBufferedEvent({
    required this.intentId,
    required this.index,
  });

  final String intentId;
  final int index;
}

class StreamCompletedEvent extends VaiTransportEvent {
  const StreamCompletedEvent({
    required this.intentId,
    required this.finalText,
    required this.status,
  });

  final String intentId;
  final String finalText;
  final String status;
}

class StreamReconciledEvent extends VaiTransportEvent {
  const StreamReconciledEvent({
    required this.intentId,
    required this.hadMismatch,
  });

  final String intentId;
  final bool hadMismatch;
}

class ServerIntentErrorEvent extends VaiTransportEvent {
  const ServerIntentErrorEvent({
    required this.intentId,
    required this.code,
    required this.message,
  });

  final String intentId;
  final String code;
  final String message;
}

enum ContentDeliveryKind { ephemeral, partial, finalResponse }

class ContentEvent extends VaiTransportEvent {
  const ContentEvent({
    required this.intentId,
    required this.content,
    required this.kind,
  });

  final String intentId;
  final ContentEnvelope content;
  final ContentDeliveryKind kind;

  String? get text => content.primaryText;
}
