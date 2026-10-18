import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:skittles/studio/scene.dart';
import 'package:skittles/studio/starter.dart';
import 'package:skittles/studio/studio_controller.dart';

void main() {
  test('the starter scene is the fixture that passes every check', () {
    final fixture = ((jsonDecode(File('../spec/fixtures/scenes.json').readAsStringSync()) as Map)['cases'] as List).first as Map<String, dynamic>;
    expect(jsonEncode(starterScene().toJson()), jsonEncode(Scene.fromJson(fixture['scene'] as Map<String, dynamic>).toJson()));
    final studio = StudioController(starterScene());
    expect(studio.report.ok, isTrue);
    expect(studio.report.label, 'Playable · finish reachable');
  });

  test('placing snaps to the grid, selects, and goes back to the select tool', () {
    final studio = StudioController(starterScene())..setTool(StudioTool.platform);
    final p = studio.place(SceneObjectType.platform, const Offset(503, 401));
    expect(p.x % 8, 0);
    expect(p.y % 8, 0);
    expect(p.name, 'Platform 6'); // the starter already has five
    expect(studio.selectedId, p.id);
    expect(studio.tool, StudioTool.select);
    expect(studio.canUndo, isTrue);
  });

  test('the player tool moves the one player instead of adding another', () {
    final studio = StudioController(starterScene());
    studio.place(SceneObjectType.player, const Offset(400, 600));
    expect(studio.scene.objects.where((o) => o.type == SceneObjectType.player), hasLength(1));
    expect(studio.scene.byId('player')!.x, 384);
  });

  test('a drag is one undo step, and an enemy takes its patrol along', () {
    final studio = StudioController(starterScene())..select('enemy-1');
    studio.beginDrag();
    studio.dragTo(const Offset(30, 0));
    studio.dragTo(const Offset(100, 0));
    studio.endDrag();
    final enemy = studio.scene.byId('enemy-1')!;
    expect(enemy.x, 1104);
    expect(enemy.param('patrol', 'from'), 1004);
    expect(enemy.param('patrol', 'to'), 1404);
    studio.undo();
    expect(studio.scene.byId('enemy-1')!.x, 1000);
    expect(studio.canUndo, isFalse);
    studio.redo();
    expect(studio.scene.byId('enemy-1')!.x, 1104);
  });

  test('breaking the level shows at once: moving the finish onto a high ledge blocks it', () {
    final studio = StudioController(starterScene())..select('finish');
    studio.beginDrag();
    studio.dragTo(const Offset(0, -500));
    studio.endDrag();
    expect(studio.report.ok, isFalse);
    expect(studio.report.errors.single.code, 'finish_unreachable');
    expect(studio.report.label, 'Blocked · the finish cannot be reached');
    studio.undo();
    expect(studio.report.ok, isTrue);
  });

  test('resizing keeps at least 8 px and stays in the scene', () {
    final studio = StudioController(starterScene())..select('ledge-a');
    studio
      ..beginDrag()
      ..resizeTo(const Offset(-1000, -1000))
      ..endDrag();
    final ledge = studio.scene.byId('ledge-a')!;
    expect(ledge.w, 8);
    expect(ledge.h, 8);
  });

  test('deleting clears the selection and can be undone', () {
    final studio = StudioController(starterScene())..select('coin-1');
    studio.deleteSelected();
    expect(studio.scene.byId('coin-1'), isNull);
    expect(studio.selectedId, isNull);
    studio.undo();
    expect(studio.scene.byId('coin-1'), isNotNull);
  });

  test('opening a file resets the history; saving clears the edited mark', () {
    final studio = StudioController(starterScene());
    studio.place(SceneObjectType.coin, const Offset(100, 100));
    expect(studio.dirty, isTrue);
    studio.saved('/tmp/forest.skittles');
    expect(studio.dirty, isFalse);
    studio.load(Scene.fromJson(jsonDecode(studio.encode()) as Map<String, dynamic>), path: '/tmp/forest.skittles');
    expect(studio.canUndo, isFalse);
    expect(studio.scene.objects, hasLength(11));
  });
}
