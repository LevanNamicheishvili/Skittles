import { readFileSync } from "node:fs";
import { join } from "node:path";
import type { Direction, World } from "../src/game/types.ts";
import type { PlaySnapshot } from "../src/game/play.ts";

export const specDir = join(import.meta.dirname, "..", "..", "spec");

export function loadJson<T = unknown>(relativeToSpec: string): T {
  return JSON.parse(readFileSync(join(specDir, relativeToSpec), "utf8")) as T;
}

export type SolverCase = {
  name: string;
  ascii: string[];
  world: World;
  expect: { solvable: boolean; steps?: number; unreachable: string[] };
};

export type PlayCase = {
  name: string;
  worldRef?: string;
  world?: World;
  inputs: Direction[];
  expect: PlaySnapshot;
};

export const solverCases = loadJson<{ cases: SolverCase[] }>("fixtures/solver.json").cases;

export const playCases = loadJson<{ cases: PlayCase[] }>("fixtures/play.json").cases;

export function playWorld(c: PlayCase): World {
  if (c.world) return c.world;
  const ref = solverCases.find((s) => s.name === c.worldRef);
  if (!ref) throw new Error(`play case ${c.name}: unknown worldRef ${c.worldRef}`);
  return ref.world;
}
