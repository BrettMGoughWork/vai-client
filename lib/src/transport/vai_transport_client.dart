import 'dart:async';
import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../content/content_data.dart';
import '../content/content_envelope.dart';
import '../content/content_type.dart';
import '../diagnostics/structured_logger.dart';
import 'lifecycle.dart';
import 'protocol_error.dart';
import 'reconnect_policy.dart';
import 'transport_events.dart';
import 'transport_message.dart';
import 'websocket_adapter.dart';

class VaiTransportClient {
  VaiTransportClient({
    required SocketConnector connector,
    ReconnectPolicy? reconnectPolicy,
    Duration handshakeTimeout = const Duration(seconds: 5),
    Duration streamInactivityTimeout = const Duration(seconds: 12),
    bool emitProtocolViolations = true,
    UuidValueGenerator? connectionIdGenerator,
    DateTime Function()? clock,
    StructuredLogger? logger,
  })  : _connector = connector,
        _reconnectPolicy = reconnectPolicy ?? ReconnectPolicy(),
        _handshakeTimeout = handshakeTimeout,
        _streamInactivityTimeout = streamInactivityTimeout,
        _emitProtocolViolations = emitProtocolViolations,
        _connectionIdGenerator = connectionIdGenerator ?? const Uuid().v4,
      _clock = clock ?? DateTime.now,
      _logger = logger ?? defaultStructuredLogger;

  static const Set<String> supportedCapabilities = <String>{
    'stt',
    'tts',
    'streaming',
  };

  final SocketConnector _connector;
  final ReconnectPolicy _reconnectPolicy;
  final Duration _handshakeTimeout;
  final Duration _streamInactivityTimeout;
  final bool _emitProtocolViolations;
  final UuidValueGenerator _connectionIdGenerator;
  final DateTime Function() _clock;
  final StructuredLogger _logger;

  final ConnectionLifecycleManager _connectionLifecycle =
      ConnectionLifecycleManager();
  final IntentLifecycleManager _intentLifecycle = IntentLifecycleManager();
  final StreamController<VaiTransportEvent> _events =
      StreamController<VaiTransportEvent>.broadcast();

  final Map<String, _IntentStreamBuffer> _streamBuffers =
      <String, _IntentStreamBuffer>{};
  final Map<String, Timer> _streamTimeouts = <String, Timer>{};

  SocketConnection? _socket;
  StreamSubscription<String>? _socketSubscription;
  Timer? _handshakeTimer;

  Uri? _uri;
  bool _manualDisconnect = false;
  bool _firstOutboundRequired = true;
  String _connectionId = '';
  Set<String> _negotiatedCapabilities = <String>{};

  Stream<VaiTransportEvent> get events => _events.stream;
  ConnectionPhase get connectionPhase => _connectionLifecycle.phase;
  String get connectionId => _connectionId;
  Set<String> get negotiatedCapabilities =>
      Set<String>.unmodifiable(_negotiatedCapabilities);

  Future<void> connect(Uri uri) async {
    if (_connectionLifecycle.phase != ConnectionPhase.closed) {
      throw const ProtocolException(
        code: ProtocolErrorCode.protocolViolation,
        message: 'Client can only connect from closed state',
      );
    }

    _manualDisconnect = false;
    _uri = uri;
    _connectionId = _connectionIdGenerator();
    _logger.info('transport', 'connect_requested', <String, Object?>{
      'uri': uri.toString(),
      'connection_id': _connectionId,
    });
    await _openSocketAndHandshake();
  }

  Future<void> disconnect() async {
    _logger.info('transport', 'disconnect_requested', <String, Object?>{
      'connection_id': _connectionId,
      'phase': _connectionLifecycle.phase.name,
    });
    _manualDisconnect = true;
    _cancelHandshakeTimer();
    _cancelAllStreamTimeouts();

    if (_connectionLifecycle.phase == ConnectionPhase.active ||
        _connectionLifecycle.phase == ConnectionPhase.handshaking) {
      _emitConnectionTransition(
        _connectionLifecycle.transition(ConnectionPhase.closing),
      );
    }
    if (_connectionLifecycle.phase == ConnectionPhase.closing) {
      _emitConnectionTransition(
        _connectionLifecycle.transition(ConnectionPhase.closed),
      );
    }

    _clearAllStreamBuffers();
    await _teardownSocket();
  }

