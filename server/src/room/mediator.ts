// Diagnosis of a broken level and deterministic fix candidates. Every candidate is re-checked by
// the solver before anyone sees it, so the mediator never offers a fix that does not work.

import { castleDoorCell, cellIndex, inBounds, rasterize, Terrain, type Grid } from "../game/raster.ts";
import { solve } from "../game/solver.ts";
import { COLORS, DELTA, DIRECTIONS, type Cell, type Color, type Direction, type Entity, type World } from "../game/types.ts";
import { applyOps, type Op } from "./ops.ts";

export type Blocker = { id: string; type: Entity["type"]; ownerId?: string };

// blockers: what stands in the way of every route. closedBy: what the change put on the route that used to work.
export type Diagnosis = { unreachable: string[]; blockers: Blocker[]; closedBy: Blocker[] };

export type FixOption = {
  id: string;
  kind: "bridge" | "move" | "key" | "cancel" | "agent";
  // For kind "agent": the author whose agent proposed this compromise.
  from?: string;
  title: string;
  detail: string;
  ops: Op[];
  // Authors whose objects this fix covers or changes; each must approve it.
  touches: string[];
};

export type NameOf = (ownerId: string | undefined) => string;

// Cells reachable from start. Items never block movement, so the state is (cell, keys) only.
export function reachableCells(world: World, grid: Grid = rasterize(world)): Uint8Array {
  const cells = grid.w * grid.h;
  const keyGain = new Uint8Array(cells);
  for (let i = 0; i < cells; i++) {
    for (const it of grid.items[i]!) if (it.kind === "key") keyGain[i]! |= 1 << COLORS.indexOf(it.color);
  }
  const seen = new Uint8Array(cells * 8);
  const reached = new Uint8Array(cells);
  const start = cellIndex(grid, world.start.x, world.start.y);
  const queue: number[] = [start * 8 + keyGain[start]!];
  seen[queue[0]!] = 1;
  reached[start] = 1;
  while (queue.length > 0) {
    const id = queue.shift()!;
    const cell = Math.floor(id / 8);
    const keys = id % 8;
    for (const dir of DIRECTIONS) {
      const nx = (cell % grid.w) + DELTA[dir].x;
      const ny = Math.floor(cell / grid.w) + DELTA[dir].y;
      if (!inBounds(grid, nx, ny)) continue;
      const n = cellIndex(grid, nx, ny);
      const t = grid.terrain[n];
      if (t === Terrain.wall || t === Terrain.lava) continue;
      if (t === Terrain.door && (keys & (1 << grid.doorColor[n]!)) === 0) continue;
      const next = n * 8 + (keys | keyGain[n]!);
      if (seen[next]) continue;
      seen[next] = 1;
      reached[n] = 1;
      queue.push(next);
    }
  }
  return reached;
}

const ownerIdOf = (e: Entity): string | undefined => e.owner.playerId;

function coversCell(e: Entity, x: number, y: number): boolean {
  const w = "w" in e ? e.w : 1;
  const h = "h" in e ? e.h : 1;
  return x >= e.x && y >= e.y && x < e.x + w && y < e.y + h;
}

// The entity that decides the terrain of a cell: the last one of the given types covering it.
function topEntityAt(world: World, x: number, y: number, types: readonly Entity["type"][]): Entity | undefined {
  let found: Entity | undefined;
  for (const e of world.entities) {
    if (!types.includes(e.type)) continue;
    if (e.type === "castle") {
      const ring = x === e.x || y === e.y || x === e.x + e.w - 1 || y === e.y + e.h - 1;
      if (ring && coversCell(e, x, y)) found = e;
    } else if (coversCell(e, x, y)) found = e;
  }
  return found;
}

// Impassable entities met when walking `path` from `from` through `world`.
function blockersOnPath(world: World, grid: Grid, from: Cell, path: readonly Direction[]): Blocker[] {
  const found = new Map<string, Blocker>();
  let { x, y } = from;
  for (const dir of path) {
    x += DELTA[dir].x;
    y += DELTA[dir].y;
    const t = grid.terrain[cellIndex(grid, x, y)];
    if (t !== Terrain.lava && t !== Terrain.wall && t !== Terrain.door) continue;
    const e = topEntityAt(world, x, y, t === Terrain.lava ? ["lava"] : ["wall", "castle", "door"]);
    if (e && !found.has(e.id)) found.set(e.id, { id: e.id, type: e.type, ownerId: ownerIdOf(e) });
  }
  return [...found.values()];
}

