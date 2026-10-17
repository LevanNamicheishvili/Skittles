// Plays scripted author moves against a running room, without an LLM. For UI checks and rehearsals.
// Usage: node scripts/simulate.ts <step> [url]   steps: river, statue, castle, reset

import { io } from "socket.io-client";

const [step = "river", url = "http://localhost:3000"] = process.argv.slice(2);
const sys = { kind: "system" };

const steps: Record<string, { as: string; summary: string; ops: unknown[] }> = {
  river: {
    as: "Nino",
    summary: "Lava river down the middle with one gap",
    ops: [
      { op: "create", entity: { id: "n1", type: "lava", owner: sys, x: 11, y: 1, w: 2, h: 5 } },
      { op: "create", entity: { id: "n2", type: "lava", owner: sys, x: 11, y: 8, w: 2, h: 5 } },
    ],
  },
  statue: {
    as: "Giorgi",
    summary: "A statue in the middle of the map",
    ops: [{ op: "create", entity: { id: "g1", type: "wall", owner: sys, x: 11, y: 6, w: 2, h: 2, label: "Statue" } }],
  },
  castle: {
    as: "Giorgi",
    summary: "Castle around the flag with a gold door",
    ops: [
      { op: "create", entity: { id: "c", type: "castle", owner: sys, x: 18, y: 4, w: 6, h: 7, door: { side: "left", offset: 2, color: "gold" } } },
      { op: "create", entity: { id: "k", type: "key", owner: sys, x: 14, y: 2, color: "gold" } },
    ],
  },
};

const socket = io(url, { transports: ["websocket"] });
socket.on("connect", async () => {
  if (step === "reset") {
    console.log(await socket.emitWithAck("room:reset", {}));
  } else {
    const s = steps[step];
    if (!s) throw new Error(`unknown step ${step}`);
    await socket.emitWithAck("join", { name: s.as, role: "author" });
    const result = await socket.emitWithAck("doc:submit", { ops: s.ops, summary: s.summary });
    console.log(JSON.stringify(result.status === "conflict" ? { status: result.status, text: result.proposal.text, options: result.proposal.options.map((o: { title: string }) => o.title) } : result));
  }
  socket.disconnect();
});