  Future<void> dispose() async {
    await disconnect();
    await _events.close();
  }

  Future<void> sendIntentStarted({
    required String intentId,
    required String text,
  }) async {
    _ensureActiveForDomainSend();
    _logger.info('transport', 'intent_send_requested', <String, Object?>{
      'connection_id': _connectionId,
      'intent_id': intentId,
      'message_type': LegacyMessageType.intentStarted.wireName,
      'text_length': text.length,
    });
    _sendTransport(
      TransportMessage(
        type: LegacyMessageType.intentStarted,
        connectionId: _connectionId,
        intentId: intentId,
        timestamp: _clock().toUtc(),
        payload: <String, Object?>{'text': text, 'input_mode': 'text'},
      ),
    );

    // Outbound prompt begins local intent lifecycle so terminal server
    // responses (error/completed/cancel) can be correlated immediately.
    _transitionIntentStarted(intentId);
  }

  Future<void> sendCancel({required String intentId}) async {
    _ensureActiveForDomainSend();
    _logger.info('transport', 'cancel_send_requested', <String, Object?>{
      'connection_id': _connectionId,
      'intent_id': intentId,
    });
    _sendTransport(
      TransportMessage(
        type: LegacyMessageType.cancel,
        connectionId: _connectionId,
        intentId: intentId,
        timestamp: _clock().toUtc(),
        payload: const <String, Object?>{},
      ),
    );
  }

  Future<void> sendPing({String intentId = 'system'}) async {
    _ensureActiveForDomainSend();
    _logger.trace('transport', 'ping_send_requested', <String, Object?>{
      'connection_id': _connectionId,
      'intent_id': intentId,
    });
    _sendTransport(
      TransportMessage(
        type: LegacyMessageType.ping,
        connectionId: _connectionId,
        intentId: intentId,
        timestamp: _clock().toUtc(),
        payload: const <String, Object?>{},
      ),
    );
  }

  Future<void> _openSocketAndHandshake() async {
    _emitConnectionTransition(
      _connectionLifecycle.transition(ConnectionPhase.handshaking),
    );
    _logger.info('transport', 'socket_connecting', <String, Object?>{
      'connection_id': _connectionId,
      'uri': _uri.toString(),
    });

    try {
      _socket = await _connector.connect(_uri!);
      _logger.info('transport', 'socket_connected', <String, Object?>{
        'connection_id': _connectionId,
      });
    } catch (error) {
      _emitError(
        ProtocolException(
          code: ProtocolErrorCode.handshakeFailed,
          message: 'Socket connection failed',
          details: error,
        ),
      );
      await _closeAndMaybeReconnect();
      return;
    }

    _firstOutboundRequired = true;
    _sendConnectionInit();

    _socketSubscription = _socket!.messages.listen(
      _onSocketMessage,
      onError: _onSocketError,
      onDone: _onSocketDone,
      cancelOnError: false,
    );

    _handshakeTimer = Timer(_handshakeTimeout, () async {
      _emitError(
        const ProtocolException(
          code: ProtocolErrorCode.handshakeFailed,
          message: 'Handshake timed out waiting for connection_ack',
        ),
      );
      await _closeAndMaybeReconnect();
    });
  }

  void _sendConnectionInit() {
    _logger.info('transport', 'handshake_init_sending', <String, Object?>{
      'connection_id': _connectionId,
      'intent_id': 'handshake',
    });
    _sendTransport(
      TransportMessage.connectionInit(
        connectionId: _connectionId,
        intentId: 'handshake',
        now: _clock(),
      ),
    );
  }

  void _onSocketMessage(String raw) {
    _logger.trace('transport', 'socket_frame_received', <String, Object?>{
      'connection_id': _connectionId,
      'raw_length': raw.length,
    });
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      _emitError(
        ProtocolException(
          code: ProtocolErrorCode.invalidPayload,
          message: 'Inbound frame is not valid JSON',
          details: raw,
        ),
      );
      return;
    }

    final TransportMessage message;
    try {
      message = TransportMessage.fromJson(decoded);
    } on ProtocolException catch (error) {
      _emitError(error);
      return;
    }

