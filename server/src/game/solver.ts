// Breadth-first solver over (cell, keys, relevant items) states (spec/rules.md section 6).

import { cellIndex, rasterize, Terrain, type Grid } from "./raster.ts";
import { COLORS, DELTA, DIRECTIONS, type Direction, type World } from "./types.ts";

export type SolveResult = {
  solvable: boolean;
  steps?: number;
  // Shortest winning input sequence, present when solvable.
  path?: Direction[];
  unreachable: string[];
};

// Validation caps treasures plus coins at 8; this guards memory if that cap is ever bypassed.
const MAX_RELEVANT_ITEMS = 12;

function popcount(n: number): number {
  let c = 0;
  for (let v = n; v !== 0; v &= v - 1) c++;
  return c;
}

export function solve(world: World, grid: Grid = rasterize(world)): SolveResult {
  const cells = grid.w * grid.h;

  // Bit per relevant item: collect targets, plus every coin when a count objective exists.
  const needsCoins = world.objectives.some((o) => o.type === "collect_count");
  const bitOf = new Map<string, number>();
  for (const e of world.entities) {
    const relevant =
      (e.type === "coin" && needsCoins) ||
      ((e.type === "treasure" || e.type === "coin") &&
        world.objectives.some((o) => o.type === "collect" && o.target === e.id));
    if (relevant && !bitOf.has(e.id)) bitOf.set(e.id, bitOf.size);
  }
  if (bitOf.size > MAX_RELEVANT_ITEMS) throw new Error(`too many relevant items: ${bitOf.size}`);
  let coinBits = 0;
  for (const e of world.entities) if (e.type === "coin" && bitOf.has(e.id)) coinBits |= 1 << bitOf.get(e.id)!;

  // What entering each cell adds to the state.
  const keyGain = new Uint8Array(cells);
  const itemGain = new Int32Array(cells);
  for (let i = 0; i < cells; i++) {
    for (const it of grid.items[i]!) {
      if (it.kind === "key") keyGain[i]! |= 1 << COLORS.indexOf(it.color);
      else if (bitOf.has(it.id)) itemGain[i]! |= 1 << bitOf.get(it.id)!;
    }
  }

  const done = (mask: number): boolean =>
    world.objectives.every((o) =>
      o.type === "collect" ? (mask & (1 << (bitOf.get(o.target) ?? 31))) !== 0 : popcount(mask & coinBits) >= o.count,
    );

  const itemStates = 1 << bitOf.size;
  const stateId = (cell: number, keys: number, mask: number): number => (cell * 8 + keys) * itemStates + mask;
  const total = cells * 8 * itemStates;
  const parent = new Int32Array(total).fill(-2); // -2 unvisited, -1 root
  const parentDir = new Int8Array(total);
  const reached = new Uint8Array(cells);
  const flagCell = cellIndex(grid, world.flag.x, world.flag.y);

  const startCell = cellIndex(grid, world.start.x, world.start.y);
  const startId = stateId(startCell, keyGain[startCell]!, itemGain[startCell]!);
  parent[startId] = -1;
  reached[startCell] = 1;
  const queue = new Int32Array(total);
  let head = 0;
  let tail = 0;
  queue[tail++] = startId;
  let goal = -1;

  while (head < tail) {
    const id = queue[head++]!;
    const mask = id % itemStates;
    const keys = Math.floor(id / itemStates) % 8;
    const cell = Math.floor(id / itemStates / 8);
    if (cell === flagCell && done(mask)) {
      goal = id;
      break;
    }
    const cx = cell % grid.w;
    const cy = Math.floor(cell / grid.w);
    for (let d = 0; d < DIRECTIONS.length; d++) {
      const delta = DELTA[DIRECTIONS[d]!];
      const nx = cx + delta.x;
      const ny = cy + delta.y;
      if (nx < 0 || ny < 0 || nx >= grid.w || ny >= grid.h) continue;
      const n = cellIndex(grid, nx, ny);
      const t = grid.terrain[n];
      if (t === Terrain.wall || t === Terrain.lava) continue;
      if (t === Terrain.door && (keys & (1 << grid.doorColor[n]!)) === 0) continue;
      const next = stateId(n, keys | keyGain[n]!, mask | itemGain[n]!);
      if (parent[next] !== -2) continue;
      parent[next] = id;
      parentDir[next] = d;
      reached[n] = 1;
      queue[tail++] = next;
    }
  }

  if (goal >= 0) {
    const path: Direction[] = [];
    for (let id = goal; parent[id] !== -1; id = parent[id]!) path.push(DIRECTIONS[parentDir[id]!]!);
    path.reverse();
    return { solvable: true, steps: path.length, path, unreachable: [] };
  }

  // Exhausted: every reachable cell is marked, so report what can never be reached.
  const unreachable: string[] = [];
  const cellOf = (id: string): number | undefined => {
    const e = world.entities.find((en) => en.id === id);
    return e && "x" in e ? cellIndex(grid, e.x, e.y) : undefined;
  };
  for (const o of world.objectives) {
    if (o.type !== "collect") continue;
    const c = cellOf(o.target);
    if (c === undefined || !reached[c]) unreachable.push(`collect:${o.target}`);
  }
  const neededCoins = Math.max(0, ...world.objectives.map((o) => (o.type === "collect_count" ? o.count : 0)));
  if (neededCoins > 0) {
    const reachableCoins = world.entities.filter((e) => e.type === "coin" && reached[cellIndex(grid, e.x, e.y)]).length;
    if (reachableCoins < neededCoins) unreachable.push("collect_count:coin");
  }
  if (!reached[flagCell]) unreachable.push("flag");
  return { solvable: false, unreachable };
}
