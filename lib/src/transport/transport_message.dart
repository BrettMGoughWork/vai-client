import '../content/content_data.dart';
import '../content/content_envelope.dart';
import '../content/content_type.dart';
import 'protocol_error.dart';
import 'timestamp.dart';

enum LegacyMessageType {
  connectionInit,
  connectionAck,
  error,
  intentStarted,
  intentUpdate,
  clarificationRequired,
  clarificationAnswer,
  intentCompleted,
  ephemeral,
  cancel,
  ping,
  partialOutput,
  finalOutput,
}

extension LegacyMessageTypeX on LegacyMessageType {
  String get wireName {
    switch (this) {
      case LegacyMessageType.connectionInit:
        return 'connection_init';
      case LegacyMessageType.connectionAck:
        return 'connection_ack';
      case LegacyMessageType.error:
        return 'error';
      case LegacyMessageType.intentStarted:
        return 'intent_started';
      case LegacyMessageType.intentUpdate:
        return 'intent_update';
      case LegacyMessageType.clarificationRequired:
        return 'clarification_required';
      case LegacyMessageType.clarificationAnswer:
        return 'clarification_answer';
      case LegacyMessageType.intentCompleted:
        return 'intent_completed';
      case LegacyMessageType.ephemeral:
        return 'ephemeral';
      case LegacyMessageType.cancel:
        return 'cancel';
      case LegacyMessageType.ping:
        return 'ping';
      case LegacyMessageType.partialOutput:
        return 'partial_output';
      case LegacyMessageType.finalOutput:
        return 'final_output';
    }
  }

  static LegacyMessageType fromWire(String value) {
    try {
      return LegacyMessageType.values.firstWhere(
        (type) => type.wireName == value,
      );
    } catch (_) {
      throw ProtocolException(
        code: ProtocolErrorCode.unknownType,
        message: 'Unknown message type',
        details: value,
      );
    }
  }
}

enum TransportEnvelopeType { handshake, ack, partial, finalEnvelope, error }

extension TransportEnvelopeTypeX on TransportEnvelopeType {
  String get wireName {
    switch (this) {
      case TransportEnvelopeType.handshake:
        return 'handshake';
      case TransportEnvelopeType.ack:
        return 'ack';
      case TransportEnvelopeType.partial:
        return 'partial';
      case TransportEnvelopeType.finalEnvelope:
        return 'final';
      case TransportEnvelopeType.error:
        return 'error';
    }
  }

  static TransportEnvelopeType fromWire(String value) {
    switch (value) {
      case 'handshake':
        return TransportEnvelopeType.handshake;
      case 'ack':
        return TransportEnvelopeType.ack;
      case 'partial':
        return TransportEnvelopeType.partial;
      case 'final':
        return TransportEnvelopeType.finalEnvelope;
      case 'error':
        return TransportEnvelopeType.error;
      default:
        throw ProtocolException(
          code: ProtocolErrorCode.invalidPayload,
          message: 'Invalid envelope type',
          details: value,
        );
    }
  }
}

class ConnectionAckPayload {
  const ConnectionAckPayload({
    required this.serverVersion,
    required this.protocolVersion,
    required this.capabilities,
  });

  final String serverVersion;
  final int protocolVersion;
  final List<String> capabilities;