    _logger.info('transport', 'message_received', <String, Object?>{
      'connection_id': message.connectionId,
      'intent_id': message.intentId,
      'message_type': message.type.wireName,
      if (message.envelope != null) 'envelope': message.envelope!.wireName,
    });

    if (_connectionLifecycle.phase == ConnectionPhase.handshaking) {
      _handleHandshakeMessage(message);
      return;
    }

    if (_connectionLifecycle.phase != ConnectionPhase.active) {
      _emitError(
        ProtocolException(
          code: ProtocolErrorCode.protocolViolation,
          message: 'Inbound message while connection is not active',
          details: message.type.wireName,
        ),
      );
      return;
    }

    _handleActiveMessage(message);
  }

  void _handleHandshakeMessage(TransportMessage message) {
    if (message.type != LegacyMessageType.connectionAck) {
      _emitError(
        ProtocolException(
          code: ProtocolErrorCode.handshakeFailed,
          message: 'Expected connection_ack during handshake',
          details: message.type.wireName,
        ),
      );
      unawaited(_closeAndMaybeReconnect());
      return;
    }

    late final ConnectionAckPayload ackPayload;
    try {
      ackPayload = ConnectionAckPayload.fromPayload(message.payload);
    } on ProtocolException catch (error) {
      _emitError(error);
      unawaited(_closeAndMaybeReconnect());
      return;
    }

    _negotiatedCapabilities = ackPayload.capabilities
        .where(supportedCapabilities.contains)
        .toSet();

    // Adopt the server-assigned connection_id for all subsequent messages.
    _connectionId = message.connectionId;

    _logger.info('transport', 'handshake_ack_received', <String, Object?>{
      'connection_id': message.connectionId,
      'intent_id': message.intentId,
      'negotiated_capabilities': _negotiatedCapabilities.toList()..sort(),
      'server_version': ackPayload.serverVersion,
      'protocol_version': ackPayload.protocolVersion,
    });

    _cancelHandshakeTimer();
    _emitConnectionTransition(
      _connectionLifecycle.transition(ConnectionPhase.active),
    );
    _reconnectPolicy.reset();
  }

  void _handleActiveMessage(TransportMessage message) {
    switch (message.type) {
      case LegacyMessageType.intentStarted:
        _transitionIntentStarted(message.intentId);
      case LegacyMessageType.ephemeral:
        _handleEphemeral(message);
      case LegacyMessageType.partialOutput:
        _handlePartialOutput(message);
      case LegacyMessageType.finalOutput:
        _handleFinalOutput(message);
      case LegacyMessageType.intentCompleted:
        _handleIntentCompleted(message);
      case LegacyMessageType.error:
        _handleServerError(message);
      case LegacyMessageType.cancel:
        _transitionIntentTerminal(message.intentId, IntentPhase.cancelled);
      case LegacyMessageType.connectionInit:
      case LegacyMessageType.connectionAck:
      case LegacyMessageType.intentUpdate:
      case LegacyMessageType.clarificationRequired:
      case LegacyMessageType.clarificationAnswer:
      case LegacyMessageType.ping:
        return;
    }
  }

  void _handleEphemeral(TransportMessage message) {
    final IntentPhase? phase = _intentLifecycle.phaseOf(message.intentId);
    if (phase == null) {
      _emitProtocolViolation(
        'ephemeral received before intent_started',
        message.intentId,
      );
      return;
    }
    if (_intentLifecycle.isTerminal(message.intentId)) {
      _emitProtocolViolation(
        'ephemeral received for terminal intent',
        message.intentId,
      );
      return;
    }

    _logger.trace('transport', 'ephemeral_received', <String, Object?>{
      'connection_id': message.connectionId,
      'intent_id': message.intentId,
      'content_type': message.resolveContentForUi().type.wireName,
    });
    _events.add(
      ContentEvent(
        intentId: message.intentId,
        content: message.resolveContentForUi(),
        kind: ContentDeliveryKind.ephemeral,
      ),
    );
  }

  void _handlePartialOutput(TransportMessage message) {
    final IntentPhase? phase = _intentLifecycle.phaseOf(message.intentId);
    if (phase == null) {
      _emitProtocolViolation(
        'partial_output received before intent_started',
        message.intentId,
      );
      return;
    }
    if (_intentLifecycle.isTerminal(message.intentId)) {
      _emitProtocolViolation(
        'partial_output ignored for terminal intent',
        message.intentId,
      );
      return;
    }

    late final PartialOutputPayload payload;
    try {
      payload = PartialOutputPayload.fromPayload(message.payload);
    } on ProtocolException catch (error) {
      _emitError(error);
      return;
    }

    if (payload.isFinalChunk) {
      _emitProtocolViolation(
        'partial_output.is_final_chunk must be false',
        message.intentId,
      );
      return;
    }

    final _IntentStreamBuffer buffer =
        _streamBuffers.putIfAbsent(message.intentId, _IntentStreamBuffer.new);

    if (phase == IntentPhase.started) {
      final LifecycleTransition<IntentPhase> transition =
          _intentLifecycle.toStreaming(message.intentId);
      _logger.info('transport', 'stream_started', <String, Object?>{
        'connection_id': message.connectionId,
        'intent_id': message.intentId,
        'from_phase': transition.from.name,
        'to_phase': transition.to.name,
      });
      _events.add(StreamStartedEvent(message.intentId));
      _events.add(
        IntentStateChangedEvent(
          intentId: message.intentId,
          from: transition.from,
          to: transition.to,
        ),
      );
    }

    _restartStreamTimeout(message.intentId);

    final _StreamApplyResult result = buffer.accept(
      index: payload.index,
      delta: payload.text,
    );

    if (result.wasBuffered) {
      _logger.warning('transport', 'stream_chunk_buffered', <String, Object?>{
        'connection_id': message.connectionId,
        'intent_id': message.intentId,
        'index': payload.index,
        'next_expected_index': buffer.nextExpectedIndex,
      });
      _events.add(
        StreamOutOfOrderBufferedEvent(
          intentId: message.intentId,
          index: payload.index,
        ),
      );
      return;
    }

    if (result.appliedChunks.isEmpty) {
      _logger.trace('transport', 'stream_chunk_duplicate_ignored', <String, Object?>{
        'connection_id': message.connectionId,
        'intent_id': message.intentId,
        'index': payload.index,
      });
      return;
    }

    for (final _AppliedChunk chunk in result.appliedChunks) {
      _logger.trace('transport', 'stream_chunk_applied', <String, Object?>{
        'connection_id': message.connectionId,
        'intent_id': message.intentId,
        'index': chunk.index,
        'delta_length': chunk.delta.length,
        'assembled_length': chunk.assembledPreview.length,
      });
      _events.add(
        StreamChunkEvent(
          intentId: message.intentId,
          index: chunk.index,
          delta: chunk.delta,
          assembledPreview: chunk.assembledPreview,
        ),
      );
    }

    _events.add(
      ContentEvent(
        intentId: message.intentId,
        content: ContentEnvelope(
          version: '1.0',
          data: TextContentData(text: buffer.assembledText),
        ),
        kind: ContentDeliveryKind.partial,
      ),
    );
  }

  void _handleFinalOutput(TransportMessage message) {
    final IntentPhase? phase = _intentLifecycle.phaseOf(message.intentId);
    if (phase == null) {
      _emitProtocolViolation(
        'final_output received before intent_started',
        message.intentId,
      );
      return;
    }
    if (_intentLifecycle.isTerminal(message.intentId)) {
      _emitProtocolViolation(
        'final_output ignored for terminal intent',
        message.intentId,
      );
      return;
    }

    late final FinalOutputPayload payload;
    try {
      payload = FinalOutputPayload.fromPayload(message.payload);
    } on ProtocolException catch (error) {
      _emitError(error);
      return;
    }

    final _IntentStreamBuffer? buffer = _streamBuffers[message.intentId];
    final String localAssembly = buffer?.assembledText ?? '';
    final String finalText = payload.text.isNotEmpty ? payload.text : localAssembly;
    final bool hadMismatch = buffer != null && localAssembly != finalText;
    _logger.info('transport', 'stream_completed', <String, Object?>{
      'connection_id': message.connectionId,
      'intent_id': message.intentId,
      'status': payload.status,
      'had_reconciliation_mismatch': hadMismatch,
      'final_text_length': finalText.length,
    });

    _cancelStreamTimeout(message.intentId);
    _streamBuffers.remove(message.intentId);

    _events.add(
      StreamReconciledEvent(
        intentId: message.intentId,
        hadMismatch: hadMismatch,
      ),
    );
    _events.add(
      StreamCompletedEvent(
        intentId: message.intentId,
        finalText: finalText,
        status: payload.status,
      ),
    );

    _transitionIntentTerminal(
      message.intentId,
      payload.isSuccess ? IntentPhase.completed : IntentPhase.errored,
    );

    _events.add(
      ContentEvent(
        intentId: message.intentId,
        content: ContentEnvelope(
          version: '1.0',
          data: TextContentData(text: finalText),
        ),
        kind: ContentDeliveryKind.finalResponse,
      ),
    );
  }

  void _handleIntentCompleted(TransportMessage message) {
    // Extract content embedded in the intent_completed payload, if present.
    final Object? contentRaw = message.payload['content'];
    ContentEnvelope? content;
    if (contentRaw != null) {
      try {
        content = ContentEnvelope.fromJson(contentRaw);
      } on ProtocolException catch (_) {
        // Malformed embedded content -- fall through to defaults below.
      }
    }
    // Fall back to top-level content field or legacy text coercion.
    content ??= message.content ?? message.resolveContentForUi();

    _events.add(
      ContentEvent(
        intentId: message.intentId,
        content: content,
        kind: ContentDeliveryKind.finalResponse,
      ),
    );

    _transitionIntentTerminal(message.intentId, IntentPhase.completed);
  }

  void _handleServerError(TransportMessage message) {
    final String code = (message.payload['code'] as String?) ?? 'UNKNOWN';
    final String errorMessage = (message.payload['message'] as String?) ?? '';
    _logger.error('transport', 'server_error_received', <String, Object?>{
      'connection_id': message.connectionId,
      'intent_id': message.intentId,
      'code': code,
      'message': errorMessage,
    });
    _events.add(
      ServerIntentErrorEvent(
        intentId: message.intentId,
        code: code,
        message: errorMessage,
      ),
    );
    _transitionIntentTerminal(message.intentId, IntentPhase.errored);
  }

  void _transitionIntentStarted(String intentId) {
    final IntentPhase? previous = _intentLifecycle.phaseOf(intentId);
    if (previous == IntentPhase.started || previous == IntentPhase.streaming) {
      _logger.trace('transport', 'intent_started_duplicate_ignored', <String, Object?>{
        'connection_id': _connectionId,
        'intent_id': intentId,
        'current_phase': previous!.name,
      });
      return;
    }

    final LifecycleTransition<IntentPhase> transition =
        _intentLifecycle.start(intentId);
    _logger.info('transport', 'intent_state_changed', <String, Object?>{
      'connection_id': _connectionId,
      'intent_id': intentId,
      'from_phase': previous?.name,
      'to_phase': transition.to.name,
    });
    _events.add(
      IntentStateChangedEvent(
        intentId: intentId,
        from: previous,
        to: transition.to,
      ),
    );
  }

  void _transitionIntentTerminal(String intentId, IntentPhase phase) {
    final IntentPhase? previous = _intentLifecycle.phaseOf(intentId);
    if (previous == null) {
      _emitProtocolViolation('terminal message for unknown intent', intentId);
      return;
    }
    if (_intentLifecycle.isTerminal(intentId)) {
      _emitProtocolViolation(
        'terminal message for already terminal intent',
        intentId,
      );
      return;
    }

    _cancelStreamTimeout(intentId);
    _streamBuffers.remove(intentId);

    final LifecycleTransition<IntentPhase> transition;
    switch (phase) {
      case IntentPhase.completed:
        transition = _intentLifecycle.complete(intentId);
      case IntentPhase.errored:
        transition = _intentLifecycle.error(intentId);
      case IntentPhase.cancelled:
        transition = _intentLifecycle.cancel(intentId);
      case IntentPhase.started:
      case IntentPhase.streaming:
        throw const ProtocolException(
          code: ProtocolErrorCode.protocolViolation,
          message: 'Only terminal phases are supported',
        );
    }

    _logger.info('transport', 'intent_state_changed', <String, Object?>{
      'connection_id': _connectionId,
      'intent_id': intentId,
      'from_phase': previous.name,
      'to_phase': transition.to.name,
    });

    _events.add(
      IntentStateChangedEvent(
        intentId: intentId,
        from: previous,
        to: transition.to,
      ),
    );
  }

  void _ensureActiveForDomainSend() {
    if (_connectionLifecycle.phase != ConnectionPhase.active) {
      throw const ProtocolException(
        code: ProtocolErrorCode.protocolViolation,
        message: 'Domain messages are blocked until connection is active',
      );
    }
  }

  void _sendTransport(TransportMessage message) {
    if (_socket == null) {
      throw const ProtocolException(
        code: ProtocolErrorCode.protocolViolation,
        message: 'Socket is not connected',
      );
    }
    if (_firstOutboundRequired &&
        message.type != LegacyMessageType.connectionInit) {
      throw const ProtocolException(
        code: ProtocolErrorCode.protocolViolation,
        message: 'connection_init must be first outbound message',
      );
    }

    _firstOutboundRequired = false;
    _logger.trace('transport', 'message_sent', <String, Object?>{
      'connection_id': message.connectionId,
      'intent_id': message.intentId,
      'message_type': message.type.wireName,
      if (message.envelope != null) 'envelope': message.envelope!.wireName,
    });
    _socket!.send(jsonEncode(message.toJson()));
  }

  void _onSocketError(Object error, StackTrace stackTrace) {
    _logger.error('transport', 'socket_error', <String, Object?>{
      'connection_id': _connectionId,
      'error': error.toString(),
    });
    _emitError(
      ProtocolException(
        code: ProtocolErrorCode.serverError,
        message: 'Socket error',
        details: error,
      ),
    );
    unawaited(_closeAndMaybeReconnect());
  }

  void _onSocketDone() {
    _logger.info('transport', 'socket_done', <String, Object?>{
      'connection_id': _connectionId,
      'manual_disconnect': _manualDisconnect,
    });
    if (_manualDisconnect) {
      return;
    }
    unawaited(_closeAndMaybeReconnect());
  }

  Future<void> _closeAndMaybeReconnect() async {
    if (_connectionLifecycle.phase == ConnectionPhase.active ||
        _connectionLifecycle.phase == ConnectionPhase.handshaking) {
      _emitConnectionTransition(
        _connectionLifecycle.transition(ConnectionPhase.closing),
      );
    }
    if (_connectionLifecycle.phase == ConnectionPhase.closing) {
      _emitConnectionTransition(
        _connectionLifecycle.transition(ConnectionPhase.closed),
      );
    }

    await _teardownSocket();

    if (_manualDisconnect || _uri == null) {
      return;
    }

    _emitInFlightInterruptions();
    _clearAllStreamBuffers();
    _cancelAllStreamTimeouts();

    final ReconnectDecision decision = _reconnectPolicy.next();
    if (!decision.shouldRetry || decision.delay == null) {
      _emitError(
        const ProtocolException(
          code: ProtocolErrorCode.handshakeFailed,
          message: 'Reconnect attempts exhausted',
        ),
      );
      return;
    }

    _logger.warning('transport', 'reconnect_scheduled', <String, Object?>{
      'connection_id': _connectionId,
      'attempt': decision.attempt,
      'delay_ms': decision.delay!.inMilliseconds,
    });

    await Future<void>.delayed(decision.delay!);
    if (_manualDisconnect) {
      return;
    }

    _connectionId = _connectionIdGenerator();
    await _openSocketAndHandshake();
  }

  Future<void> _teardownSocket() async {
    _cancelHandshakeTimer();
    await _socketSubscription?.cancel();
    _socketSubscription = null;
    final SocketConnection? socket = _socket;
    _socket = null;
    if (socket != null) {
      await socket.close();
    }
  }

  void _emitConnectionTransition(LifecycleTransition<ConnectionPhase> transition) {
    _logger.info('transport', 'connection_state_changed', <String, Object?>{
      'connection_id': _connectionId,
      'from_phase': transition.from.name,
      'to_phase': transition.to.name,
    });
    _events.add(
      ConnectionStateChangedEvent(from: transition.from, to: transition.to),
    );
  }

  void _emitProtocolViolation(String message, String intentId) {
    if (!_emitProtocolViolations) {
      return;
    }

    _emitError(
      ProtocolException(
        code: ProtocolErrorCode.protocolViolation,
        message: message,
        details: <String, Object?>{'intent_id': intentId},
      ),
    );
  }

  void _emitError(ProtocolException error) {
    _logger.error('transport', 'protocol_error', <String, Object?>{
      'connection_id': _connectionId,
      'code': error.code.wireName,
      'message': error.message,
      'details': error.details?.toString(),
    });
    _events.add(ProtocolErrorEvent(error));
  }

  void _cancelHandshakeTimer() {
    _handshakeTimer?.cancel();
    _handshakeTimer = null;
  }

  void _restartStreamTimeout(String intentId) {
    _cancelStreamTimeout(intentId);
    _streamTimeouts[intentId] = Timer(_streamInactivityTimeout, () {
      final IntentPhase? currentPhase = _intentLifecycle.phaseOf(intentId);
      if (currentPhase != IntentPhase.streaming) {
        return;
      }

      _logger.warning('transport', 'stream_timeout', <String, Object?>{
        'connection_id': _connectionId,
        'intent_id': intentId,
        'timeout_ms': _streamInactivityTimeout.inMilliseconds,
      });

      _emitError(
        ProtocolException(
          code: ProtocolErrorCode.protocolViolation,
          message: 'Streaming inactivity timeout',
          details: <String, Object?>{'intent_id': intentId},
        ),
      );
      _transitionIntentTerminal(intentId, IntentPhase.errored);
    });
  }

  void _cancelStreamTimeout(String intentId) {
    _streamTimeouts.remove(intentId)?.cancel();
  }

  void _cancelAllStreamTimeouts() {
    final List<Timer> timers = _streamTimeouts.values.toList(growable: false);
    _streamTimeouts.clear();
    for (final Timer timer in timers) {
      timer.cancel();
    }
  }

  void _clearAllStreamBuffers() {
    _streamBuffers.clear();
  }

  void _emitInFlightInterruptions() {
    _intentLifecycle.snapshot.forEach((String intentId, IntentPhase phase) {
      if (phase != IntentPhase.completed &&
          phase != IntentPhase.errored &&
          phase != IntentPhase.cancelled) {
        _logger.warning('transport', 'intent_interrupted', <String, Object?>{
          'connection_id': _connectionId,
          'intent_id': intentId,
          'phase': phase.name,
        });
        _events.add(IntentInterruptedEvent(intentId));
      }
    });
  }
}

