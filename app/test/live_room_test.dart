// Joins a real room server over a real socket. Starts its own server on a spare port (never the live room),
// joins as two authors, and checks a change by one reaches the other. Skipped when node is not installed.
// No testWidgets here on purpose: the widget test binding blocks real network connections.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:skittles/net/models.dart';
import 'package:skittles/net/room_client.dart';
import 'package:skittles/net/room_store.dart';

const _port = 3097;
final _haveNode = Process.runSync('which', ['node']).exitCode == 0;

void main() {
  Process? server;

  setUpAll(() async {
    if (!_haveNode) return;
    server = await Process.start('node', ['src/index.ts'], workingDirectory: '../server', environment: {'PORT': '$_port', 'SKITTLES_AGENT': 'cli'});
    final ready = Completer<void>();
    server!.stdout.transform(utf8.decoder).listen((line) {
      if (line.contains('Skittles room on') && !ready.isCompleted) ready.complete();
    });
    server!.stderr.transform(utf8.decoder).listen((_) {});
    await ready.future.timeout(const Duration(seconds: 20));
  });

  tearDownAll(() => server?.kill());

  test('joins, sees the room, and gets another author\'s change live', () async {
    final nino = RoomClient(RoomStore());
    final giorgi = RoomClient(RoomStore());
    addTearDown(() async {
      await nino.disconnect();
      await giorgi.disconnect();
    });

    final snapshot = await nino.connectAndJoin('localhost:$_port', 'Nino', Role.author);
    expect(snapshot.you.letter, 'A');
    expect(nino.store.connection, Connection.connected);
    expect(nino.store.state!.solve.solvable, isTrue);
    final startRev = nino.store.state!.rev;

    await giorgi.connectAndJoin('http://localhost:$_port', 'Giorgi', Role.author);
    expect(nino.store.members.map((m) => m.name), contains('Giorgi'));

    final result = await giorgi.submitOps([
      {'op': 'create', 'entity': {'id': 'new', 'type': 'wall', 'owner': {'kind': 'assistant'}, 'x': 3, 'y': 2, 'w': 1, 'h': 1, 'label': 'Rock'}},
    ], summary: 'A rock');
    expect(result, isA<Committed>());

    // Nino's client hears about it without asking.
    for (var i = 0; i < 50 && nino.store.state!.rev == startRev; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(nino.store.state!.rev, startRev + 1);
    expect(nino.store.log.last.summary, 'A rock');
    expect(nino.store.member(nino.store.log.last.by)?.name, 'Giorgi');
  }, skip: !_haveNode);

  test('a room that is not there gives a readable error', () async {
    final client = RoomClient(RoomStore());
    await expectLater(client.connectAndJoin('localhost:9', 'Nino', Role.author, timeout: const Duration(seconds: 3)), throwsA(isA<String>()));
    expect(client.store.error, isNotNull);
    expect(client.store.connection, Connection.idle);
  });
}
