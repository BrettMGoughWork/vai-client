import 'protocol_error.dart';

enum ConnectionPhase { handshaking, active, closing, closed }

enum IntentPhase { started, streaming, completed, errored, cancelled }

class LifecycleTransition<T> {
  const LifecycleTransition({required this.from, required this.to});

  final T from;
  final T to;
}

class ConnectionLifecycleManager {
  ConnectionLifecycleManager({ConnectionPhase initial = ConnectionPhase.closed})
      : _phase = initial;

  ConnectionPhase _phase;
  final List<LifecycleTransition<ConnectionPhase>> _history =
      <LifecycleTransition<ConnectionPhase>>[];

  ConnectionPhase get phase => _phase;
  List<LifecycleTransition<ConnectionPhase>> get history =>
      List<LifecycleTransition<ConnectionPhase>>.unmodifiable(_history);

  LifecycleTransition<ConnectionPhase> transition(ConnectionPhase next) {
    if (!_isValidTransition(_phase, next)) {
      throw ProtocolException(
        code: ProtocolErrorCode.protocolViolation,
        message: 'Invalid connection transition from $_phase to $next',
      );
    }

    final LifecycleTransition<ConnectionPhase> transition =
        LifecycleTransition<ConnectionPhase>(from: _phase, to: next);
    _phase = next;
    _history.add(transition);
    return transition;
  }

  bool _isValidTransition(ConnectionPhase from, ConnectionPhase to) {
    if (from == to) {
      return false;
    }

    switch (from) {
      case ConnectionPhase.closed:
        return to == ConnectionPhase.handshaking;
      case ConnectionPhase.handshaking:
        return to == ConnectionPhase.active ||
            to == ConnectionPhase.closing ||
            to == ConnectionPhase.closed;
      case ConnectionPhase.active:
        return to == ConnectionPhase.closing || to == ConnectionPhase.closed;
      case ConnectionPhase.closing:
        return to == ConnectionPhase.closed;
    }
  }
}

class IntentLifecycleManager {
  final Map<String, IntentPhase> _intentPhases = <String, IntentPhase>{};

  IntentPhase? phaseOf(String intentId) => _intentPhases[intentId];

  Map<String, IntentPhase> get snapshot =>
      Map<String, IntentPhase>.unmodifiable(_intentPhases);

  bool isTerminal(String intentId) {
    final IntentPhase? phase = _intentPhases[intentId];
    return phase == IntentPhase.completed ||
        phase == IntentPhase.errored ||
        phase == IntentPhase.cancelled;
  }

  LifecycleTransition<IntentPhase> start(String intentId) {
    final IntentPhase? current = _intentPhases[intentId];
    if (current != null && !isTerminal(intentId)) {
      throw ProtocolException(
        code: ProtocolErrorCode.protocolViolation,
        message: 'Intent $intentId already started in phase $current',
      );
    }

    final IntentPhase from = current ?? IntentPhase.cancelled;
    _intentPhases[intentId] = IntentPhase.started;
    return LifecycleTransition<IntentPhase>(
      from: from,
      to: IntentPhase.started,
    );
  }

  LifecycleTransition<IntentPhase> toStreaming(String intentId) {
    final IntentPhase? current = _intentPhases[intentId];
    if (current != IntentPhase.started && current != IntentPhase.streaming) {
      throw ProtocolException(
        code: ProtocolErrorCode.protocolViolation,
        message: 'Intent $intentId must be started before streaming',
      );
    }

    _intentPhases[intentId] = IntentPhase.streaming;
    return LifecycleTransition<IntentPhase>(
      from: current!,
      to: IntentPhase.streaming,
    );
  }

  LifecycleTransition<IntentPhase> complete(String intentId) {
    return _toTerminal(intentId, IntentPhase.completed);
  }

  LifecycleTransition<IntentPhase> error(String intentId) {
    return _toTerminal(intentId, IntentPhase.errored);
  }

  LifecycleTransition<IntentPhase> cancel(String intentId) {
    return _toTerminal(intentId, IntentPhase.cancelled);
  }

  LifecycleTransition<IntentPhase> _toTerminal(String intentId, IntentPhase next) {
    final IntentPhase? current = _intentPhases[intentId];
    if (current == null) {
      throw ProtocolException(
        code: ProtocolErrorCode.protocolViolation,
        message: 'Intent $intentId is unknown',
      );
    }
    if (isTerminal(intentId)) {
      throw ProtocolException(
        code: ProtocolErrorCode.protocolViolation,
        message: 'Intent $intentId is already terminal: $current',
      );
    }

    _intentPhases[intentId] = next;
    return LifecycleTransition<IntentPhase>(from: current, to: next);
  }
}