// Walks a winning path in a relaxed copy of the world and reports what the real world puts in its way.
// With the world before the change, it also reports what the change put on the route that used to work.
export function diagnose(world: World, before?: World): Diagnosis {
  const unreachable = solve(world).unreachable;
  const grid = rasterize(world);
  const oldPath = before ? solve(before).path : undefined;
  const closedBy = before && oldPath ? blockersOnPath(world, grid, before.start, oldPath) : [];
  const relaxations: Entity["type"][][] = [["lava"], ["lava", "wall", "castle", "door"]];
  for (const removed of relaxations) {
    const relaxed: World = { ...world, entities: world.entities.filter((e) => !removed.includes(e.type)) };
    const result = solve(relaxed);
    if (!result.solvable || !result.path) continue;
    return { unreachable, blockers: blockersOnPath(world, grid, world.start, result.path), closedBy };
  }
  return { unreachable, blockers: [], closedBy };
}

export function describeDiagnosis(d: Diagnosis, nameOf: NameOf): string {
  const goals = d.unreachable.map((u) =>
    u === "flag" ? "the flag" : u === "collect_count:coin" ? "enough coins" : `treasure ${u.slice("collect:".length)}`,
  );
  const what = goals.length > 0 ? goals.join(" and ") : "the goal";
  const list = (bs: Blocker[]) => bs.map((b) => `${nameOf(b.ownerId)}'s ${b.type} ${b.id}`).join(" and ");
  const rest = d.blockers.filter((b) => !d.closedBy.some((c) => c.id === b.id));
  if (d.closedBy.length > 0 && rest.length > 0) {
    return `This would make ${what} unreachable: ${list(d.closedBy)} closes the old route, and ${list(rest)} leaves no way around.`;
  }
  if (d.closedBy.length > 0) return `This would make ${what} unreachable: ${list(d.closedBy)} closes the only route.`;
  if (d.blockers.length > 0) return `This would make ${what} unreachable: ${list(d.blockers)} cuts the only way through.`;
  return `This would make ${what} unreachable.`;
}

const distance = (a: Cell, b: Cell): number => Math.abs(a.x - b.x) + Math.abs(a.y - b.y);

// Free cells the player can reach: ground or bridge, no item, not start or flag. Nearest to `near` first.
function freeReachableCells(world: World, grid: Grid, reached: Uint8Array, near: Cell): Cell[] {
  const cells: Cell[] = [];
  for (let y = 0; y < grid.h; y++) {
    for (let x = 0; x < grid.w; x++) {
      const i = cellIndex(grid, x, y);
      if (!reached[i] || grid.items[i]!.length > 0) continue;
      if (grid.terrain[i] !== Terrain.ground && grid.terrain[i] !== Terrain.bridge) continue;
      if ((x === world.start.x && y === world.start.y) || (x === world.flag.x && y === world.flag.y)) continue;
      cells.push({ x, y });
    }
  }
  return cells.sort((a, b) => distance(a, near) - distance(b, near) || a.y - b.y || a.x - b.x);
}

const fixes = (world: World, ops: Op[]): boolean => {
  const applied = applyOps(world, ops);
  return applied.ok && solve(applied.world).solvable;
};

// Straight bridges from the reachable area across lava to new ground, shortest first.
function bridgeFixes(world: World, grid: Grid, reached: Uint8Array, newId: () => string): Op[][] {
  const seen = new Set<string>();
  const candidates: { x: number; y: number; w: number; h: number; len: number }[] = [];
  for (let y = 0; y < grid.h; y++) {
    for (let x = 0; x < grid.w; x++) {
      if (!reached[cellIndex(grid, x, y)]) continue;
      for (const dir of DIRECTIONS) {
        const d = DELTA[dir];
        let len = 0;
        let cx = x + d.x;
        let cy = y + d.y;
        while (inBounds(grid, cx, cy) && grid.terrain[cellIndex(grid, cx, cy)] === Terrain.lava) {
          len++;
          cx += d.x;
          cy += d.y;
        }
        if (len === 0 || !inBounds(grid, cx, cy)) continue;
        const end = cellIndex(grid, cx, cy);
        if (reached[end] || grid.terrain[end] === Terrain.wall || grid.terrain[end] === Terrain.lava) continue;
        const bx = Math.min(x + d.x, cx - d.x);
        const by = Math.min(y + d.y, cy - d.y);
        const rect = { x: bx, y: by, w: d.x !== 0 ? len : 1, h: d.y !== 0 ? len : 1, len };
        const key = `${rect.x},${rect.y},${rect.w},${rect.h}`;
        if (!seen.has(key)) {
          seen.add(key);
          candidates.push(rect);
        }
      }
    }
  }
  candidates.sort((a, b) => a.len - b.len || a.y - b.y || a.x - b.x);
  // Among the shortest bridges that work, keep the one that leaves the player the shortest route.
  let best: { ops: Op[]; len: number; steps: number } | undefined;
  for (const r of candidates.slice(0, 80)) {
    if (best && r.len > best.len) break;
    const ops: Op[] = [
      {
        op: "create",
        entity: { id: "pending", type: "bridge", owner: { kind: "mediator" }, x: r.x, y: r.y, w: r.w, h: r.h, label: "Stone bridge" },
      },
    ];
    const applied = applyOps(world, ops);
    if (!applied.ok) continue;
    const result = solve(applied.world);
    if (!result.solvable) continue;
    if (!best || result.steps! < best.steps) best = { ops, len: r.len, steps: result.steps! };
  }
  if (!best) return [];
  (best.ops[0] as { entity: Entity }).entity.id = newId();
  return [best.ops];
}

