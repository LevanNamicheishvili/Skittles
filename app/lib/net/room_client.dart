// One socket to the room server, speaking the events in docs/guide (Events). Incoming events go to the
// RoomStore; requests that expect an answer use Socket.IO acknowledgements, like the web client.

import 'dart:async';

import 'package:socket_io_client/socket_io_client.dart' as io;

import '../game/model.dart' show Direction;
import 'models.dart';
import 'room_store.dart';

class RoomClient {
  RoomClient(this.store);

  final RoomStore store;
  io.Socket? _socket;
  ({String name, Role role})? _joined;

  static const _events = ['state', 'log', 'chat', 'proposal', 'play', 'members', 'report', 'suggestion'];

  Uri? server;

  /// Connects to the room at [url] (for example http://localhost:3001) and joins it. Throws a message fit for
  /// the connect screen when the room cannot be reached or refuses the join.
  Future<Snapshot> connectAndJoin(String url, String name, Role role, {Duration timeout = const Duration(seconds: 6)}) async {
    await disconnect();
    final uri = Uri.parse(url.contains('://') ? url : 'http://$url');
    server = uri;
    store.setConnection(Connection.connecting);
    final socket = io.io(uri.toString(), <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
      'forceNew': true,
      'reconnection': true,
    });
    _socket = socket;
    final ready = Completer<void>();
    socket.onConnect((_) {
      store.setConnection(Connection.connected);
      if (!ready.isCompleted) {
        ready.complete();
      } else {
        unawaited(_rejoin()); // a reconnect: fetch the room again
      }
    });
    socket.onDisconnect((_) => store.setConnection(Connection.offline));
    socket.onConnectError((e) {
      if (!ready.isCompleted) ready.completeError('Could not reach a Skittles room at ${uri.origin}.');
    });
    for (final event in _events) {
      socket.on(event, (data) => store.handle(event, payloadOf(data)));
    }
    socket.on('reset', (_) => unawaited(_rejoin()));
    socket.connect();
    try {
      await ready.future.timeout(timeout, onTimeout: () => throw 'No answer from ${uri.origin}. Is the server running?');
    } catch (e) {
      await disconnect();
      store.setConnection(Connection.idle, error: '$e');
      rethrow;
    }
    _joined = (name: name, role: role);
    return _rejoin();
  }

  /// The room sends one argument per event, but its Socket.IO server has connection state recovery on, which
  /// appends a string offset to every broadcast. This library hands several arguments over as a list, so a
  /// broadcast arrives as [payload, offset]. The browser client ignores the extra argument; so does this.
  static Object? payloadOf(Object? data) {
    if (data is List && data.length >= 2 && data.last is String) return data.first;
    return data;
  }

  Future<Snapshot> _rejoin() async {
    final joined = _joined!;
    final answer = await _request('join', {'name': joined.name, 'role': joined.role.name});
    final snapshot = Snapshot.fromJson(Map<String, dynamic>.from(answer as Map));
    store.applySnapshot(snapshot);
    return snapshot;
  }

  Future<Object?> _request(String event, Object? data) {
    final socket = _socket;
    if (socket == null) throw StateError('Not connected to a room.');
    final answer = Completer<Object?>();
    socket.emitWithAck(event, data, ack: (Object? reply) {
      if (!answer.isCompleted) answer.complete(reply);
    });
    return answer.future.timeout(const Duration(seconds: 15));
  }

  Future<SubmitResult> _submit(String event, Object? data) async =>
      SubmitResult.fromJson(Map<String, dynamic>.from(await _request(event, data) as Map));

  void _emit(String event, [Object? data]) => _socket?.emit(event, data);

  /// Sends a request to your own agent. Its answer arrives in your chat.
  Future<void> say(String text) async {
    final id = store.you?.id;
    if (id != null) store.startThinking(id);
    await _request('agent:say', {'text': text});
  }

  /// Direct edits without an agent: the debug path tests use (`doc:submit`). The room checks them like any change.
  Future<SubmitResult> submitOps(List<OpJson> ops, {String? summary}) => _submit('doc:submit', {'ops': ops, 'summary': ?summary});

  Future<SubmitResult> choose(String proposalId, String optionId) => _submit('proposal:choose', {'proposalId': proposalId, 'optionId': optionId});
  Future<SubmitResult> answer(String proposalId, {required bool accept}) => _submit('approval:answer', {'proposalId': proposalId, 'accept': accept});
  Future<SubmitResult> revert(int rev) => _submit('history:revert', {'rev': rev});
  Future<SubmitResult> applySuggestion(String id) => _submit('suggestion:apply', {'id': id});
  void dismissSuggestion(String id) => _emit('suggestion:dismiss', {'id': id});
  void move(Direction dir) => _emit('play:move', {'dir': dir.name});
  void restart() => _emit('play:restart');
  Future<Object?> report(String text) => _request('play:report', {'text': text});
  Future<Object?> resetRoom() => _request('room:reset', <String, dynamic>{});

  Future<void> disconnect() async {
    final socket = _socket;
    _socket = null;
    _joined = null;
    if (socket == null) return;
    socket.clearListeners();
    socket.dispose();
  }
}
