import { describe, test } from "node:test";
import assert from "node:assert/strict";
import { toAscii } from "../src/game/raster.ts";
import { PlayEngine, snapshot } from "../src/game/play.ts";
import { solve } from "../src/game/solver.ts";
import { validateWorld } from "../src/game/validate.ts";
import { playCases, playWorld, solverCases } from "./fixtures.ts";

describe("solver fixtures", () => {
  for (const c of solverCases) {
    test(c.name, () => {
      assert.deepEqual(validateWorld(c.world).errors, []);
      assert.deepEqual(toAscii(c.world), c.ascii);

      const { path, ...result } = solve(c.world);
      assert.deepEqual(result, c.expect);

      // The solver's path must win under the Play rules in exactly that many inputs.
      if (path) {
        const engine = new PlayEngine(c.world);
        const beforeLast = engine.run(path.slice(0, -1));
        const final = engine.step(beforeLast, path.at(-1)!);
        assert.equal(beforeLast.won, false);
        assert.equal(final.won, true);
        assert.equal(final.deaths, 0);
      }
    });
  }
});

describe("play fixtures", () => {
  for (const c of playCases) {
    test(c.name, () => {
      const engine = new PlayEngine(playWorld(c));
      assert.deepEqual(snapshot(engine.run(c.inputs)), c.expect);
    });
  }
});