export type ProposeInput = {
  after: World;
  // Ids the change created or changed, so the mediator prefers to move the author's own items.
  touchedIds: string[];
  requesterId: string;
  nameOf: NameOf;
  newId: () => string;
};

export function proposeFixes(input: ProposeInput): FixOption[] {
  const { after, touchedIds, requesterId, nameOf, newId } = input;
  const grid = rasterize(after);
  const reached = reachableCells(after, grid);
  const options: FixOption[] = [];
  const others = (ids: (string | undefined)[]): string[] =>
    [...new Set(ids.filter((id): id is string => id !== undefined && id !== requesterId))];

  for (const ops of bridgeFixes(after, grid, reached, newId)) {
    const b = (ops[0] as { entity: Entity & { w: number; h: number } }).entity;
    const covered: Entity[] = [];
    for (let y = b.y; y < b.y + b.h; y++) {
      for (let x = b.x; x < b.x + b.w; x++) {
        const lava = topEntityAt(after, x, y, ["lava"]);
        if (lava && !covered.includes(lava)) covered.push(lava);
      }
    }
    const over = covered.map((e) => `${nameOf(ownerIdOf(e))}'s lava`).join(" and ");
    options.push({
      id: "bridge",
      kind: "bridge",
      title: "Build a stone bridge",
      detail: `A ${b.w * b.h}-tile bridge at (${b.x}, ${b.y}) over ${over}. Both ideas stay.`,
      ops,
      touches: others(covered.map(ownerIdOf)),
    });
  }

  // Move an unreachable item to the nearest reachable free cell, the author's own items first.
  const items = after.entities
    .filter((e) => (e.type === "key" || e.type === "treasure" || e.type === "coin") && !reached[cellIndex(grid, e.x, e.y)])
    .sort((a, b) => Number(touchedIds.includes(b.id)) - Number(touchedIds.includes(a.id)));
  for (const item of items) {
    const spot = freeReachableCells(after, grid, reached, item).slice(0, 20).find((c) => fixes(after, [{ op: "update", id: item.id, set: c }]));
    if (!spot) continue;
    const name = item.type === "key" ? `the ${item.color} key` : `${item.type} ${item.id}`;
    options.push({
      id: "move",
      kind: "move",
      title: `Move ${name}`,
      detail: `Put ${name} at (${spot.x}, ${spot.y}), where the player can reach it.`,
      ops: [{ op: "update", id: item.id, set: { x: spot.x, y: spot.y } }],
      touches: others([ownerIdOf(item)]),
    });
    break;
  }

  // A locked door whose key cannot be reached: add a key of that color on the player's side.
  const doors = after.entities.filter(
    (e): e is Extract<Entity, { type: "door" | "castle" }> =>
      (e.type === "door" || (e.type === "castle" && e.door.color !== null)) && touchedIds.includes(e.id),
  );
  for (const door of doors) {
    const color: Color = door.type === "door" ? door.color : door.door.color!;
    const at = door.type === "door" ? { x: door.x, y: door.y } : castleDoorCell(door);
    const keyOps = (c: Cell): Op[] => [
      { op: "create", entity: { id: "pending", type: "key", owner: { kind: "mediator" }, x: c.x, y: c.y, color } },
    ];
    const spot = freeReachableCells(after, grid, reached, at).slice(0, 20).find((c) => fixes(after, keyOps(c)));
    if (!spot) continue;
    const ops = keyOps(spot);
    (ops[0] as { entity: Entity }).entity.id = newId();
    options.push({
      id: "key",
      kind: "key",
      title: `Add a ${color} key`,
      detail: `Place a ${color} key at (${spot.x}, ${spot.y}), on the player's side of the obstacle.`,
      ops,
      touches: [],
    });
    break;
  }

  options.push({ id: "cancel", kind: "cancel", title: "Cancel my change", detail: "Keep the level as it is now.", ops: [], touches: [] });
  return options;
}
