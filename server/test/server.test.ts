import { after, before, describe, test } from "node:test";
import assert from "node:assert/strict";
import type { AddressInfo } from "node:net";
import { io as connect, type Socket } from "socket.io-client";
import { demoLevel } from "../src/levels/demo.ts";
import { Room } from "../src/room/room.ts";
import { createRoomServer } from "../src/server.ts";

describe("socket server", () => {
  const room = new Room(demoLevel());
  const { http, io } = createRoomServer({ room });
  let url = "";
  const sockets: Socket[] = [];

  before(async () => {
    await new Promise<void>((resolve) => http.listen(0, resolve));
    url = `http://localhost:${(http.address() as AddressInfo).port}`;
  });

  after(async () => {
    for (const s of sockets) s.disconnect();
    await io.close();
  });

  const client = (): Socket => {
    const s = connect(url, { transports: ["websocket"], forceNew: true });
    sockets.push(s);
    return s;
  };

  const next = <T>(s: Socket, event: string): Promise<T> => new Promise((resolve) => s.once(event, resolve));

  test("an author's change reaches everyone, and the player's moves too", async () => {
    const nino = client();
    const giorgi = client();
    const player = client();
    const joinedNino = await nino.emitWithAck("join", { name: "Nino", role: "author" });
    await giorgi.emitWithAck("join", { name: "Giorgi", role: "author" });
    await player.emitWithAck("join", { name: "Luka", role: "player" });
    assert.equal(joinedNino.you.letter, "A");
    assert.equal(joinedNino.state.solve.solvable, true);

    const seenByGiorgi = next<{ rev: number; world: { entities: { id: string }[] } }>(giorgi, "state");
    const result = await nino.emitWithAck("doc:submit", {
      ops: [{ op: "create", entity: { id: "pond", type: "lava", owner: { kind: "system" }, x: 10, y: 2, w: 2, h: 2 } }],
      summary: "a small lava pond",
    });
    assert.deepEqual(result, { status: "committed", rev: 1 });
    const state = await seenByGiorgi;
    assert.equal(state.rev, 1);
    assert.ok(state.world.entities.some((e) => e.id === "A1"));

    const seenByNino = next<{ x: number; y: number; deaths: number; trail: { x: number; y: number }[] }>(nino, "play");
    player.emit("play:move", { dir: "right" });
    const play = await seenByNino;
    assert.deepEqual([play.x, play.y, play.deaths], [2, 7, 0]);
    assert.deepEqual(play.trail, [{ x: 2, y: 7 }]);
  });

  test("only people with a window open are here; someone who comes back is the same member", async () => {
    const visitor = client();
    const ana = client();
    const anaAgain = client();
    await ana.emitWithAck("join", { name: "Ana", role: "author" });
    await anaAgain.emitWithAck("join", { name: "Ana", role: "author" }); // a second window
    const here = (await visitor.emitWithAck("room:who", {})) as { name: string; online: boolean }[];
    assert.ok(here.some((m) => m.name === "Ana"));
    assert.ok(here.every((m) => m.online));
    // Closing one of two windows: still here.
    ana.disconnect();
    await new Promise((r) => setTimeout(r, 50));
    assert.ok(((await visitor.emitWithAck("room:who", {})) as { name: string }[]).some((m) => m.name === "Ana"));
    // Closing the last: gone, and everyone hears it.
    const update = next<{ name: string; online: boolean }[]>(visitor, "members");
    anaAgain.disconnect();
    assert.equal((await update).find((m) => m.name === "Ana")?.online, false);
    assert.ok(!((await visitor.emitWithAck("room:who", {})) as { name: string }[]).some((m) => m.name === "Ana"));
    // Back again: the same member, online.
    const back = client();
    const joined = await back.emitWithAck("join", { name: "ana", role: "author" });
    assert.equal(joined.you.name, "Ana");
    assert.equal(joined.you.online, true);
  });

  test("a player cannot edit the level", async () => {
    const player = client();
    await player.emitWithAck("join", { name: "Luka", role: "player" });
    const result = await player.emitWithAck("doc:submit", { ops: [] });
    assert.equal(result.code, "not_author");
  });
});
