import 'package:flutter_test/flutter_test.dart';
import 'package:skittles/studio/actions.dart';
import 'package:skittles/studio/scene.dart';
import 'package:skittles/studio/starter.dart';
import 'package:skittles/studio/validate.dart';

SceneAction a(String type, [Map<String, dynamic> fields = const {}]) => SceneAction(type, {'type': type, ...fields});

void main() {
  test('CREATE_OBJECT names, sizes and keeps the object inside', () {
    final r = applyActions(starterScene(), [
      a('CREATE_OBJECT', {'objectType': 'platform', 'x': 1500, 'y': 500, 'w': 300}),
      a('CREATE_OBJECT', {'objectType': 'coin', 'x': 600, 'y': 560, 'points': 25}),
    ]);
    final ledge = r.scene.byId(r.created[0])!;
    expect(ledge.name, 'Platform 6');
    expect(ledge.x + ledge.w, 1600);
    expect(r.scene.byId(r.created[1])!.param('collectible', 'points'), 25);
    expect(r.notes, ['+ Platform 6 at (1300, 500)', '+ Coin 3 at (600, 560)']);
  });

  test('creating a player moves the one player there is', () {
    final r = applyActions(starterScene(), [a('CREATE_OBJECT', {'objectType': 'player', 'x': 400, 'y': 672, 'jump': 700})]);
    expect(r.scene.objects.where((o) => o.type == SceneObjectType.player), hasLength(1));
    expect(r.scene.byId('player')!.x, 400);
    expect(r.scene.byId('player')!.param('controller', 'jump'), 700);
    expect(r.created, isEmpty);
  });

  test('UPDATE_OBJECT moves an enemy with its patrol; unknown ids are skipped', () {
    final r = applyActions(starterScene(), [a('UPDATE_OBJECT', {'id': 'enemy-1', 'x': 1100}), a('UPDATE_OBJECT', {'id': 'nope', 'x': 1})]);
    final enemy = r.scene.byId('enemy-1')!;
    expect(enemy.param('patrol', 'from'), 1000);
    expect(enemy.param('patrol', 'to'), 1400);
    expect(r.notes.last, '· Skipped: there is no nope');
  });

  test('DELETE_OBJECT, ADD_COMPONENT, UPDATE_SCENE and UPDATE_UI', () {
    final r = applyActions(starterScene(), [
      a('DELETE_OBJECT', {'id': 'coin-2'}),
      a('ADD_COMPONENT', {'id': 'enemy-1', 'component': 'patrol', 'speed': 150}),
      a('UPDATE_SCENE', {'theme': 'night', 'sceneName': 'Night run'}),
      a('UPDATE_UI', {'score': false}),
    ]);
    expect(r.scene.byId('coin-2'), isNull);
    expect(r.scene.byId('enemy-1')!.param('patrol', 'speed'), 150);
    expect(r.scene.theme, 'night');
    expect(r.scene.name, 'Night run');
    expect(r.scene.score, isFalse);
    expect(validateScene(r.scene).ok, isTrue);
  });

  test('an unknown action type changes nothing', () {
    final scene = starterScene();
    final r = applyActions(scene, [a('CREATE_SCRIPT', {'code': 'while(true){}'})]);
    expect(identical(r.scene, scene), isTrue);
    expect(r.notes, isEmpty);
  });
}
