import { describe, test } from "node:test";
import assert from "node:assert/strict";
import { Ajv2020 } from "ajv/dist/2020.js";
import { loadJson, playCases, solverCases } from "./fixtures.ts";

const ajv = new Ajv2020({ allErrors: true, strict: true });
ajv.addSchema(loadJson("schema/world.schema.json"));
ajv.addSchema(loadJson("schema/ops.schema.json"));
const worldSchema = ajv.getSchema("https://github.com/LevanNamicheishvili/Skittles/blob/main/spec/schema/world.schema.json")!;
const opsSchema = ajv.getSchema("https://github.com/LevanNamicheishvili/Skittles/blob/main/spec/schema/ops.schema.json")!;

describe("world schema", () => {
  const worlds = [
    ...solverCases.map((c) => [c.name, c.world] as const),
    ...playCases.filter((c) => c.world).map((c) => [c.name, c.world] as const),
  ];
  for (const [name, world] of worlds) {
    test(`fixture ${name} matches the schema`, () => {
      assert.ok(worldSchema(world), JSON.stringify(worldSchema.errors));
    });
  }

  test("rejects an unknown entity type", () => {
    const world = structuredClone(solverCases[0]!.world) as unknown as { entities: unknown[] };
    world.entities.push({ id: "x1", type: "dragon", owner: { kind: "system" }, x: 0, y: 0 });
    assert.equal(worldSchema(world), false);
  });

  test("rejects a castle smaller than 3 x 3", () => {
    const world = structuredClone(solverCases[0]!.world) as unknown as { entities: unknown[] };
    world.entities.push({
      id: "c9", type: "castle", owner: { kind: "system" }, x: 0, y: 0, w: 2, h: 3,
      door: { side: "left", offset: 0, color: null },
    });
    assert.equal(worldSchema(world), false);
  });
});

describe("ops schema", () => {
  test("accepts every op kind", () => {
    const batch = {
      clientSeq: 7,
      ops: [
        { op: "create", entity: { id: "p1:1", type: "lava", owner: { kind: "player", playerId: "p1" }, x: 3, y: 0, w: 2, h: 7 } },
        { op: "update", id: "p1:1", set: { x: 4, label: "ლავის მდინარე" } },
        { op: "delete", id: "p1:1" },
        { op: "set_world", set: { start: { x: 0, y: 3 } } },
        { op: "set_objectives", objectives: [{ type: "collect_count", item: "coin", count: 2 }] },
      ],
    };
    assert.ok(opsSchema(batch), JSON.stringify(opsSchema.errors));
  });

  test("rejects an update of a property that is not editable", () => {
    assert.equal(opsSchema({ clientSeq: 1, ops: [{ op: "update", id: "a:1", set: { type: "wall" } }] }), false);
  });

  test("rejects an empty update and an empty batch", () => {
    assert.equal(opsSchema({ clientSeq: 1, ops: [{ op: "update", id: "a:1", set: {} }] }), false);
    assert.equal(opsSchema({ clientSeq: 1, ops: [] }), false);
  });
});
