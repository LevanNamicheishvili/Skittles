import { describe, test } from "node:test";
import assert from "node:assert/strict";
import { solve } from "../src/game/solver.ts";
import type { Entity, World } from "../src/game/types.ts";
import { demoLevel } from "../src/levels/demo.ts";
import { applyOps, type Op } from "../src/room/ops.ts";
import { Room, type RoomEvent } from "../src/room/room.ts";

const system = { kind: "system" } as const;

// 12 x 7, start on the left, flag on the right, nothing in between.
function field(): World {
  return { schemaVersion: 1, grid: { w: 12, h: 7 }, start: { x: 0, y: 3 }, flag: { x: 11, y: 3 }, entities: [], objectives: [] };
}

// Distributes over the union so each entity type keeps its own fields.
type NewEntity = Entity extends infer E ? (E extends Entity ? Omit<E, "id" | "owner"> & { id?: string } : never) : never;

const create = (entity: NewEntity): Op =>
  ({ op: "create", entity: { id: entity.id ?? "new", owner: system, ...entity } }) as Op;

function roomWithAuthors(world: World = field()) {
  const room = new Room(world);
  const events: RoomEvent[] = [];
  room.onEvent = (e) => events.push(e);
  const nino = room.join("Nino", "author");
  const giorgi = room.join("Giorgi", "author");
  return { room, events, nino, giorgi };
}

describe("ops", () => {
  test("a batch applies whole or not at all", () => {
    const world = field();
    const result = applyOps(world, [create({ type: "wall", x: 3, y: 0, w: 1, h: 2 }), { op: "delete", id: "missing" }]);
    assert.equal(result.ok, false);
    assert.equal(world.entities.length, 0);
  });

  test("rejects properties that a type does not have", () => {
    const world = field();
    world.entities.push({ id: "w1", type: "wall", owner: system, x: 3, y: 0, w: 1, h: 2 });
    const result = applyOps(world, [{ op: "update", id: "w1", set: { color: "red" } }]);
    assert.deepEqual(result.ok ? null : result.code, "not_editable");
  });

  test("rejects an object outside the grid", () => {
    const result = applyOps(field(), [create({ type: "lava", x: 10, y: 0, w: 5, h: 1 })]);
    assert.deepEqual(result.ok ? null : result.code, "out_of_bounds");
  });

  test("deleting an objective target also removes the objective", () => {
    const world = field();
    world.entities.push({ id: "t1", type: "treasure", owner: system, x: 5, y: 3 });
    world.objectives.push({ type: "collect", target: "t1" });
    const result = applyOps(world, [{ op: "delete", id: "t1" }]);
    assert.ok(result.ok);
    assert.deepEqual(result.world.objectives, []);
  });
});

