import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:skittles/editor/editor_screen.dart';
import 'package:skittles/main.dart';
import 'package:skittles/net/models.dart';
import 'package:skittles/net/room_client.dart';
import 'package:skittles/net/room_store.dart';
import 'package:skittles/screens/connect_screen.dart';
import 'package:skittles/screens/gallery_screen.dart';
import 'package:skittles/screens/room_screen.dart';
import 'package:skittles/studio/studio_screen.dart';
import 'package:skittles/ui/kit.dart';
import 'package:skittles/ui/theme.dart';

Snapshot recordedSnapshot() {
  final session = jsonDecode(File('../spec/fixtures/protocol/session.json').readAsStringSync()) as Map<String, dynamic>;
  return Snapshot.fromJson(session['snapshot'] as Map<String, dynamic>);
}

void minimumWindow(WidgetTester tester) {
  tester.view.physicalSize = const Size(1280, 720);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('opens dark on the connect screen at the minimum window size', (tester) async {
    minimumWindow(tester);
    await tester.pumpWidget(const SkittlesApp());
    await tester.pump(const Duration(seconds: 2));

    expect(find.byType(ConnectScreen), findsOneWidget);
    expect(find.text('Build any 2D game, with tools and AI'), findsOneWidget);
    expect(find.text('Start creating'), findsOneWidget);
    expect(find.text('Open project…'), findsOneWidget);
    expect(Theme.of(tester.element(find.text('Start creating'))).brightness, Brightness.dark);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the features advance on their own and can be picked', (tester) async {
    minimumWindow(tester);
    await tester.pumpWidget(const SkittlesApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 6100));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining("Nino's agent"), findsWidgets); // the "together" preview shows several agents
    await tester.tap(find.text('Never break the game'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('MEDIATOR'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a project and the demo room ask for a name first', (tester) async {
    minimumWindow(tester);
    await tester.pumpWidget(const SkittlesApp());
    await tester.ensureVisible(find.text('Start creating'));
    await tester.tap(find.text('Start creating'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('Type your name first: your team sees it'), findsOneWidget);
    // The grid demo room's Join is the last one.
    await tester.tap(find.widgetWithText(SkButton, 'Join').last);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Type your name first.'), findsOneWidget);
  });

  testWidgets('Start creating opens an empty studio, offline when there is no server', (tester) async {
    minimumWindow(tester);
    await tester.pumpWidget(SkittlesApp(openLink: (uri) async => throw 'Could not reach a Skittles server at ${uri.origin}.'));
    await tester.enterText(find.widgetWithText(TextField, 'Your name'), 'Nino');
    await tester.ensureVisible(find.text('Start creating'));
    await tester.tap(find.text('Start creating'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(StudioScreen), findsOneWidget);
    expect(find.text('Untitled'), findsWidgets);
    expect(find.text('Empty scene'), findsOneWidget);
    expect(find.text('Describe your game'), findsOneWidget);
    expect(find.text('Working offline'), findsOneWidget);
    // The example is one click away.
    await tester.tap(find.text('Start from the forest example'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Playable · finish reachable'), findsOneWidget);
    expect(find.text('Describe your game'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the room shows the recorded session: version, status, members, history', (tester) async {
    minimumWindow(tester);
    final store = RoomStore()..applySnapshot(recordedSnapshot());
    final client = RoomClient(store);
    await tester.pumpWidget(MaterialApp(theme: skTheme(Brightness.dark), home: RoomScreen(client: client, onLeave: () {})));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('v4'), findsWidgets);
    expect(find.textContaining('Winnable · '), findsOneWidget);
    expect(find.text('Giorgi'), findsOneWidget);
    expect(find.text('Restored version 1'), findsOneWidget);
    expect(find.text('Nino, creator'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the gallery switches theme', (tester) async {
    minimumWindow(tester);
    var dark = true;
    await tester.pumpWidget(StatefulBuilder(
      builder: (context, setState) => MaterialApp(
        theme: skTheme(dark ? Brightness.dark : Brightness.light),
        home: GalleryScreen(dark: dark, onDarkChanged: (v) => setState(() => dark = v)),
      ),
    ));
    await tester.tap(find.widgetWithText(SkToggle, 'Dark'));
    // The first frame starts the theme animation; the second lands after it.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(Theme.of(tester.element(find.byType(GalleryScreen))).brightness, Brightness.light);
  });

  testWidgets('the legacy editor still opens on the sample level', (tester) async {
    minimumWindow(tester);
    await tester.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: const EditorScreen()));

    expect(find.text('Castle Story'), findsWidgets);
    expect(find.textContaining('Winnable'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
