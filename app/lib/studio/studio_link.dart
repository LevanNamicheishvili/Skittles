// The studio's line to a shared project: the server's Socket.IO namespace /studio. Requests use acknowledgements;
// everything the project broadcasts arrives through onEvent. Tests put their own link in its place.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../net/room_client.dart' show RoomClient;

abstract class StudioLink {
  /// Every event the project sends: change, members, team, thread, history, presence.
  void Function(String event, Object? data)? onEvent;

  /// The connection came back after a drop: the studio joins again.
  VoidCallback? onReconnect;
  ValueChanged<bool>? onConnection;

  Future<Map<String, dynamic>> request(String event, [Map<String, dynamic> data = const {}]);

  /// Fire and forget: presence.
  void send(String event, Map<String, dynamic> data);

  Future<void> close();
}

class SocketStudioLink extends StudioLink {
  SocketStudioLink._(this._socket);

  final io.Socket _socket;

  static const _events = ['change', 'members', 'team', 'thread', 'history', 'presence'];

  /// Connects to the studio on [server] (for example http://localhost:3001). Throws a message fit for the screen when
  /// it cannot be reached.
  static Future<SocketStudioLink> open(Uri server, {Duration timeout = const Duration(seconds: 5)}) async {
    final socket = io.io('${server.origin}/studio', <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
      'forceNew': true,
      'reconnection': true,
    });
    final link = SocketStudioLink._(socket);
    final ready = Completer<void>();
    socket.onConnect((_) {
      link.onConnection?.call(true);
      if (!ready.isCompleted) {
        ready.complete();
      } else {
        link.onReconnect?.call();
      }
    });
    socket.onDisconnect((_) => link.onConnection?.call(false));
    socket.onConnectError((_) {
      if (!ready.isCompleted) ready.completeError('Could not reach a Skittles server at ${server.origin}.');
    });
    for (final event in _events) {
      socket.on(event, (data) => link.onEvent?.call(event, RoomClient.payloadOf(data)));
    }
    socket.connect();
    try {
      await ready.future.timeout(timeout, onTimeout: () => throw 'No answer from ${server.origin}. Is the server running?');
    } catch (_) {
      socket.dispose();
      rethrow;
    }
    return link;
  }

  @override
  Future<Map<String, dynamic>> request(String event, [Map<String, dynamic> data = const {}]) {
    final answer = Completer<Map<String, dynamic>>();
    _socket.emitWithAck(event, data, ack: (Object? reply) {
      if (answer.isCompleted) return;
      final payload = RoomClient.payloadOf(reply);
      answer.complete(payload is Map ? payload.cast<String, dynamic>() : {'ok': false, 'message': 'The server sent no answer.'});
    });
    return answer.future.timeout(const Duration(seconds: 15), onTimeout: () => {'ok': false, 'message': 'The server did not answer in time.'});
  }

  @override
  void send(String event, Map<String, dynamic> data) => _socket.emit(event, data);

  @override
  Future<void> close() async {
    _socket
      ..clearListeners()
      ..dispose();
  }
}
