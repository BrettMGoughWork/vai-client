import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../content/content_type.dart';
import '../diagnostics/structured_logger.dart';
import '../transport/lifecycle.dart';
import '../transport/protocol_error.dart';
import '../transport/transport_events.dart';
import '../transport/vai_transport_client.dart';
import 'chat_turn.dart';

enum ChatConnectionIndicatorState { idle, pending, connected, unavailable }

class ChatController extends ChangeNotifier {
  ChatController({
    required VaiTransportClient transportClient,
    required Uri serverUri,
    String Function()? intentIdGenerator,
    StructuredLogger? logger,
  })  : _transportClient = transportClient,
        _serverUri = serverUri,
        _intentIdGenerator = intentIdGenerator ?? const Uuid().v4,
        _logger = logger ?? defaultStructuredLogger {
    _subscription = _transportClient.events.listen(_handleEvent);
  }

  final VaiTransportClient _transportClient;
  final Uri _serverUri;
  final String Function() _intentIdGenerator;
  final StructuredLogger _logger;

  late final StreamSubscription<VaiTransportEvent> _subscription;
  final List<ChatTurn> _turns = <ChatTurn>[];

  bool _started = false;
  String? _lastErrorMessage;
  ChatConnectionIndicatorState _connectionState =
      ChatConnectionIndicatorState.idle;

  List<ChatTurn> get turns => List<ChatTurn>.unmodifiable(_turns);
  ChatConnectionIndicatorState get connectionState => _connectionState;
  String? get lastErrorMessage => _lastErrorMessage;
  bool get canSend => _connectionState == ChatConnectionIndicatorState.connected;

  Future<void> start() async {
    if (_started) {
      return;
    }
    _started = true;
    _setConnectionState(ChatConnectionIndicatorState.pending);
    _logger.info('ux', 'chat_controller_start', <String, Object?>{
      'server_uri': _serverUri.toString(),
    });
    try {
      await _transportClient.connect(_serverUri);
    } on ProtocolException catch (error) {
      _lastErrorMessage = error.message;
      _setConnectionState(ChatConnectionIndicatorState.unavailable);
    }
  }

