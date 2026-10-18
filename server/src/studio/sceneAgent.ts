// The studio's AI assistant (spec/scene.md): a request and the scene in, structured actions out. It never writes
// code; game logic is behaviours with numbers. The studio applies the actions and checks the result with the same
// rules as every hand edit, and holds anything that would make the game unwinnable for the person to approve.

import Anthropic from "@anthropic-ai/sdk";
import { runClaude, type MessagesClient, type Runner } from "../agent/agent.ts";

export const ACTION_TYPES = ["CREATE_OBJECT", "UPDATE_OBJECT", "DELETE_OBJECT", "ADD_COMPONENT", "UPDATE_SCENE", "UPDATE_UI"] as const;
const OBJECT_TYPES = ["player", "platform", "coin", "enemy", "finish"] as const;
const COMPONENTS = ["controller", "collectible", "patrol"] as const;
const THEMES = ["forest", "desert", "night"] as const;
const NUMBERS = ["x", "y", "w", "h", "speed", "jump", "points", "from", "to"] as const;

export type SceneAction = {
  type: (typeof ACTION_TYPES)[number];
  id?: string;
  objectType?: (typeof OBJECT_TYPES)[number];
  name?: string;
  component?: (typeof COMPONENTS)[number];
  theme?: (typeof THEMES)[number];
  sceneName?: string;
  score?: boolean;
} & Partial<Record<(typeof NUMBERS)[number], number>>;

export type SceneReply = { message: string; actions: SceneAction[] };

/// The scene as the studio sends it: spec/scene.md's document. Only what the prompt needs is typed.
export type SceneDocument = {
  name?: string;
  size: { w: number; h: number };
  physics?: { gravity?: number };
  objects: { id: string; type: string; behaviours?: Record<string, Record<string, number>> }[];
};

/// [context] is what a shared project adds: who asks, the team's chat, others' recent changes.
export type SceneAssistant = (scene: SceneDocument, request: string, context?: string) => Promise<SceneReply>;

const ACTION_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["type"],
  properties: {
    type: { type: "string", enum: ACTION_TYPES },
    id: { type: "string", description: "The object to change (UPDATE_OBJECT, DELETE_OBJECT, ADD_COMPONENT)." },
    objectType: { type: "string", enum: OBJECT_TYPES, description: "CREATE_OBJECT: what to create." },
    name: { type: "string" },
    x: { type: "number" },
    y: { type: "number" },
    w: { type: "number" },
    h: { type: "number" },
    component: { type: "string", enum: COMPONENTS, description: "ADD_COMPONENT: which behaviour to set." },
    speed: { type: "number", description: "controller: run speed, or patrol: walking speed, px/s." },
    jump: { type: "number", description: "controller: take-off speed, px/s." },
    points: { type: "number", description: "collectible: points." },
    from: { type: "number", description: "patrol: leftmost x of the enemy's left edge." },
    to: { type: "number", description: "patrol: rightmost x of the enemy's left edge." },
    sceneName: { type: "string", description: "UPDATE_SCENE: the scene's new name." },
    theme: { type: "string", enum: THEMES, description: "UPDATE_SCENE: the look." },
    score: { type: "boolean", description: "UPDATE_UI: show the score." },
  },
} as const;

export const REPLY_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["message", "actions"],
  properties: {
    message: { type: "string", description: "One or two short sentences for the person, in their language." },
    actions: { type: "array", items: ACTION_SCHEMA },
  },
} as const;

export const SCENE_SYSTEM = `You are the AI assistant inside the Skittles studio, an editor for 2D platformer games. People describe what they want; you change their scene only by returning actions. You never write code: game logic is behaviours with numbers.

The scene: pixels, x grows to the right from 0, y grows down from 0. An object's x, y is its top-left corner; w, h its size.
Object types (default size; behaviour and its numbers):
- player, 32×48; controller: speed (run, px/s), jump (take-off speed, px/s). Exactly one per scene.
- platform, 192×24 by default, any size; solid: the player stands on its top.
- coin, 24×24; collectible: points.
- enemy, 40×36; patrol: walks between from and to (x of its left edge), at speed px/s.
- finish, 60×120; goal: touching it wins. At least one per scene.

Actions:
- CREATE_OBJECT: objectType, x, y, and optionally w, h, name and its behaviour numbers. Leave out id; the studio names new objects.
- UPDATE_OBJECT: id and the fields to change (name, x, y, w, h).
- DELETE_OBJECT: id.
- ADD_COMPONENT: id, component (controller, collectible or patrol) and its numbers (controller: speed, jump; collectible: points; patrol: from, to, speed).
- UPDATE_SCENE: sceneName and/or theme (forest, desert or night).
- UPDATE_UI: score (true or false) shows or hides the score.

How you work:
- Keep every object entirely inside the scene.
- Stand the player, enemies and the finish on a platform: their y + h equals that platform's y. Coins float above platforms, within jump height.
- The studio checks that the player can reach the finish. Use the jump numbers given with the request: a platform's top may be at most the jump height above the platform the player comes from, and the horizontal gap between them at most the reach listed for that height. Keep a margin of at least 10%.
- Prefer few, large platforms. Do not move or delete objects the person did not mention.
- To build a whole new level, you may delete the old objects and create new ones, but keep exactly one player and at least one finish.
- If the request needs something the studio does not have (scripts, sounds, music, new object types, 3D), return no actions and say what is possible instead.
- message: one or two short sentences in the language the person wrote in (English or Georgian), saying what you did.
- In a shared project you are one member's agent, and teammates may ask you too. An object's by says who made it: a member id, or agent:<id> for that member's agent. Do not move or delete what others made unless the request asks for it.`;

