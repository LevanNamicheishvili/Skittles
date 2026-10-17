// Breadth-first solver over (cell, keys, relevant items) states (spec/rules.md section 6).

import 'dart:math' as math;
import 'dart:typed_data';

import 'model.dart';
import 'raster.dart';

class SolveResult {
  const SolveResult({required this.solvable, this.path, required this.unreachable});

  final bool solvable;

  /// Shortest winning input sequence, present when solvable.
  final List<Direction>? path;
  final List<String> unreachable;

  int? get steps => path?.length;
}

const _maxRelevantItems = 12;

int _popcount(int n) {
  var c = 0;
  for (var v = n; v != 0; v &= v - 1) {
    c++;
  }
  return c;
}

SolveResult solve(World world, [Grid? grid]) {
  final g = grid ?? rasterize(world);
  final cells = g.width * g.height;

  // Bit per relevant item: collect targets, plus every coin when a count objective exists.
  final needsCoins = world.objectives.any((o) => o is CollectCountObjective);
  final targets = {for (final o in world.objectives) if (o is CollectObjective) o.target};
  final bitOf = <String, int>{};
  for (final e in world.entities) {
    final relevant = (e.type == EntityType.coin && needsCoins) ||
        ((e.type == EntityType.treasure || e.type == EntityType.coin) && targets.contains(e.id));
    if (relevant) bitOf.putIfAbsent(e.id, () => bitOf.length);
  }
  if (bitOf.length > _maxRelevantItems) throw StateError('too many relevant items: ${bitOf.length}');
  var coinBits = 0;
  for (final e in world.entities) {
    if (e.type == EntityType.coin && bitOf.containsKey(e.id)) coinBits |= 1 << bitOf[e.id]!;
  }

  // What entering each cell adds to the state.
  final keyGain = Uint8List(cells);
  final itemGain = Int32List(cells);
  for (var i = 0; i < cells; i++) {
    for (final it in g.items[i]) {
      if (it.type == EntityType.key) {
        keyGain[i] |= 1 << it.color!.index;
      } else if (bitOf.containsKey(it.id)) {
        itemGain[i] |= 1 << bitOf[it.id]!;
      }
    }
  }

  bool done(int mask) => world.objectives.every((o) => switch (o) {
        CollectObjective(:final target) => bitOf.containsKey(target) && mask & (1 << bitOf[target]!) != 0,
        CollectCountObjective(:final count) => _popcount(mask & coinBits) >= count,
      });

  final itemStates = 1 << bitOf.length;
  int stateId(int cell, int keys, int mask) => (cell * 8 + keys) * itemStates + mask;
  final total = cells * 8 * itemStates;
  final parent = Int32List(total)..fillRange(0, total, -2); // -2 unvisited, -1 root
  final parentDir = Int8List(total);
  final reached = Uint8List(cells);
  final flagCell = g.index(world.flag.x, world.flag.y);

  final startCell = g.index(world.start.x, world.start.y);
  final startId = stateId(startCell, keyGain[startCell], itemGain[startCell]);
  parent[startId] = -1;
  reached[startCell] = 1;
  final queue = Int32List(total);
  var head = 0;
  var tail = 0;
  queue[tail++] = startId;
  var goal = -1;

  while (head < tail) {
    final id = queue[head++];
    final mask = id % itemStates;
    final keys = (id ~/ itemStates) % 8;
    final cell = id ~/ itemStates ~/ 8;
    if (cell == flagCell && done(mask)) {
      goal = id;
      break;
    }
    final cx = cell % g.width;
    final cy = cell ~/ g.width;
    for (final d in Direction.values) {
      final nx = cx + d.dx;
      final ny = cy + d.dy;
      if (!g.inBounds(nx, ny)) continue;
      final n = g.index(nx, ny);
      final t = g.terrain[n];
      if (t == Terrain.wall || t == Terrain.lava) continue;
      if (t == Terrain.door && keys & (1 << g.doorColor[n]!.index) == 0) continue;
      final next = stateId(n, keys | keyGain[n], mask | itemGain[n]);
      if (parent[next] != -2) continue;
      parent[next] = id;
      parentDir[next] = d.index;
      reached[n] = 1;
      queue[tail++] = next;
    }
  }

  if (goal >= 0) {
    final path = <Direction>[];
    for (var id = goal; parent[id] != -1; id = parent[id]) {
      path.add(Direction.values[parentDir[id]]);
    }
    return SolveResult(solvable: true, path: path.reversed.toList(), unreachable: const []);
  }

  // Exhausted: every reachable cell is marked, so report what can never be reached.
  final unreachable = <String>[];
  for (final o in world.objectives) {
    if (o is! CollectObjective) continue;
    final e = world.byId(o.target);
    if (e == null || reached[g.index(e.x, e.y)] == 0) unreachable.add('collect:${o.target}');
  }
  final neededCoins = world.objectives.whereType<CollectCountObjective>().map((o) => o.count).fold(0, math.max);
  if (neededCoins > 0) {
    final reachableCoins =
        world.entities.where((e) => e.type == EntityType.coin && reached[g.index(e.x, e.y)] == 1).length;
    if (reachableCoins < neededCoins) unreachable.add('collect_count:coin');
  }
  if (reached[flagCell] == 0) unreachable.add('flag');
  return SolveResult(solvable: false, unreachable: unreachable);
}