  factory ConnectionAckPayload.fromPayload(Map<String, Object?> payload) {
    final Object? serverVersionRaw = payload['server_version'];
    final Object? protocolVersionRaw = payload['protocol_version'];
    final Object? capabilitiesRaw = payload['capabilities'];

    if (serverVersionRaw is! String || serverVersionRaw.isEmpty) {
      throw const ProtocolException(
        code: ProtocolErrorCode.handshakeFailed,
        message: 'connection_ack.server_version is required',
      );
    }
    if (protocolVersionRaw is! int) {
      throw const ProtocolException(
        code: ProtocolErrorCode.handshakeFailed,
        message: 'connection_ack.protocol_version must be int',
      );
    }
    if (capabilitiesRaw is! List) {
      throw const ProtocolException(
        code: ProtocolErrorCode.handshakeFailed,
        message: 'connection_ack.capabilities must be a list',
      );
    }

    final List<String> capabilities = capabilitiesRaw
        .map((Object? item) {
          if (item is! String) {
            throw const ProtocolException(
              code: ProtocolErrorCode.handshakeFailed,
              message: 'connection_ack.capabilities must contain strings only',
            );
          }
          return item;
        })
        .toList(growable: false);

    return ConnectionAckPayload(
      serverVersion: serverVersionRaw,
      protocolVersion: protocolVersionRaw,
      capabilities: capabilities,
    );
  }
}

class PartialOutputPayload {
  const PartialOutputPayload({
    required this.index,
    required this.text,
    required this.isFinalChunk,
  });

  final int index;
  final String text;
  final bool isFinalChunk;

  factory PartialOutputPayload.fromPayload(Map<String, Object?> payload) {
    final Object? indexRaw = payload['index'];
    final Object? textRaw = payload['text'];
    final Object? isFinalChunkRaw = payload['is_final_chunk'];

    if (indexRaw is! int || indexRaw < 0) {
      throw const ProtocolException(
        code: ProtocolErrorCode.invalidPayload,
        message: 'partial_output.index must be a non-negative int',
      );
    }
    if (textRaw is! String) {
      throw const ProtocolException(
        code: ProtocolErrorCode.invalidPayload,
        message: 'partial_output.text must be a string',
      );
    }
    if (isFinalChunkRaw != null && isFinalChunkRaw is! bool) {
      throw const ProtocolException(
        code: ProtocolErrorCode.invalidPayload,
        message: 'partial_output.is_final_chunk must be a bool when provided',
      );
    }

    return PartialOutputPayload(
      index: indexRaw,
      text: textRaw,
      isFinalChunk: isFinalChunkRaw as bool? ?? false,
    );
  }
}

class FinalOutputPayload {
  const FinalOutputPayload({
    required this.text,
    required this.status,
    required this.summary,
    required this.isFinal,
  });

  final String text;
  final String status;
  final Object? summary;
  final bool isFinal;

  bool get isSuccess => status == 'success';

  factory FinalOutputPayload.fromPayload(Map<String, Object?> payload) {
    final Object? textRaw = payload['text'];
    final Object? statusRaw = payload['status'];
    final Object? isFinalRaw = payload['is_final'];

    if (textRaw != null && textRaw is! String) {
      throw const ProtocolException(
        code: ProtocolErrorCode.invalidPayload,
        message: 'final_output.text must be a string when provided',
      );
    }
    if (statusRaw is! String ||
        (statusRaw != 'success' && statusRaw != 'error')) {
      throw const ProtocolException(
        code: ProtocolErrorCode.invalidPayload,
        message: 'final_output.status must be "success" or "error"',
      );
    }
    if (isFinalRaw != null && isFinalRaw != true) {
      throw const ProtocolException(
        code: ProtocolErrorCode.invalidPayload,
        message: 'final_output.is_final must be true when provided',
      );
    }

    return FinalOutputPayload(
      text: textRaw as String? ?? '',
      status: statusRaw,
      summary: payload['summary'],
      isFinal: isFinalRaw as bool? ?? true,
    );
  }
}

class TransportMessage {
  const TransportMessage({
    required this.type,
    required this.connectionId,
    required this.intentId,
    required this.timestamp,
    required this.payload,
    this.envelope,
    this.protocolVersion,
    this.content,
  });

  final LegacyMessageType type;
  final String connectionId;
  final String intentId;
  final DateTime timestamp;
  final Map<String, Object?> payload;
  final TransportEnvelopeType? envelope;
  final String? protocolVersion;
  final ContentEnvelope? content;

