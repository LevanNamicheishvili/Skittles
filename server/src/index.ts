// Entry point: one room with the demo level, the web client from web/dist, and the agent when a key is set.

import { existsSync } from "node:fs";
import { join } from "node:path";
import { demoLevel } from "./levels/demo.ts";
import { Room } from "./room/room.ts";
import { createRoomServer, type AgentHandler, type NegotiateHandler, type SuggestHandler } from "./server.ts";
import { StudioHub } from "./studio/hub.ts";
import type { PlaytestReviewer } from "./studio/playtester.ts";
import type { SceneAssistant } from "./studio/sceneAgent.ts";

const port = Number(process.env.PORT ?? 3000);
const staticDir = join(import.meta.dirname, "..", "..", "web", "dist");

// The API when a key is set, otherwise the signed-in Claude Code CLI. SKITTLES_AGENT=api|cli forces one.
async function loadAgent(): Promise<{ agent: AgentHandler; suggester: SuggestHandler; negotiator: NegotiateHandler; sceneAssistant: SceneAssistant; reviewer: PlaytestReviewer } | undefined> {
  const { apiBackend, cliBackend, createAgent, createNegotiator, createSuggester } = await import("./agent/agent.ts");
  const { apiSceneAssistant, cliSceneAssistant } = await import("./studio/sceneAgent.ts");
  const { apiPlaytestReviewer, cliPlaytestReviewer } = await import("./studio/playtester.ts");
  const choice = process.env.SKITTLES_AGENT ?? (process.env.ANTHROPIC_API_KEY ? "api" : "cli");
  if (choice === "api" && !process.env.ANTHROPIC_API_KEY) {
    console.warn("SKITTLES_AGENT=api but ANTHROPIC_API_KEY is not set: agents will not answer.");
    return undefined;
  }
  const backend = choice === "api" ? apiBackend() : cliBackend();
  console.log(`Agents run on ${backend.label}.`);
  const sceneAssistant = choice === "api" ? apiSceneAssistant() : cliSceneAssistant();
  const reviewer = choice === "api" ? apiPlaytestReviewer() : cliPlaytestReviewer();
  return { agent: createAgent({ backend }), suggester: createSuggester({ backend }), negotiator: createNegotiator({ backend }), sceneAssistant, reviewer };
}

const room = new Room(demoLevel());
const agents = await loadAgent();
// Studio projects are saved in server/data/projects (SKITTLES_DATA moves it).
const studio = new StudioHub({ assistant: agents?.sceneAssistant, reviewer: agents?.reviewer, dataDir: process.env.SKITTLES_DATA ?? join(import.meta.dirname, "..", "data", "projects") });
const { http } = createRoomServer({ room, staticDir: existsSync(staticDir) ? staticDir : undefined, ...agents, studio });
http.listen(port, () => console.log(`Skittles room on http://localhost:${port}`));
for (const signal of ["SIGINT", "SIGTERM"] as const) {
  process.on(signal, () => {
    studio.flushAll();
    process.exit(0);
  });
}
