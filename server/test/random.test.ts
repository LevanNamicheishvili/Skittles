// Cross-checks the solver against a second, independent search that only uses the Play rules.

import { test } from "node:test";
import assert from "node:assert/strict";
import { PlayEngine, type PlayState } from "../src/game/play.ts";
import { solve } from "../src/game/solver.ts";
import { validateWorld } from "../src/game/validate.ts";
import { COLORS, DIRECTIONS, type Entity, type Objective, type World } from "../src/game/types.ts";

function mulberry32(seed: number): () => number {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function randomWorld(seed: number): World {
  const rnd = mulberry32(seed);
  const int = (lo: number, hi: number): number => lo + Math.floor(rnd() * (hi - lo + 1));
  const pick = <T,>(xs: readonly T[]): T => xs[int(0, xs.length - 1)]!;
  const w = int(4, 8);
  const h = int(3, 6);
  const entities: Entity[] = [];
  let n = 0;
  const owner = { kind: "system" } as const;
  for (let i = int(0, 4); i > 0; i--) {
    const x = int(0, w - 1);
    const y = int(0, h - 1);
    entities.push({ id: `e${n++}`, type: pick(["wall", "lava", "bridge"] as const), owner, x, y, w: int(1, w - x), h: int(1, h - y) });
  }
  if (rnd() < 0.3 && w >= 4 && h >= 4) {
    const cw = int(3, w);
    const ch = int(3, h);
    const side = pick(["left", "right", "top", "bottom"] as const);
    const span = side === "left" || side === "right" ? ch : cw;
    entities.push({
      id: `e${n++}`, type: "castle", owner, x: int(0, w - cw), y: int(0, h - ch), w: cw, h: ch,
      door: { side, offset: int(0, span - 3), color: rnd() < 0.3 ? null : pick(COLORS) },
    });
  }
  for (let i = int(0, 2); i > 0; i--) entities.push({ id: `e${n++}`, type: "door", owner, x: int(0, w - 1), y: int(0, h - 1), color: pick(COLORS) });
  for (let i = int(0, 3); i > 0; i--) entities.push({ id: `e${n++}`, type: "key", owner, x: int(0, w - 1), y: int(0, h - 1), color: pick(COLORS) });
  const collectibles: string[] = [];
  for (let i = int(0, 4); i > 0; i--) {
    const id = `e${n++}`;
    collectibles.push(id);
    entities.push({ id, type: pick(["treasure", "coin"] as const), owner, x: int(0, w - 1), y: int(0, h - 1) });
  }
  const objectives: Objective[] = [];
  for (const id of collectibles) if (rnd() < 0.4) objectives.push({ type: "collect", target: id });
  const coins = entities.filter((e) => e.type === "coin").length;
  if (coins > 0 && rnd() < 0.4) objectives.push({ type: "collect_count", item: "coin", count: int(1, coins) });
  return {
    schemaVersion: 1, grid: { w, h },
    start: { x: int(0, w - 1), y: int(0, h - 1) }, flag: { x: int(0, w - 1), y: int(0, h - 1) },
    entities, objectives,
  };
}

// Shortest number of inputs to win, searching states produced by PlayEngine.step alone.
function playSearch(engine: PlayEngine): number | null {
  const key = (s: PlayState): string => `${s.x},${s.y}|${[...s.keys].sort().join()}|${[...s.taken].sort().join()}`;
  const start = engine.initialState();
  const seen = new Set([key(start)]);
  let frontier = [start];
  for (let depth = 1; frontier.length > 0; depth++) {
    const next: PlayState[] = [];
    for (const s of frontier) {
      for (const d of DIRECTIONS) {
        const t = engine.step(s, d);
        if (t.won) return depth;
        // A death restarts from the initial state, which is already seen.
        const k = key({ ...t, deaths: 0 });
        if (seen.has(k)) continue;
        seen.add(k);
        next.push(t);
      }
    }
    frontier = next;
  }
  return null;
}

test("solver agrees with an independent Play-rules search on random worlds", () => {
  let checked = 0;
  let solvable = 0;
  for (let seed = 1; checked < 400; seed++) {
    const world = randomWorld(seed);
    if (validateWorld(world).errors.length > 0) continue;
    checked++;
    const result = solve(world);
    const expected = playSearch(new PlayEngine(world));
    assert.equal(result.solvable, expected !== null, `seed ${seed}`);
    if (expected !== null) {
      solvable++;
      assert.equal(result.steps, expected, `seed ${seed}`);
      assert.deepEqual(result.unreachable, [], `seed ${seed}`);
    } else {
      // Lemma in spec/rules.md section 6: unwinnable means something is unreachable.
      assert.ok(result.unreachable.length > 0, `seed ${seed}: unsolvable but nothing unreachable`);
    }
  }
  assert.ok(solvable > 50 && solvable < 350, `random worlds should mix outcomes, got ${solvable}/400 solvable`);
});
