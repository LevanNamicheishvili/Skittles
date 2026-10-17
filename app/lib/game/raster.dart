// Rasterization: entities -> one terrain per cell plus an item layer (spec/rules.md section 3).

import 'model.dart';

/// Declaration order is the precedence: a later value wins when entities overlap.
enum Terrain { ground, lava, bridge, wall, door }

class Item {
  const Item(this.id, this.type, [this.color]);
  final String id;
  final EntityType type; // key, treasure or coin
  final GameColor? color;
}

class Grid {
  Grid(this.width, this.height)
      : terrain = List.filled(width * height, Terrain.ground),
        doorColor = List.filled(width * height, null),
        items = List.generate(width * height, (_) => <Item>[]);

  final int width;
  final int height;
  final List<Terrain> terrain;
  final List<GameColor?> doorColor;
  final List<List<Item>> items;

  int index(int x, int y) => y * width + x;
  bool inBounds(int x, int y) => x >= 0 && y >= 0 && x < width && y < height;
  Terrain terrainAt(int x, int y) => terrain[index(x, y)];
}

Cell castleDoorCell(Entity c) {
  final d = c.door!;
  return switch (d.side) {
    DoorSide.left => (x: c.x, y: c.y + 1 + d.offset),
    DoorSide.right => (x: c.x + c.w - 1, y: c.y + 1 + d.offset),
    DoorSide.top => (x: c.x + 1 + d.offset, y: c.y),
    DoorSide.bottom => (x: c.x + 1 + d.offset, y: c.y + c.h - 1),
  };
}

Grid rasterize(World world) {
  final grid = Grid(world.width, world.height);

  void paint(int x, int y, Terrain code, [GameColor? color]) {
    if (!grid.inBounds(x, y)) return;
    final i = grid.index(x, y);
    final current = grid.terrain[i];
    // Equal precedence only matters for doors: the later door decides the color.
    if (code.index > current.index || (code == Terrain.door && current == Terrain.door)) {
      grid.terrain[i] = code;
      grid.doorColor[i] = code == Terrain.door ? color : null;
    }
  }

  void fillRect(Entity e, Terrain code) {
    for (var y = e.y; y < e.y + e.h; y++) {
      for (var x = e.x; x < e.x + e.w; x++) {
        paint(x, y, code);
      }
    }
  }

  for (final e in world.entities) {
    switch (e.type) {
      case EntityType.wall:
        fillRect(e, Terrain.wall);
      case EntityType.lava:
        fillRect(e, Terrain.lava);
      case EntityType.bridge:
        fillRect(e, Terrain.bridge);
      case EntityType.castle:
        final door = castleDoorCell(e);
        for (var y = e.y; y < e.y + e.h; y++) {
          for (var x = e.x; x < e.x + e.w; x++) {
            final onRing = x == e.x || y == e.y || x == e.x + e.w - 1 || y == e.y + e.h - 1;
            if (!onRing) continue;
            if (x == door.x && y == door.y) {
              // An open doorway (color null) leaves this cell to other entities.
              if (e.door!.color != null) paint(x, y, Terrain.door, e.door!.color);
            } else {
              paint(x, y, Terrain.wall);
            }
          }
        }
      case EntityType.door:
        paint(e.x, e.y, Terrain.door, e.color);
      case EntityType.key || EntityType.treasure || EntityType.coin:
        if (grid.inBounds(e.x, e.y)) grid.items[grid.index(e.x, e.y)].add(Item(e.id, e.type, e.color));
    }
  }
  return grid;
}

bool isBlocked(Terrain t) => t == Terrain.wall || t == Terrain.lava;

/// Ascii map used by the shared fixtures. S, F and the first item on a cell are drawn over terrain.
List<String> toAscii(World world, [Grid? grid]) {
  final g = grid ?? rasterize(world);
  const terrainChar = {Terrain.ground: '.', Terrain.lava: '~', Terrain.bridge: '=', Terrain.wall: '#'};
  const doorChar = {GameColor.red: 'R', GameColor.blue: 'B', GameColor.gold: 'G'};
  const keyChar = {GameColor.red: 'r', GameColor.blue: 'b', GameColor.gold: 'g'};
  return [
    for (var y = 0; y < g.height; y++)
      [
        for (var x = 0; x < g.width; x++)
          if (x == world.start.x && y == world.start.y)
            'S'
          else if (x == world.flag.x && y == world.flag.y)
            'F'
          else if (g.items[g.index(x, y)].firstOrNull case final item?)
            switch (item.type) {
              EntityType.key => keyChar[item.color]!,
              EntityType.treasure => 'T',
              _ => 'c',
            }
          else if (g.terrainAt(x, y) == Terrain.door)
            doorChar[g.doorColor[g.index(x, y)]]!
          else
            terrainChar[g.terrainAt(x, y)]!,
      ].join(),
  ];
}
