import 'package:flutter/material.dart';

import 'src/ux/chat_controller.dart';
import 'src/ux/chat_page.dart';
import 'src/transport/vai_transport_client.dart';
import 'src/transport/websocket_adapter.dart';

void main() {
  runApp(const MainApp());
}

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  late final ChatController _controller = ChatController(
    transportClient: VaiTransportClient(
      connector: const WebSocketChannelConnector(),
    ),
    serverUri: _serverUriFromEnvironment(),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF000000),
        useMaterial3: true,
      ),
      home: ChatPage(controller: _controller),
    );
  }
}

Uri _serverUriFromEnvironment() {
  const String defaultWebSocketUrl = 'ws://10.0.0.1:8000/ws';
  const String raw = String.fromEnvironment(
    'VAI_WS_URL',
    defaultValue: defaultWebSocketUrl,
  );
  return Uri.tryParse(raw) ?? Uri.parse(defaultWebSocketUrl);
}
