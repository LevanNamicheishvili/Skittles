import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skittles/studio/play.dart';
import 'package:skittles/studio/play_view.dart';
import 'package:skittles/studio/scene.dart';
import 'package:skittles/studio/starter.dart';
import 'package:skittles/studio/studio_controller.dart';
import 'package:skittles/studio/studio_screen.dart';
import 'package:skittles/ui/kit.dart';

import 'fake_link.dart';

/// Ground, a player, and the finish a short run to the right.
Scene shortRun() => const Scene(name: 'Short run', width: 1600, height: 900, objects: [
      SceneObject(id: 'ground', name: 'Ground', type: SceneObjectType.platform, x: 0, y: 820, w: 1600, h: 80),
      SceneObject(id: 'coin-1', name: 'Coin', type: SceneObjectType.coin, x: 200, y: 780, w: 24, h: 24, behaviours: {
        'collectible': {'points': 10},
      }),
      SceneObject(id: 'finish', name: 'Finish', type: SceneObjectType.finish, x: 300, y: 700, w: 60, h: 120),
      SceneObject(id: 'player', name: 'Player', type: SceneObjectType.player, x: 100, y: 772, w: 32, h: 48, behaviours: {
        'controller': {'speed': 260, 'jump': 640},
      }),
    ]);

Future<StudioController> pumpStudio(WidgetTester tester, StudioController studio) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: skTheme(Brightness.dark), home: StudioScreen(studio: studio, onHome: () {})));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  return studio;
}

Future<(StudioController, FakeLink)> shared(WidgetTester tester, Scene scene, {List<Map<String, dynamic>> team = const []}) async {
  final link = FakeLink()..join = (teamSnapshot(scene)..['team'] = team);
  return (await pumpStudio(tester, await StudioController.join(link, server: Uri.parse('http://localhost:3001'), name: 'Nino')), link);
}

PlaySession session(WidgetTester tester) => tester.widget<PlayView>(find.byType(PlayView)).session;

/// Lets the game run for [seconds] in 60 frames a second.
Future<void> run(WidgetTester tester, double seconds) async {
  for (var i = 0; i < (seconds * 60).round(); i++) {
    await tester.pump(const Duration(microseconds: 16667));
  }
}

void main() {
  testWidgets('Play runs the scene with the keyboard, and Esc goes back to editing', (tester) async {
    await pumpStudio(tester, StudioController(starterScene()));
    await tester.tap(find.widgetWithText(SkButton, 'Play'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(PlayView), findsOneWidget);
    expect(find.text('Stop'), findsOneWidget);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    await run(tester, 1);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    final x = session(tester).game.x;
    expect(x, closeTo(80 + 260, 6)); // a second of running
    expect(find.text('1.0 s'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byType(PlayView), findsNothing);
    expect(find.text('Play'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a finished run can be shared with the team, and replays the same', (tester) async {
    final (_, link) = await shared(tester, shortRun());
    await tester.tap(find.widgetWithText(SkButton, 'Play'));
    await tester.pump();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD);
    await run(tester, 1.5);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyD);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Finished!'), findsOneWidget);
    expect(find.textContaining('10 points · coins 1/1 · no falls'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Anything to tell the team? (optional)'), 'Too short!');
    await tester.tap(find.text('Share with the team'));
    await tester.pump();
    final sent = link.sentAs('playtest:share').single;
    expect(sent['version'], 3);
    expect(sent['note'], 'Too short!');
    // What was sent replays to the same finish.
    final game = Game(shortRun());
    final replayer = RunPlayer(segmentsFromJson(sent['run']));
    while (!replayer.done && !game.won) {
      game.step(replayer.next());
    }
    expect(game.won, isTrue);
    expect(game.frame, session(tester).game.frame);
    expect(find.text('Shared with the team'), findsOneWidget);
  });

  testWidgets('a playtest in the team chat can be watched; the AI\'s problems go to whoever made the objects', (tester) async {
    final (_, link) = await shared(tester, shortRun(), team: [
      {
        'id': 'p1',
        'kind': 'playtest',
        'from': 'ai',
        'for': 'm1',
        'text': 'Short and sweet.',
        'at': 1,
        'playtest': {
          'status': 'done',
          'version': 3,
          'finished': true,
          'coinsMissed': <String>[],
          'result': {'won': true, 'frame': 80, 'score': 10, 'coins': ['coin-1'], 'coinsTotal': 1, 'deaths': 0},
          'run': [
            [120, 2],
          ],
          'summary': 'Short and sweet.',
          'issues': [
            {'text': 'The finish is too close to the start.', 'objects': ['finish'], 'owners': ['m2'], 'kind': 'idea'},
          ],
        },
      },
      {
        'id': 'p2',
        'kind': 'playtest',
        'from': 'm2',
        'text': 'Easy',
        'at': 2,
        'playtest': {
          'status': 'done',
          'version': 3,
          'note': 'Easy',
          'result': {'won': true, 'frame': 81, 'score': 10, 'coins': ['coin-1'], 'coinsTotal': 1, 'deaths': 0},
          'run': [
            [120, 2],
          ],
        },
      },
      {'id': 'p3', 'kind': 'playtest', 'from': 'ai', 'for': 'm2', 'text': '', 'at': 3, 'playtest': {'status': 'playing', 'version': 3}},
    ]);
    await tester.tap(find.text('Team'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('AI playtest · asked by you · v3'), findsOneWidget);
    expect(find.text('Finished in 0.7 s without falling · every coin reachable'), findsOneWidget);
    expect(find.text('Giorgi played · v3'), findsOneWidget);
    expect(find.text('“Easy”'), findsOneWidget);
    expect(find.text('The AI is playing the level…'), findsOneWidget);

    await tester.tap(find.text("Ask Giorgi's agent"));
    await tester.pump();
    expect(link.sentAs('ask').single, {'text': 'From the AI playtest: The finish is too close to the start.', 'agent': 'm2'});

    // The list is newest first: the AI's card is the last one found.
    await tester.ensureVisible(find.text('Watch run').last);
    await tester.pump();
    await tester.tap(find.text('Watch run').last);
    await tester.pump();
    await tester.pump();
    expect(find.text("Watching the AI's run · v3"), findsOneWidget);
    await run(tester, 1);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Finished'), findsOneWidget);
    expect(session(tester).game.frame, 78);
  });

  testWidgets('AI playtest asks the project; the AI needs a finish', (tester) async {
    final (_, link) = await shared(tester, shortRun());
    await tester.tap(find.text('AI playtest'));
    await tester.pump();
    expect(link.sentAs('playtest:ai'), hasLength(1));
    await tester.pump(const Duration(seconds: 5));

    final (empty, _) = await shared(tester, Scene.blank());
    expect(tester.widget<SkButton>(find.widgetWithText(SkButton, 'AI playtest')).onPressed, isNull);
    expect(tester.widget<SkButton>(find.widgetWithText(SkButton, 'Play')).onPressed, isNull);
    expect(empty.isShared, isTrue);
  });
}
