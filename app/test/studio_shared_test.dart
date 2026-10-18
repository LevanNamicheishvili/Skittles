// Two studios in one shared project on a real server: starts its own server on a spare port (never the live room),
// with projects saved to a temporary folder, and checks that edits, undo, chat and presence reach the other side.
// No testWidgets here on purpose: the widget test binding blocks real network connections. Skipped without node.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:skittles/net/projects_api.dart';
import 'package:skittles/studio/play.dart';
import 'package:skittles/studio/scene.dart';
import 'package:skittles/studio/starter.dart';
import 'package:skittles/studio/studio_controller.dart';
import 'package:skittles/studio/studio_link.dart';

const _port = 3096;
final _server = Uri.parse('http://localhost:$_port');
final _haveNode = Process.runSync('which', ['node']).exitCode == 0;

/// Waits until [done] holds, checking every 20 ms for up to two seconds.
Future<void> until(bool Function() done, {int seconds = 2}) async {
  for (var i = 0; i < seconds * 50 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  expect(done(), isTrue);
}

void main() {
  Process? server;
  Directory? data;

  setUpAll(() async {
    if (!_haveNode) return;
    data = Directory.systemTemp.createTempSync('skittles-projects-');
    // No AI engine: the AI player still plays (it is a search), there is just no written review.
    server = await Process.start('node', ['src/index.ts'], workingDirectory: '../server', environment: {'PORT': '$_port', 'SKITTLES_AGENT': 'api', 'ANTHROPIC_API_KEY': '', 'SKITTLES_DATA': data!.path});
    final ready = Completer<void>();
    server!.stdout.transform(utf8.decoder).listen((line) {
      if (line.contains('Skittles room on') && !ready.isCompleted) ready.complete();
    });
    server!.stderr.transform(utf8.decoder).listen((_) {});
    await ready.future.timeout(const Duration(seconds: 20));
  });

  tearDownAll(() {
    server?.kill();
    data?.deleteSync(recursive: true);
  });

  Future<StudioController> open(String name, {String? project, Scene? scene}) async =>
      StudioController.join(await SocketStudioLink.open(_server), server: _server, name: name, project: project, scene: scene);

  test('a second window finds the project its teammate is in, and joins it', () async {
    final nino = await open('Nino');
    addTearDown(nino.dispose);
    final listed = await listOpenProjects(_server.toString());
    final mine = listed.where((p) => p.id == nino.shared!.id).single;
    expect(mine.people, ['Nino']);
    final giorgi = await open('Giorgi', project: mine.id);
    addTearDown(giorgi.dispose);
    await until(() => nino.shared!.people.length == 2);
    expect((await listOpenProjects(_server.toString())).where((p) => p.id == mine.id).single.people, ['Nino', 'Giorgi']);
  }, skip: !_haveNode);

  test('a new project starts empty, and a teammate joins it by its code', () async {
    final nino = await open('Nino');
    addTearDown(nino.dispose);
    expect(nino.isShared, isTrue);
    expect(nino.scene.objects, isEmpty);
    expect(nino.scene.name, 'Untitled');
    final giorgi = await open('Giorgi', project: nino.shared!.id);
    addTearDown(giorgi.dispose);
    await until(() => nino.shared!.members.length == 2);
    expect(giorgi.shared!.people.map((m) => m.name), ['Giorgi', 'Nino']);
  }, skip: !_haveNode);

  test('edits reach the teammate, keep their author, and undo is your own', () async {
    final nino = await open('Nino', scene: starterScene());
    addTearDown(nino.dispose);
    final giorgi = await open('Giorgi', project: nino.shared!.id);
    addTearDown(giorgi.dispose);

    final coin = nino.place(SceneObjectType.coin, const Offset(600, 560));
    expect(nino.scene.byId(coin.id), isNotNull); // shows at once
    await until(() => giorgi.scene.byId(coin.id) != null);
    expect(giorgi.scene.byId(coin.id)!.by, nino.shared!.you);

    giorgi
      ..select('ledge-b')
      ..beginDrag()
      ..dragTo(const Offset(40, 0))
      ..endDrag();
    await until(() => nino.scene.byId('ledge-b')!.x == 600);
    await until(() => nino.canUndo && giorgi.canUndo);

    // Nino's undo takes back Nino's coin, not Giorgi's move.
    nino.undo();
    await until(() => giorgi.scene.byId(coin.id) == null);
    expect(giorgi.scene.byId('ledge-b')!.x, 600);
    await until(() => nino.canRedo);
    nino.redo();
    await until(() => giorgi.scene.byId(coin.id) != null);
  }, skip: !_haveNode);

  test('two people creating at once both keep their object', () async {
    final nino = await open('Nino', scene: starterScene());
    addTearDown(nino.dispose);
    final giorgi = await open('Giorgi', project: nino.shared!.id);
    addTearDown(giorgi.dispose);
    final a = nino.place(SceneObjectType.platform, const Offset(300, 300));
    final b = giorgi.place(SceneObjectType.platform, const Offset(900, 300));
    expect(a.id, b.id); // both thought platform-1 was free
    await until(() => nino.scene.objects.where((o) => o.type == SceneObjectType.platform).length == 7 && giorgi.scene.objects.where((o) => o.type == SceneObjectType.platform).length == 7);
    expect(nino.scene.toJson(), giorgi.scene.toJson());
  }, skip: !_haveNode);

  test('the team chat and where people point', () async {
    final nino = await open('Nino', scene: starterScene());
    addTearDown(nino.dispose);
    final giorgi = await open('Giorgi', project: nino.shared!.id);
    addTearDown(giorgi.dispose);
    expect(await giorgi.sayToTeam('Let us make it a night level'), isNull);
    await until(() => nino.shared!.team.isNotEmpty);
    expect(nino.shared!.team.single.text, 'Let us make it a night level');
    expect(nino.shared!.unreadTeam, 1);

    giorgi
      ..select('finish')
      ..pointAt(const Offset(400, 300));
    final id = giorgi.shared!.you;
    await until(() => nino.shared!.presence[id]?.cursor == const Offset(400, 300));
    expect(nino.shared!.presence[id]!.selected, 'finish');
  }, skip: !_haveNode);

  test('the AI\'s run, found on the server, plays the same here; a shared run gets the same result there', () async {
    final nino = await open('Nino', scene: starterScene());
    addTearDown(nino.dispose);
    expect(await nino.playtestWithAi(), isNull);
    await until(() => nino.shared!.team.any((m) => m.playtest?.status == 'done'), seconds: 20);
    final ai = nino.shared!.team.lastWhere((m) => m.kind == 'playtest').playtest!;
    expect(ai.finished, isTrue);
    expect(ai.coinsMissed, isEmpty);
    final game = Game(starterScene());
    final player = RunPlayer(ai.run);
    while (!player.done && !game.won) {
      game.step(player.next());
    }
    expect(game.won, isTrue);
    expect(game.frame, ai.result!.frame);
    expect(game.deaths, 0);

    // Nino replays the AI's inputs and shares them as her own run: the project gets the same numbers.
    expect(await nino.shareRun(nino.version, ai.run, note: 'Copied the AI'), isNull);
    await until(() => nino.shared!.team.any((m) => m.from == nino.shared!.you && m.kind == 'playtest'));
    final mine = nino.shared!.team.lastWhere((m) => m.from == nino.shared!.you).playtest!;
    expect(mine.result!.frame, game.frame);
    expect(mine.note, 'Copied the AI');
  }, skip: !_haveNode);

  test('a project that is not there says so', () async {
    await expectLater(open('Nino', project: 'nope00'), throwsA(contains('no project nope00')));
  }, skip: !_haveNode);
}
