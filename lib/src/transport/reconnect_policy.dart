import 'dart:math';

class ReconnectDecision {
  const ReconnectDecision({
    required this.shouldRetry,
    required this.attempt,
    this.delay,
  });

  final bool shouldRetry;
  final int attempt;
  final Duration? delay;
}

class ReconnectPolicy {
  ReconnectPolicy({
    this.baseDelay = const Duration(milliseconds: 500),
    this.maxDelay = const Duration(seconds: 30),
    this.maxAttempts = 5,
    Random? random,
  }) : _random = random ?? Random();

  final Duration baseDelay;
  final Duration maxDelay;
  final int maxAttempts;
  final Random _random;

  int _attempt = 0;

  int get currentAttempt => _attempt;

  void reset() {
    _attempt = 0;
  }

  ReconnectDecision next() {
    _attempt += 1;
    if (_attempt > maxAttempts) {
      return ReconnectDecision(shouldRetry: false, attempt: _attempt);
    }

    final int exponentialMs = baseDelay.inMilliseconds * (1 << (_attempt - 1));
    final int boundedMs = exponentialMs > maxDelay.inMilliseconds
        ? maxDelay.inMilliseconds
        : exponentialMs;

    final int jitterMs = (_random.nextDouble() * 250).round();
    return ReconnectDecision(
      shouldRetry: true,
      attempt: _attempt,
      delay: Duration(milliseconds: boundedMs + jitterMs),
    );
  }
}