/// The jump model of spec/scene.md section 5.
export function jumpNumbers(scene: SceneDocument): { height: number; reach: (dh: number) => number } {
  const controller = scene.objects.find((o) => o.type === "player")?.behaviours?.controller ?? {};
  const v = controller.jump ?? 640;
  const s = controller.speed ?? 260;
  const g = scene.physics?.gravity ?? 1800;
  return {
    height: (v * v) / (2 * g),
    reach: (dh) => {
      const under = v * v - 2 * g * dh;
      return under < 0 ? -1 : (0.9 * s * (v + Math.sqrt(under))) / g;
    },
  };
}

export function scenePrompt(scene: SceneDocument, request: string, context?: string): string {
  const jump = jumpNumbers(scene);
  const reach = [0, 40, 80, Math.floor(jump.height)].map((dh) => `${Math.round(jump.reach(dh))} px for a platform ${dh} px higher`).join("; ");
  return [
    `The scene (JSON, ${scene.size.w}×${scene.size.h}):`,
    JSON.stringify(scene),
    "",
    `The player's jump: at most ${Math.floor(jump.height)} px high. Horizontal reach: ${reach}; dropping lower reaches farther.`,
    ...(context ? ["", context] : []),
    "",
    `Request: ${request}`,
  ].join("\n");
}

/// Keeps only well-formed actions: known types and fields, finite whole numbers, at most 60 actions.
export function cleanReply(raw: unknown): SceneReply {
  const answer = (raw ?? {}) as { message?: unknown; actions?: unknown };
  const actions: SceneAction[] = [];
  for (const item of Array.isArray(answer.actions) ? answer.actions.slice(0, 60) : []) {
    const a = item as Record<string, unknown>;
    if (!ACTION_TYPES.includes(a.type as SceneAction["type"])) continue;
    const action: SceneAction = { type: a.type as SceneAction["type"] };
    if (typeof a.id === "string") action.id = a.id.slice(0, 64);
    if (OBJECT_TYPES.includes(a.objectType as never)) action.objectType = a.objectType as SceneAction["objectType"];
    if (typeof a.name === "string") action.name = a.name.slice(0, 40);
    if (COMPONENTS.includes(a.component as never)) action.component = a.component as SceneAction["component"];
    if (THEMES.includes(a.theme as never)) action.theme = a.theme as SceneAction["theme"];
    if (typeof a.sceneName === "string") action.sceneName = a.sceneName.slice(0, 60);
    if (typeof a.score === "boolean") action.score = a.score;
    for (const key of NUMBERS) {
      const n = a[key];
      if (typeof n === "number" && Number.isFinite(n)) action[key] = Math.round(n);
    }
    if (action.type === "CREATE_OBJECT" && !action.objectType) continue;
    if (["UPDATE_OBJECT", "DELETE_OBJECT", "ADD_COMPONENT"].includes(action.type) && !action.id) continue;
    actions.push(action);
  }
  const message = typeof answer.message === "string" && answer.message.trim() ? answer.message.trim().slice(0, 500) : actions.length ? "Done." : "I could not do that.";
  return { message, actions };
}

/// The assistant on the Claude API: one forced tool call whose input is the reply.
export function apiSceneAssistant(options: { client?: MessagesClient; model?: string } = {}): SceneAssistant {
  const client = options.client ?? new Anthropic();
  const model = options.model ?? process.env.SKITTLES_MODEL ?? "claude-sonnet-5-5";
  return async (scene, request, context) => {
    const response = await client.messages.create({
      model,
      max_tokens: 6000,
      system: [{ type: "text", text: SCENE_SYSTEM, cache_control: { type: "ephemeral" } }],
      tools: [{ name: "scene_actions", description: "Change the scene with these actions and tell the person what you did.", input_schema: REPLY_SCHEMA as unknown as Anthropic.Tool.InputSchema }],
      tool_choice: { type: "tool", name: "scene_actions" },
      messages: [{ role: "user", content: scenePrompt(scene, request, context) }],
    });
    if (response.stop_reason === "refusal") return { message: "I can't help with that request.", actions: [] };
    const use = response.content.find((b): b is Anthropic.ToolUseBlock => b.type === "tool_use");
    return cleanReply(use?.input);
  };
}

/// The assistant on the signed-in Claude Code CLI, with the reply schema as structured output.
export function cliSceneAssistant(options: { run?: Runner; model?: string } = {}): SceneAssistant {
  const run = options.run ?? runClaude;
  const model = options.model ?? process.env.SKITTLES_CLI_MODEL ?? "sonnet";
  const args = ["-p", "--model", model, "--effort", "low", "--output-format", "json", "--no-session-persistence", "--tools", "", "--system-prompt", SCENE_SYSTEM, "--json-schema", JSON.stringify(REPLY_SCHEMA)];
  return async (scene, request, context) => {
    const result = JSON.parse(await run(args, scenePrompt(scene, request, context))) as { is_error?: boolean; result?: string; structured_output?: unknown };
    if (result.is_error || !result.structured_output) throw new Error(result.result || "the assistant returned no answer");
    return cleanReply(result.structured_output);
  };
}
