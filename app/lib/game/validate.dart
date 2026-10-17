// Semantic validation (spec/rules.md section 7).

import 'model.dart';
import 'raster.dart';

class Issue {
  const Issue(this.code, this.message, [this.id]);
  final String code;
  final String message;
  final String? id;
}

class ValidationResult {
  const ValidationResult(this.errors, this.warnings);
  final List<Issue> errors;
  final List<Issue> warnings;
}

const maxCollectibles = 8;

ValidationResult validateWorld(World world) {
  final errors = <Issue>[];
  final warnings = <Issue>[];
  bool inGrid(int x, int y) => x >= 0 && y >= 0 && x < world.width && y < world.height;

  if (!inGrid(world.start.x, world.start.y)) errors.add(const Issue('out_of_bounds', 'Start is outside the grid'));
  if (!inGrid(world.flag.x, world.flag.y)) errors.add(const Issue('out_of_bounds', 'Flag is outside the grid'));
  if (world.start == world.flag) errors.add(const Issue('start_equals_flag', 'Start and flag are on the same cell'));

  final seen = <String>{};
  var collectibles = 0;
  for (final e in world.entities) {
    if (!seen.add(e.id)) errors.add(Issue('duplicate_id', 'Duplicate id ${e.id}', e.id));
    if (!inGrid(e.x, e.y) || !inGrid(e.x + e.w - 1, e.y + e.h - 1)) {
      errors.add(Issue('out_of_bounds', '${e.id} extends outside the grid', e.id));
    }
    if (e.type == EntityType.castle) {
      final span = e.door!.side == DoorSide.left || e.door!.side == DoorSide.right ? e.h : e.w;
      if (e.door!.offset > span - 3) {
        errors.add(Issue('invalid_castle_door', '${e.id} door offset must be 0..${span - 3}', e.id));
      }
    }
    if (e.type == EntityType.treasure || e.type == EntityType.coin) collectibles++;
  }
  if (collectibles > maxCollectibles) {
    errors.add(Issue('collectible_limit', '$collectibles treasures and coins, limit is $maxCollectibles'));
  }
  for (final o in world.objectives.whereType<CollectObjective>()) {
    final t = world.byId(o.target);
    if (t == null || (t.type != EntityType.treasure && t.type != EntityType.coin)) {
      errors.add(Issue('objective_target', 'Collect target ${o.target} is not a treasure or coin', o.target));
    }
  }

  if (errors.any((e) => e.code == 'out_of_bounds')) return ValidationResult(errors, warnings);
  final grid = rasterize(world);
  if (isBlocked(grid.terrainAt(world.start.x, world.start.y))) {
    warnings.add(const Issue('protected_cell', 'Start is on a wall or lava'));
  }
  if (isBlocked(grid.terrainAt(world.flag.x, world.flag.y))) {
    warnings.add(const Issue('protected_cell', 'Flag is on a wall or lava'));
  }
  for (final e in world.entities.where((e) => e.type.isItem)) {
    if (isBlocked(grid.terrainAt(e.x, e.y))) warnings.add(Issue('item_on_blocked', '${e.id} lies on a wall or lava', e.id));
    if (e.x == world.start.x && e.y == world.start.y) {
      warnings.add(Issue('item_on_start', '${e.id} lies on the start cell', e.id));
    }
  }
  return ValidationResult(errors, warnings);
}
