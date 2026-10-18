// The AI's actions (server/src/studio/sceneAgent.ts) applied to a scene: the same kinds of change a person makes
// with the tools, kept inside the scene and to its rules (one player, behaviours as numbers). Each action leaves a
// line saying what it did, so the chat can show the change.

import 'dart:math' as math;

import 'scene.dart';

class SceneAction {
  const SceneAction(this.type, this.fields);

  factory SceneAction.fromJson(Map<String, dynamic> j) => SceneAction(j['type'] as String, j);

  final String type;
  final Map<String, dynamic> fields;

  String? str(String key) => fields[key] as String?;
  double? n(String key) => (fields[key] as num?)?.toDouble();
}

/// What a batch of actions did: the new scene, a line per action, and the objects it created.
class AppliedActions {
  const AppliedActions(this.scene, this.notes, this.created);

  final Scene scene;
  final List<String> notes;
  final List<String> created;
}

const _behaviourKeys = {
  'controller': ['speed', 'jump'],
  'collectible': ['points'],
  'patrol': ['from', 'to', 'speed'],
};

const _behaviourOf = {
  SceneObjectType.player: 'controller',
  SceneObjectType.coin: 'collectible',
  SceneObjectType.enemy: 'patrol',
};

/// A given name, or with the lowest free number from 2 when another object has it already.
String? _freeName(Scene scene, String? name) {
  if (name == null) return null;
  final names = {for (final o in scene.objects) o.name};
  if (!names.contains(name)) return name;
  var n = 2;
  while (names.contains('$name $n')) {
    n++;
  }
  return '$name $n';
}

AppliedActions applyActions(Scene scene, List<SceneAction> actions) {
  var s = scene;
  final notes = <String>[];
  final created = <String>[];

  SceneObject withNumbers(SceneObject o, SceneAction a, String? behaviour) {
    if (behaviour == null) return o;
    var out = o;
    for (final key in _behaviourKeys[behaviour]!) {
      final v = a.n(key);
      if (v != null) out = out.withParam(behaviour, key, v);
    }
    return out;
  }

  for (final a in actions) {
    switch (a.type) {
      case 'CREATE_OBJECT':
        final type = SceneObjectType.values.where((t) => t.name == a.str('objectType')).firstOrNull;
        if (type == null) continue;
        final size = defaultSizes[type]!;
        final w = a.n('w') ?? size.width;
        final h = a.n('h') ?? size.height;
        final x = a.n('x') ?? (s.width - w) / 2;
        final y = a.n('y') ?? (s.height - h) / 2;
        // One player per scene: creating a player moves the one there is.
        final existing = type == SceneObjectType.player ? s.objects.where((o) => o.type == type).firstOrNull : null;
        if (existing != null) {
          final moved = s.fit(withNumbers(existing.copyWith(x: x, y: y), a, 'controller'));
          s = s.replace(moved);
          notes.add('~ Moved ${moved.name} to (${moved.x.round()}, ${moved.y.round()})');
          continue;
        }
        var number = 1;
        final ids = {for (final o in s.objects) o.id};
        while (ids.contains('${type.name}-$number')) {
          number++;
        }
        // A given id is used when it is free (undo restores a deleted object this way).
        final wanted = a.str('id');
        final id = wanted != null && !ids.contains(wanted) ? wanted : '${type.name}-$number';
        final label = '${type.name[0].toUpperCase()}${type.name.substring(1)}';
        final count = s.objects.where((o) => o.type == type).length + 1;
        var behaviours = defaultBehaviours(type, x: x);
        if (type == SceneObjectType.enemy) {
          behaviours = {
            'patrol': {'from': x, 'to': math.min(x + 200, s.width - w), 'speed': 90},
          };
        }
        var object = SceneObject(
          id: id,
          name: _freeName(s, a.str('name')) ?? (count == 1 ? label : '$label $count'),
          type: type,
          x: x,
          y: y,
          w: w,
          h: h,
          behaviours: behaviours,
        );
        object = s.fit(withNumbers(object, a, _behaviourOf[type]));
        s = s.copyWith(objects: [...s.objects, object]);
        created.add(object.id);
        notes.add('+ ${object.name} at (${object.x.round()}, ${object.y.round()})');
      case 'UPDATE_OBJECT':
        final o = s.byId(a.str('id'));
        if (o == null) {
          notes.add('· Skipped: there is no ${a.str('id')}');
          continue;
        }
        var changed = o.copyWith(name: a.str('name'), x: a.n('x'), y: a.n('y'), w: a.n('w'), h: a.n('h'));
        // Moving an enemy takes its patrol along, as a drag does.
        if (o.type == SceneObjectType.enemy && changed.x != o.x) {
          final shift = changed.x - o.x;
          changed = changed
              .withParam('patrol', 'from', (o.param('patrol', 'from') ?? o.x) + shift)
              .withParam('patrol', 'to', (o.param('patrol', 'to') ?? o.x) + shift);
        }
        changed = s.fit(changed);
        s = s.replace(changed);
        notes.add('~ Changed ${changed.name}');
      case 'DELETE_OBJECT':
        final o = s.byId(a.str('id'));
        if (o == null) {
          notes.add('· Skipped: there is no ${a.str('id')}');
          continue;
        }
        s = s.copyWith(objects: [for (final x in s.objects) if (x.id != o.id) x]);
        notes.add('− Removed ${o.name}');
      case 'ADD_COMPONENT':
        final o = s.byId(a.str('id'));
        final behaviour = a.str('component');
        if (o == null || behaviour == null || !_behaviourKeys.containsKey(behaviour)) {
          notes.add('· Skipped a behaviour change');
          continue;
        }
        final changed = s.fit(withNumbers(o, a, behaviour));
        s = s.replace(changed);
        notes.add('~ Set ${changed.name}\'s $behaviour');
      case 'UPDATE_SCENE':
        final theme = a.str('theme');
        final name = a.str('sceneName');
        s = s.copyWith(name: name, theme: const {'forest', 'desert', 'night'}.contains(theme) ? theme : null);
        notes.add('~ Scene${name != null ? ' renamed to $name' : ''}${theme != null ? ' · $theme theme' : ''}');
      case 'UPDATE_UI':
        final score = a.fields['score'];
        if (score is bool) {
          s = s.copyWith(score: score);
          notes.add('~ Score ${score ? 'shown' : 'hidden'}');
        }
    }
  }
  return AppliedActions(s, notes, created);
}
