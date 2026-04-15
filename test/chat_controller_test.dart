import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vai_client/src/content/content_data.dart';
import 'package:vai_client/src/ux/chat_controller.dart';
import 'package:vai_client/src/transport/vai_transport_client.dart';

import 'helpers/fake_socket.dart';

void main() {
  test('ChatController tracks connection state and maps stream events to chat turns', () async {
    final FakeSocketConnection connection = FakeSocketConnection();
    final ChatController controller = ChatController(
      transportClient: VaiTransportClient(
        connector: FakeSocketConnector(connection),
        handshakeTimeout: const Duration(milliseconds: 200),
      ),
      serverUri: Uri.parse('ws://localhost:8080/ws'),
      intentIdGenerator: () => 'intent-fixed',
    );

    await controller.start();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(controller.connectionState, ChatConnectionIndicatorState.pending);

    connection.emit(_ackMessage());
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(controller.connectionState, ChatConnectionIndicatorState.connected);

    await controller.sendPrompt('Run diagnostics');
    expect(controller.turns.single.prompt, 'Run diagnostics');

    connection.emit(_message('intent_started', 'intent-fixed', <String, Object?>{'text': 'Run diagnostics'}));
    connection.emit(_message('ephemeral', 'intent-fixed', <String, Object?>{'text': 'Planning'}));
    connection.emit(_message('ephemeral', 'intent-fixed', <String, Object?>{'text': 'Executing'}));
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(controller.turns.single.ephemeralLines, <String>['Planning', 'Executing']);

    connection.emit(_message('partial_output', 'intent-fixed', <String, Object?>{
      'index': 0,
      'text': 'Done',
      'is_final_chunk': false,
    }));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(controller.turns.single.partialText, 'Done');
    expect(controller.turns.single.ephemeralLines, isEmpty);

    connection.emit(_message('final_output', 'intent-fixed', <String, Object?>{
      'text': 'Done successfully',
      'status': 'success',
      'summary': null,
      'is_final': true,
    }));
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(controller.turns.single.finalContent, isNotNull);
    expect(controller.turns.single.finalContent!.data, isA<TextContentData>());
    expect(controller.turns.single.finalContent!.primaryText, 'Done successfully');
    expect(controller.turns.single.partialText, isNull);

    controller.dispose();
  });
}

String _ackMessage() {
  return jsonEncode(
    <String, Object?>{
      'type': 'connection_ack',
      'connection_id': '3',
      'intent_id': 'handshake',
      'timestamp': '2026-04-14T10:00:00.000Z',
      'payload': <String, Object?>{
        'server_version': 'v1',
        'protocol_version': 1,
        'capabilities': <String>['streaming'],
      }
    },
  );
}

String _message(String type, String intentId, Map<String, Object?> payload) {
  return jsonEncode(
    <String, Object?>{
      'type': type,
      'connection_id': '3',
      'intent_id': intentId,
      'timestamp': '2026-04-14T10:00:00.000Z',
      'payload': payload,
    },
  );
}
