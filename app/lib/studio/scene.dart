// A scene, as spec/scene.md defines it: a 2D world of objects with positions, sizes and behaviours. Behaviours are
// data (numbers to tune), never code. Immutable: every edit makes a new Scene, which is what undo keeps.

import 'dart:ui' show Rect, Size;

enum SceneObjectType { player, platform, coin, enemy, finish }

/// Default sizes and behaviours per type (spec/scene.md section 3).
const defaultSizes = {
  SceneObjectType.player: Size(32, 48),
  SceneObjectType.platform: Size(192, 24),
  SceneObjectType.coin: Size(24, 24),
  SceneObjectType.enemy: Size(40, 36),
  SceneObjectType.finish: Size(60, 120),
};

Map<String, Map<String, num>> defaultBehaviours(SceneObjectType type, {double x = 0}) => switch (type) {
      SceneObjectType.player => {
          'controller': {'speed': 260, 'jump': 640},
        },
      SceneObjectType.coin => {
          'collectible': {'points': 10},
        },
      SceneObjectType.enemy => {
          'patrol': {'from': x, 'to': x + 200, 'speed': 90},
        },
      _ => {},
    };

class SceneObject {
  const SceneObject({required this.id, required this.name, required this.type, required this.x, required this.y, required this.w, required this.h, this.behaviours = const {}, this.by});

  factory SceneObject.fromJson(Map<String, dynamic> j) => SceneObject(
        id: j['id'] as String,
        name: j['name'] as String? ?? j['id'] as String,
        type: SceneObjectType.values.byName(j['type'] as String),
        x: (j['x'] as num).toDouble(),
        y: (j['y'] as num).toDouble(),
        w: (j['w'] as num).toDouble(),
        h: (j['h'] as num).toDouble(),
        behaviours: {
          for (final e in ((j['behaviours'] as Map?) ?? const {}).entries) e.key as String: {for (final p in (e.value as Map).entries) p.key as String: p.value as num},
        },
        by: j['by'] as String?,
      );

  final String id;
  final String name;
  final SceneObjectType type;
  final double x;
  final double y;
  final double w;
  final double h;
  final Map<String, Map<String, num>> behaviours;

  /// Who made it in a shared project: a member id, or `agent:<id>` for that member's agent.
  final String? by;

  Rect get rect => Rect.fromLTWH(x, y, w, h);

  num? param(String behaviour, String key) => behaviours[behaviour]?[key];

  SceneObject copyWith({String? id, String? name, double? x, double? y, double? w, double? h, Map<String, Map<String, num>>? behaviours}) =>
      SceneObject(id: id ?? this.id, name: name ?? this.name, type: type, x: x ?? this.x, y: y ?? this.y, w: w ?? this.w, h: h ?? this.h, behaviours: behaviours ?? this.behaviours, by: by);

  /// A copy with one behaviour parameter changed.
  SceneObject withParam(String behaviour, String key, num value) => copyWith(behaviours: {
        ...behaviours,
        behaviour: {...?behaviours[behaviour], key: value},
      });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'x': _num(x),
        'y': _num(y),
        'w': _num(w),
        'h': _num(h),
        if (behaviours.isNotEmpty) 'behaviours': behaviours,
        'by': ?by,
      };
}

num _num(double v) => v == v.roundToDouble() ? v.round() : v;

class Scene {
  const Scene({
    required this.name,
    this.template = 'platformer',
    required this.width,
    required this.height,
    this.theme = 'forest',
    this.gravity = 1800,
    required this.objects,
    this.score = true,
  });

  factory Scene.fromJson(Map<String, dynamic> j) {
    if (j['format'] != 'skittles-scene') throw const FormatException('Not a Skittles scene file.');
    if (j['version'] != 1) throw FormatException('Scene version ${j['version']} is newer than this studio understands.');
    final size = j['size'] as Map<String, dynamic>;
    return Scene(
      name: j['name'] as String? ?? 'Untitled',
      template: j['template'] as String? ?? 'platformer',
      width: (size['w'] as num).toDouble(),
      height: (size['h'] as num).toDouble(),
      theme: j['theme'] as String? ?? 'forest',
      gravity: ((j['physics'] as Map?)?['gravity'] as num? ?? 1800).toDouble(),
      objects: [for (final o in j['objects'] as List) SceneObject.fromJson(o as Map<String, dynamic>)],
      score: (j['ui'] as Map?)?['score'] as bool? ?? true,
    );
  }

  final String name;
  final String template;
  final double width;
  final double height;
  final String theme;
  final double gravity;
  final List<SceneObject> objects;
  final bool score;

  /// A new, empty project: nothing in it until someone places something or asks an agent.
  factory Scene.blank({String name = 'Untitled'}) => Scene(name: name, width: 1600, height: 900, objects: const []);

  Rect get bounds => Rect.fromLTWH(0, 0, width, height);

  SceneObject? byId(String? id) {
    for (final o in objects) {
      if (o.id == id) return o;
    }
    return null;
  }

  Scene copyWith({String? name, String? theme, List<SceneObject>? objects, bool? score}) => Scene(
        name: name ?? this.name,
        template: template,
        width: width,
        height: height,
        theme: theme ?? this.theme,
        gravity: gravity,
        objects: objects ?? this.objects,
        score: score ?? this.score,
      );

  /// The object moved and sized to lie inside the scene (at least 8 px), with an enemy's patrol kept inside too.
  SceneObject fit(SceneObject object) {
    final w = object.w.clamp(8.0, width);
    final h = object.h.clamp(8.0, height);
    var fitted = object.copyWith(w: w, h: h, x: object.x.clamp(0.0, width - w), y: object.y.clamp(0.0, height - h));
    if (object.type == SceneObjectType.enemy) {
      final limit = width - w;
      fitted = fitted
          .withParam('patrol', 'from', (object.param('patrol', 'from') ?? object.x).toDouble().clamp(0.0, limit))
          .withParam('patrol', 'to', (object.param('patrol', 'to') ?? object.x).toDouble().clamp(0.0, limit));
    }
    return fitted;
  }

  Scene replace(SceneObject object) => copyWith(objects: [for (final o in objects) o.id == object.id ? object : o]);

  Map<String, dynamic> toJson() => {
        'format': 'skittles-scene',
        'version': 1,
        'name': name,
        'template': template,
        'size': {'w': _num(width), 'h': _num(height)},
        'theme': theme,
        'physics': {'gravity': _num(gravity)},
        'objects': [for (final o in objects) o.toJson()],
        'ui': {'score': score},
      };
}
