// An author's personal agent. It reads the level and what the other author changed, then proposes
// ops. It never writes code and never writes to the level directly: its ops go through room.submit
// like anyone's, so the validator and the mediator have the last word.
//
// Two engines produce the proposal: the Claude API (tool use, needs ANTHROPIC_API_KEY) and the
// local Claude Code CLI in print mode (structured output, uses the signed-in Claude account).

import { spawn } from "node:child_process";
import { mkdirSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import Anthropic from "@anthropic-ai/sdk";
import { describeReport, type PlaytestReport } from "../room/playtest.ts";
import { describeOps, type Op } from "../room/ops.ts";
import type { Proposal as Conflict, Room } from "../room/room.ts";
import type { AgentHandler } from "../server.ts";
import { levelContext, toOps, type ChangeInput } from "./context.ts";

const RULES = `You are a personal level-design agent inside LIVEFORGE, a live 2D grid game that two human authors edit at the same time, each through their own agent, while a third person plays it.

The level: a grid of cells, x grows to the right from 0, y grows down from 0. The player walks one cell at a time from the start S to the flag F.
Objects you can create:
- wall, lava, bridge: rectangles (x, y, w, h). Walls block. Lava kills the player. A bridge over lava makes those cells walkable.
- castle: a rectangle with w>=3 and h>=3. Its outline becomes walls, its inside is ground, and one outline cell is a door: door_side (left/right/top/bottom) and door_offset (0 .. side length - 3, counted from the corner along that side, skipping the corner). color red/blue/gold makes it a locked door, no color leaves an open gateway.
- door: one cell, locked, opens with the key of the same color.
- key: one cell, color red/blue/gold. The player picks it up by walking onto it.
- treasure, coin: one cell items.
You can also move the start (set_start) and the flag (set_flag), update an object's position or size by id, or delete an object by id.
Map legend: . ground, # wall, ~ lava, = bridge, R/B/G locked door (red/blue/gold), r/b/g key, T treasure, c coin, S start, F flag.

How you work:
- Make the change your author asks for. Prefer few, large rectangles. Keep every object inside the grid and off the S and F cells.
- You see what the other author changed. Respect their work: do not delete or move their objects unless your author explicitly asks, and then say so. If your author's request touches their work, mention it in one short sentence.
- Do not try to keep the level winnable yourself and do not add bridges on your own. The room checks every change; if a change breaks the level, a mediator shows fix options to the humans.
- message is what your author reads: one or two short, plain sentences in the language your author wrote in (English or Georgian), saying what you are doing. summary is a short history line in English, at most 8 words.`;

const API_SYSTEM = `${RULES}
- Apply the change by calling change_level once.
- If a request needs something this game does not have (enemies, physics, sounds, new object types), do not call the tool. Reply in one or two sentences with what is possible instead.`;

const CLI_SYSTEM = `${RULES}
- Answer with one JSON object. To change the level: action "change" with the ops.
- If a request needs something this game does not have (enemies, physics, sounds, new object types): action "reply", no ops, and a message saying what is possible instead.`;

const OP_ITEM = {
  type: "object",
  additionalProperties: false,
  required: ["op"],
  properties: {
    op: { type: "string", enum: ["create", "update", "delete", "set_flag", "set_start"] },
    id: { type: "string", description: "update/delete: the existing object's id. create: optional temporary name." },
    type: { type: "string", enum: ["wall", "lava", "bridge", "castle", "door", "key", "treasure", "coin"] },
    x: { type: "integer" },
    y: { type: "integer" },
    w: { type: "integer" },
    h: { type: "integer" },
    color: { type: "string", enum: ["red", "blue", "gold"] },
    door_side: { type: "string", enum: ["left", "right", "top", "bottom"] },
    door_offset: { type: "integer" },
    label: { type: "string", description: "Optional short name, e.g. Lava river." },
  },
} as const;

const TOOL: Anthropic.Tool = {
  name: "change_level",
  description: "Apply one batch of changes to the shared level. The room validates it; the result says whether it went live.",
  input_schema: {
    type: "object",
    additionalProperties: false,
    required: ["message", "summary", "ops"],
    properties: {
      message: { type: "string", description: "One or two short sentences to your author about what you are doing." },
      summary: { type: "string", description: "History line, at most 8 words." },
      ops: { type: "array", minItems: 1, maxItems: 20, items: OP_ITEM },
    },
  },
};

const CLI_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["action", "message", "summary", "ops"],
  properties: {
    action: { type: "string", enum: ["change", "reply"] },
    message: { type: "string" },
    summary: { type: "string" },
    ops: { type: "array", maxItems: 20, items: OP_ITEM },
  },
};

