enum ProtocolErrorCode {
  unknownType,
  invalidPayload,
  handshakeFailed,
  protocolViolation,
  serverError,
  cancelled,
}

extension ProtocolErrorCodeWire on ProtocolErrorCode {
  String get wireName {
    switch (this) {
      case ProtocolErrorCode.unknownType:
        return 'UNKNOWN_TYPE';
      case ProtocolErrorCode.invalidPayload:
        return 'INVALID_PAYLOAD';
      case ProtocolErrorCode.handshakeFailed:
        return 'HANDSHAKE_FAILED';
      case ProtocolErrorCode.protocolViolation:
        return 'PROTOCOL_VIOLATION';
      case ProtocolErrorCode.serverError:
        return 'SERVER_ERROR';
      case ProtocolErrorCode.cancelled:
        return 'CANCELLED';
    }
  }
}

class ProtocolException implements Exception {
  const ProtocolException({
    required this.code,
    required this.message,
    this.details,
  });

  final ProtocolErrorCode code;
  final String message;
  final Object? details;

  @override
  String toString() =>
      'ProtocolException(code: ${code.wireName}, message: $message, details: $details)';
}
