// Client-side "what if": apply proposed ops to a copy of the level and run the shared solver on it.
// Shape and rule checks stay on the server; this only feeds the board's previews.

import { cellIndex, rasterize, Terrain } from "../../server/src/game/raster.ts";
import { solve } from "../../server/src/game/solver.ts";
import { DELTA, type Cell, type Direction, type Entity, type World } from "../../server/src/game/types.ts";
import type { Op } from "../../server/src/room/ops.ts";

export function previewWorld(world: World, ops: readonly Op[]): World {
  const next: World = structuredClone(world);
  for (const op of ops) {
    if (op.op === "create") next.entities.push(structuredClone(op.entity));
    else if (op.op === "update") {
      const i = next.entities.findIndex((e) => e.id === op.id);
      if (i >= 0) next.entities[i] = { ...next.entities[i]!, ...op.set } as Entity;
    } else if (op.op === "delete") next.entities = next.entities.filter((e) => e.id !== op.id);
    else if (op.op === "set_world") {
      if (op.set.start) next.start = op.set.start;
      if (op.set.flag) next.flag = op.set.flag;
    } else if (op.op === "replace_world") return structuredClone(op.world);
  }
  return next;
}

export function routeOf(world: World): Direction[] | undefined {
  try {
    return solve(world).path;
  } catch {
    return undefined;
  }
}

// The step at which the route first runs into something impassable in `world`, if it does.
export function blockedAt(world: World, from: Cell, path: readonly Direction[]): number | undefined {
  const grid = rasterize(world);
  let { x, y } = from;
  for (let i = 0; i < path.length; i++) {
    x += DELTA[path[i]!].x;
    y += DELTA[path[i]!].y;
    const t = grid.terrain[cellIndex(grid, x, y)];
    if (t === Terrain.wall || t === Terrain.lava) return i;
  }
  return undefined;
}
