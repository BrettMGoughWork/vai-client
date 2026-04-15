import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

abstract class SocketConnection {
  Stream<String> get messages;
  void send(String data);
  Future<void> close([int? code, String? reason]);
}

abstract class SocketConnector {
  Future<SocketConnection> connect(Uri uri);
}

class WebSocketChannelConnector implements SocketConnector {
  const WebSocketChannelConnector();

  @override
  Future<SocketConnection> connect(Uri uri) async {
    final WebSocketChannel channel = WebSocketChannel.connect(uri);
    return _ChannelConnection(channel);
  }
}

class _ChannelConnection implements SocketConnection {
  _ChannelConnection(this._channel);

  final WebSocketChannel _channel;

  @override
  Stream<String> get messages => _channel.stream.map((dynamic data) {
        if (data is String) {
          return data;
        }
        return jsonEncode(data);
      });

  @override
  void send(String data) {
    _channel.sink.add(data);
  }

  @override
  Future<void> close([int? code, String? reason]) async {
    await _channel.sink.close(code, reason);
  }
}
