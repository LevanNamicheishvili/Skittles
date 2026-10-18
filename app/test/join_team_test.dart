import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skittles/net/projects_api.dart';
import 'package:skittles/net/room_client.dart';
import 'package:skittles/net/room_store.dart';
import 'package:skittles/screens/connect_screen.dart';
import 'package:skittles/ui/kit.dart';

void main() {
  test('the project code is found in whatever was pasted', () {
    expect(projectCode('4f2a9c'), '4f2a9c');
    expect(projectCode('  4f2a9c \n'), '4f2a9c');
    expect(projectCode('Join my Skittles project: code 4f2a9c on http://localhost:3001'), '4f2a9c');
    expect(projectCode('Join my Skittles project: code 4f2a9c on https://abc.trycloudflare.com'), '4f2a9c');
    expect(projectCode('something else'), 'something else');
  });

  testWidgets('a second window sees the project its team is in and joins it with one click', (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final joined = <String?>[];
    await tester.pumpWidget(MaterialApp(
      theme: skTheme(Brightness.dark),
      home: ConnectScreen(
        client: RoomClient(RoomStore()),
        name: 'Giorgi',
        findProjects: (server) async => const [OpenProject(id: 'abc123', name: 'Forest platformer', people: ['Nino'])],
        onNewProject: ({required server, required name, project}) async => null,
        onJoinProject: ({required server, required name, project}) async {
          joined.add(project);
          return null;
        },
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Forest platformer  ·  Nino here now', findRichText: true), findsOneWidget);
    await tester.ensureVisible(find.widgetWithText(SkButton, 'Join').first);
    await tester.tap(find.widgetWithText(SkButton, 'Join').first);
    await tester.pump();
    expect(joined, ['abc123']);

    // Pasting the whole invite works too.
    await tester.enterText(find.widgetWithText(TextField, 'Or paste a project code'), 'Join my Skittles project: code 77aa01 on http://localhost:3001');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(joined, ['abc123', '77aa01']);
    expect(tester.takeException(), isNull);
  });
}
