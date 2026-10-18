// Records what the room sends during one scripted session, using the real room code, into
// spec/fixtures/protocol/session.json. Both clients test their message parsing against it.
// Run from server/: node scripts/record-protocol.ts

import { writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { demoLevel } from "../src/levels/demo.ts";
import type { Op } from "../src/room/ops.ts";
import { Room, type RoomEvent, type SubmitResult } from "../src/room/room.ts";

const room = new Room(demoLevel());
const events: RoomEvent[] = [];
room.onEvent = (e) => events.push(structuredClone(e));
const results: Record<string, SubmitResult> = {};
const keep = (name: string, r: SubmitResult): SubmitResult => ((results[name] = structuredClone(r)), r);
const owner = { kind: "assistant" as const };

const nino = room.join("Nino", "author");
const giorgi = room.join("Giorgi", "author");
const luka = room.join("Luka", "player");
room.join("Stage", "stage");

// Nino's agent: a lava river with one gap at row 4.
room.say(nino.id, "you", "Add a lava river down the middle. Leave one gap.");
const river: Op[] = [
  { op: "create", entity: { id: "new1", type: "lava", owner, x: 11, y: 1, w: 2, h: 3, label: "Lava river" } },
  { op: "create", entity: { id: "new2", type: "lava", owner, x: 11, y: 5, w: 2, h: 8, label: "Lava river" } },
];
keep("committed", room.submit(nino.id, river, "Lava river with one gap"));
room.say(nino.id, "agent", "Done: a river at column 11 with one gap at row 4. Still winnable.");

// Giorgi's statue lands in the gap: held back, the mediator opens.
room.say(giorgi.id, "you", "Put a big statue right in the gap.");
const statue: Op[] = [{ op: "create", entity: { id: "new3", type: "wall", owner, x: 11, y: 4, w: 2, h: 1, label: "Statue" } }];
const conflict = keep("conflict", room.submit(giorgi.id, statue, "Statue in the gap"));
if (conflict.status !== "conflict") throw new Error(`expected a conflict, got ${conflict.status}`);
const proposal = conflict.proposal;

// Nino's agent negotiates: keep the statue, open a new gap at row 8.
room.startNegotiation(proposal.id, nino.id);
room.addAgentOption(proposal.id, nino.id, "open a gap further down", "Keep the statue and open a gap in my river at row 8.", [
  { op: "update", id: "A2", set: { y: 9, h: 4 } },
  { op: "create", entity: { id: "new4", type: "lava", owner, x: 11, y: 5, w: 2, h: 3, label: "Lava river" } },
]);

// Giorgi picks the bridge; it covers Nino's lava, so she approves.
const bridge = proposal.options.find((o) => o.kind === "bridge");
if (!bridge) throw new Error("the mediator offered no bridge");
keep("awaiting_approval", room.choose(giorgi.id, proposal.id, bridge.id));
room.answer(nino.id, proposal.id, true);

// Something the room refuses.
keep("rejected", room.submit(nino.id, [{ op: "delete", id: "Z9" }]));

// Luka walks into the lava twice at the same cell: dev mode reports it to Nino. The bridge crosses row 7,
// so he takes row 8.
for (let fall = 0; fall < 2; fall++) {
  room.move("down");
  for (let i = 0; i < 10; i++) room.move("right");
}
const report = [...events].reverse().find((e) => e.type === "report");
if (!report || report.type !== "report") throw new Error("no playtest report");

// Nino's agent drafts a fix for the report.
const suggestion = room.startSuggestion(nino.id, report.payload.id);
room.completeSuggestion(suggestion.id, "Shorten the river by one row, so the crossing is fair.", "Shorter lava river", [{ op: "update", id: "A1", set: { h: 2 } }]);

// A change under the player's feet waits until Luka steps away.
room.move("up");
const underFoot = room.statePayload().world.start;
keep("deferred", room.submit(giorgi.id, [{ op: "create", entity: { id: "new5", type: "wall", owner, x: underFoot.x, y: underFoot.y - 1, w: 1, h: 1, label: "Pillar" } }]));
room.move("down");

// Restoring an old version, then a reset.
keep("revert", room.revert(nino.id, 1));
const snapshot = structuredClone(room.snapshotFor(nino.id));
room.reset();

const out = {
  $comment: "Recorded by server/scripts/record-protocol.ts from the real room code. Do not edit by hand; run the script again.",
  members: { nino: nino.id, giorgi: giorgi.id, luka: luka.id },
  snapshot,
  results,
  events,
};
const root = join(dirname(fileURLToPath(import.meta.url)), "../..");
writeFileSync(join(root, "spec/fixtures/protocol/session.json"), JSON.stringify(out, null, 2) + "\n");
const counts = events.reduce<Record<string, number>>((n, e) => ((n[e.type] = (n[e.type] ?? 0) + 1), n), {});
console.log(`recorded ${events.length} events`, counts, "results:", Object.keys(results).join(", "));
