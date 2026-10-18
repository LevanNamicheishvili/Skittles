import { describe, test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { applyActions, applyPatch, blankScene, byId, describePatch, diff, inverse, isEmpty, jumpOf, newErrors, readScene, validateScene, type Action, type Scene } from "../src/studio/scene.ts";

const fixture = (name: string) => JSON.parse(readFileSync(new URL(`../../spec/fixtures/${name}`, import.meta.url), "utf8"));

describe("spec/fixtures/scenes.json", () => {
  for (const c of fixture("scenes.json").cases as { name: string; scene: unknown; expect: { errors: string[]; warnings: string[]; finishReachable: boolean } }[]) {
    test(c.name, () => {
      const report = validateScene(readScene(c.scene));
      assert.deepEqual(new Set(report.errors.map((i) => i.code)), new Set(c.expect.errors), "errors");
      assert.deepEqual(new Set(report.issues.filter((i) => i.severity === "warning").map((i) => i.code)), new Set(c.expect.warnings), "warnings");
      assert.equal(report.finishReachable, c.expect.finishReachable, "finish");
    });
  }
});

describe("spec/fixtures/actions.json", () => {
  const file = fixture("actions.json");
  const scene = readScene(file.scene);
  for (const c of file.cases as { name: string; actions: Action[]; expect: Record<string, unknown> & { count: number; created: string[]; notes: string[]; objects: Record<string, unknown>[]; missing?: string[] } }[]) {
    test(c.name, () => {
      const r = applyActions(scene, c.actions);
      const e = c.expect;
      assert.equal(r.scene.objects.length, e.count);
      assert.deepEqual(r.created, e.created);
      assert.deepEqual(r.notes, e.notes);
      for (const o of e.objects) {
        const got = byId(r.scene, o.id as string) as unknown as Record<string, unknown>;
        for (const key of Object.keys(o)) assert.deepEqual(got[key], o[key], `${String(o.id)}.${key}`);
      }
      for (const id of e.missing ?? []) assert.equal(byId(r.scene, id), undefined);
      if ("theme" in e) assert.equal(r.scene.theme, e.theme);
      if ("name" in e) assert.equal(r.scene.name, e.name);
      if ("score" in e) assert.equal(r.scene.ui.score, e.score);
    });
  }
});

describe("scenes", () => {
  const starter: Scene = readScene(fixture("scenes.json").cases[0].scene);

  test("the jump model matches the spec", () => {
    const jump = jumpOf(260, 640, 1800);
    assert.equal(Math.round(jump.height * 10) / 10, 113.8);
    assert.ok(Math.abs(jump.reach(-120) - 202.4) < 0.1);
    assert.ok(jump.reach(200) < 0);
  });

  test("files that are not scenes are refused, and unknown fields dropped", () => {
    assert.throws(() => readScene({ format: "other" }));
    assert.throws(() => readScene({ ...starter, version: 9 }));
    const read = readScene({ ...starter, objects: [{ id: "a", type: "coin", x: 1, y: 2, w: 24, h: 24, script: "x", behaviours: { collectible: { points: 5, eval: 1 }, magic: {} } }] });
    assert.deepEqual(read.objects[0], { id: "a", name: "a", type: "coin", x: 1, y: 2, w: 24, h: 24, behaviours: { collectible: { points: 5 } } });
  });

  test("objects an agent creates carry its member, and a free id it gives is kept", () => {
    const r = applyActions(starter, [
      { type: "CREATE_OBJECT", objectType: "coin", x: 100, y: 100, id: "sky-coin" },
      { type: "CREATE_OBJECT", objectType: "coin", x: 140, y: 100, id: "coin-1" },
    ], "m2");
    assert.deepEqual(r.created, ["sky-coin", "coin-3"]);
    assert.equal(byId(r.scene, "sky-coin")!.by, "m2");
  });

  test("a blank scene is empty and says there is no player and no finish", () => {
    const report = validateScene(blankScene());
    assert.deepEqual(report.errors.map((e) => e.code), ["no_player", "no_finish"]);
  });

  test("a patch records a change, applies it again and undoes it", () => {
    const after = applyActions(starter, [
      { type: "UPDATE_OBJECT", id: "coin-1", x: 300 },
      { type: "DELETE_OBJECT", id: "coin-2" },
      { type: "CREATE_OBJECT", objectType: "platform", x: 200, y: 300 },
      { type: "UPDATE_SCENE", theme: "night" },
    ]).scene;
    const patch = diff(starter, after);
    assert.deepEqual(Object.keys(patch.objects).sort(), ["coin-1", "coin-2", "platform-1"]);
    assert.equal(patch.objects["coin-2"], null);
    assert.deepEqual(patch.scene, { theme: "night" });
    assert.deepEqual(applyPatch(starter, patch), after);
    const undone = applyPatch(after, inverse(starter, patch));
    assert.deepEqual(new Set(undone.objects.map((o) => o.id)), new Set(starter.objects.map((o) => o.id)));
    assert.deepEqual(byId(undone, "coin-1"), byId(starter, "coin-1"));
    assert.equal(undone.theme, starter.theme);
    assert.ok(isEmpty(diff(starter, starter)));
    assert.deepEqual(describePatch(starter, patch), ["~ Moved Coin to (300, 660)", "+ Platform 6 at (200, 300)", "− Removed Coin", "~ Scene · night theme"]);
  });

  test("a patch keeps objects inside the scene", () => {
    const p = applyPatch(starter, { objects: { "coin-1": { ...byId(starter, "coin-1")!, x: -50, y: 5000 } } });
    assert.deepEqual([byId(p, "coin-1")!.x, byId(p, "coin-1")!.y], [0, starter.size.h - 24]);
  });

  test("newErrors names only what a change broke", () => {
    const broken = applyActions(starter, [{ type: "DELETE_OBJECT", id: "ground-2" }]).scene;
    assert.deepEqual(newErrors(starter, broken).map((e) => e.code), ["finish_unreachable"]);
    assert.deepEqual(newErrors(broken, broken), []);
  });
});
