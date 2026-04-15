import 'package:flutter_test/flutter_test.dart';
import 'package:vai_client/vai_transport.dart';

void main() {
  group('ConnectionLifecycleManager', () {
    test('valid transitions closed -> handshaking -> active -> closing -> closed', () {
      final ConnectionLifecycleManager manager = ConnectionLifecycleManager();

      expect(manager.phase, ConnectionPhase.closed);
      manager.transition(ConnectionPhase.handshaking);
      expect(manager.phase, ConnectionPhase.handshaking);
      manager.transition(ConnectionPhase.active);
      expect(manager.phase, ConnectionPhase.active);
      manager.transition(ConnectionPhase.closing);
      expect(manager.phase, ConnectionPhase.closing);
      manager.transition(ConnectionPhase.closed);
      expect(manager.phase, ConnectionPhase.closed);
    });

    test('invalid transition throws protocol violation', () {
      final ConnectionLifecycleManager manager = ConnectionLifecycleManager();

      expect(
        () => manager.transition(ConnectionPhase.active),
        throwsA(isA<ProtocolException>()),
      );
    });
  });

  group('IntentLifecycleManager', () {
    test('enforces per-intent transitions', () {
      final IntentLifecycleManager manager = IntentLifecycleManager();

      manager.start('intent-1');
      manager.toStreaming('intent-1');
      manager.complete('intent-1');

      expect(manager.phaseOf('intent-1'), IntentPhase.completed);
    });

    test('rejects terminal duplicate transitions', () {
      final IntentLifecycleManager manager = IntentLifecycleManager();

      manager.start('intent-1');
      manager.complete('intent-1');

      expect(
        () => manager.complete('intent-1'),
        throwsA(isA<ProtocolException>()),
      );
    });
  });
}
