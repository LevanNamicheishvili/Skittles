import { describe, test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, readdirSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import type { AddressInfo } from "node:net";
import { io as connect, type Socket } from "socket.io-client";
import { demoLevel } from "../src/levels/demo.ts";
import { Room } from "../src/room/room.ts";
import { createRoomServer } from "../src/server.ts";
import { StudioHub } from "../src/studio/hub.ts";
import { StudioProject, type ProjectEvent } from "../src/studio/project.ts";
import { byId, readScene, type Scene } from "../src/studio/scene.ts";
import type { SceneAssistant, SceneReply } from "../src/studio/sceneAgent.ts";
import type { PlaytestReviewer } from "../src/studio/playtester.ts";
import { RIGHT } from "../src/studio/play.ts";

const starter: Scene = readScene(JSON.parse(readFileSync(new URL("../../spec/fixtures/scenes.json", import.meta.url), "utf8")).cases[0].scene);

/// An assistant that answers from a list and remembers what it was asked.
function scripted(...replies: SceneReply[]) {
  const asked: { request: string; context?: string }[] = [];
  const assistant: SceneAssistant = async (_scene, request, context) => {
    asked.push({ request, context });
    return replies.shift() ?? { message: "Nothing more.", actions: [] };
  };
  return { assistant, asked };
}

function project(assistant?: SceneAssistant) {
  const p = new StudioProject("p1", starter, assistant);
  const events: ProjectEvent[] = [];
  p.onEvent = (e) => events.push(e);
  const nino = p.join("Nino").id;
  const giorgi = p.join("Giorgi").id;
  return { p, events, nino, giorgi };
}

describe("a shared project", () => {
  test("edits get versions and authors; a new object whose id was taken gets the next one", () => {
    const { p, events, nino, giorgi } = project();
    const coin = { name: "Coin 3", type: "coin", x: 100, y: 100, w: 24, h: 24 };
    assert.deepEqual(p.edit(nino, { objects: { "coin-3": coin } }, ["coin-3"], 1), { ok: true, version: 1, renamed: {} });
    const second = p.edit(giorgi, { objects: { "coin-3": { ...coin, x: 200 } } }, ["coin-3"], 1);
    assert.deepEqual(second.renamed, { "coin-3": "coin-4" });
    assert.equal(byId(p.scene, "coin-3")!.by, nino);
    assert.equal(byId(p.scene, "coin-4")!.by, giorgi);
    const changes = events.filter((e) => e.type === "change").map((e) => e.payload as { v: number; by: string; seq?: number; notes: string[] });
    assert.deepEqual(changes.map((c) => [c.v, c.by, c.seq]), [[1, nino, 1], [2, giorgi, 1]]);
    assert.deepEqual(changes[1]!.notes, ["+ Coin 3 at (200, 100)"]);
  });

  test("an edit to something a teammate removed changes nothing, and who made an object never changes", () => {
    const { p, nino, giorgi } = project();
    p.edit(nino, { objects: { "coin-1": null } });
    p.edit(giorgi, { objects: { "coin-1": { ...byId(starter, "coin-1"), x: 5 } } });
    assert.equal(byId(p.scene, "coin-1"), undefined);
    p.edit(nino, { objects: { "coin-9": { name: "C", type: "coin", x: 1, y: 1, w: 24, h: 24 } } }, ["coin-9"]);
    p.edit(giorgi, { objects: { "coin-9": { name: "C", type: "coin", x: 50, y: 1, w: 24, h: 24, by: giorgi } } });
    assert.equal(byId(p.scene, "coin-9")!.by, nino);
    assert.equal(byId(p.scene, "coin-9")!.x, 50);
  });

  test("undo and redo are each member's own", () => {
    const { p, nino, giorgi } = project();
    p.edit(nino, { objects: { "ledge-a": { ...byId(starter, "ledge-a"), x: 320 } } });
    p.edit(giorgi, { objects: { "ledge-b": { ...byId(starter, "ledge-b"), x: 600 } } });
    assert.ok(p.undo(nino).ok);
    assert.equal(byId(p.scene, "ledge-a")!.x, 300);
    assert.equal(byId(p.scene, "ledge-b")!.x, 600);
    assert.deepEqual(p.history(nino), { member: nino, canUndo: false, canRedo: true });
    assert.ok(p.redo(nino).ok);
    assert.equal(byId(p.scene, "ledge-a")!.x, 320);
    assert.ok(p.undo(nino).ok);
    assert.equal(p.undo(nino).ok, false);
  });

  test("undoing a removal brings the object back, under a new id if its old one was taken", () => {
    const { p, nino, giorgi } = project();
    p.edit(nino, { objects: { "coin-2": null } });
    p.edit(giorgi, { objects: { "coin-2": { name: "Other", type: "coin", x: 10, y: 10, w: 24, h: 24 } } }, ["coin-2"]);
    p.undo(nino);
    assert.equal(byId(p.scene, "coin-2")!.name, "Other");
    assert.equal(byId(p.scene, "coin-3")!.x, byId(starter, "coin-2")!.x);
  });

  test("a teammate's @mention runs my agent right away; I see it in my thread and can undo it", async () => {
    const { assistant, asked } = scripted({ message: "Added a coin over Ledge B.", actions: [{ type: "CREATE_OBJECT", objectType: "coin", x: 600, y: 560 }] });
    const { p, nino, giorgi } = project(assistant);
    p.say(giorgi, "Let's make it shinier.");
    p.say(giorgi, "@Nino's agent add a coin above ledge B");
    await p.idle();
    assert.equal(asked[0]!.request, "add a coin above ledge B");
    assert.match(asked[0]!.context!, /Giorgi, a teammate, asks you from the team chat; Nino sees what you do/);
    assert.match(asked[0]!.context!, /Giorgi: Let's make it shinier\./);
    const thread = p.threads.get(nino)!;
    assert.deepEqual(thread.map((m) => [m.from, m.by, m.viaTeam, m.outcome]), [
      ["member", giorgi, true, undefined],
      ["agent", undefined, undefined, "applied"],
    ]);
    const report = p.team.at(-1)!;
    assert.equal(report.kind, "agent");
    assert.equal(report.from, nino);
    assert.equal(report.for, giorgi);
    assert.deepEqual(report.notes, ["+ Coin 3 at (600, 560)"]);
    assert.equal(byId(p.scene, "coin-3")!.by, `agent:${nino}`);
    const change = p.changes.at(-1)!;
    assert.deepEqual([change.by, change.agentOf, change.kind], [giorgi, nino, "agent"]);
    // The owner undoes it from the card.
    assert.ok(p.revert(nino, report.change!).ok);
    assert.equal(byId(p.scene, "coin-3"), undefined);
    assert.equal(p.team.at(-1)!.outcome, "undone");
    assert.equal(p.threads.get(nino)!.at(-1)!.undoneBy, nino);
  });

  test("my own requests stay in my thread, and the team sees what my agent did", async () => {
    const { assistant } = scripted({ message: "Night it is.", actions: [{ type: "UPDATE_SCENE", theme: "night" }] }, { message: "That needs sounds, which the studio does not have.", actions: [] });
    const { p, nino } = project(assistant);
    p.ask(nino, nino, "make it night");
    p.ask(nino, nino, "add music");
    assert.equal(p.members.get(nino)!.agent.queued, 1);
    await p.idle();
    assert.equal(p.scene.theme, "night");
    assert.deepEqual(p.team.map((m) => [m.kind, m.text, m.outcome]), [["agent", "Night it is.", "applied"]]);
    assert.deepEqual(p.threads.get(nino)!.map((m) => m.from), ["member", "member", "agent", "agent"]);
  });

  test("actions that change nothing leave no change lines", async () => {
    const { assistant } = scripted({ message: "It is forest now.", actions: [{ type: "UPDATE_SCENE", theme: "forest" }] });
    const { p, nino } = project(assistant);
    p.ask(nino, nino, "make it a forest");
    await p.idle();
    const reply = p.threads.get(nino)!.at(-1)!;
    assert.deepEqual([reply.notes, reply.outcome, p.version], [[], undefined, 0]);
  });

  test("a change that would break the game is retried once, then held for whoever asked", async () => {
    const breakIt: SceneReply = { message: "Removed the ground.", actions: [{ type: "DELETE_OBJECT", id: "ground-2" }] };
    const { assistant, asked } = scripted(breakIt, breakIt);
    const { p, nino, giorgi } = project(assistant);
    p.say(giorgi, "@nino's agent remove the right ground");
    await p.idle();
    assert.match(asked[1]!.request, /would have broken the game: The finish cannot be reached\./);
    const held = p.team.at(-1)!;
    assert.deepEqual([held.outcome, held.reason], ["held", "The finish cannot be reached."]);
    assert.ok(byId(p.scene, "ground-2"));
    assert.equal(p.approve("m9", held.task!).ok, false);
    assert.ok(p.approve(giorgi, held.task!).ok);
    assert.equal(byId(p.scene, "ground-2"), undefined);
    assert.equal(p.threads.get(nino)!.at(-1)!.outcome, "approved");
  });

  test("a retry that fixes it is applied", async () => {
    const { assistant } = scripted(
      { message: "Removed it.", actions: [{ type: "DELETE_OBJECT", id: "ground-2" }] },
      { message: "Moved it instead.", actions: [{ type: "UPDATE_OBJECT", id: "coin-1", x: 400 }] },
    );
    const { p, nino } = project(assistant);
    p.ask(nino, nino, "clean up");
    await p.idle();
    assert.equal(p.threads.get(nino)!.at(-1)!.outcome, "applied");
    assert.ok(byId(p.scene, "ground-2"));
  });

  test("my agent knows what others changed", async () => {
    const { assistant, asked } = scripted();
    const { p, nino, giorgi } = project(assistant);
    p.edit(giorgi, { objects: { "ledge-c": { ...byId(starter, "ledge-c"), y: 500 } } });
    p.ask(nino, nino, "what changed?");
    await p.idle();
    assert.match(asked[0]!.context!, /Recent changes by others:\n- Giorgi: ~ Moved Ledge C to \(840, 500\)/);
  });

  test("coming back takes the old place instead of leaving a ghost", () => {
    const { p, nino } = project();
    p.leave(nino);
    assert.equal(p.join("nino").id, nino);
    assert.equal(p.members.size, 2);
    assert.equal(p.join("Nino").id, "m3"); // Nino is online now, so this is someone else
  });

  test("a project survives saving and loading", () => {
    const { p, nino, giorgi } = project();
    p.say(nino, "hi");
    p.edit(giorgi, { objects: { "coin-1": null } });
    const again = StudioProject.fromJSON(JSON.parse(JSON.stringify(p)));
    assert.deepEqual(again.scene, p.scene);
    assert.equal(again.version, p.version);
    assert.equal(again.team[0]!.text, "hi");
    assert.equal(again.join("Giorgi").id, giorgi);
    assert.equal(again.join("Ana").id, "m3");
    // The history comes along: Giorgi can still undo, and the change can still be reverted by name.
    assert.deepEqual(again.history(giorgi), { member: giorgi, canUndo: true, canRedo: false });
    assert.ok(again.undo(giorgi).ok);
    assert.ok(byId(again.scene, "coin-1"));
  });
});

describe("playtests", () => {
  test("a shared run is replayed on the version it was played on, even after the scene changed", () => {
    const { p, nino, giorgi } = project();
    const v = p.version;
    p.edit(giorgi, { objects: { "ground-1": null } }); // after Nino played, the ground goes
    const ok = p.shareRun(nino, v, [[1, 0], [400, RIGHT]], "The first gap is easy");
    assert.ok(ok.ok);
    const card = p.team.at(-1)!;
    assert.equal(card.kind, "playtest");
    assert.equal(card.playtest!.version, v);
    assert.equal(card.playtest!.note, "The first gap is easy");
    // Running right from the start on the original scene: the player walks off the first ground into the gap.
    assert.equal(card.playtest!.result!.won, false);
    assert.ok(card.playtest!.result!.deaths >= 1);
    const byIdOrder = (s: Scene | null) => [...(s?.objects ?? [])].sort((a, b) => a.id.localeCompare(b.id));
    assert.deepEqual(byIdOrder(p.sceneAt(v)), byIdOrder(starter));
    assert.equal(p.sceneAt(v + 5), null);
    assert.equal(p.shareRun(nino, v, [[0, 9]]).ok, false);
  });

  test("the AI plays, the reviewer names the objects behind each problem, and they go to who made them", async () => {
    const seen: string[] = [];
    const reviewer: PlaytestReviewer = async (scene, facts) => {
      seen.push(`${facts.finished} ${facts.coinsMissed.join(",")}`);
      return { summary: "Plays well; one coin is out of reach.", issues: [{ text: "Coin 3 is too high; lower it to 560.", objects: ["coin-3", "nope"], kind: "problem" }] };
    };
    const p = new StudioProject("p2", starter, undefined, reviewer);
    const nino = p.join("Nino").id;
    const giorgi = p.join("Giorgi").id;
    p.edit(giorgi, { objects: { "coin-3": { name: "Coin 3", type: "coin", x: 600, y: 200, w: 24, h: 24 } } }, ["coin-3"]);
    assert.ok(p.playtestAi(nino).ok);
    assert.equal(p.playtestAi(nino).ok, false); // one at a time
    assert.equal(p.team.at(-1)!.playtest!.status, "playing");
    await p.playtestsIdle();
    const card = p.team.at(-1)!;
    assert.deepEqual([card.from, card.for, card.playtest!.status, card.playtest!.finished], ["ai", nino, "done", true]);
    assert.deepEqual(card.playtest!.coinsMissed, ["coin-3"]);
    assert.deepEqual(seen, ["true coin-3"]);
    assert.deepEqual(card.playtest!.issues, [{ text: "Coin 3 is too high; lower it to 560.", objects: ["coin-3", "nope"], kind: "problem", owners: [giorgi] }]);
    // The agents hear about it.
    assert.match(p.contextFor({ id: "t", owner: giorgi, by: giorgi, text: "", viaTeam: false }), /Recent playtests:\n- The AI player \(v1\): finished in [\d.]+ s, \d+ points; could not reach coin-3; problem: Coin 3 is too high/);
  });

  test("the AI needs a player and a finish", () => {
    const p = new StudioProject("p3", readScene({ ...starter, objects: [] }));
    const nino = p.join("Nino").id;
    assert.equal(p.playtestAi(nino).ok, false);
  });
});

describe("the /studio namespace", () => {
  async function serve(hub: StudioHub) {
    const { http, io } = createRoomServer({ room: new Room(demoLevel()), studio: hub });
    await new Promise<void>((r) => http.listen(0, r));
    const url = `http://localhost:${(http.address() as AddressInfo).port}`;
    const sockets: Socket[] = [];
    const client = () => {
      const s = connect(`${url}/studio`, { transports: ["websocket"], forceNew: true });
      sockets.push(s);
      return s;
    };
    const close = () =>
      new Promise<void>((r) => {
        for (const s of sockets) s.disconnect();
        io.close(() => r());
      });
    return { url, client, close };
  }
  const call = <T>(s: Socket, event: string, payload: unknown) => new Promise<T>((r) => s.emit(event, payload, r));
  const next = <T>(s: Socket, event: string) => new Promise<T>((r) => s.once(event, r));

  test("create, join, edit, see each other, and find the project saved", async () => {
    const dataDir = mkdtempSync(join(tmpdir(), "skittles-studio-"));
    const hub = new StudioHub({ dataDir });
    const server = await serve(hub);
    const a = server.client();
    const created = await call<{ ok: boolean; project: string; you: string; scene: Scene }>(a, "join", { name: "Nino", sceneName: "Cave" });
    assert.ok(created.ok);
    assert.equal(created.scene.name, "Cave");
    assert.equal(created.scene.objects.length, 0);
    const b = server.client();
    const joined = await call<{ ok: boolean; you: string; members: { name: string }[] }>(b, "join", { name: "Giorgi", project: created.project });
    assert.deepEqual(joined.members.map((m) => m.name), ["Nino", "Giorgi"]);

    const seen = next<{ v: number; by: string; patch: { objects: Record<string, unknown> } }>(b, "change");
    const ack = await call<{ ok: boolean; version: number }>(a, "edit", { objects: { player: { name: "Player", type: "player", x: 80, y: 700, w: 32, h: 48 } }, created: ["player"], seq: 1 });
    assert.deepEqual([ack.ok, ack.version], [true, 1]);
    const change = await seen;
    assert.equal(change.by, created.you);
    assert.ok(change.patch.objects.player);

    const pointed = next<{ member: string; cursor: { x: number; y: number } }>(a, "presence");
    b.emit("presence", { cursor: { x: 10.4, y: 20 }, selected: "player" });
    assert.deepEqual((await pointed).cursor, { x: 10, y: 20 });

    const said = next<{ text: string; from: string }>(a, "team");
    await call(b, "say", { text: "hello" });
    assert.equal((await said).text, "hello");

    assert.equal((await call<{ ok: boolean }>(a, "join", { project: "nope", name: "X" })).ok, false);
    const list = (await (await fetch(`${server.url}/api/projects`)).json()) as { id: string; objects: number; people: string[] }[];
    assert.deepEqual(list.map((p) => [p.id, p.objects, p.people]), [[created.project, 1, ["Nino", "Giorgi"]]]);
    hub.flushAll();
    assert.deepEqual(readdirSync(dataDir), [`${created.project}.json`]);
    await server.close();
    assert.equal(new StudioHub({ dataDir }).projects.get(created.project)!.scene.objects.length, 1);
  });

  test("leaving marks a member offline", async () => {
    const server = await serve(new StudioHub());
    const a = server.client();
    const b = server.client();
    const first = await call<{ project: string; you: string }>(a, "join", { name: "Nino" });
    await call(b, "join", { name: "Giorgi", project: first.project });
    const update = next<{ name: string; online: boolean }[]>(b, "members");
    a.disconnect();
    assert.deepEqual((await update).map((m) => [m.name, m.online]), [["Nino", false], ["Giorgi", true]]);
    await server.close();
  });
});
