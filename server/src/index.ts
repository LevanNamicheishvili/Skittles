// Entry point: one room with the demo level, the web client from web/dist, and the agent when a key is set.

import { existsSync } from "node:fs";
import { join } from "node:path";
import { demoLevel } from "./levels/demo.ts";
import { Room } from "./room/room.ts";
import { createRoomServer, type AgentHandler, type NegotiateHandler, type SuggestHandler } from "./server.ts";

const port = Number(process.env.PORT ?? 3000);
const staticDir = join(import.meta.dirname, "..", "..", "web", "dist");

// The API when a key is set, otherwise the signed-in Claude Code CLI. LIVEFORGE_AGENT=api|cli forces one.
async function loadAgent(): Promise<{ agent: AgentHandler; suggester: SuggestHandler; negotiator: NegotiateHandler } | undefined> {
  const { apiBackend, cliBackend, createAgent, createNegotiator, createSuggester } = await import("./agent/agent.ts");
  const choice = process.env.LIVEFORGE_AGENT ?? (process.env.ANTHROPIC_API_KEY ? "api" : "cli");
  if (choice === "api" && !process.env.ANTHROPIC_API_KEY) {
    console.warn("LIVEFORGE_AGENT=api but ANTHROPIC_API_KEY is not set: agents will not answer.");
    return undefined;
  }
  const backend = choice === "api" ? apiBackend() : cliBackend();
  console.log(`Agents run on ${backend.label}.`);
  return { agent: createAgent({ backend }), suggester: createSuggester({ backend }), negotiator: createNegotiator({ backend }) };
}

const room = new Room(demoLevel());
const agents = await loadAgent();
const { http } = createRoomServer({ room, staticDir: existsSync(staticDir) ? staticDir : undefined, ...agents });
http.listen(port, () => console.log(`LIVEFORGE room on http://localhost:${port}`));