  factory TransportMessage.fromJson(Object? raw) {
    if (raw is! Map<String, Object?>) {
      throw const ProtocolException(
        code: ProtocolErrorCode.invalidPayload,
        message: 'transport message must be an object',
      );
    }

    final Object? typeRaw = raw['type'];
    final Object? connectionIdRaw = raw['connection_id'];
    final Object? intentIdRaw = raw['intent_id'];
    final Object? timestampRaw = raw['timestamp'];
    final Object? payloadRaw = raw['payload'];

    if (typeRaw is! String || typeRaw.isEmpty) {
      throw const ProtocolException(
        code: ProtocolErrorCode.invalidPayload,
        message: 'type is required and must be a non-empty string',
      );
    }
    if (connectionIdRaw is! String || connectionIdRaw.isEmpty) {
      throw const ProtocolException(
        code: ProtocolErrorCode.invalidPayload,
        message: 'connection_id is required and must be non-empty',
      );
    }
    if (intentIdRaw is! String || intentIdRaw.isEmpty) {
      throw const ProtocolException(
        code: ProtocolErrorCode.invalidPayload,
        message: 'intent_id is required and must be non-empty',
      );
    }
    if (payloadRaw is! Map<String, Object?>) {
      throw const ProtocolException(
        code: ProtocolErrorCode.invalidPayload,
        message: 'payload must be an object',
      );
    }

    final Object? envelopeRaw = raw['envelope'];
    final Object? protocolVersionRaw = raw['protocol_version'];
    final Object? contentRaw = raw['content'];

    TransportEnvelopeType? envelope;
    if (envelopeRaw != null) {
      if (envelopeRaw is! String) {
        throw const ProtocolException(
          code: ProtocolErrorCode.invalidPayload,
          message: 'envelope must be a string',
        );
      }
      envelope = TransportEnvelopeTypeX.fromWire(envelopeRaw);
    }

    if (protocolVersionRaw != null && protocolVersionRaw != '1.0') {
      throw const ProtocolException(
        code: ProtocolErrorCode.invalidPayload,
        message: 'protocol_version must be "1.0" when provided',
      );
    }

    ContentEnvelope? content;
    if (contentRaw != null) {
      content = ContentEnvelope.fromJson(contentRaw);
    }

    return TransportMessage(
      type: LegacyMessageTypeX.fromWire(typeRaw),
      connectionId: connectionIdRaw,
      intentId: intentIdRaw,
      timestamp: parseIso8601UtcTimestamp(timestampRaw),
      payload: Map<String, Object?>.unmodifiable(payloadRaw),
      envelope: envelope,
      protocolVersion: protocolVersionRaw as String?,
      content: content,
    );
  }

  ContentEnvelope resolveContentForUi() {
    if (content != null) {
      return content!;
    }

    if (payload.containsKey('text') || payload.containsKey('message')) {
      return ContentEnvelope.coerceFromLegacyPayload(payload);
    }

    return ContentEnvelope(
      version: '1.0',
      data: TextContentData(text: ''),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'type': type.wireName,
      'connection_id': connectionId,
      'intent_id': intentId,
      'timestamp': toIso8601UtcTimestamp(timestamp),
      'payload': payload,
      if (envelope != null) 'envelope': envelope!.wireName,
      if (protocolVersion != null) 'protocol_version': protocolVersion,
      if (content != null) 'content': content!.toJson(),
    };
  }

  static TransportMessage connectionInit({
    required String connectionId,
    required String intentId,
    required DateTime now,
  }) {
    return TransportMessage(
      type: LegacyMessageType.connectionInit,
      connectionId: connectionId,
      intentId: intentId,
      timestamp: now.toUtc(),
      envelope: TransportEnvelopeType.handshake,
      protocolVersion: '1.0',
      payload: const <String, Object?>{
        'version': 1,
        'client': 'flutter-app',
        'capabilities': <String>['stt', 'tts', 'streaming'],
      },
    );
  }
}