typedef UuidValueGenerator = String Function();

class _IntentStreamBuffer {
  int nextExpectedIndex = 0;
  final Map<int, String> _buffered = <int, String>{};
  final StringBuffer _assembled = StringBuffer();

  String get assembledText => _assembled.toString();

  _StreamApplyResult accept({required int index, required String delta}) {
    if (index < nextExpectedIndex || _buffered.containsKey(index)) {
      return const _StreamApplyResult(appliedChunks: <_AppliedChunk>[]);
    }

    if (index > nextExpectedIndex) {
      _buffered[index] = delta;
      return const _StreamApplyResult(
        appliedChunks: <_AppliedChunk>[],
        wasBuffered: true,
      );
    }

    final List<_AppliedChunk> applied = <_AppliedChunk>[];
    _apply(index, delta, applied);

    while (_buffered.containsKey(nextExpectedIndex)) {
      final String bufferedDelta = _buffered.remove(nextExpectedIndex)!;
      _apply(nextExpectedIndex, bufferedDelta, applied);
    }

    return _StreamApplyResult(appliedChunks: applied);
  }

  void _apply(int index, String delta, List<_AppliedChunk> applied) {
    _assembled.write(delta);
    applied.add(
      _AppliedChunk(
        index: index,
        delta: delta,
        assembledPreview: assembledText,
      ),
    );
    nextExpectedIndex += 1;
  }
}

class _StreamApplyResult {
  const _StreamApplyResult({
    required this.appliedChunks,
    this.wasBuffered = false,
  });

  final List<_AppliedChunk> appliedChunks;
  final bool wasBuffered;
}

class _AppliedChunk {
  const _AppliedChunk({
    required this.index,
    required this.delta,
    required this.assembledPreview,
  });

  final int index;
  final String delta;
  final String assembledPreview;
}