export type Proposal = { kind: "change"; input: ChangeInput } | { kind: "reply"; text: string };

// One request to an engine. retry() tells it why the room rejected the proposal.
export type Turn = { proposal: Proposal; retry(error: string): Promise<Turn> };

export type Backend = { label: string; begin(prompt: string): Promise<Turn> };

// The part of the SDK client the API engine uses, so tests can pass a fake.
export type MessagesClient = { messages: { create(params: Anthropic.MessageCreateParamsNonStreaming): Promise<Anthropic.Message> } };

type Effort = "low" | "medium" | "high";

export function apiBackend(options: { client?: MessagesClient; model?: string; effort?: Effort } = {}): Backend {
  const client = options.client ?? new Anthropic();
  const model = options.model ?? process.env.LIVEFORGE_MODEL ?? "claude-sonnet-5-5";
  const effort = options.effort ?? (process.env.LIVEFORGE_EFFORT as Effort | undefined) ?? "low";
  const call = (messages: Anthropic.MessageParam[]): Promise<Anthropic.Message> =>
    client.messages.create({
      model,
      max_tokens: 4000,
      system: [{ type: "text", text: API_SYSTEM, cache_control: { type: "ephemeral" } }],
      tools: [TOOL],
      messages,
      // Sonnet 5.5 takes between_tools as its lowest thinking setting; other models use their default.
      ...(model === "claude-sonnet-5-5" ? { thinking: { type: "between_tools" as const } } : {}),
      output_config: { effort },
    });

  const turn = async (messages: Anthropic.MessageParam[]): Promise<Turn> => {
    const response = await call(messages);
    if (response.stop_reason === "refusal") return { proposal: { kind: "reply", text: "I can't help with that request." }, retry: () => turn(messages) };
    const use = response.content.find((b): b is Anthropic.ToolUseBlock => b.type === "tool_use");
    if (!use) {
      const text = response.content.flatMap((b) => (b.type === "text" ? [b.text] : [])).join("\n").trim();
      return { proposal: { kind: "reply", text }, retry: () => turn(messages) };
    }
    return {
      proposal: { kind: "change", input: use.input as ChangeInput },
      retry: (error) =>
        turn([
          ...messages,
          { role: "assistant", content: response.content },
          {
            role: "user",
            content: [{ type: "tool_result", tool_use_id: use.id, is_error: true, content: `Rejected, nothing changed: ${error}. Fix the ops and call change_level again.` }],
          },
        ]),
    };
  };
  return { label: `Claude API (${model})`, begin: (prompt) => turn([{ role: "user", content: prompt }]) };
}

// Runs the CLI with the prompt on stdin and returns its stdout.
export type Runner = (args: string[], stdin: string) => Promise<string>;

const runClaude: Runner = (args, stdin) =>
  new Promise((resolve, reject) => {
    // A clean working directory, so no project instructions or settings leak into the agent.
    const cwd = join(tmpdir(), "liveforge-agent");
    mkdirSync(cwd, { recursive: true });
    const child = spawn(process.env.LIVEFORGE_CLAUDE_BIN ?? "claude", args, { cwd, env: process.env });
    let out = "";
    let err = "";
    const timer = setTimeout(() => child.kill(), 60_000);
    child.stdout.on("data", (d: Buffer) => (out += d.toString()));
    child.stderr.on("data", (d: Buffer) => (err += d.toString()));
    child.on("error", reject);
    child.on("close", (code) => {
      clearTimeout(timer);
      if (code === 0) resolve(out);
      else reject(new Error(`claude exited with ${code}: ${(err || out).trim().slice(0, 300)}`));
    });
    child.stdin.end(stdin);
  });

