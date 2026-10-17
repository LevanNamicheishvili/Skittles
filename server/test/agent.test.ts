import { describe, test } from "node:test";
import assert from "node:assert/strict";
import type Anthropic from "@anthropic-ai/sdk";
import { apiBackend, cliBackend, createAgent, createNegotiator, type MessagesClient } from "../src/agent/agent.ts";
import { levelContext, toOps } from "../src/agent/context.ts";
import { demoLevel } from "../src/levels/demo.ts";
import { Room } from "../src/room/room.ts";

// Answers each call with the next scripted reply and records what it was sent.
function fakeClient(replies: Anthropic.ContentBlock[][]): MessagesClient & { calls: Anthropic.MessageCreateParamsNonStreaming[] } {
  const calls: Anthropic.MessageCreateParamsNonStreaming[] = [];
  return {
    calls,
    messages: {
      async create(params) {
        calls.push(structuredClone(params));
        const content = replies.shift() ?? [];
        return { content, stop_reason: content.some((b) => b.type === "tool_use") ? "tool_use" : "end_turn" } as unknown as Anthropic.Message;
      },
    },
  };
}

const toolUse = (input: unknown, id = "t1") => ({ type: "tool_use", id, name: "change_level", input }) as Anthropic.ContentBlock;
const text = (t: string) => ({ type: "text", text: t }) as Anthropic.ContentBlock;

function setup() {
  const room = new Room(demoLevel());
  const nino = room.join("Nino", "author");
  const giorgi = room.join("Giorgi", "author");
  return { room, nino, giorgi };
}

const quiet = () => {};

describe("agent", () => {
  test("a tool call becomes a committed change and a chat reply", async () => {
    const { room, nino } = setup();
    const client = fakeClient([
      [toolUse({ message: "Adding a lava river.", summary: "Lava river", ops: [{ op: "create", type: "lava", x: 11, y: 1, w: 2, h: 5 }] })],
    ]);
    await createAgent({ backend: apiBackend({ client }), log: quiet })(room, nino.id, "lava river please");
    assert.equal(room.rev, 1);
    assert.equal(room.log[0]!.summary, "Lava river");
    assert.equal(room.chats.get(nino.id)!.at(-1)!.text, "Adding a lava river.");
    assert.equal(client.calls[0]!.model, "claude-sonnet-5-5");
  });

  test("a rejected batch goes back to the model once with the reason", async () => {
    const { room, nino } = setup();
    const client = fakeClient([
      [toolUse({ message: "Lava!", summary: "Lava", ops: [{ op: "create", type: "lava", x: 22, y: 1, w: 5, h: 2 }] })],
      [toolUse({ message: "Lava, inside the map.", summary: "Lava", ops: [{ op: "create", type: "lava", x: 19, y: 1, w: 3, h: 2 }] }, "t2")],
    ]);
    await createAgent({ backend: apiBackend({ client }), log: quiet })(room, nino.id, "lava in the top right");
    assert.equal(room.rev, 1);
    const retry = client.calls[1]!.messages.at(-1)!.content as Anthropic.ToolResultBlockParam[];
    assert.equal(retry[0]!.is_error, true);
    assert.match(String(retry[0]!.content), /outside the grid/);
  });

  test("a plain answer is passed on and nothing changes", async () => {
    const { room, nino } = setup();
    const client = fakeClient([[text("This game has no enemies yet. I can add lava or walls instead.")]]);
    await createAgent({ backend: apiBackend({ client }), log: quiet })(room, nino.id, "add a dragon");
    assert.equal(room.rev, 0);
    assert.match(room.chats.get(nino.id)!.at(-1)!.text, /no enemies/);
  });

  test("the context tells an agent what the other author changed", async () => {
    const { room, nino, giorgi } = setup();
    const client = fakeClient([
      [toolUse({ message: "River added.", summary: "Lava river", ops: [{ op: "create", type: "lava", x: 11, y: 1, w: 2, h: 5 }] })],
    ]);
    await createAgent({ backend: apiBackend({ client }), log: quiet })(room, nino.id, "river");
    const context = levelContext(room, giorgi.id, 0);
    assert.match(context, /Changes by others since your last request:\nv1 by Nino: Lava river/);
    assert.match(context, /A1 lava x=11 y=1 w=2 h=5 \(by Nino\)/);
    assert.match(context, /Status: winnable in \d+ steps/);
  });

  test("the CLI engine reads structured output and retries with the rejection", async () => {
    const { room, nino } = setup();
    const prompts: string[] = [];
    const answers = [
      { action: "change", message: "Lava!", summary: "Lava", ops: [{ op: "create", type: "lava", x: 22, y: 1, w: 5, h: 2 }] },
      { action: "change", message: "Lava inside the map.", summary: "Lava", ops: [{ op: "create", type: "lava", x: 19, y: 1, w: 3, h: 2 }] },
    ];
    const run = async (args: string[], stdin: string) => {
      assert.ok(args.includes("--json-schema"));
      prompts.push(stdin);
      return JSON.stringify({ type: "result", is_error: false, structured_output: answers.shift() });
    };
    await createAgent({ backend: cliBackend({ run }), log: quiet })(room, nino.id, "lava top right");
    assert.equal(room.rev, 1);
    assert.equal(prompts.length, 2);
    assert.match(prompts[1]!, /rejected by the room/);
    assert.equal(room.chats.get(nino.id)!.at(-1)!.text, "Lava inside the map.");
  });

  test("a CLI reply action changes nothing", async () => {
    const { room, nino } = setup();
    const run = async () => JSON.stringify({ is_error: false, structured_output: { action: "reply", message: "No dragons in v1.", summary: "", ops: [] } });
    await createAgent({ backend: cliBackend({ run }), log: quiet })(room, nino.id, "dragon");
    assert.equal(room.rev, 0);
    assert.equal(room.chats.get(nino.id)!.at(-1)!.text, "No dragons in v1.");
  });

  test("castle doors and updates convert to room ops", () => {
    const world = demoLevel();
    const [castle] = toOps(
      { message: "", summary: "", ops: [{ op: "create", type: "castle", x: 18, y: 4, w: 6, h: 7, door_side: "left", door_offset: 2, color: "gold" }] },
      world,
    );
    assert.deepEqual(castle, {
      op: "create",
      entity: { id: "new0", owner: { kind: "system" }, x: 18, y: 4, type: "castle", w: 6, h: 7, door: { side: "left", offset: 2, color: "gold" } },
    });
    world.entities.push({ id: "B1", type: "castle", owner: { kind: "system" }, x: 18, y: 4, w: 6, h: 7, door: { side: "left", offset: 2, color: "gold" } });
    const [open] = toOps({ message: "", summary: "", ops: [{ op: "update", id: "B1", color: null }] }, world);
    assert.deepEqual(open, { op: "update", id: "B1", set: { door: { side: "left", offset: 2, color: null } } });
  });
});