describe("room", () => {
  test("the demo level starts winnable", () => {
    assert.equal(solve(demoLevel()).solvable, true);
  });

  test("a change is committed with the author's id and letter", () => {
    const { room, nino } = roomWithAuthors();
    const result = room.submit(nino.id, [create({ id: "river", type: "lava", x: 5, y: 0, w: 1, h: 2 })], "lava pond");
    assert.deepEqual(result, { status: "committed", rev: 1 });
    const lava = room.world.entities.find((e) => e.type === "lava")!;
    assert.equal(lava.id, "A1");
    assert.deepEqual(lava.owner, { kind: "assistant", playerId: nino.id });
    assert.equal(room.log[0]!.by, nino.id);
    assert.equal(room.log[0]!.summary, "lava pond");
  });

  test("a change that breaks the level waits for a fix and the level does not change", () => {
    const { room, nino } = roomWithAuthors();
    const result = room.submit(nino.id, [create({ type: "lava", x: 5, y: 0, w: 1, h: 7 })]);
    assert.equal(result.status, "conflict");
    assert.equal(room.rev, 0);
    assert.equal(room.world.entities.length, 0);
    const proposal = result.status === "conflict" ? result.proposal : undefined;
    assert.deepEqual(proposal?.diagnosis.unreachable, ["flag"]);
    assert.deepEqual(proposal?.options.map((o) => o.kind), ["bridge", "cancel"]);
    // The lava is Nino's own, so nobody else has to approve the bridge.
    assert.deepEqual(proposal?.options[0]!.touches, []);

    const chosen = room.choose(nino.id, proposal!.id, "bridge");
    assert.equal(chosen.status, "committed");
    assert.equal(room.solveResult.solvable, true);
    assert.equal(room.log[0]!.fix?.ops.length, 1);
  });

  test("two authors: a fix over someone else's object needs their approval", () => {
    const { room, nino, giorgi } = roomWithAuthors();
    // Nino: a lava river with one gap at the middle row.
    const river = room.submit(nino.id, [
      create({ id: "north", type: "lava", x: 5, y: 0, w: 1, h: 3 }),
      create({ id: "south", type: "lava", x: 5, y: 4, w: 1, h: 3 }),
    ]);
    assert.equal(river.status, "committed");

    // Giorgi: a statue that happens to stand in the gap. Each change alone is fine; together they break the level.
    const statue = room.submit(giorgi.id, [create({ type: "wall", x: 5, y: 3, w: 1, h: 1 })], "statue");
    assert.equal(statue.status, "conflict");
    const proposal = statue.status === "conflict" ? statue.proposal : undefined;
    assert.equal(
      proposal!.text,
      "This would make the flag unreachable: Giorgi's wall B1 closes the old route, and Nino's lava A1 leaves no way around.",
    );

    const bridge = proposal!.options.find((o) => o.kind === "bridge")!;
    assert.deepEqual(bridge.touches, [nino.id]);
    assert.equal(room.choose(giorgi.id, proposal!.id, "bridge").status, "awaiting_approval");
    assert.equal(room.rev, 1);

    assert.equal(room.answer(nino.id, proposal!.id, true).status, "committed");
    assert.equal(room.rev, 2);
    assert.equal(room.solveResult.solvable, true);
    assert.deepEqual(room.log[1]!.fix?.approvedBy, [nino.id]);
    assert.equal(room.log[1]!.by, giorgi.id);
  });

  test("a declined fix goes back to the author with the remaining options", () => {
    const { room, nino, giorgi } = roomWithAuthors();
    room.submit(nino.id, [create({ type: "lava", x: 5, y: 0, w: 1, h: 3 }), create({ type: "lava", x: 5, y: 4, w: 1, h: 3 })]);
    const statue = room.submit(giorgi.id, [create({ type: "wall", x: 5, y: 3, w: 1, h: 1 })]);
    const proposal = statue.status === "conflict" ? statue.proposal : undefined;
    room.choose(giorgi.id, proposal!.id, "bridge");
    assert.equal(room.answer(nino.id, proposal!.id, false).status, "rejected");
    assert.equal(proposal!.status, "open");
    assert.deepEqual(proposal!.options.map((o) => o.kind), ["cancel"]);
    assert.equal(room.rev, 1);
  });

  test("a locked castle with no reachable key gets a key on the player's side", () => {
    const { room, giorgi } = roomWithAuthors();
    const castle = room.submit(giorgi.id, [
      create({ type: "castle", x: 8, y: 1, w: 4, h: 5, door: { side: "left", offset: 1, color: "gold" } }),
      { op: "set_world", set: { flag: { x: 10, y: 3 } } },
    ]);
    assert.equal(castle.status, "conflict");
    const proposal = castle.status === "conflict" ? castle.proposal : undefined;
    assert.ok(proposal!.options.some((o) => o.kind === "key"));
    assert.equal(room.choose(giorgi.id, proposal!.id, "key").status, "committed");
    assert.equal(room.solveResult.solvable, true);
  });

  test("an unreachable key can be moved to where the player can reach it", () => {
    const { room, nino, giorgi } = roomWithAuthors();
    // Nino rings a cell with lava; Giorgi puts the castle key inside the ring.
    room.submit(nino.id, [
      create({ type: "lava", x: 1, y: 0, w: 3, h: 1 }),
      create({ type: "lava", x: 1, y: 2, w: 3, h: 1 }),
      create({ type: "lava", x: 1, y: 1, w: 1, h: 1 }),
      create({ type: "lava", x: 3, y: 1, w: 1, h: 1 }),
    ]);
    const result = room.submit(giorgi.id, [
      create({ type: "castle", x: 8, y: 1, w: 4, h: 5, door: { side: "left", offset: 1, color: "gold" } }),
      create({ type: "key", x: 2, y: 1, color: "gold" }),
      { op: "set_world", set: { flag: { x: 10, y: 3 } } },
    ]);
    const proposal = result.status === "conflict" ? result.proposal : undefined;
    const move = proposal!.options.find((o) => o.kind === "move");
    assert.ok(move, JSON.stringify(proposal!.options.map((o) => o.kind)));
    assert.equal(room.choose(giorgi.id, proposal!.id, "move").status, "committed");
    assert.equal(room.solveResult.solvable, true);
  });

  test("a change under the player's feet waits until they step away", () => {
    const { room, nino } = roomWithAuthors(demoLevel());
    room.join("Luka", "player");
    room.move("right");
    assert.deepEqual([room.playState().x, room.playState().y], [2, 7]);

    assert.equal(room.submit(nino.id, [create({ type: "lava", x: 2, y: 7, w: 1, h: 1 })]).status, "deferred");
    assert.equal(room.rev, 0);
    assert.equal(room.statePayload().deferred, 1);

    room.move("up");
    assert.equal(room.rev, 1);
    assert.equal(room.statePayload().deferred, 0);
    assert.ok(room.world.entities.some((e) => e.type === "lava" && e.x === 2 && e.y === 7));
  });

  test("restoring a version is a new log entry and the log replays to the same world", () => {
    const { room, nino, giorgi } = roomWithAuthors();
    room.submit(nino.id, [create({ type: "lava", x: 5, y: 0, w: 1, h: 2 })]);
    room.submit(giorgi.id, [create({ type: "wall", x: 7, y: 5, w: 2, h: 1 })]);
    const versionOne = structuredClone(room.world.entities.slice(0, 1));
    assert.deepEqual(room.revert(nino.id, 1), { status: "committed", rev: 3 });
    assert.deepEqual(room.world.entities, versionOne);
    assert.equal(room.log.at(-1)!.revertTo, 1);
    assert.equal(room.log.length, 3);
    assert.deepEqual(Room.replay(field(), room.log), room.world);
    const history = room.history();
    assert.equal(history.length, 4);
    assert.deepEqual(history[3], room.world);
    assert.deepEqual(Room.replay(field(), room.log.slice(0, 2)), history[2]);
  });

  test("only authors can change the level", () => {
    const { room } = roomWithAuthors();
    const player = room.join("Luka", "player");
    assert.equal(room.submit(player.id, [create({ type: "wall", x: 3, y: 3, w: 1, h: 1 })]).status, "rejected");
  });

  test("reset brings back the prepared level and keeps members", () => {
    const { room, nino, events } = roomWithAuthors();
    room.submit(nino.id, [create({ type: "wall", x: 3, y: 3, w: 1, h: 1 })]);
    room.reset();
    assert.equal(room.rev, 0);
    assert.deepEqual(room.world, field());
    assert.ok(room.members.has(nino.id));
    assert.equal(events.at(-1)!.type, "reset");
  });
});
