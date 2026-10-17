// Level document. Mirrors spec/schema/world.schema.json; semantics live in spec/rules.md.

typedef Cell = ({int x, int y});

enum GameColor { red, blue, gold }

enum EntityType { wall, lava, bridge, castle, door, key, treasure, coin }

enum DoorSide { left, right, top, bottom }

enum OwnerKind { player, assistant, mediator, system }

extension EntityTypeShape on EntityType {
  bool get isRect => this == EntityType.wall || this == EntityType.lava || this == EntityType.bridge || this == EntityType.castle;
  bool get isItem => this == EntityType.key || this == EntityType.treasure || this == EntityType.coin;
  bool get hasColor => this == EntityType.key || this == EntityType.door;
}

class Owner {
  const Owner(this.kind, [this.playerId]);
  const Owner.system() : this(OwnerKind.system);

  final OwnerKind kind;
  final String? playerId;

  factory Owner.fromJson(Map<String, dynamic> j) =>
      Owner(OwnerKind.values.byName(j['kind'] as String), j['playerId'] as String?);

  Map<String, dynamic> toJson() => {'kind': kind.name, if (playerId != null) 'playerId': playerId};
}

class CastleDoor {
  const CastleDoor({required this.side, required this.offset, required this.color});

  final DoorSide side;
  final int offset;
  final GameColor? color;

  CastleDoor copyWith({DoorSide? side, int? offset, GameColor? Function()? color}) => CastleDoor(
        side: side ?? this.side,
        offset: offset ?? this.offset,
        color: color != null ? color() : this.color,
      );

  factory CastleDoor.fromJson(Map<String, dynamic> j) => CastleDoor(
        side: DoorSide.values.byName(j['side'] as String),
        offset: j['offset'] as int,
        color: j['color'] == null ? null : GameColor.values.byName(j['color'] as String),
      );

  Map<String, dynamic> toJson() => {'side': side.name, 'offset': offset, 'color': color?.name};
}

/// One entity. Cell types (door, key, treasure, coin) always have w = h = 1.
class Entity {
  const Entity({
    required this.id,
    required this.type,
    required this.owner,
    required this.x,
    required this.y,
    this.w = 1,
    this.h = 1,
    this.color,
    this.door,
    this.label,
    this.icon,
  });

  final String id;
  final EntityType type;
  final Owner owner;
  final int x;
  final int y;
  final int w;
  final int h;
  final GameColor? color;
  final CastleDoor? door;
  final String? label;
  final String? icon;

  bool contains(int cx, int cy) => cx >= x && cy >= y && cx < x + w && cy < y + h;

  Entity copyWith({int? x, int? y, int? w, int? h, GameColor? color, CastleDoor? door, String? Function()? label}) => Entity(
        id: id,
        type: type,
        owner: owner,
        x: x ?? this.x,
        y: y ?? this.y,
        w: w ?? this.w,
        h: h ?? this.h,
        color: color ?? this.color,
        door: door ?? this.door,
        label: label != null ? label() : this.label,
        icon: icon,
      );

  factory Entity.fromJson(Map<String, dynamic> j) {
    final type = EntityType.values.byName(j['type'] as String);
    return Entity(
      id: j['id'] as String,
      type: type,
      owner: Owner.fromJson(j['owner'] as Map<String, dynamic>),
      x: j['x'] as int,
      y: j['y'] as int,
      w: type.isRect ? j['w'] as int : 1,
      h: type.isRect ? j['h'] as int : 1,
      color: j['color'] == null ? null : GameColor.values.byName(j['color'] as String),
      door: j['door'] == null ? null : CastleDoor.fromJson(j['door'] as Map<String, dynamic>),
      label: j['label'] as String?,
      icon: j['icon'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'owner': owner.toJson(),
        if (label != null) 'label': label,
        if (icon != null) 'icon': icon,
        'x': x,
        'y': y,
        if (type.isRect) ...{'w': w, 'h': h},
        if (type.hasColor) 'color': color!.name,
        if (type == EntityType.castle) 'door': door!.toJson(),
      };
}

sealed class Objective {
  const Objective();

  factory Objective.fromJson(Map<String, dynamic> j) => switch (j['type']) {
        'collect' => CollectObjective(j['target'] as String),
        'collect_count' => CollectCountObjective(j['count'] as int),
        final t => throw FormatException('unknown objective type $t'),
      };

  Map<String, dynamic> toJson();
}

class CollectObjective extends Objective {
  const CollectObjective(this.target);
  final String target;

  @override
  Map<String, dynamic> toJson() => {'type': 'collect', 'target': target};
}

class CollectCountObjective extends Objective {
  const CollectCountObjective(this.count);
  final int count;

  @override
  Map<String, dynamic> toJson() => {'type': 'collect_count', 'item': 'coin', 'count': count};
}

class World {
  const World({
    required this.width,
    required this.height,
    required this.start,
    required this.flag,
    required this.entities,
    required this.objectives,
  });

  final int width;
  final int height;
  final Cell start;
  final Cell flag;
  final List<Entity> entities;
  final List<Objective> objectives;

  World copyWith({Cell? start, Cell? flag, List<Entity>? entities, List<Objective>? objectives}) => World(
        width: width,
        height: height,
        start: start ?? this.start,
        flag: flag ?? this.flag,
        entities: entities ?? this.entities,
        objectives: objectives ?? this.objectives,
      );

  Entity? byId(String id) {
    for (final e in entities) {
      if (e.id == id) return e;
    }
    return null;
  }

  static Cell _cell(Object? j) => (x: (j as Map<String, dynamic>)['x'] as int, y: j['y'] as int);

  factory World.fromJson(Map<String, dynamic> j) {
    final grid = j['grid'] as Map<String, dynamic>;
    return World(
      width: grid['w'] as int,
      height: grid['h'] as int,
      start: _cell(j['start']),
      flag: _cell(j['flag']),
      entities: [for (final e in j['entities'] as List) Entity.fromJson(e as Map<String, dynamic>)],
      objectives: [for (final o in j['objectives'] as List) Objective.fromJson(o as Map<String, dynamic>)],
    );
  }

  Map<String, dynamic> toJson() => {
        'schemaVersion': 1,
        'grid': {'w': width, 'h': height},
        'start': {'x': start.x, 'y': start.y},
        'flag': {'x': flag.x, 'y': flag.y},
        'entities': [for (final e in entities) e.toJson()],
        'objectives': [for (final o in objectives) o.toJson()],
      };
}

enum Direction {
  up(0, -1),
  down(0, 1),
  left(-1, 0),
  right(1, 0);

  const Direction(this.dx, this.dy);
  final int dx;
  final int dy;
}
