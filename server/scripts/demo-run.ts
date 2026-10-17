// Autopilot for rehearsals: plays the whole stage scenario against a running room with the real agents,
// and prints how long each beat took. Usage: node scripts/demo-run.ts [url]

import { io, type Socket } from "socket.io-client";
import type { Direction, World } from "../src/game/types.ts";
import { cellIndex, rasterize, Terrain } from "../src/game/raster.ts";
import type { Proposal } from "../src/room/room.ts";
import type { Suggestion } from "../src/room/playtest.ts";

const url = process.argv[2] ?? "http://localhost:3000";
const wait = (ms: number) => new Promise((r) => setTimeout(r, ms));
const t0 = Date.now();
const say = (line: string) => console.log(`[${((Date.now() - t0) / 1000).toFixed(1).padStart(5)}s] ${line}`);

type Snap = { you: { id: string }; state: { world: World; rev: number; solve: { path?: Direction[] } } };

async function connect(name: string, role: string): Promise<{ s: Socket; id: string }> {
  const s = io(url, { transports: ["websocket"], forceNew: true });
  await new Promise((r) => s.once("connect", r));
  const snap: Snap = await s.emitWithAck("join", { name, role });
  return { s, id: snap.you.id };
}

const nino = await connect("Nino", "author");
const giorgi = await connect("Giorgi", "author");
const luka = await connect("Luka", "player");
const stage = nino.s;

let state: Snap["state"] | undefined;
const proposals = new Map<string, Proposal>();
const suggestions = new Map<string, Suggestion>();
stage.on("state", (s: Snap["state"]) => (state = s));
stage.on("proposal", (p: Proposal) => proposals.set(p.id, p));
stage.on("suggestion", (g: Suggestion) => suggestions.set(g.id, g));
const replies: { authorId: string; from: string; text: string }[] = [];
stage.on("chat", (m: { authorId: string; from: string; text: string }) => replies.push(m));

async function until<T>(check: () => T | undefined | false, ms: number, what: string): Promise<T> {
  const end = Date.now() + ms;
  while (Date.now() < end) {
    const v = check();
    if (v) return v;
    await wait(150);
  }
  throw new Error(`timed out waiting for ${what}`);
}

async function ask(who: { s: Socket; id: string }, name: string, text: string): Promise<void> {
  const before = replies.length;
  say(`${name} says: ${text}`);
  await who.s.emitWithAck("agent:say", { text });
  const reply = await until(() => replies.slice(before).find((m) => m.authorId === who.id && m.from === "agent"), 90_000, `${name}'s agent`);
  say(`  ${name}'s agent: ${reply.text}`);
}

await stage.emitWithAck("room:reset", {});
await wait(500);
const fresh: Snap = await stage.emitWithAck("join", { name: "Nino", role: "author" });
state = fresh.state;
say("Room reset to the prepared level.");

await ask(nino, "Nino", "Add a lava river down the middle of the map, top to bottom, with one gap so the player can still cross.");
await wait(1500);
await ask(giorgi, "Giorgi", "Put a big stone statue right in the middle of the map.");
await wait(1500);
const open = () => [...proposals.values()].find((p) => p.status === "open");
if (!open()) {
  say("  No conflict: Giorgi's agent kept the gap open by itself. Giorgi insists.");
  await ask(giorgi, "Giorgi", "No, I want the statue right in the gap of Nino's river. Move it there.");
}
const conflict = await until(open, 20_000, "the conflict");
say(`Mediator: ${conflict.text}`);
const negotiated = await until(() => {
  const p = proposals.get(conflict.id)!;
  return p.negotiating.length === 0 && p.options.some((o) => o.kind === "agent") ? p : undefined;
}, 60_000, "Nino's agent's compromise").catch(() => proposals.get(conflict.id)!);
for (const o of negotiated.options) say(`  option: ${o.title} (${o.detail})`);
const pick = negotiated.options.find((o) => o.kind === "bridge") ?? negotiated.options.find((o) => o.kind === "agent")!;
say(`Giorgi picks: ${pick.title}`);
const chosen = await giorgi.s.emitWithAck("proposal:choose", { proposalId: conflict.id, optionId: pick.id });
if (chosen.status === "awaiting_approval") {
  await wait(1500);
  say("Nino approves.");
  await nino.s.emitWithAck("approval:answer", { proposalId: conflict.id, accept: true });
}
await until(() => state && state.rev >= 2 && state, 5000, "the fix to go live");
say(`Live: v${state!.rev}.`);
await wait(2000);

// Luka walks the route and steps into the lava next to the crossing, twice.
const grid = rasterize(state!.world);
const lavaAt = (x: number, y: number) => x >= 0 && y >= 0 && x < grid.w && y < grid.h && grid.terrain[cellIndex(grid, x, y)] === Terrain.lava;
const path = state!.solve.path!;
let fall: { prefix: Direction[]; into: Direction } | undefined;
{
  let { x, y } = state!.world.start;
  for (let i = 0; i < path.length && !fall; i++) {
    for (const [d, dx, dy] of [["up", 0, -1], ["down", 0, 1]] as const) {
      if (lavaAt(x + dx, y + dy)) {
        fall = { prefix: path.slice(0, i), into: d };
        break;
      }
    }
    const step = path[i]!;
    x += step === "left" ? -1 : step === "right" ? 1 : 0;
    y += step === "up" ? -1 : step === "down" ? 1 : 0;
  }
}
if (fall) {
  for (let run = 0; run < 2; run++) {
    for (const d of fall.prefix) {
      luka.s.emit("play:move", { dir: d });
      await wait(90);
    }
    luka.s.emit("play:move", { dir: fall.into });
    say(`Luka falls into the lava (${run + 1}).`);
    await wait(900);
  }
  const fix = await until(() => [...suggestions.values()].find((g) => g.status === "open" || g.status === "failed"), 90_000, "the dev mode fix");
  say(`Dev mode → ${fix.status === "open" ? `fix from the owner's agent: ${fix.message}` : `no fix: ${fix.note}`}`);
  if (fix.status === "open") {
    await wait(2000);
    const applied = await (fix.authorId === nino.id ? nino : giorgi).s.emitWithAck("suggestion:apply", { id: fix.id });
    say(`Applied: ${applied.status}${applied.rev ? ` v${applied.rev}` : ""}.`);
  }
} else say("No lava next to the route; skipped the playtest beat.");

say("Done.");
for (const c of [nino, giorgi, luka]) c.s.disconnect();
