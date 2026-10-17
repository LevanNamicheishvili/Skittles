// Sends real requests to the authors' agents on a running room and reports what happened and how long it took.
// Usage: node scripts/agent-check.ts [url]

import { io, type Socket } from "socket.io-client";

const url = process.argv[2] ?? "http://localhost:3000";
const suite = process.argv[3] ?? "broad";

const demo: [string, string][] = [
  ["Nino", "Add a lava river down the middle of the map, top to bottom, with one gap so the player can still cross."],
  ["Giorgi", "Put a big stone statue right in the middle of the map."],
];

const insist: [string, string][] = [["Giorgi", "No, I want the statue right in the gap of Nino's river. Move it there."]];

const broad: [string, string][] = [
  ["Nino", "Add a lava river down the middle of the map, top to bottom, with one gap so the player can still cross."],
  ["Giorgi", "Put the flag inside a small castle with a gold locked door, and hide the gold key in the top right corner."],
  ["Nino", "Add three coins along the way to the river."],
  ["Giorgi", "Add a dragon that chases the player."],
  ["Nino", "Move the start one cell down."],
  ["Giorgi", "Add a treasure chest in the bottom right corner."],
  ["Nino", "Build a small wall maze in the bottom left area."],
  ["Giorgi", "Put a blue locked door somewhere on the main path and a blue key near the start."],
  ["Nino", "Remove the coins I added."],
  ["Giorgi", "Surround the treasure chest with lava, leaving one way in."],
];

const requests = suite === "demo" ? demo : suite === "insist" ? insist : broad;

type Chat = { authorId: string; from: string; text: string; proposalId?: string };

async function connect(name: string): Promise<{ socket: Socket; id: string }> {
  const socket = io(url, { transports: ["websocket"], forceNew: true });
  await new Promise((r) => socket.once("connect", r));
  const joined = await socket.emitWithAck("join", { name, role: "author" });
  return { socket, id: joined.you.id };
}

const authors = { Nino: await connect("Nino"), Giorgi: await connect("Giorgi") };
const watcher = authors.Nino.socket;
let rev = 0;
watcher.on("state", (s: { rev: number }) => (rev = s.rev));

for (const [name, text] of requests) {
  const { socket, id } = authors[name as keyof typeof authors];
  const started = Date.now();
  const before = rev;
  const replies: Chat[] = [];
  const done = new Promise<void>((resolve) => {
    const onChat = (m: Chat) => {
      if (m.authorId !== id || m.from === "you") return;
      replies.push(m);
      if (m.from === "agent") {
        // Let the mediator's message, if any, arrive too.
        setTimeout(() => {
          watcher.off("chat", onChat);
          resolve();
        }, 300);
      }
    };
    watcher.on("chat", onChat);
    setTimeout(resolve, 90_000);
  });
  await socket.emitWithAck("agent:say", { text });
  await done;
  const seconds = ((Date.now() - started) / 1000).toFixed(1);
  const outcome = rev > before ? `committed v${rev}` : replies.some((r) => r.from === "mediator") ? "conflict, mediator asked" : "no change";
  console.log(`\n${name} (${seconds}s, ${outcome}): ${text}`);
  for (const r of replies) console.log(`  ${r.from}: ${r.text}`);
}
for (const a of Object.values(authors)) a.socket.disconnect();
