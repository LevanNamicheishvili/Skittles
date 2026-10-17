import 'package:flutter_test/flutter_test.dart';
import 'package:skittles/editor/editor_controller.dart';
import 'package:skittles/game/model.dart';

void main() {
  test('the sample level is winnable', () {
    final c = EditorController();
    expect(c.solveResult!.solvable, isTrue);
  });

  test('deleting the bridge blocks the level and undo brings it back', () {
    final c = EditorController();
    c.deleteEntity('M:1');
    expect(c.solveResult!.solvable, isFalse);
    expect(c.solveResult!.unreachable, contains('flag'));

    c.undo();
    expect(c.world.byId('M:1'), isNotNull);
    expect(c.solveResult!.solvable, isTrue);
    c.redo();
    expect(c.world.byId('M:1'), isNull);
  });

  test('dragging with the lava tool draws a rectangle owned by the local player', () {
    final c = EditorController()..newLevel();
    c.setTool(EditorTool.lava);
    c.pointerDown((x: 5, y: 2));
    c.pointerMove((x: 6, y: 9));
    c.pointerUp();

    final lava = c.world.entities.single;
    expect((lava.type, lava.x, lava.y, lava.w, lava.h), (EntityType.lava, 5, 2, 2, 8));
    expect(lava.owner.playerId, 'me');
    expect(c.selectedId, lava.id);
  });

  test('a castle smaller than 3 x 3 is refused with a notice', () {
    final c = EditorController()..newLevel();
    c.setTool(EditorTool.castle);
    c.pointerDown((x: 3, y: 3));
    c.pointerMove((x: 4, y: 3));
    c.pointerUp();

    expect(c.world.entities, isEmpty);
    expect(c.notice.value, contains('3 × 3'));
  });

  test('moving an object by dragging is one undo step', () {
    final c = EditorController();
    final before = c.world.byId('M:2')!;
    c.setTool(EditorTool.select);
    c.pointerDown((x: before.x, y: before.y));
    c.pointerMove((x: before.x + 1, y: before.y));
    c.pointerMove((x: before.x + 2, y: before.y + 1));
    c.pointerUp();
    expect((c.world.byId('M:2')!.x, c.world.byId('M:2')!.y), (before.x + 2, before.y + 1));

    c.undo();
    expect((c.world.byId('M:2')!.x, c.world.byId('M:2')!.y), (before.x, before.y));
  });

  test('play mode: walking into lava counts a fall and restarts', () {
    final c = EditorController()..newLevel();
    c.setTool(EditorTool.lava);
    c.pointerDown((x: 2, y: 7));
    c.pointerUp();
    c.startPlay();
    c.playMove(Direction.right);
    expect(c.playState!.deaths, 1);
    expect((c.playState!.x, c.playState!.y), (1, 7));
    c.stopPlay();
    expect(c.mode, EditorMode.edit);
  });
}
