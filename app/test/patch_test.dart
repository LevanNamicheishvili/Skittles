import 'package:flutter_test/flutter_test.dart';
import 'package:skittles/studio/patch.dart';
import 'package:skittles/studio/scene.dart';
import 'package:skittles/studio/starter.dart';

void main() {
  final starter = starterScene();

  test('a patch holds what changed, and applying it gives the same scene', () {
    final after = starter.copyWith(theme: 'night', objects: [
      for (final o in starter.objects)
        if (o.id != 'coin-2') o.id == 'coin-1' ? o.copyWith(x: 300) : o,
      const SceneObject(id: 'platform-1', name: 'Platform 6', type: SceneObjectType.platform, x: 200, y: 300, w: 192, h: 24, by: 'm1'),
    ]);
    final patch = diffScenes(starter, after);
    expect(patch.objects.keys.toSet(), {'coin-1', 'coin-2', 'platform-1'});
    expect(patch.objects['coin-2'], isNull);
    expect(patch.theme, 'night');
    expect(patch.name, isNull);
    expect(applyPatch(starter, patch).toJson(), after.toJson());
    expect(diffScenes(starter, starter).isEmpty, isTrue);
  });

  test('patches read and write the server\'s form', () {
    final patch = ScenePatch.fromJson({
      'objects': {
        'coin-1': null,
        'sky': {'name': 'Sky', 'type': 'coin', 'x': 10, 'y': 20, 'w': 24, 'h': 24, 'by': 'agent:m2'},
      },
      'scene': {'score': false},
    });
    final scene = applyPatch(starter, patch);
    expect(scene.byId('coin-1'), isNull);
    expect(scene.byId('sky')!.by, 'agent:m2');
    expect(scene.score, isFalse);
    expect(patch.toJson()['scene'], {'score': false});
    expect((patch.toJson()['objects'] as Map)['coin-1'], isNull);
  });

  test('applying keeps objects inside the scene', () {
    final far = starter.byId('coin-1')!.copyWith(x: -40, y: 5000);
    final scene = applyPatch(starter, ScenePatch({'coin-1': far}));
    expect([scene.byId('coin-1')!.x, scene.byId('coin-1')!.y], [0, starter.height - 24]);
  });
}
