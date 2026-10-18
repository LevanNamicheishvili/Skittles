import { describe, test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import type Anthropic from "@anthropic-ai/sdk";
import type { MessagesClient } from "../src/agent/agent.ts";
import { aiPlaytest } from "../src/studio/play.ts";
import { apiPlaytestReviewer, cleanReview, cliPlaytestReviewer, reviewPrompt } from "../src/studio/playtester.ts";
import { readScene } from "../src/studio/scene.ts";

const starter = readScene(JSON.parse(readFileSync(new URL("../../spec/fixtures/scenes.json", import.meta.url), "utf8")).cases[0].scene);

describe("the AI playtester's review", () => {
  test("the prompt carries what the AI player found, coin by coin", async () => {
    const facts = await aiPlaytest(starter);
    const prompt = reviewPrompt(starter, facts, "Team chat, latest last:\n- Nino: make it harder");
    assert.match(prompt, /reached the finish in [\d.]+ s without dying, standing on: Ground → /);
    assert.match(prompt, /On that run it picked up \d of 2 coins\./);
    assert.match(prompt, /Trying each coin on its own, it could reach: Coin \(coin-1\), Coin \(coin-2\); it could not reach: none\./);
    assert.match(prompt, /make it harder$/);
  });

  test("only issues with text get through, and only objects that exist", () => {
    const review = cleanReview(
      { summary: " Fine. ", issues: [{ text: "Coin too high.", objects: ["coin-1", "ghost"], kind: "problem" }, { text: "" }, { text: "More enemies.", objects: "enemy-1", kind: "wish" }] },
      starter,
    );
    assert.deepEqual(review, {
      summary: "Fine.",
      issues: [
        { text: "Coin too high.", objects: ["coin-1"], kind: "problem" },
        { text: "More enemies.", objects: [], kind: "idea" },
      ],
    });
  });

  test("runs on the API as one forced tool call, and on the CLI with the schema", async () => {
    const facts = await aiPlaytest(starter);
    const client: MessagesClient = {
      messages: {
        async create(params) {
          assert.deepEqual(params.tool_choice, { type: "tool", name: "playtest_review" });
          return { content: [{ type: "tool_use", id: "t", name: "playtest_review", input: { summary: "Good.", issues: [] } }] } as unknown as Anthropic.Message;
        },
      },
    };
    assert.deepEqual(await apiPlaytestReviewer({ client })(starter, facts), { summary: "Good.", issues: [] });
    let args: string[] = [];
    const run = async (a: string[]) => {
      args = a;
      return JSON.stringify({ structured_output: { summary: "Good.", issues: [] } });
    };
    assert.deepEqual(await cliPlaytestReviewer({ run })(starter, facts), { summary: "Good.", issues: [] });
    assert.ok(args.includes("--json-schema"));
  });
});