export function cliBackend(options: { run?: Runner; model?: string; effort?: Effort } = {}): Backend {
  const run = options.run ?? runClaude;
  const model = options.model ?? process.env.LIVEFORGE_CLI_MODEL ?? "sonnet";
  const effort = options.effort ?? (process.env.LIVEFORGE_EFFORT as Effort | undefined) ?? "low";
  const args = [
    "-p",
    "--model", model,
    "--effort", effort,
    "--output-format", "json",
    "--no-session-persistence",
    "--tools", "",
    "--system-prompt", CLI_SYSTEM,
    "--json-schema", JSON.stringify(CLI_SCHEMA),
  ];

  const turn = async (prompt: string): Promise<Turn> => {
    const result = JSON.parse(await run(args, prompt)) as { is_error?: boolean; result?: string; structured_output?: unknown };
    if (result.is_error || !result.structured_output) throw new Error(result.result || "the agent returned no answer");
    const answer = result.structured_output as ChangeInput & { action: "change" | "reply" };
    const proposal: Proposal =
      answer.action === "reply" || answer.ops.length === 0
        ? { kind: "reply", text: answer.message }
        : { kind: "change", input: { message: answer.message, summary: answer.summary, ops: answer.ops } };
    return {
      proposal,
      retry: (error) =>
        turn(
          `${prompt}\n\nYour previous answer was rejected by the room and nothing changed: ${error}\nYour previous ops: ${JSON.stringify(answer.ops)}\nAnswer again with corrected ops.`,
        ),
    };
  };
  return { label: `Claude Code CLI (${model})`, begin: turn };
}

export type AgentOptions = { backend: Backend; log?: (line: string) => void };

export function createAgent({ backend, log = (line) => console.log(line) }: AgentOptions): AgentHandler {
  // What each author's agent has already seen, so it can be told what the others changed since.
  const seenRev = new Map<string, number>();
  const busy = new Set<string>();

  return async (room: Room, authorId: string, text: string) => {
    if (busy.has(authorId)) {
      room.say(authorId, "system", "Your agent is still working on the previous request.");
      return;
    }
    busy.add(authorId);
    const started = Date.now();
    const who = room.nameOf(authorId);
    try {
      const context = levelContext(room, authorId, seenRev.get(authorId) ?? 0);
      let turn = await backend.begin(`${context}\n\nRequest from ${who}: ${text}`);
      // One try plus one retry when the room rejects the ops; the rejection reason goes back to the model.
      for (let attempt = 1; ; attempt++) {
        const { proposal } = turn;
        if (proposal.kind === "reply") {
          room.say(authorId, "agent", proposal.text || "I did not change anything.");
          log(`[agent] ${who} replied in ${Date.now() - started} ms`);
          return;
        }
        let error: string;
        try {
          const ops = toOps(proposal.input, room.world);
          const check = room.preview(ops);
          if (!check.ok) throw new Error(check.message);
          // The agent speaks first, then the room answers: committed, or stopped by the mediator.
          room.say(authorId, "agent", proposal.input.message || proposal.input.summary);
          const result = room.submit(authorId, ops, proposal.input.summary);
          if (result.status === "rejected") throw new Error(result.message);
          log(`[agent] ${who} ${result.status} in ${Date.now() - started} ms (attempt ${attempt})`);
          return;
        } catch (err) {
          error = err instanceof Error ? err.message : String(err);
        }
        log(`[agent] ${who} rejected: ${error}`);
        if (attempt >= 2) break;
        turn = await turn.retry(error);
      }
      room.say(authorId, "agent", "I couldn't make that change fit the level. Try describing it differently.");
    } finally {
      seenRev.set(authorId, room.rev);
      busy.delete(authorId);
    }
  };
}

export type SuggestHandler = (room: Room, authorId: string, report: PlaytestReport) => Promise<void>;

