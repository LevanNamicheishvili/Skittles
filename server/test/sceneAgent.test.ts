import { describe, test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import type { AddressInfo } from "node:net";
import type Anthropic from "@anthropic-ai/sdk";
import type { MessagesClient } from "../src/agent/agent.ts";
import { demoLevel } from "../src/levels/demo.ts";
import { Room } from "../src/room/room.ts";
import { createRoomServer } from "../src/server.ts";
import { apiSceneAssistant, cleanReply, cliSceneAssistant, jumpNumbers, scenePrompt, type SceneAssistant, type SceneDocument } from "../src/studio/sceneAgent.ts";

// The starter scene from the shared cases.
const starter = (JSON.parse(readFileSync(new URL("../../spec/fixtures/scenes.json", import.meta.url), "utf8")) as { cases: { scene: SceneDocument }[] }).cases[0]!.scene;

describe("scene assistant", () => {
  test("the jump numbers match spec/scene.md", () => {
    const jump = jumpNumbers(starter);
    assert.equal(Math.round(jump.height * 10) / 10, 113.8);
    assert.equal(Math.round(jump.reach(0) * 10) / 10, 166.4);
    assert.equal(Math.round(jump.reach(100) * 10) / 10, 112.2);
  });

  test("the prompt carries the scene, the jump and the request", () => {
    const prompt = scenePrompt(starter, "add two coins above ledge B");
    assert.match(prompt, /at most 113 px high/);
    assert.match(prompt, /166 px for a platform 0 px higher/);
    assert.match(prompt, /"id":"ledge-b"/);
    assert.match(prompt, /Request: add two coins above ledge B$/);
  });

  test("only well-formed actions get through, with whole numbers", () => {
    const reply = cleanReply({
      message: "  Added a ledge.  ",
      actions: [
        { type: "CREATE_OBJECT", objectType: "platform", x: 300.6, y: 500.2, w: 160 },
        { type: "CREATE_OBJECT", x: 1, y: 1 }, // no objectType
        { type: "DELETE_OBJECT" }, // no id
        { type: "RUN_SHELL", command: "rm -rf /" }, // not an action
        { type: "UPDATE_OBJECT", id: "coin-1", x: Number.NaN, y: 410 },
        { type: "ADD_COMPONENT", id: "enemy-1", component: "patrol", from: 900, to: 1200, speed: 120, extra: "ignored" },
      ],
    });
    assert.equal(reply.message, "Added a ledge.");
    assert.deepEqual(reply.actions, [
      { type: "CREATE_OBJECT", objectType: "platform", x: 301, y: 500, w: 160 },
      { type: "UPDATE_OBJECT", id: "coin-1", y: 410 },
      { type: "ADD_COMPONENT", id: "enemy-1", component: "patrol", from: 900, to: 1200, speed: 120 },
    ]);
  });

  test("an empty answer says so", () => {
    assert.deepEqual(cleanReply(undefined), { message: "I could not do that.", actions: [] });
  });

  test("on the API it forces one tool call and returns its input, cleaned", async () => {
    const calls: Anthropic.MessageCreateParamsNonStreaming[] = [];
    const client: MessagesClient = {
      messages: {
        async create(params) {
          calls.push(params);
          return {
            stop_reason: "tool_use",
            content: [{ type: "tool_use", id: "t1", name: "scene_actions", input: { message: "Two coins above ledge B.", actions: [{ type: "CREATE_OBJECT", objectType: "coin", x: 600, y: 560 }] } }],
          } as unknown as Anthropic.Message;
        },
      },
    };
    const reply = await apiSceneAssistant({ client, model: "claude-sonnet-5-5" })(starter, "add a coin");
    assert.equal(reply.actions.length, 1);
    assert.deepEqual(calls[0]!.tool_choice, { type: "tool", name: "scene_actions" });
    assert.match(JSON.stringify(calls[0]!.system), /never write code/);
  });

  test("on the CLI it uses the reply schema as structured output", async () => {
    let seen: string[] = [];
    const run = async (args: string[]) => {
      seen = args;
      return JSON.stringify({ structured_output: { message: "Night it is.", actions: [{ type: "UPDATE_SCENE", theme: "night" }] } });
    };
    const reply = await cliSceneAssistant({ run })(starter, "make it night");
    assert.deepEqual(reply, { message: "Night it is.", actions: [{ type: "UPDATE_SCENE", theme: "night" }] });
    assert.ok(seen.includes("--json-schema"));
    assert.ok(seen.includes("--tools"));
  });
});

describe("POST /api/scene/ask", () => {
  async function serve(sceneAssistant?: SceneAssistant) {
    const { http, io } = createRoomServer({ room: new Room(demoLevel()), sceneAssistant });
    await new Promise<void>((r) => http.listen(0, r));
    const url = `http://localhost:${(http.address() as AddressInfo).port}/api/scene/ask`;
    return { url, close: () => new Promise<void>((r) => io.close(() => r())) };
  }

  test("answers with the assistant's actions and how long it took", async () => {
    const asked: string[] = [];
    const server = await serve(async (_scene, request) => {
      asked.push(request);
      return { message: "Done.", actions: [{ type: "UPDATE_UI", score: false }] };
    });
    const res = await fetch(server.url, { method: "POST", body: JSON.stringify({ scene: starter, prompt: "hide the score" }) });
    const body = (await res.json()) as { message: string; actions: unknown[]; ms: number };
    await server.close();
    assert.equal(res.status, 200);
    assert.deepEqual(body.actions, [{ type: "UPDATE_UI", score: false }]);
    assert.equal(typeof body.ms, "number");
    assert.deepEqual(asked, ["hide the score"]);
  });

  test("refuses bad requests and says when no AI is configured", async () => {
    const server = await serve(async () => ({ message: "", actions: [] }));
    assert.equal((await fetch(server.url)).status, 405);
    assert.equal((await fetch(server.url, { method: "POST", body: "not json" })).status, 400);
    assert.equal((await fetch(server.url, { method: "POST", body: JSON.stringify({ scene: starter }) })).status, 400);
    await server.close();
    const bare = await serve();
    const res = await fetch(bare.url, { method: "POST", body: JSON.stringify({ scene: starter, prompt: "hi" }) });
    await bare.close();
    assert.equal(res.status, 503);
  });

  test("an assistant failure becomes a readable 502", async () => {
    const server = await serve(async () => {
      throw new Error("timed out");
    });
    const res = await fetch(server.url, { method: "POST", body: JSON.stringify({ scene: starter, prompt: "hi" }) });
    const body = (await res.json()) as { error: string };
    await server.close();
    assert.equal(res.status, 502);
    assert.match(body.error, /timed out/);
  });
});
