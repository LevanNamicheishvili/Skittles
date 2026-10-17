// Rasterization: entities -> one terrain per cell plus an item layer (spec/rules.md section 3).

import { COLORS, type CastleEntity, type Cell, type Color, type World } from "./types.ts";

// The numeric value is the precedence: a higher value wins when entities overlap.
export const Terrain = { ground: 0, lava: 1, bridge: 2, wall: 3, door: 4 } as const;
export type TerrainCode = (typeof Terrain)[keyof typeof Terrain];

export type Item =
  | { id: string; kind: "key"; color: Color }
  | { id: string; kind: "treasure" | "coin" };

export type Grid = {
  w: number;
  h: number;
  terrain: Uint8Array;
  // Index into COLORS for door cells, -1 elsewhere.
  doorColor: Int8Array;
  // Items per cell index, in entity order.
  items: Item[][];
};

export function cellIndex(grid: { w: number }, x: number, y: number): number {
  return y * grid.w + x;
}

export function inBounds(grid: { w: number; h: number }, x: number, y: number): boolean {
  return x >= 0 && y >= 0 && x < grid.w && y < grid.h;
}

export function castleDoorCell(c: CastleEntity): Cell {
  switch (c.door.side) {
    case "left":
      return { x: c.x, y: c.y + 1 + c.door.offset };
    case "right":
      return { x: c.x + c.w - 1, y: c.y + 1 + c.door.offset };
    case "top":
      return { x: c.x + 1 + c.door.offset, y: c.y };
    case "bottom":
      return { x: c.x + 1 + c.door.offset, y: c.y + c.h - 1 };
  }
}

export function rasterize(world: World): Grid {
  const { w, h } = world.grid;
  const grid: Grid = {
    w,
    h,
    terrain: new Uint8Array(w * h),
    doorColor: new Int8Array(w * h).fill(-1),
    items: Array.from({ length: w * h }, () => []),
  };

  const paint = (x: number, y: number, code: TerrainCode, color: Color | null = null): void => {
    if (!inBounds(grid, x, y)) return;
    const i = cellIndex(grid, x, y);
    const current = grid.terrain[i] as TerrainCode;
    // Equal precedence only matters for doors: the later door decides the color.
    if (code > current || (code === Terrain.door && current === Terrain.door)) {
      grid.terrain[i] = code;
      grid.doorColor[i] = code === Terrain.door && color !== null ? COLORS.indexOf(color) : -1;
    }
  };

  const fillRect = (x0: number, y0: number, rw: number, rh: number, code: TerrainCode): void => {
    for (let y = y0; y < y0 + rh; y++) {
      for (let x = x0; x < x0 + rw; x++) paint(x, y, code);
    }
  };

  for (const e of world.entities) {
    switch (e.type) {
      case "wall":
        fillRect(e.x, e.y, e.w, e.h, Terrain.wall);
        break;
      case "lava":
        fillRect(e.x, e.y, e.w, e.h, Terrain.lava);
        break;
      case "bridge":
        fillRect(e.x, e.y, e.w, e.h, Terrain.bridge);
        break;
      case "castle": {
        const door = castleDoorCell(e);
        for (let y = e.y; y < e.y + e.h; y++) {
          for (let x = e.x; x < e.x + e.w; x++) {
            const onRing = x === e.x || y === e.y || x === e.x + e.w - 1 || y === e.y + e.h - 1;
            if (!onRing) continue;
            if (x === door.x && y === door.y) {
              // An open doorway (color null) leaves this cell to other entities.
              if (e.door.color !== null) paint(x, y, Terrain.door, e.door.color);
            } else {
              paint(x, y, Terrain.wall);
            }
          }
        }
        break;
      }
      case "door":
        paint(e.x, e.y, Terrain.door, e.color);
        break;
      case "key":
        if (inBounds(grid, e.x, e.y)) grid.items[cellIndex(grid, e.x, e.y)]!.push({ id: e.id, kind: "key", color: e.color });
        break;
      case "treasure":
      case "coin":
        if (inBounds(grid, e.x, e.y)) grid.items[cellIndex(grid, e.x, e.y)]!.push({ id: e.id, kind: e.type });
        break;
    }
  }
  return grid;
}

export function isBlockedTerrain(code: number): boolean {
  return code === Terrain.wall || code === Terrain.lava;
}

const TERRAIN_CHAR: Record<number, string> = {
  [Terrain.ground]: ".",
  [Terrain.lava]: "~",
  [Terrain.bridge]: "=",
  [Terrain.wall]: "#",
};
const DOOR_CHAR: Record<Color, string> = { red: "R", blue: "B", gold: "G" };
const KEY_CHAR: Record<Color, string> = { red: "r", blue: "b", gold: "g" };

// Ascii map used by the shared fixtures. S, F and the first item on a cell are drawn over terrain.
export function toAscii(world: World, grid: Grid = rasterize(world)): string[] {
  const rows: string[] = [];
  for (let y = 0; y < grid.h; y++) {
    let row = "";
    for (let x = 0; x < grid.w; x++) {
      const i = cellIndex(grid, x, y);
      const item = grid.items[i]![0];
      if (x === world.start.x && y === world.start.y) row += "S";
      else if (x === world.flag.x && y === world.flag.y) row += "F";
      else if (item) row += item.kind === "key" ? KEY_CHAR[item.color] : item.kind === "treasure" ? "T" : "c";
      else if (grid.terrain[i] === Terrain.door) row += DOOR_CHAR[COLORS[grid.doorColor[i]!]!];
      else row += TERRAIN_CHAR[grid.terrain[i]!];
    }
    rows.push(row);
  }
  return rows;
}
