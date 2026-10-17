// Play-mode rules (spec/rules.md sections 4 and 5).

import 'model.dart';
import 'raster.dart';

class PlayState {
  const PlayState({
    required this.x,
    required this.y,
    required this.keys,
    required this.collected,
    required this.taken,
    required this.deaths,
    required this.won,
  });

  final int x;
  final int y;
  final Set<GameColor> keys;

  /// Ids of collected treasures and coins.
  final Set<String> collected;

  /// Ids of every item taken off the map, keys included.
  final Set<String> taken;
  final int deaths;
  final bool won;

  PlayState copyWith({int? x, int? y, Set<GameColor>? keys, Set<String>? collected, Set<String>? taken, bool? won}) =>
      PlayState(
        x: x ?? this.x,
        y: y ?? this.y,
        keys: keys ?? this.keys,
        collected: collected ?? this.collected,
        taken: taken ?? this.taken,
        deaths: deaths,
        won: won ?? this.won,
      );
}

class PlayEngine {
  PlayEngine(this.world) : grid = rasterize(world);

  final World world;
  final Grid grid;

  PlayState initialState([int deaths = 0]) => _pickUp(PlayState(
        x: world.start.x,
        y: world.start.y,
        keys: const {},
        collected: const {},
        taken: const {},
        deaths: deaths,
        won: false,
      ));

  PlayState step(PlayState s, Direction dir) {
    if (s.won) return s;
    final x = s.x + dir.dx;
    final y = s.y + dir.dy;
    if (!grid.inBounds(x, y)) return s;
    final t = grid.terrainAt(x, y);
    if (t == Terrain.wall) return s;
    if (t == Terrain.door && !s.keys.contains(grid.doorColor[grid.index(x, y)])) return s;
    if (t == Terrain.lava) return initialState(s.deaths + 1);

    final moved = _pickUp(s.copyWith(x: x, y: y));
    final won = x == world.flag.x && y == world.flag.y && objectivesDone(moved.collected);
    return won ? moved.copyWith(won: true) : moved;
  }

  PlayState run(Iterable<Direction> inputs, [PlayState? from]) => inputs.fold(from ?? initialState(), step);

  bool objectivesDone(Set<String> collected) => world.objectives.every((o) => switch (o) {
        CollectObjective(:final target) => collected.contains(target),
        CollectCountObjective(:final count) =>
          world.entities.where((e) => e.type == EntityType.coin && collected.contains(e.id)).length >= count,
      });

  PlayState _pickUp(PlayState s) {
    final items = grid.items[grid.index(s.x, s.y)].where((it) => !s.taken.contains(it.id)).toList();
    if (items.isEmpty) return s;
    return s.copyWith(
      keys: {...s.keys, for (final it in items) if (it.type == EntityType.key) it.color!},
      collected: {...s.collected, for (final it in items) if (it.type != EntityType.key) it.id},
      taken: {...s.taken, for (final it in items) it.id},
    );
  }
}