// A playtest report becomes a fix your author can apply with one click. The draft is checked
// against the level before the author sees it; nothing goes live without the author.
export function createSuggester({ backend, log = (line) => console.log(line) }: AgentOptions): SuggestHandler {
  return async (room, authorId, report) => {
    const suggestion = room.startSuggestion(authorId, report.id);
    const started = Date.now();
    const who = room.nameOf(authorId);
    try {
      const prompt = [
        levelContext(room, authorId, 0),
        "",
        "Playtest report, captured by the game while it was being played:",
        describeReport(report, room.nameOf),
        "",
        `Request: propose one small fix for ${who} to approve. Keep ${who}'s idea (for example keep the lava, but make the spot fair) and prefer changing ${who}'s own objects or adding new ones. message tells ${who} what the fix is and why, in at most two sentences. Do not use action reply unless no change can help.`,
      ].join("\n");
      let turn = await backend.begin(prompt);
      for (let attempt = 1; ; attempt++) {
        const { proposal } = turn;
        if (proposal.kind === "reply") {
          room.failSuggestion(suggestion.id, proposal.text || "I don't see a change that would help here.");
          return;
        }
        let problem: string;
        try {
          const ops = toOps(proposal.input, room.world);
          const check = room.preview(ops);
          if (!check.ok) throw new Error(check.message);
          if (check.breaks) throw new Error("this fix would make the level unwinnable");
          room.completeSuggestion(suggestion.id, proposal.input.message || proposal.input.summary, proposal.input.summary, ops);
          log(`[agent] fix for ${who} drafted in ${Date.now() - started} ms (attempt ${attempt})`);
          return;
        } catch (err) {
          problem = err instanceof Error ? err.message : String(err);
        }
        log(`[agent] fix for ${who} rejected: ${problem}`);
        if (attempt >= 2) break;
        turn = await turn.retry(problem);
      }
      room.failSuggestion(suggestion.id, "I couldn't find a fix that fits the level. You can describe one yourself.");
    } catch (err) {
      room.failSuggestion(suggestion.id, `The agent failed: ${err instanceof Error ? err.message : String(err)}`);
    }
  };
}

export type NegotiateHandler = (room: Room, proposal: Conflict, ownerId: string) => Promise<void>;

function describePending(ops: Op[]): string {
  return ops
    .map((op) => {
      if (op.op === "create") {
        const e = op.entity;
        const size = "w" in e ? ` w=${e.w} h=${e.h}` : "";
        return `- create ${e.id} ${e.type} x=${e.x} y=${e.y}${size}${e.label ? ` "${e.label}"` : ""}`;
      }
      return `- ${describeOps([op])}`;
    })
    .join("\n");
}

// When someone's change would break this author's work, this author's agent proposes a compromise
// that keeps both ideas. The room checks it; the requester decides; the owner approves if it touches theirs.
export function createNegotiator({ backend, log = (line) => console.log(line) }: AgentOptions): NegotiateHandler {
  return async (room, proposal, ownerId) => {
    if (!room.startNegotiation(proposal.id, ownerId)) return;
    const started = Date.now();
    const owner = room.nameOf(ownerId);
    const requester = room.nameOf(proposal.requesterId);
    try {
      const prompt = [
        levelContext(room, ownerId, 0),
        "",
        `A conflict needs a compromise. ${requester} asked their agent for: "${proposal.summary}". That change is NOT live, because it would break the level:`,
        proposal.text,
        `${requester}'s pending change:`,
        describePending(proposal.ops),
        "",
        `Request: you are ${owner}'s agent. Propose one compromise that keeps both ideas and keeps the level winnable; for this request keeping it winnable is required. Prefer adjusting ${requester}'s pending objects with update ops on their ids (for example move them a little), or else change ${owner}'s own objects as little as possible. Do not delete either idea. summary is a short title for the option, for example "Move the statue two cells up". message is one friendly sentence to ${requester} explaining the compromise.`,
      ].join("\n");
      let turn = await backend.begin(prompt);
      for (let attempt = 1; ; attempt++) {
        const { proposal: answer } = turn;
        if (answer.kind === "reply") break;
        let problem: string;
        try {
          const ops = toOps(answer.input, room.world);
          const check = room.preview([...proposal.ops, ...ops]);
          if (!check.ok) throw new Error(check.message);
          if (check.breaks) throw new Error("together with the pending change, this still makes the level unwinnable");
          room.addAgentOption(proposal.id, ownerId, answer.input.summary, answer.input.message || answer.input.summary, ops);
          log(`[agent] ${owner} negotiated in ${Date.now() - started} ms (attempt ${attempt})`);
          return;
        } catch (err) {
          problem = err instanceof Error ? err.message : String(err);
        }
        log(`[agent] ${owner} compromise rejected: ${problem}`);
        if (attempt >= 2) break;
        turn = await turn.retry(problem);
      }
    } catch (err) {
      log(`[agent] ${owner} negotiation failed: ${err instanceof Error ? err.message : String(err)}`);
    }
    room.endNegotiation(proposal.id, ownerId);
  };
}
