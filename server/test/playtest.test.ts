import { describe, test } from "node:test";
import assert from "node:assert/strict";
import { cliBackend, createSuggester } from "../src/agent/agent.ts";
import { demoLevel } from "../src/levels/demo.ts";
import { Room, type RoomEvent } from "../src/room/room.ts";

const quiet = () => {};
const sys = { kind: "system" } as const;

// Nino owns a lava pond right of the start; Luka plays.
function setup() {
  const room = new Room(demoLevel());
  const events: RoomEvent[] = [];
  room.onEvent = (e) => events.push(e);
  const nino = room.join("Nino", "author");
  const giorgi = room.join("Giorgi", "author");
  const luka = room.join("Luka", "player");
  room.submit(nino.id, [{ op: "create", entity: { id: "pond", type: "lava", owner: sys, x: 3, y: 6, w: 1, h: 3 } }], "Lava pond");
  return { room, events, nino, giorgi, luka };
}

describe("playtest dev mode", () => {
  test("a report carries the game's context and goes to the owner of the object at the spot", () => {
    const { room, nino, luka } = setup();
    room.move("right");
    room.move("right"); // into Nino's lava at (3, 7)
    const report = room.report(luka.id, "I keep falling here")!;
    assert.deepEqual(report.spot, { x: 3, y: 7 });
    assert.deepEqual(report.position, { x: 1, y: 7 });
    assert.equal(report.falls, 1);
    assert.equal(report.suspects[0]!.id, "A1");
    assert.deepEqual(report.routedTo, [nino.id]);
    assert.equal(room.chats.get(nino.id)!.at(-1)!.reportId, report.id);
  });

  test("a report about the base level goes to every author", () => {
    const { room, nino, giorgi, luka } = setup();
    room.move("up");
    room.move("up");
    const report = room.report(luka.id, "This corner is boring")!;
    assert.deepEqual(report.routedTo.sort(), [nino.id, giorgi.id].sort());
  });

  test("falling twice at the same cell raises a report on its own", () => {
    const { room, events, nino } = setup();
    room.move("right");
    room.move("right");
    room.move("right");
    room.move("right");
    const signals = events.filter((e): e is Extract<RoomEvent, { type: "report" }> => e.type === "report");
    assert.equal(signals.length, 1);
    assert.equal(signals[0]!.payload.kind, "signal");
    assert.equal(signals[0]!.payload.fallsHere, 2);
    assert.deepEqual(signals[0]!.payload.routedTo, [nino.id]);
  });

  test("the agent drafts a checked fix and it goes live only when the author applies it", async () => {
    const { room, nino, luka } = setup();
    room.move("right");
    room.move("right");
    const report = room.report(luka.id, "I keep falling here")!;
    const answers = [
      { action: "change", message: "Lava over the start, oops.", summary: "Bad fix", ops: [{ op: "create", type: "lava", x: 0, y: 1, w: 3, h: 12 }] },
      { action: "change", message: "A one-tile bridge over your pond keeps the lava but makes the crossing fair.", summary: "Bridge over the pond", ops: [{ op: "create", type: "bridge", x: 3, y: 7, w: 1, h: 1 }] },
    ];
    const prompts: string[] = [];
    const run = async (_args: string[], stdin: string) => {
      prompts.push(stdin);
      return JSON.stringify({ is_error: false, structured_output: answers.shift() });
    };
    await createSuggester({ backend: cliBackend({ run }), log: quiet })(room, nino.id, report);
    assert.match(prompts[0]!, /I keep falling here/);
    assert.match(prompts[0]!, /Objects at the spot: A1 lava by Nino/);
    assert.match(prompts[1]!, /unwinnable/);

    const suggestion = [...room.suggestions.values()][0]!;
    assert.equal(suggestion.status, "open");
    assert.equal(room.rev, 1);
    assert.equal(room.applySuggestion(nino.id, suggestion.id).status, "committed");
    assert.equal(room.rev, 2);
    assert.equal(suggestion.status, "applied");
    assert.ok(room.world.entities.some((e) => e.type === "bridge" && e.x === 3 && e.y === 7));
  });

  test("another author cannot apply someone else's suggestion", () => {
    const { room, nino, giorgi, luka } = setup();
    room.move("right");
    room.move("right");
    const report = room.report(luka.id, "falling")!;
    const s = room.startSuggestion(nino.id, report.id);
    room.completeSuggestion(s.id, "Bridge", "Bridge", [{ op: "create", entity: { id: "b", type: "bridge", owner: sys, x: 3, y: 7, w: 1, h: 1 } }]);
    assert.equal(room.applySuggestion(giorgi.id, s.id).status, "rejected");
    assert.equal(room.rev, 1);
  });
});
