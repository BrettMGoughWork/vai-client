import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:vai_client/vai_transport.dart';

import 'helpers/fake_socket.dart';

void main() {
  group('VaiTransportClient handshake', () {
    test('sends connection_init first', () async {
      final FakeSocketConnection connection = FakeSocketConnection();
      final VaiTransportClient client = VaiTransportClient(
        connector: FakeSocketConnector(connection),
        handshakeTimeout: const Duration(milliseconds: 200),
        connectionIdGenerator: () => 'conn-fixed',
        clock: () => DateTime.utc(2026, 4, 14, 10, 0),
      );

      unawaited(client.connect(Uri.parse('ws://localhost:8080/ws')));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final Map<String, dynamic> first =
          jsonDecode(connection.sentMessages.first) as Map<String, dynamic>;
      expect(first['type'], 'connection_init');

      await client.dispose();
    });

    test('blocks domain send before ack', () async {
      final FakeSocketConnection connection = FakeSocketConnection();
      final VaiTransportClient client = VaiTransportClient(
        connector: FakeSocketConnector(connection),
        handshakeTimeout: const Duration(milliseconds: 200),
        connectionIdGenerator: () => 'conn-fixed',
      );

      unawaited(client.connect(Uri.parse('ws://localhost:8080/ws')));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(
        () => client.sendIntentStarted(intentId: 'i1', text: 'hello'),
        throwsA(isA<ProtocolException>()),
      );

      await client.dispose();
    });

    test('transitions to active on valid ack and negotiates capabilities', () async {
      final FakeSocketConnection connection = FakeSocketConnection();
      final VaiTransportClient client = VaiTransportClient(
        connector: FakeSocketConnector(connection),
        handshakeTimeout: const Duration(milliseconds: 300),
        connectionIdGenerator: () => 'conn-fixed',
      );

      final List<VaiTransportEvent> events = <VaiTransportEvent>[];
      final StreamSubscription<VaiTransportEvent> sub =
          client.events.listen(events.add);

      unawaited(client.connect(Uri.parse('ws://localhost:8080/ws')));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      connection.emit(_ackMessage(capabilities: <String>['stt', 'streaming', 'other']));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(client.connectionPhase, ConnectionPhase.active);
      expect(client.negotiatedCapabilities, <String>{'stt', 'streaming'});
      expect(
        events.whereType<ConnectionStateChangedEvent>().map((e) => e.to),
        contains(ConnectionPhase.active),
      );

      await sub.cancel();
      await client.dispose();
    });

    test('fails on malformed ack', () async {
      final FakeSocketConnection connection = FakeSocketConnection();
      final VaiTransportClient client = VaiTransportClient(
        connector: FakeSocketConnector(connection),
        handshakeTimeout: const Duration(milliseconds: 200),
        connectionIdGenerator: () => 'conn-fixed',
      );

      final List<VaiTransportEvent> events = <VaiTransportEvent>[];
      final StreamSubscription<VaiTransportEvent> sub =
          client.events.listen(events.add);

      unawaited(client.connect(Uri.parse('ws://localhost:8080/ws')));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      connection.emit(
        jsonEncode(<String, Object?>{
          'type': 'connection_ack',
          'connection_id': 'conn-fixed',
          'intent_id': 'handshake',
          'timestamp': '2026-04-14T10:00:00.000Z',
          'payload': <String, Object?>{
            'protocol_version': 1,
            'capabilities': <String>['stt']
          }
        }),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(
        events.whereType<ProtocolErrorEvent>().last.error.code,
        ProtocolErrorCode.handshakeFailed,
      );

      await sub.cancel();
      await client.dispose();
    });

    test('fails on handshake timeout', () async {
      final FakeSocketConnection connection = FakeSocketConnection();
      final VaiTransportClient client = VaiTransportClient(
        connector: FakeSocketConnector(connection),
        handshakeTimeout: const Duration(milliseconds: 40),
        connectionIdGenerator: () => 'conn-fixed',
      );

      final List<VaiTransportEvent> events = <VaiTransportEvent>[];
      final StreamSubscription<VaiTransportEvent> sub =
          client.events.listen(events.add);

      unawaited(client.connect(Uri.parse('ws://localhost:8080/ws')));
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(
        events.whereType<ProtocolErrorEvent>().any(
              (ProtocolErrorEvent event) =>
                  event.error.code == ProtocolErrorCode.handshakeFailed,
            ),
        isTrue,
      );

      await sub.cancel();
      await client.dispose();
    });

    test('emits UNKNOWN_TYPE protocol error for unknown legacy type', () async {
      final FakeSocketConnection connection = FakeSocketConnection();
      final VaiTransportClient client = VaiTransportClient(
        connector: FakeSocketConnector(connection),
        handshakeTimeout: const Duration(milliseconds: 200),
        connectionIdGenerator: () => 'conn-fixed',
      );

      final List<VaiTransportEvent> events = <VaiTransportEvent>[];
      final StreamSubscription<VaiTransportEvent> sub =
          client.events.listen(events.add);

      unawaited(client.connect(Uri.parse('ws://localhost:8080/ws')));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      connection.emit(_ackMessage());
      connection.emit(
        jsonEncode(<String, Object?>{
          'type': 'unrecognized_type',
          'connection_id': 'conn-fixed',
          'intent_id': 'intent-1',
          'timestamp': '2026-04-14T10:00:00.000Z',
          'payload': <String, Object?>{'text': 'bad'},
        }),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(
        events.whereType<ProtocolErrorEvent>().any(
              (ProtocolErrorEvent event) =>
                  event.error.code == ProtocolErrorCode.unknownType,
            ),
        isTrue,
      );

      await sub.cancel();
      await client.dispose();
    });
  });

  group('VaiTransportClient streaming', () {
    test('in-order stream grows assembled preview and completes once', () async {
      final _Harness harness = await _Harness.connected();

      harness.connection.emit(_message('intent_started', 'intent-1', <String, Object?>{'text': 'prompt'}));
      harness.connection.emit(_message('ephemeral', 'intent-1', <String, Object?>{'text': 'thinking'}));
      harness.connection.emit(_message('partial_output', 'intent-1', _partialPayload(0, 'A')));
      harness.connection.emit(_message('partial_output', 'intent-1', _partialPayload(1, 'B')));
      harness.connection.emit(_message('partial_output', 'intent-1', _partialPayload(2, 'C')));
      harness.connection.emit(_message('final_output', 'intent-1', _finalPayload('ABC')));
      await harness.flush();

      final List<StreamChunkEvent> chunks = harness.events.whereType<StreamChunkEvent>().toList();
      expect(chunks.map((event) => event.assembledPreview), <String>['A', 'AB', 'ABC']);
      expect(harness.events.whereType<StreamStartedEvent>(), hasLength(1));
      expect(harness.events.whereType<StreamCompletedEvent>(), hasLength(1));
      expect(harness.events.whereType<StreamCompletedEvent>().single.finalText, 'ABC');

      final List<ContentEvent> contentEvents = harness.events.whereType<ContentEvent>().toList();
      expect(contentEvents.first.kind, ContentDeliveryKind.ephemeral);
      expect(contentEvents.last.kind, ContentDeliveryKind.finalResponse);
      expect(contentEvents.last.text, 'ABC');

      await harness.dispose();
    });

    test('duplicate partial is ignored idempotently', () async {
      final _Harness harness = await _Harness.connected();

      harness.connection.emit(_message('intent_started', 'intent-2', <String, Object?>{'text': 'prompt'}));
      harness.connection.emit(_message('partial_output', 'intent-2', _partialPayload(0, 'Hi')));
      harness.connection.emit(_message('partial_output', 'intent-2', _partialPayload(0, 'Hi')));
      harness.connection.emit(_message('partial_output', 'intent-2', _partialPayload(1, '!')));
      harness.connection.emit(_message('final_output', 'intent-2', _finalPayload('Hi!')));
      await harness.flush();

      final List<StreamChunkEvent> chunks = harness.events.whereType<StreamChunkEvent>().toList();
      expect(chunks.map((event) => event.index), <int>[0, 1]);
      expect(harness.events.whereType<StreamCompletedEvent>().single.finalText, 'Hi!');

      await harness.dispose();
    });

    test('out-of-order partial is buffered and drained when gap closes', () async {
      final _Harness harness = await _Harness.connected();

      harness.connection.emit(_message('intent_started', 'intent-3', <String, Object?>{'text': 'prompt'}));
      harness.connection.emit(_message('partial_output', 'intent-3', _partialPayload(0, 'A')));
      harness.connection.emit(_message('partial_output', 'intent-3', _partialPayload(2, 'C')));
      harness.connection.emit(_message('partial_output', 'intent-3', _partialPayload(1, 'B')));
      harness.connection.emit(_message('final_output', 'intent-3', _finalPayload('ABC')));
      await harness.flush();

      expect(
        harness.events.whereType<StreamOutOfOrderBufferedEvent>().single.index,
        2,
      );
      expect(
        harness.events.whereType<StreamChunkEvent>().map((event) => event.assembledPreview),
        <String>['A', 'AB', 'ABC'],
      );

      await harness.dispose();
    });

    test('late partial after final is rejected by lifecycle guard', () async {
      final _Harness harness = await _Harness.connected();

      harness.connection.emit(_message('intent_started', 'intent-4', <String, Object?>{'text': 'prompt'}));
      harness.connection.emit(_message('partial_output', 'intent-4', _partialPayload(0, 'A')));
      harness.connection.emit(_message('final_output', 'intent-4', _finalPayload('A')));
      harness.connection.emit(_message('partial_output', 'intent-4', _partialPayload(1, 'B')));
      await harness.flush();

      expect(harness.events.whereType<StreamCompletedEvent>(), hasLength(1));
      expect(
        harness.events.whereType<ProtocolErrorEvent>().any(
              (ProtocolErrorEvent event) =>
                  event.error.code == ProtocolErrorCode.protocolViolation,
            ),
        isTrue,
      );

      await harness.dispose();
    });

    test('unknown intent stream emits protocol violation and no completion', () async {
      final _Harness harness = await _Harness.connected();

      harness.connection.emit(_message('partial_output', 'intent-unknown', _partialPayload(0, 'A')));
      harness.connection.emit(_message('final_output', 'intent-unknown', _finalPayload('A')));
      await harness.flush();

      expect(harness.events.whereType<StreamCompletedEvent>(), isEmpty);
      expect(
        harness.events.whereType<ProtocolErrorEvent>().where(
              (ProtocolErrorEvent event) =>
                  event.error.code == ProtocolErrorCode.protocolViolation,
            ),
        hasLength(2),
      );

      await harness.dispose();
    });

    test('final reconciliation mismatch prefers server final text', () async {
      final _Harness harness = await _Harness.connected();

      harness.connection.emit(_message('intent_started', 'intent-5', <String, Object?>{'text': 'prompt'}));
      harness.connection.emit(_message('partial_output', 'intent-5', _partialPayload(0, 'hello ')));
      harness.connection.emit(_message('partial_output', 'intent-5', _partialPayload(1, 'there')));
      harness.connection.emit(_message('final_output', 'intent-5', _finalPayload('hello world')));
      await harness.flush();

      expect(
        harness.events.whereType<StreamReconciledEvent>().single.hadMismatch,
        isTrue,
      );
      expect(
        harness.events.whereType<StreamCompletedEvent>().single.finalText,
        'hello world',
      );
      expect(
        harness.events.whereType<ContentEvent>().last.text,
        'hello world',
      );

      await harness.dispose();
    });

    test('streaming timeout transitions intent to errored', () async {
      final FakeSocketConnection connection = FakeSocketConnection();
      final VaiTransportClient client = VaiTransportClient(
        connector: FakeSocketConnector(connection),
        handshakeTimeout: const Duration(milliseconds: 200),
        streamInactivityTimeout: const Duration(milliseconds: 40),
        connectionIdGenerator: () => 'conn-fixed',
      );
      final List<VaiTransportEvent> events = <VaiTransportEvent>[];
      final StreamSubscription<VaiTransportEvent> sub =
          client.events.listen(events.add);

      unawaited(client.connect(Uri.parse('ws://localhost:8080/ws')));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      connection.emit(_ackMessage());
      await Future<void>.delayed(const Duration(milliseconds: 10));

      connection.emit(_message('intent_started', 'intent-timeout', <String, Object?>{'text': 'prompt'}));
      connection.emit(_message('partial_output', 'intent-timeout', _partialPayload(0, 'A')));
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(
        events.whereType<ProtocolErrorEvent>().any(
              (ProtocolErrorEvent event) =>
                  event.error.message == 'Streaming inactivity timeout',
            ),
        isTrue,
      );
      expect(
        events.whereType<IntentStateChangedEvent>().last.to,
        IntentPhase.errored,
      );

      await sub.cancel();
      await client.dispose();
    });

    test('outbound intent can receive terminal error without inbound intent_started', () async {
      final _Harness harness = await _Harness.connected();

      await harness.client.sendIntentStarted(
        intentId: 'intent-outbound-error',
        text: 'scrobble emily by joanna newsom',
      );
      harness.connection.emit(
        _message('error', 'intent-outbound-error', <String, Object?>{
          'code': 'UNIMPLEMENTED',
          'message': 'not implemented',
        }),
      );
      await harness.flush();

      expect(
        harness.events.whereType<ProtocolErrorEvent>().where(
              (ProtocolErrorEvent event) =>
                  event.error.code == ProtocolErrorCode.protocolViolation,
            ),
        isEmpty,
      );
      expect(
        harness.events.whereType<IntentStateChangedEvent>().any(
              (IntentStateChangedEvent event) =>
                  event.intentId == 'intent-outbound-error' &&
                  event.to == IntentPhase.errored,
            ),
        isTrue,
      );

      await harness.dispose();
    });

    test('reconnect emits interruption event and re-handshakes', () async {
      final FakeSocketConnection first = FakeSocketConnection();
      final FakeSocketConnection second = FakeSocketConnection();
      final FakeSocketConnector connector =
          FakeSocketConnector.queue(<FakeSocketConnection>[first, second]);
      final VaiTransportClient client = VaiTransportClient(
        connector: connector,
        reconnectPolicy: ReconnectPolicy(
          baseDelay: const Duration(milliseconds: 1),
          maxDelay: const Duration(milliseconds: 1),
          maxAttempts: 1,
          random: _ZeroRandom(),
        ),
        handshakeTimeout: const Duration(milliseconds: 200),
        connectionIdGenerator: () => 'conn-fixed',
      );
      final List<VaiTransportEvent> events = <VaiTransportEvent>[];
      final StreamSubscription<VaiTransportEvent> sub =
          client.events.listen(events.add);

      unawaited(client.connect(Uri.parse('ws://localhost:8080/ws')));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      first.emit(_ackMessage());
      first.emit(_message('intent_started', 'intent-r1', <String, Object?>{'text': 'prompt'}));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      first.emitError(StateError('network dropped'));
  await Future<void>.delayed(const Duration(milliseconds: 40));
      second.emit(_ackMessage());
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(connector.connectCalls, 2);
      expect(
        events.whereType<IntentInterruptedEvent>().map((e) => e.intentId),
        contains('intent-r1'),
      );
      expect(client.connectionPhase, ConnectionPhase.active);

      await sub.cancel();
      await client.dispose();
    });
  });
}

class _ZeroRandom implements Random {
  @override
  bool nextBool() => false;

  @override
  double nextDouble() => 0;

  @override
  int nextInt(int max) => 0;
}

class _Harness {
  _Harness({
    required this.client,
    required this.connection,
    required this.events,
    required this.subscription,
  });

  final VaiTransportClient client;
  final FakeSocketConnection connection;
  final List<VaiTransportEvent> events;
  final StreamSubscription<VaiTransportEvent> subscription;

  static Future<_Harness> connected() async {
    final FakeSocketConnection connection = FakeSocketConnection();
    final VaiTransportClient client = VaiTransportClient(
      connector: FakeSocketConnector(connection),
      handshakeTimeout: const Duration(milliseconds: 200),
      streamInactivityTimeout: const Duration(milliseconds: 150),
      connectionIdGenerator: () => 'conn-fixed',
    );
    final List<VaiTransportEvent> events = <VaiTransportEvent>[];
    final StreamSubscription<VaiTransportEvent> subscription =
        client.events.listen(events.add);
    final _Harness harness = _Harness(
      client: client,
      connection: connection,
      events: events,
      subscription: subscription,
    );

    unawaited(client.connect(Uri.parse('ws://localhost:8080/ws')));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    connection.emit(_ackMessage());
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return harness;
  }

  Future<void> flush() async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }

  Future<void> dispose() async {
    await subscription.cancel();
    await client.dispose();
  }
}

String _ackMessage({List<String> capabilities = const <String>['streaming']}) {
  return jsonEncode(
    <String, Object?>{
      'type': 'connection_ack',
      'connection_id': 'conn-fixed',
      'intent_id': 'handshake',
      'timestamp': '2026-04-14T10:00:00.000Z',
      'payload': <String, Object?>{
        'server_version': 'v1',
        'protocol_version': 1,
        'capabilities': capabilities,
      }
    },
  );
}

String _message(String type, String intentId, Map<String, Object?> payload) {
  return jsonEncode(
    <String, Object?>{
      'type': type,
      'connection_id': 'conn-fixed',
      'intent_id': intentId,
      'timestamp': '2026-04-14T10:00:00.000Z',
      'payload': payload,
    },
  );
}

Map<String, Object?> _partialPayload(int index, String text) {
  return <String, Object?>{
    'index': index,
    'text': text,
    'is_final_chunk': false,
  };
}

Map<String, Object?> _finalPayload(String text, {String status = 'success'}) {
  return <String, Object?>{
    'text': text,
    'status': status,
    'summary': null,
    'is_final': true,
  };
}
