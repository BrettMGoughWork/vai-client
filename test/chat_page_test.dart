import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vai_client/src/transport/vai_transport_client.dart';
import 'package:vai_client/src/ux/chat_controller.dart';
import 'package:vai_client/src/ux/chat_page.dart';
import 'package:vai_client/src/ux/shimmer_text.dart';

import 'helpers/fake_socket.dart';

void main() {
  testWidgets('ChatPage renders title, connection dot, user prompt, and replaces ephemeral progress with final text', (WidgetTester tester) async {
    final FakeSocketConnection connection = FakeSocketConnection();
    final ChatController controller = ChatController(
      transportClient: VaiTransportClient(
        connector: FakeSocketConnector(connection),
        handshakeTimeout: const Duration(milliseconds: 200),
      ),
      serverUri: Uri.parse('ws://localhost:8080/ws'),
      intentIdGenerator: () => 'intent-fixed',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ChatPage(controller: controller),
      ),
    );

    expect(find.text('Vai'), findsOneWidget);

    connection.emit(_ackMessage());
    await tester.pump(const Duration(milliseconds: 30));

    final Container dot = tester.widget<Container>(find.byKey(const Key('connection-indicator-dot')));
    final BoxDecoration decoration = dot.decoration! as BoxDecoration;
    expect(decoration.color, const Color(0xFF2BD576));

    await tester.enterText(find.byKey(const Key('chat-input')), 'Start analysis');
    await tester.tap(find.byKey(const Key('submit-button')));
    await tester.pump();

    expect(find.text('Start analysis'), findsOneWidget);
    expect(connection.sentMessages.last, contains('intent_started'));

    connection.emit(_message('intent_started', 'intent-fixed', <String, Object?>{'text': 'Start analysis'}));
    connection.emit(_message('ephemeral', 'intent-fixed', <String, Object?>{'text': 'Planning'}));
    connection.emit(_message('ephemeral', 'intent-fixed', <String, Object?>{'text': 'Calling tools'}));
    await tester.pump(const Duration(milliseconds: 30));

    expect(find.text('Planning'), findsOneWidget);
    expect(find.text('Calling tools'), findsOneWidget);
    expect(find.byType(ShimmerText), findsOneWidget);

    connection.emit(_message('final_output', 'intent-fixed', <String, Object?>{
      'text': 'Analysis complete.',
      'status': 'success',
      'summary': null,
      'is_final': true,
    }));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 260));

    expect(find.text('Analysis complete.'), findsOneWidget);
    expect(find.text('Planning'), findsNothing);
    expect(find.text('Calling tools'), findsNothing);

    controller.dispose();
  });
}

String _ackMessage() {
  return jsonEncode(
    <String, Object?>{
      'type': 'connection_ack',
      'connection_id': '5',
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
      'connection_id': '5',
      'intent_id': intentId,
      'timestamp': '2026-04-14T10:00:00.000Z',
      'payload': payload,
    },
  );
}
