import 'dart:async';

import 'package:vai_client/src/transport/websocket_adapter.dart';

class FakeSocketConnection implements SocketConnection {
  final StreamController<String> _incoming = StreamController<String>.broadcast();
  final List<String> sentMessages = <String>[];

  bool isClosed = false;

  @override
  Stream<String> get messages => _incoming.stream;

  @override
  void send(String data) {
    sentMessages.add(data);
  }

  void emit(String data) {
    _incoming.add(data);
  }

  void emitError(Object error) {
    _incoming.addError(error);
  }

  Future<void> closeIncoming() async {
    await _incoming.close();
  }

  @override
  Future<void> close([int? code, String? reason]) async {
    isClosed = true;
    if (!_incoming.isClosed) {
      await _incoming.close();
    }
  }
}

class FakeSocketConnector implements SocketConnector {
  FakeSocketConnector(this.connection) : _queue = null;

  FakeSocketConnector.queue(List<FakeSocketConnection> connections)
      : _queue = List<FakeSocketConnection>.from(connections),
        connection = connections.first;

  final FakeSocketConnection connection;
  final List<FakeSocketConnection>? _queue;
  int connectCalls = 0;

  @override
  Future<SocketConnection> connect(Uri uri) async {
    connectCalls += 1;
    if (_queue == null) {
      return connection;
    }

    if (_queue.isEmpty) {
      return connection;
    }

    return _queue.removeAt(0);
  }
}
