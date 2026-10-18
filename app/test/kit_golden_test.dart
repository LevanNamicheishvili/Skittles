// Snapshots of the component gallery in both themes, with the real San Francisco fonts so they can be compared
// with the site. macOS only (it reads the system font files); refresh with `flutter test --update-goldens`.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:convert';

import 'package:skittles/net/models.dart';
import 'package:skittles/net/room_client.dart';
import 'package:skittles/net/room_store.dart';
import 'package:skittles/screens/connect_screen.dart';
import 'package:skittles/screens/gallery_screen.dart';
import 'package:skittles/screens/room_screen.dart';
import 'package:skittles/studio/scene.dart';
import 'package:skittles/studio/starter.dart';
import 'package:skittles/studio/studio_controller.dart';
import 'package:skittles/studio/studio_screen.dart';
import 'package:skittles/ui/kit.dart';

import 'fake_link.dart';

const _sans = '/System/Library/Fonts/SFNS.ttf';
const _mono = '/System/Library/Fonts/SFNSMono.ttf';
final _haveFonts = File(_sans).existsSync() && File(_mono).existsSync();

Future<void> _load(String family, String path) async {
  final bytes = File(path).readAsBytesSync();
  await (FontLoader(family)..addFont(Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)))).load();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (!_haveFonts) return;
    await _load('SkSans', _sans);
    await _load('SkMono', _mono);
  });

  for (final dark in [true, false]) {
    testWidgets('gallery, ${dark ? 'dark' : 'light'}', (tester) async {
      tester.view.physicalSize = const Size(1280, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      const fonts = SkFonts(sans: 'SkSans', mono: 'SkMono');
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: skTheme(dark ? Brightness.dark : Brightness.light, fonts: fonts),
        home: GalleryScreen(dark: dark, onDarkChanged: (_) {}),
      ));
      await tester.pump(const Duration(seconds: 3));
      await expectLater(find.byType(GalleryScreen), matchesGoldenFile('goldens/gallery_${dark ? 'dark' : 'light'}.png'));
    }, skip: !_haveFonts);
  }

  const fonts = SkFonts(sans: 'SkSans', mono: 'SkMono');

  testWidgets('connect screen', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: skTheme(Brightness.dark, fonts: fonts),
      home: ConnectScreen(client: RoomClient(RoomStore())),
    ));
    // The sky's glyph sheet renders asynchronously.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    // One frame starts the arrival animations; the next lands after them.
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    await expectLater(find.byType(ConnectScreen), matchesGoldenFile('goldens/connect_dark.png'));
  }, skip: !_haveFonts);

  testWidgets('connect screen at the minimum window size', (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: skTheme(Brightness.dark, fonts: fonts),
      home: ConnectScreen(client: RoomClient(RoomStore())),
    ));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 4500));
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.takeException(), isNull);
    await expectLater(find.byType(ConnectScreen), matchesGoldenFile('goldens/connect_min.png'));
  }, skip: !_haveFonts);

  testWidgets('room screen, recorded session', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final session = jsonDecode(File('../spec/fixtures/protocol/session.json').readAsStringSync()) as Map<String, dynamic>;
    final store = RoomStore()..applySnapshot(Snapshot.fromJson(session['snapshot'] as Map<String, dynamic>));
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: skTheme(Brightness.dark, fonts: fonts),
      home: RoomScreen(client: RoomClient(store), onLeave: () {}),
    ));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await expectLater(find.byType(RoomScreen), matchesGoldenFile('goldens/room_dark.png'));
  }, skip: !_haveFonts);

  testWidgets('studio, starter scene with the player selected', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final studio = StudioController(starterScene())..select('player');
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: skTheme(Brightness.dark, fonts: fonts),
      home: StudioScreen(studio: studio, onHome: () {}),
    ));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await expectLater(find.byType(StudioScreen), matchesGoldenFile('goldens/studio_dark.png'));
  }, skip: !_haveFonts);

  testWidgets('studio, a shared project with a team', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final link = FakeLink()..join = teamSnapshot(starterScene());
    final studio = await StudioController.join(link, server: Uri.parse('http://localhost:3001'), name: 'Nino');
    studio.select('coin-1');
    link.emit('presence', {'member': 'm2', 'cursor': {'x': 1180, 'y': 700}, 'selected': 'enemy-1'});
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: skTheme(Brightness.dark, fonts: fonts),
      home: StudioScreen(studio: studio, onHome: () {}),
    ));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await expectLater(find.byType(StudioScreen), matchesGoldenFile('goldens/studio_team_dark.png'));
  }, skip: !_haveFonts);

  testWidgets('studio, a new empty project', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final link = FakeLink()..join = (teamSnapshot(Scene.blank())..['team'] = []..['threads'] = {});
    final studio = await StudioController.join(link, server: Uri.parse('http://localhost:3001'), name: 'Nino');
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: skTheme(Brightness.dark, fonts: fonts),
      home: StudioScreen(studio: studio, onHome: () {}),
    ));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await expectLater(find.byType(StudioScreen), matchesGoldenFile('goldens/studio_empty_dark.png'));
  }, skip: !_haveFonts);

  testWidgets('studio, playing the starter scene', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final link = FakeLink()..join = teamSnapshot(starterScene());
    final studio = await StudioController.join(link, server: Uri.parse('http://localhost:3001'), name: 'Nino');
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: skTheme(Brightness.dark, fonts: fonts),
      home: StudioScreen(studio: studio, onHome: () {}),
    ));
    await tester.pump();
    await tester.tap(find.widgetWithText(SkButton, 'Play'));
    await tester.pump();
    await tester.pump();
    // Run right and jump onto Ledge A.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    for (var i = 0; i < 50; i++) {
      await tester.pump(const Duration(microseconds: 16667));
    }
    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(microseconds: 16667));
    }
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    await expectLater(find.byType(StudioScreen), matchesGoldenFile('goldens/studio_play_dark.png'));
  }, skip: !_haveFonts);

  testWidgets('studio, playtests in the team chat', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final link = FakeLink()
      ..join = (teamSnapshot(starterScene())
        ..['team'] = [
          {
            'id': 'p1',
            'kind': 'playtest',
            'from': 'ai',
            'for': 'm1',
            'text': '',
            'at': 1,
            'playtest': {
              'status': 'done',
              'version': 3,
              'finished': true,
              'coinsMissed': ['coin-2'],
              'result': {'won': true, 'frame': 1104, 'score': 10, 'coins': ['coin-1'], 'coinsTotal': 2, 'deaths': 0},
              'run': [
                [60, 2],
              ],
              'summary': 'A gentle climb to a finish anyone can reach; the second coin is hard to get.',
              'issues': [
                {'text': 'Coin 2 sits right above the enemy on Ledge C; move it 60 px left so it can be taken safely.', 'objects': ['coin-2', 'enemy-1'], 'owners': ['m2'], 'kind': 'problem'},
                {'text': 'The ground gap is the only challenge; a moving enemy near it would add tension.', 'objects': ['ground-1'], 'owners': ['m1'], 'kind': 'idea'},
              ],
            },
          },
          {
            'id': 'p2',
            'kind': 'playtest',
            'from': 'm2',
            'text': 'The jump to Ledge C is tight',
            'at': 2,
            'playtest': {
              'status': 'done',
              'version': 3,
              'note': 'The jump to Ledge C is tight',
              'result': {'won': true, 'frame': 1490, 'score': 20, 'coins': ['coin-1', 'coin-2'], 'coinsTotal': 2, 'deaths': 2},
              'run': [
                [60, 2],
              ],
            },
          },
          {'id': 'p3', 'kind': 'playtest', 'from': 'ai', 'for': 'm2', 'text': '', 'at': 3, 'playtest': {'status': 'playing', 'version': 4}},
        ]);
    final studio = await StudioController.join(link, server: Uri.parse('http://localhost:3001'), name: 'Nino');
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: skTheme(Brightness.dark, fonts: fonts),
      home: StudioScreen(studio: studio, onHome: () {}),
    ));
    await tester.pump();
    await tester.tap(find.text('Team'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await expectLater(find.byType(StudioScreen), matchesGoldenFile('goldens/studio_playtests_dark.png'));
  }, skip: !_haveFonts);
}
