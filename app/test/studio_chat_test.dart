import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skittles/studio/scene.dart';
import 'package:skittles/studio/starter.dart';
import 'package:skittles/studio/studio_controller.dart';
import 'package:skittles/studio/studio_screen.dart';
import 'package:skittles/ui/kit.dart';

import 'fake_link.dart';

Future<(StudioController, FakeLink)> pumpShared(WidgetTester tester, {Scene? scene}) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final link = FakeLink()..join = teamSnapshot(scene ?? starterScene());
  final studio = await StudioController.join(link, server: Uri.parse('http://localhost:3001'), name: 'Nino');
  await tester.pumpWidget(MaterialApp(theme: skTheme(Brightness.dark), home: StudioScreen(studio: studio, onHome: () {})));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  return (studio, link);
}

void main() {
  testWidgets('people show what their agents are doing; your thread shows a teammate\'s request', (tester) async {
    await pumpShared(tester);
    expect(find.text('Nino  you', findRichText: true), findsOneWidget);
    expect(find.text('Giorgi', findRichText: true), findsWidgets);
    expect(find.text('Ana  away', findRichText: true), findsOneWidget);
    expect(find.text('make the right ground a lava pit'), findsOneWidget); // Giorgi's agent at work
    expect(find.text('Agent idle'), findsNWidgets(2)); // Nino's and Ana's
    expect(find.text('Giorgi → your agent'), findsOneWidget);
    expect(find.text('Held: The finish cannot be reached.'), findsOneWidget);
    expect(find.text('Invite · k3x9ab'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a held change waits for Apply anyway or Discard', (tester) async {
    final (_, link) = await pumpShared(tester);
    await tester.tap(find.text('Apply anyway'));
    await tester.pump();
    expect(link.sentAs('approve').single, {'task': 'k3'});
    await tester.tap(find.text('Discard'));
    await tester.pump();
    expect(link.sentAs('discard').single, {'task': 'k3'});
  });

  testWidgets('the team chat shows every agent\'s change with Undo, and @ picks an agent', (tester) async {
    final (_, link) = await pumpShared(tester);
    await tester.tap(find.text('Team'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Your agent · for Giorgi'), findsOneWidget);
    expect(find.text("Giorgi's agent is working…"), findsOneWidget);
    await tester.tap(find.widgetWithText(SkButton, 'Undo'));
    await tester.pump();
    expect(link.sentAs('revert').single, {'change': 2});

    final composer = find.widgetWithText(TextField, 'Message, or @ an agent');
    await tester.enterText(composer, '@gi');
    await tester.pump();
    await tester.tap(find.text("Giorgi's agent").last);
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField).last).controller!.text, "@Giorgi's agent ");
    await tester.enterText(find.byType(TextField).last, "@Giorgi's agent make the pit wider");
    await tester.tap(find.text('Send'));
    await tester.pump();
    expect(link.sentAs('say').single, {'text': "@Giorgi's agent make the pit wider", 'agents': ['m2']});
  });

  testWidgets('a teammate\'s row asks their agent; your own opens your thread', (tester) async {
    final (_, link) = await pumpShared(tester);
    await tester.tap(find.text('Giorgi', findRichText: true).first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.widget<TextField>(find.byType(TextField).last).controller!.text, "@Giorgi's agent ");
    await tester.tap(find.text('Nino  you', findRichText: true));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.widgetWithText(TextField, 'Ask your agent…'), 'make it night');
    await tester.tap(find.text('Send'));
    await tester.pump();
    expect(link.sentAs('ask').single, {'text': 'make it night'});
  });

  testWidgets('news on the other tab shows as a count', (tester) async {
    final (_, link) = await pumpShared(tester);
    link.emit('team', {'id': 't9', 'kind': 'chat', 'from': 'm2', 'text': 'Look at the pit', 'at': 9});
    await tester.pump();
    final badge = find.descendant(of: find.ancestor(of: find.text('Team'), matching: find.byType(Row)).first, matching: find.text('1'));
    expect(badge, findsOneWidget);
    await tester.tap(find.text('Team'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Look at the pit'), findsOneWidget);
    expect(badge, findsNothing);
  });

  testWidgets('a teammate\'s change and pointer show on the canvas', (tester) async {
    final (studio, link) = await pumpShared(tester);
    link.emit('change', {
      'v': 4,
      'by': 'm2',
      'kind': 'edit',
      'patch': {
        'objects': {
          'ledge-b': {...starterScene().byId('ledge-b')!.toJson(), 'x': 600},
        },
      },
      'notes': ['~ Moved Ledge B to (600, 620)'],
    });
    link.emit('presence', {'member': 'm2', 'cursor': {'x': 640, 'y': 600}, 'selected': 'ledge-b'});
    await tester.pump();
    expect(studio.scene.byId('ledge-b')!.x, 600);
    expect(studio.shared!.presence['m2']!.selected, 'ledge-b');
    // A gap means something was missed: the studio asks for the project again.
    link.emit('change', {'v': 9, 'by': 'm2', 'kind': 'edit', 'patch': {'objects': {}}, 'notes': []});
    await tester.pump();
    expect(studio.scene.byId('ledge-b')!.x, starterScene().byId('ledge-b')!.x); // the join answer's scene again
  });

  testWidgets('an empty project asks you to describe the game; Build asks your agent', (tester) async {
    final (studio, link) = await pumpShared(tester, scene: Scene.blank());
    expect(find.text('Describe your game'), findsOneWidget);
    expect(find.text('Empty scene'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'A desert level with three ledges and a few coins'), 'A night level with two ledges');
    await tester.tap(find.text('Build'));
    await tester.pump();
    expect(link.sentAs('ask').single, {'text': 'A night level with two ledges'});
    // Placing something sends it to the project.
    studio.place(SceneObjectType.platform, const Offset(800, 700));
    await tester.pump();
    final edit = link.sentAs('edit').single;
    expect(edit['created'], ['platform-1']);
    expect((edit['objects'] as Map).keys, ['platform-1']);
    // The project confirms it by broadcasting the change.
    link.emit('change', {'v': 4, 'by': 'm1', 'seq': edit['seq'], 'kind': 'edit', 'patch': {'objects': edit['objects']}, 'notes': []});
    await tester.pump();
    expect(studio.scene.byId('platform-1'), isNotNull);
    expect(find.text('Describe your game'), findsNothing);
  });
}
