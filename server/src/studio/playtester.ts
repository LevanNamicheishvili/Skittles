// The AI playtester's review (spec/scene-play.md section 6). The AI player has already played the scene with the exact
// physics; this turns what it found into a short review for the team, each problem tied to the objects behind it,
// so it reaches the people who made them. Words only: fixes are for the creators and their agents.

import Anthropic from "@anthropic-ai/sdk";
import { runClaude, type MessagesClient, type Runner } from "../agent/agent.ts";
import type { AiPlaytest } from "./play.ts";
import { validateScene, type Scene } from "./scene.ts";
import { jumpNumbers } from "./sceneAgent.ts";

export type PlaytestIssue = { text: string; objects: string[]; kind: "problem" | "idea" };
export type PlaytestReview = { summary: string; issues: PlaytestIssue[] };
export type PlaytestReviewer = (scene: Scene, facts: AiPlaytest, context?: string) => Promise<PlaytestReview>;

export const REVIEW_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["summary", "issues"],
  properties: {
    summary: { type: "string", description: "One or two sentences: how the level plays." },
    issues: {
      type: "array",
      maxItems: 5,
      items: {
        type: "object",
        additionalProperties: false,
        required: ["text", "objects", "kind"],
        properties: {
          text: { type: "string", description: "The problem or idea and the fix in words: at most 30 words." },
          objects: { type: "array", items: { type: "string" }, description: "Ids of the objects behind it." },
          kind: { type: "string", enum: ["problem", "idea"] },
        },
      },
    },
  },
} as const;

export const REVIEW_SYSTEM = `You are the AI playtester in the Skittles studio, where a team builds 2D platformer levels together, each person with their own AI agent. An AI player has just played the level with the game's exact physics, searching for a way to the finish without dying and then for each coin. You get the level and what it found.

Write a short review for the team:
- summary: one or two sentences on how the level plays.
- issues: at most five, each at most 30 words. A problem blocks or frustrates a player (the finish or a coin cannot be reached, an enemy patrols where the player must land, a jump that only just works). An idea makes the level more fun (a better place for a coin, a missing challenge). Each names the ids of the objects behind it, so it goes to whoever made them, and says the fix in words.
- Base problems on the facts given: what the AI player reached and could not reach, and the checks. Do not invent problems. A level that plays well may have no problems at all.
- Its run to the finish is one run; each coin was tried separately. Do not say it collected coins on the way unless the facts say so.
- Write in the language the team chat uses (English or Georgian); English if unsure. Never write code.`;

/// What the reviewer is told: the level, the jump, the checks and the AI player's findings.
export function reviewPrompt(scene: Scene, facts: AiPlaytest, context?: string): string {
  const jump = jumpNumbers(scene);
  const name = (id: string) => scene.objects.find((o) => o.id === id)?.name ?? id;
  const report = validateScene(scene);
  const lines = [
    `The level (JSON, ${scene.size.w}×${scene.size.h}): ${JSON.stringify(scene)}`,
    `The player jumps at most ${Math.floor(jump.height)} px high and about ${Math.round(jump.reach(0) / 0.9)} px far on flat ground.`,
    `Checks: ${report.issues.length ? report.issues.map((i) => `${i.severity} ${i.code}: ${i.message}`).join("; ") : "no errors or warnings"}.`,
    facts.finished
      ? `The AI player reached the finish in ${facts.result.time.toFixed(1)} s without dying, standing on: ${facts.route.map(name).join(" → ")}. On that run it picked up ${facts.result.coins.length} of ${facts.result.coinsTotal} coins.`
      : `The AI player could not reach the finish without dying. It got as far as: ${facts.route.map(name).join(" → ") || "its start"}.`,
    `Trying each coin on its own, it could reach: ${facts.coinsReached.map((id) => `${name(id)} (${id})`).join(", ") || "none"}; it could not reach: ${facts.coinsMissed.map((id) => `${name(id)} (${id})`).join(", ") || "none"}.`,
  ];
  if (context) lines.push("", context);
  return lines.join("\n");
}

/// Keeps well-formed issues about objects that exist.
export function cleanReview(raw: unknown, scene: Scene): PlaytestReview {
  const r = (raw ?? {}) as { summary?: unknown; issues?: unknown };
  const ids = new Set(scene.objects.map((o) => o.id));
  const issues: PlaytestIssue[] = [];
  for (const item of Array.isArray(r.issues) ? r.issues.slice(0, 5) : []) {
    const i = item as { text?: unknown; objects?: unknown; kind?: unknown };
    if (typeof i.text !== "string" || !i.text.trim()) continue;
    issues.push({
      text: i.text.trim().slice(0, 400),
      objects: Array.isArray(i.objects) ? i.objects.filter((o): o is string => typeof o === "string" && ids.has(o)).slice(0, 8) : [],
      // Only an explicit problem shows as one; anything else is an idea.
      kind: i.kind === "problem" ? "problem" : "idea",
    });
  }
  return { summary: typeof r.summary === "string" ? r.summary.trim().slice(0, 500) : "", issues };
}

export function apiPlaytestReviewer(options: { client?: MessagesClient; model?: string } = {}): PlaytestReviewer {
  const client = options.client ?? new Anthropic();
  const model = options.model ?? process.env.SKITTLES_MODEL ?? "claude-sonnet-5-5";
  return async (scene, facts, context) => {
    const response = await client.messages.create({
      model,
      max_tokens: 3000,
      system: [{ type: "text", text: REVIEW_SYSTEM, cache_control: { type: "ephemeral" } }],
      tools: [{ name: "playtest_review", description: "The review for the team.", input_schema: REVIEW_SCHEMA as unknown as Anthropic.Tool.InputSchema }],
      tool_choice: { type: "tool", name: "playtest_review" },
      messages: [{ role: "user", content: reviewPrompt(scene, facts, context) }],
    });
    const use = response.content.find((b): b is Anthropic.ToolUseBlock => b.type === "tool_use");
    return cleanReview(use?.input, scene);
  };
}

export function cliPlaytestReviewer(options: { run?: Runner; model?: string } = {}): PlaytestReviewer {
  const run = options.run ?? runClaude;
  const model = options.model ?? process.env.SKITTLES_CLI_MODEL ?? "sonnet";
  const args = ["-p", "--model", model, "--effort", "low", "--output-format", "json", "--no-session-persistence", "--tools", "", "--system-prompt", REVIEW_SYSTEM, "--json-schema", JSON.stringify(REVIEW_SCHEMA)];
  return async (scene, facts, context) => {
    const result = JSON.parse(await run(args, reviewPrompt(scene, facts, context))) as { is_error?: boolean; result?: string; structured_output?: unknown };
    if (result.is_error || !result.structured_output) throw new Error(result.result || "the playtester returned no answer");
    return cleanReview(result.structured_output, scene);
  };
}
