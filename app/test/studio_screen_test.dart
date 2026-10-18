import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skittles/studio/scene.dart';
import 'package:skittles/studio/scene_painter.dart';
import 'package:skittles/studio/starter.dart';
import 'package:skittles/studio/studio_controller.dart';
import 'package:skittles/studio/studio_screen.dart';
import 'package:skittles/ui/kit.dart';

final _canvas = find.byWidgetPredicate((w) => w is CustomPaint && w.painter is ScenePainter);
ScenePainter _painter(WidgetTester tester) => tester.widget<CustomPaint>(_canvas).painter! as ScenePainter;

/// Where a point of the scene is on screen right now.
Offset screenOf(WidgetTester tester, Offset world) => tester.getTopLeft(_canvas) + _painter(tester).pan + world * _painter(tester).zoom;

Future<StudioController> pumpStudio(WidgetTester tester, {Size size = const Size(1440, 900)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final studio = StudioController(starterScene());
  await tester.pumpWidget(MaterialApp(theme: skTheme(Brightness.dark), home: StudioScreen(studio: studio, onHome: () {})));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  return studio;
}

void main() {
  testWidgets('a coin placed with the tool lands in the scene and the hierarchy', (tester) async {
    final studio = await pumpStudio(tester);
    await tester.tap(find.byTooltip('Coin (C)'));
    await tester.pump();
    // The canvas sits between the 248px left column and the 320px right column.
    await tester.tapAt(const Offset(248 + (1440 - 248 - 320) / 2, 56 + (900 - 56) / 2));
    await tester.pump();
    expect(studio.scene.objects.where((o) => o.type == SceneObjectType.coin), hasLength(3));
    expect(find.text('Coin 3'), findsWidgets); // in the hierarchy and the inspector
    expect(studio.tool, StudioTool.select);
  });

  testWidgets('the inspector edits the selection and the checks follow', (tester) async {
    final studio = await pumpStudio(tester);
    studio.select('finish');
    await tester.pump();
    expect(find.text('FINISH'), findsOneWidget);
    // Typing a new Y that lifts the finish into the sky blocks the game.
    final yField = find.descendant(of: find.widgetWithText(Row, 'Y'), matching: find.byType(TextField)).first;
    await tester.enterText(yField, '100');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(studio.scene.byId('finish')!.y, 100);
    expect(find.text('Blocked · the finish cannot be reached'), findsOneWidget);
    expect(find.text('The finish cannot be reached.'), findsOneWidget);
  });

  testWidgets('keys on the canvas: tool letters, delete, undo', (tester) async {
    final studio = await pumpStudio(tester);
    await tester.tapAt(const Offset(800, 300)); // focus the canvas
    studio.select('coin-1');
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();
    expect(studio.scene.byId('coin-1'), isNull);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    expect(studio.scene.byId('coin-1'), isNotNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.pump();
    expect(studio.tool, StudioTool.enemy);
  });

  testWidgets('a small object grabbed near its edge follows the mouse', (tester) async {
    final studio = await pumpStudio(tester);
    final coin = studio.scene.byId('coin-1')!;
    final zoom = _painter(tester).zoom;
    final mouse = await tester.startGesture(screenOf(tester, Offset(coin.x + coin.w - 3, coin.y + coin.h / 2)), kind: PointerDeviceKind.mouse);
    for (var i = 0; i < 10; i++) {
      await mouse.moveBy(const Offset(10, 0));
      await tester.pump();
    }
    await mouse.up();
    await tester.pump();
    expect(studio.selectedId, 'coin-1');
    expect(studio.scene.byId('coin-1')!.x - coin.x, closeTo(100 / zoom, StudioController.gridStep));
  });

  testWidgets('a two-finger trackpad scroll pans the view and never moves objects', (tester) async {
    final studio = await pumpStudio(tester);
    final ledge = studio.scene.byId('ledge-a')!;
    final at = screenOf(tester, ledge.rect.center);
    final before = _painter(tester).pan;
    final fingers = await tester.createGesture(kind: PointerDeviceKind.trackpad);
    await fingers.panZoomStart(at);
    for (var i = 1; i <= 5; i++) {
      await fingers.panZoomUpdate(at, pan: Offset(0, 20.0 * i));
      await tester.pump();
    }
    await fingers.panZoomEnd();
    await tester.pump();
    expect(studio.scene.byId('ledge-a')!.y, ledge.y);
    expect(_painter(tester).pan - before, const Offset(0, 100));
  });

  testWidgets('a pinch zooms by how far the fingers spread, around them', (tester) async {
    await pumpStudio(tester);
    final before = _painter(tester).zoom;
    final at = tester.getCenter(_canvas);
    final pinch = await tester.createGesture(kind: PointerDeviceKind.trackpad);
    await pinch.panZoomStart(at);
    for (var i = 0; i < 6; i++) {
      await pinch.panZoomUpdate(at, scale: 1.2); // spread to 1.2× and held
      await tester.pump();
    }
    await pinch.panZoomEnd();
    await tester.pump();
    expect(_painter(tester).zoom, closeTo(before * 1.2, 0.001));
  });

  testWidgets('nothing overflows at the minimum window size, whatever is selected or wrong', (tester) async {
    final studio = await pumpStudio(tester, size: const Size(1280, 720));
    for (final id in ['player', 'finish', 'enemy-1', 'coin-1', 'ledge-a', null]) {
      studio.select(id);
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'selected $id');
    }
    // The longest message: an enemy whose patrol runs backwards.
    final enemy = studio.scene.byId('enemy-1')!;
    studio.update(enemy.withParam('patrol', 'from', 1400).withParam('patrol', 'to', 100));
    await tester.pump();
    expect(studio.report.ok, isFalse);
    expect(tester.takeException(), isNull);
  });

  test('values typed into the inspector keep the object inside the scene', () {
    final studio = StudioController(starterScene());
    final ledge = studio.scene.byId('ledge-a')!;
    studio.update(ledge.copyWith(x: 1550, w: 400));
    final fitted = studio.scene.byId('ledge-a')!;
    expect(fitted.x + fitted.w, lessThanOrEqualTo(studio.scene.width));
    expect(fitted.w, 400);
    studio.update(fitted.copyWith(y: -50, h: 2));
    expect(studio.scene.byId('ledge-a')!.y, 0);
    expect(studio.scene.byId('ledge-a')!.h, 8);
    expect(studio.report.errors.where((e) => e.code == 'out_of_bounds'), isEmpty);
  });

  testWidgets('the scene stays centred when the window changes size', (tester) async {
    await pumpStudio(tester, size: const Size(1280, 720));
    tester.view.physicalSize = const Size(1600, 1000);
    await tester.pump();
    await tester.pump();
    final canvas = tester.getRect(_canvas);
    final p = _painter(tester);
    final scene = Rect.fromLTWH(canvas.left + p.pan.dx, canvas.top + p.pan.dy, 1600 * p.zoom, 900 * p.zoom);
    expect((scene.center.dx - canvas.center.dx).abs(), lessThan(1));
    expect((scene.center.dy - canvas.center.dy).abs(), lessThan(1));
  });
}