  Future<void> sendPrompt(String rawText) async {
    final String text = rawText.trim();
    if (text.isEmpty || !canSend) {
      return;
    }

    final String intentId = _intentIdGenerator();
    _logger.info('ux', 'prompt_submitted', <String, Object?>{
      'intent_id': intentId,
      'prompt_length': text.length,
    });
    _turns.add(ChatTurn(intentId: intentId, prompt: text));
    notifyListeners();

    try {
      await _transportClient.sendIntentStarted(intentId: intentId, text: text);
    } on ProtocolException catch (error) {
      _lastErrorMessage = error.message;
      _replaceTurn(intentId, (ChatTurn turn) => turn.copyWith(isErrored: true));
    }
  }

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    unawaited(_transportClient.dispose());
    super.dispose();
  }

  void _handleEvent(VaiTransportEvent event) {
    _logger.trace('ux', 'transport_event_received', <String, Object?>{
      'event_type': event.runtimeType.toString(),
    });
    switch (event) {
      case ConnectionStateChangedEvent connectionEvent:
        _handleConnectionStateChanged(connectionEvent);
      case ProtocolErrorEvent errorEvent:
        _lastErrorMessage = errorEvent.error.message;
        if (errorEvent.error.code == ProtocolErrorCode.handshakeFailed ||
            errorEvent.error.code == ProtocolErrorCode.serverError) {
          _setConnectionState(ChatConnectionIndicatorState.unavailable);
        } else {
          notifyListeners();
        }
      case ContentEvent contentEvent:
        _handleContentEvent(contentEvent);
      case StreamChunkEvent chunkEvent:
        _replaceTurn(
          chunkEvent.intentId,
          (ChatTurn turn) => turn.copyWith(
            ephemeralLines: const <String>[],
            partialText: chunkEvent.assembledPreview,
            clearFinalContent: true,
          ),
        );
      case StreamCompletedEvent completedEvent:
        _replaceTurn(
          completedEvent.intentId,
          (ChatTurn turn) => turn.copyWith(
            ephemeralLines: const <String>[],
            clearPartialText: true,
            isErrored: completedEvent.status != 'success',
          ),
        );
      case IntentInterruptedEvent interruptedEvent:
        _replaceTurn(
          interruptedEvent.intentId,
          (ChatTurn turn) => turn.copyWith(
            ephemeralLines: <String>[
              ...turn.ephemeralLines,
              'Connection interrupted.',
            ],
            isErrored: true,
          ),
        );
      case IntentStateChangedEvent intentEvent:
        if (intentEvent.to == IntentPhase.errored ||
            intentEvent.to == IntentPhase.cancelled) {
          _replaceTurn(
            intentEvent.intentId,
            (ChatTurn turn) => turn.copyWith(isErrored: true),
          );
        }
      case ServerIntentErrorEvent serverError:
        _logger.error('ux', 'server_intent_error', <String, Object?>{
          'intent_id': serverError.intentId,
          'code': serverError.code,
          'message': serverError.message,
        });
        _replaceTurn(
          serverError.intentId,
          (ChatTurn turn) => turn.copyWith(
            isErrored: true,
            errorMessage: serverError.message.isNotEmpty
                ? serverError.message
                : 'Server error (${serverError.code})',
          ),
        );
      case StreamStartedEvent():
      case StreamOutOfOrderBufferedEvent():
      case StreamReconciledEvent():
        return;
    }
  }

  void _handleContentEvent(ContentEvent contentEvent) {
    final String? primaryText = contentEvent.content.primaryText;
    _logger.trace('ux', 'content_event_applied', <String, Object?>{
      'intent_id': contentEvent.intentId,
      'delivery_kind': contentEvent.kind.name,
      'content_type': contentEvent.content.type.wireName,
      'primary_text_length': primaryText?.length,
    });
    switch (contentEvent.kind) {
      case ContentDeliveryKind.ephemeral:
        if (primaryText == null || primaryText.isEmpty) {
          return;
        }
        _replaceTurn(
          contentEvent.intentId,
          (ChatTurn turn) => turn.copyWith(
            ephemeralLines: <String>[...turn.ephemeralLines, primaryText],
          ),
        );
      case ContentDeliveryKind.partial:
        return;
      case ContentDeliveryKind.finalResponse:
        _replaceTurn(
          contentEvent.intentId,
          (ChatTurn turn) => turn.copyWith(
            ephemeralLines: const <String>[],
            clearPartialText: true,
            finalContent: contentEvent.content,
          ),
        );
    }
  }

  void _handleConnectionStateChanged(ConnectionStateChangedEvent event) {
    _logger.info('ux', 'connection_indicator_changed', <String, Object?>{
      'from_phase': event.from.name,
      'to_phase': event.to.name,
    });
    switch (event.to) {
      case ConnectionPhase.handshaking:
        _setConnectionState(ChatConnectionIndicatorState.pending);
      case ConnectionPhase.active:
        _lastErrorMessage = null;
        _setConnectionState(ChatConnectionIndicatorState.connected);
      case ConnectionPhase.closing:
      case ConnectionPhase.closed:
        if (_lastErrorMessage != null) {
          _setConnectionState(ChatConnectionIndicatorState.unavailable);
        } else {
          _setConnectionState(ChatConnectionIndicatorState.idle);
        }
    }
  }

  void _replaceTurn(String intentId, ChatTurn Function(ChatTurn turn) update) {
    final int index = _turns.indexWhere((ChatTurn turn) => turn.intentId == intentId);
    if (index == -1) {
      return;
    }

    _turns[index] = update(_turns[index]);
    notifyListeners();
  }

  void _setConnectionState(ChatConnectionIndicatorState value) {
    if (_connectionState == value) {
      return;
    }
    _connectionState = value;
    notifyListeners();
  }
}