describe("negotiation", () => {
  test("the owner's agent proposes a checked compromise that joins the options", async () => {
    const { room, nino, giorgi } = setup();
    room.submit(nino.id, [
      { op: "create", entity: { id: "n", type: "lava", owner: { kind: "system" }, x: 11, y: 1, w: 2, h: 5 } },
      { op: "create", entity: { id: "s", type: "lava", owner: { kind: "system" }, x: 11, y: 8, w: 2, h: 5 } },
    ]);
    const conflict = room.submit(giorgi.id, [{ op: "create", entity: { id: "st", type: "wall", owner: { kind: "system" }, x: 11, y: 6, w: 2, h: 2, label: "Statue" } }]);
    assert.equal(conflict.status, "conflict");
    const proposal = conflict.status === "conflict" ? conflict.proposal : undefined;
    const prompts: string[] = [];
    const answers = [
      { action: "change", message: "Still blocked.", summary: "Nudge", ops: [{ op: "update", id: "B1", x: 11, y: 6 }] },
      { action: "change", message: "Giorgi, your statue can stand just left of the river, so my crossing stays open.", summary: "Move the statue left", ops: [{ op: "update", id: "B1", x: 8, y: 6 }] },
    ];
    const run = async (_args: string[], stdin: string) => {
      prompts.push(stdin);
      return JSON.stringify({ is_error: false, structured_output: answers.shift() });
    };
    await createNegotiator({ backend: cliBackend({ run }), log: quiet })(room, proposal!, nino.id);
    assert.match(prompts[0]!, /create B1 wall x=11 y=6 w=2 h=2 "Statue"/);
    assert.match(prompts[1]!, /still makes the level unwinnable/);
    const option = proposal!.options.find((o) => o.kind === "agent")!;
    assert.equal(option.title, "Nino's agent: Move the statue left");
    assert.deepEqual(option.touches, []);
    assert.deepEqual(proposal!.negotiating, []);
    assert.equal(room.choose(giorgi.id, proposal!.id, option.id).status, "committed");
    assert.ok(room.world.entities.some((e) => e.id === "B1" && e.x === 8));
    assert.equal(room.solveResult.solvable, true);
  });
});
