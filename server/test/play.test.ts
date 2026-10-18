import { describe, test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { aiPlaytest, enemyX, Game, readRun, replay, RIGHT, routeOf, search, type Segment } from "../src/studio/play.ts";
import { applyActions, readScene, type Scene } from "../src/studio/scene.ts";

const fixture = (name: string) => JSON.parse(readFileSync(new URL(`../../spec/fixtures/${name}`, import.meta.url), "utf8"));
const starter: Scene = readScene(fixture("scenes.json").cases[0].scene);

describe("spec/fixtures/scene_runs.json", () => {
  for (const c of fixture("scene_runs.json").cases as { name: string; scene: unknown; run: Segment[]; checks: { after: number; expect: Record<string, unknown> }[] }[]) {
    test(c.name, () => {
      const game = new Game(readScene(c.scene));
      const flat = c.run.flatMap(([frames, bits]) => Array<number>(frames).fill(bits));
      let done = 0;
      for (const check of c.checks) {
        while (done < check.after) game.step(flat[done++] ?? 0);
        const state: Record<string, unknown> = { ...game, enemies: Object.fromEntries(game.enemies.map((e) => [e.id, enemyAt(game, e.id)])) };
        for (const [key, want] of Object.entries(check.expect)) {
          const got = state[key];
          if (typeof want === "number") assert.ok(Math.abs((got as number) - want) < 1e-6, `${key} after ${check.after}: ${String(got)} ≠ ${want}`);
          else if (key === "enemies") for (const [id, x] of Object.entries(want as Record<string, number>)) assert.ok(Math.abs((state.enemies as Record<string, number>)[id]! - x) < 1e-6, `${id} after ${check.after}`);
          else assert.deepEqual(got, want, `${key} after ${check.after}`);
        }
      }
    });
  }
});

function enemyAt(game: Game, id: string) {
  return enemyX(game.enemies.find((e) => e.id === id)!, game.frame);
}

describe("the AI player", () => {
  test("finishes the starter scene and gets both coins", async () => {
    const report = await aiPlaytest(starter);
    assert.ok(report.finished, "it reaches the finish");
    assert.equal(report.result.won, true);
    assert.equal(report.result.deaths, 0);
    assert.ok(report.result.time > 4 && report.result.time < 20, `time ${report.result.time}`);
    assert.deepEqual(report.coinsMissed, []);
    assert.equal(report.route[0], "ground-1");
    assert.ok(report.route.includes("ground-2"));
    // Its run is a real run: replayed, it wins the same way.
    const again = replay(starter, report.run);
    assert.deepEqual(again.result(), report.result);
  });

  test("says when the finish cannot be reached, and which coin is out of reach", async () => {
    const gap = applyActions(starter, [
      { type: "DELETE_OBJECT", id: "ledge-c" },
      { type: "UPDATE_OBJECT", id: "ground-2", x: 1100, w: 500 },
      { type: "UPDATE_OBJECT", id: "enemy-1", x: 1200 },
      { type: "CREATE_OBJECT", objectType: "coin", x: 300, y: 200, id: "sky-coin" },
    ]).scene;
    let ticks = 0;
    const timer = setInterval(() => ticks++, 5);
    const report = await aiPlaytest(gap);
    clearInterval(timer);
    assert.ok(ticks > 10, "the server keeps answering while the AI plays");
    assert.equal(report.finished, false);
    assert.ok(report.coinsMissed.includes("sky-coin"));
    assert.ok(!report.coinsMissed.includes("coin-1"));
  });

  test("finds a way past a patrolling enemy without dying", () => {
    const result = search(starter, (g) => g.x > 1350, { x: 1400, y: 772, w: 32, h: 48 });
    assert.ok(result.found);
    assert.equal(result.game.deaths, 0);
  });

  test("a run's route names the platforms it stood on", () => {
    assert.deepEqual(routeOf(starter, [[60, RIGHT]]), ["ground-1"]);
  });
});

describe("runs from clients", () => {
  test("are checked before they are replayed", () => {
    assert.deepEqual(readRun([[10, 2], [1, 6]]), [[10, 2], [1, 6]]);
    assert.throws(() => readRun([[0, 2]]));
    assert.throws(() => readRun([[10, 9]]));
    assert.throws(() => readRun("run"));
  });

  test("a replay stops at ten minutes", () => {
    const game = replay(starter, [[120 * 700, 0]]);
    assert.equal(game.frame, 120 * 600);
  });
});
