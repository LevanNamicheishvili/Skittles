// What a change did, object by object (server/src/studio/scene.ts, Patch): each touched object as it ends up, or
// null when the change removes it, and the scene fields it set. The studio sends its edits as patches and applies
// the project's changes the same way.

import 'dart:convert';

import 'scene.dart';

class ScenePatch {
  const ScenePatch(this.objects, {this.name, this.theme, this.score});

  factory ScenePatch.fromJson(Map<String, dynamic> j) {
    final scene = (j['scene'] as Map?)?.cast<String, dynamic>() ?? const {};
    return ScenePatch(
      {
        for (final e in ((j['objects'] as Map?) ?? const {}).entries)
          e.key as String: e.value == null ? null : SceneObject.fromJson({...(e.value as Map).cast<String, dynamic>(), 'id': e.key}),
      },
      name: scene['name'] as String?,
      theme: scene['theme'] as String?,
      score: scene['score'] as bool?,
    );
  }

  final Map<String, SceneObject?> objects;
  final String? name;
  final String? theme;
  final bool? score;

  bool get isEmpty => objects.isEmpty && name == null && theme == null && score == null;

  Map<String, dynamic> toJson() => {
        'objects': {for (final e in objects.entries) e.key: e.value?.toJson()},
        if (name != null || theme != null || score != null) 'scene': {'name': ?name, 'theme': ?theme, 'score': ?score},
      };
}

String _key(SceneObject o) => jsonEncode(o.toJson());

/// The patch that turns [before] into [after].
ScenePatch diffScenes(Scene before, Scene after) {
  final old = {for (final o in before.objects) o.id: o};
  final objects = <String, SceneObject?>{};
  for (final o in after.objects) {
    final was = old.remove(o.id);
    if (was == null || _key(was) != _key(o)) objects[o.id] = o;
  }
  for (final id in old.keys) {
    objects[id] = null;
  }
  return ScenePatch(
    objects,
    name: before.name != after.name ? after.name : null,
    theme: before.theme != after.theme ? after.theme : null,
    score: before.score != after.score ? after.score : null,
  );
}

/// Sets each object in the patch to its state there (null removes it), kept inside the scene. New objects go last.
Scene applyPatch(Scene scene, ScenePatch patch) {
  if (patch.isEmpty) return scene;
  final pending = Map.of(patch.objects);
  final objects = <SceneObject>[];
  for (final o in scene.objects) {
    if (!pending.containsKey(o.id)) {
      objects.add(o);
    } else {
      final next = pending.remove(o.id);
      if (next != null) objects.add(scene.fit(next));
    }
  }
  for (final next in pending.values) {
    if (next != null) objects.add(scene.fit(next));
  }
  return scene.copyWith(name: patch.name, theme: patch.theme, score: patch.score, objects: objects);
}
