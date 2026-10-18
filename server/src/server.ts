// HTTP + Socket.IO front of one room. Every room event goes to every client; clients pick what they show.

import { readFile } from "node:fs/promises";
import { createServer, type Server as HttpServer } from "node:http";
import { extname, join, normalize } from "node:path";
import { Server } from "socket.io";
import type { Direction } from "./game/types.ts";
import type { Op } from "./room/ops.ts";
import type { PlaytestReport } from "./room/playtest.ts";
import { Room, type Proposal, type Role } from "./room/room.ts";
import { StudioHub } from "./studio/hub.ts";
import type { SceneAssistant, SceneDocument } from "./studio/sceneAgent.ts";

// The agent sits outside the room: it may take seconds, and it reports back through room commands.
export type AgentHandler = (room: Room, authorId: string, text: string) => Promise<void>;

// Lets the agent of an author whose work a pending change would break propose a compromise.
export type NegotiateHandler = (room: Room, proposal: Proposal, ownerId: string) => Promise<void>;

// Drafts a fix for one author from a playtest report.
export type SuggestHandler = (room: Room, authorId: string, report: PlaytestReport) => Promise<void>;

export type ServerOptions = {
  room: Room;
  staticDir?: string;
  agent?: AgentHandler;
  suggester?: SuggestHandler;
  negotiator?: NegotiateHandler;
  // The studio's AI assistant, behind POST /api/scene/ask and every agent in a shared project.
  sceneAssistant?: SceneAssistant;
  // The shared studio projects on /studio. One without saving is made when none is given.
  studio?: StudioHub;
};

// Reads a JSON request body, refusing anything over the limit.
function readJson(req: import("node:http").IncomingMessage, limit = 512 * 1024): Promise<unknown> {
  return new Promise((resolve, reject) => {
    let size = 0;
    const chunks: Buffer[] = [];
    req.on("data", (chunk: Buffer) => {
      size += chunk.length;
      if (size > limit) {
        reject(new Error("too large"));
        req.destroy();
      } else chunks.push(chunk);
    });
    req.on("end", () => {
      try {
        resolve(JSON.parse(Buffer.concat(chunks).toString("utf8")));
      } catch {
        reject(new Error("not JSON"));
      }
    });
    req.on("error", reject);
  });
}

const TYPES: Record<string, string> = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".svg": "image/svg+xml",
  ".png": "image/png",
  ".json": "application/json",
  ".woff2": "font/woff2",
};

const ROLES: readonly Role[] = ["author", "player", "stage"];
const DIRS: readonly Direction[] = ["up", "down", "left", "right"];

type Ack = (response: unknown) => void;
const noAck: Ack = () => {};

export function createRoomServer({ room, staticDir, agent, suggester, negotiator, sceneAssistant, studio = new StudioHub({ assistant: sceneAssistant }) }: ServerOptions): { http: HttpServer; io: Server; studio: StudioHub } {
  const http = createServer(async (req, res) => {
    if (req.url === "/api/projects") {
      return res.writeHead(200, { "content-type": "application/json" }).end(JSON.stringify(studio.list()));
    }
    // The studio asks its AI assistant: { scene, prompt } in, { message, actions } out.
    if (req.url?.startsWith("/api/scene/ask")) {
      const send = (status: number, body: unknown) => res.writeHead(status, { "content-type": "application/json" }).end(JSON.stringify(body));
      if (req.method !== "POST") return send(405, { error: "Use POST." });
      if (!sceneAssistant) return send(503, { error: "No AI is configured on this server. Sign in to the Claude Code CLI or set ANTHROPIC_API_KEY." });
      let body: { scene?: SceneDocument; prompt?: unknown };
      try {
        body = (await readJson(req)) as typeof body;
      } catch (e) {
        return send(400, { error: `The request was ${(e as Error).message}.` });
      }
      const prompt = typeof body.prompt === "string" ? body.prompt.trim().slice(0, 1000) : "";
      const scene = body.scene;
      if (!prompt || !scene || !Array.isArray(scene.objects) || !scene.size) return send(400, { error: "Send a scene and a prompt." });
      if (scene.objects.length > 300) return send(400, { error: "The scene has too many objects for one request." });
      const started = Date.now();
      try {
        const reply = await sceneAssistant(scene, prompt);
        return send(200, { ...reply, ms: Date.now() - started });
      } catch (e) {
        console.error("scene assistant failed", e);
        return send(502, { error: `The AI did not answer: ${(e as Error).message}` });
      }
    }
    if (!staticDir) {
      res.writeHead(404).end();
      return;
    }
    const url = new URL(req.url ?? "/", "http://localhost");
    const path = normalize(decodeURIComponent(url.pathname)).replace(/^(\.\.[/\\])+/, "");
    const file = join(staticDir, path === "/" ? "index.html" : path);
    try {
      const body = await readFile(file);
      res.writeHead(200, { "content-type": TYPES[extname(file)] ?? "application/octet-stream" }).end(body);
    } catch {
      // Unknown paths fall back to the app shell so ?role=... links work.
      try {
        res.writeHead(200, { "content-type": TYPES[".html"]! }).end(await readFile(join(staticDir, "index.html")));
      } catch {
        res.writeHead(404).end("Build the web client first: cd web && npm run build");
      }
    }
  });

  const io = new Server(http, { cors: { origin: true }, connectionStateRecovery: {} });
  studio.attach(io);
  const negotiated = new Set<string>();
  room.onEvent = (e) => {
    io.emit(e.type, e.payload);
    // A new conflict: the agents of the other authors whose work is in the way propose compromises.
    if (e.type === "proposal" && negotiator && e.payload.status === "open" && !negotiated.has(e.payload.id)) {
      negotiated.add(e.payload.id);
      const p = e.payload;
      const authors = new Set([...room.members.values()].filter((m) => m.role === "author").map((m) => m.id));
      const owners = new Set([...p.diagnosis.blockers, ...p.diagnosis.closedBy].flatMap((b) => (b.ownerId && b.ownerId !== p.requesterId && authors.has(b.ownerId) ? [b.ownerId] : [])));
      for (const ownerId of owners) negotiator(room, p, ownerId).catch((err: unknown) => console.error("negotiator failed", err));
    }
    // Every report goes to the agents of the authors it was routed to, who draft a fix right away.
    if (e.type === "report" && suggester) {
      for (const authorId of e.payload.routedTo) {
        suggester(room, authorId, e.payload).catch((err: unknown) => console.error("suggester failed", err));
      }
    }
  };

  // Open windows per member: a member is online while they have at least one.
  const windows = new Map<string, number>();
  const left = (id: string) => {
    const n = (windows.get(id) ?? 1) - 1;
    if (n > 0) return windows.set(id, n);
    windows.delete(id);
    room.leave(id);
  };

  io.on("connection", (socket) => {
    let memberId: string | null = null;
    const author = (): string | null => (memberId && room.members.get(memberId)?.role === "author" ? memberId : null);

    socket.on("join", (payload: { name?: unknown; role?: unknown }, ack: Ack = noAck) => {
      const role = ROLES.includes(payload?.role as Role) ? (payload.role as Role) : "stage";
      const member = room.join(String(payload?.name ?? ""), role);
      if (memberId !== member.id) {
        if (memberId) left(memberId);
        windows.set(member.id, (windows.get(member.id) ?? 0) + 1);
      }
      memberId = member.id;
      ack(room.snapshotFor(member.id));
    });

    // The landing page asks who is building right now, without joining.
    socket.on("room:who", (_payload: unknown, ack: Ack = noAck) => ack(room.present()));

    socket.on("disconnect", () => {
      if (memberId) left(memberId);
    });

    socket.on("agent:say", (payload: { text?: unknown }, ack: Ack = noAck) => {
      const id = author();
      const text = String(payload?.text ?? "").trim().slice(0, 500);
      if (!id || !text) return ack({ ok: false, message: "Join as an author and type a request." });
      room.say(id, "you", text);
      if (!agent) {
        room.say(id, "system", "No agent is configured on the server. Set ANTHROPIC_API_KEY in server/.env.");
        return ack({ ok: false, message: "no agent" });
      }
      ack({ ok: true });
      agent(room, id, text).catch((err: unknown) => {
        room.say(id, "system", `The agent failed: ${err instanceof Error ? err.message : String(err)}`);
      });
    });

    // Direct edits: used by tests and the debug panel. Agents go through the same room.submit.
    socket.on("doc:submit", (payload: { ops?: Op[]; summary?: string }, ack: Ack = noAck) => {
      const id = author();
      if (!id) return ack({ status: "rejected", code: "not_author", message: "Join as an author first." });
      ack(room.submit(id, Array.isArray(payload?.ops) ? payload.ops : [], payload?.summary));
    });

    socket.on("proposal:choose", (payload: { proposalId: string; optionId: string }, ack: Ack = noAck) => {
      const id = author();
      ack(id ? room.choose(id, payload.proposalId, payload.optionId) : { status: "rejected", code: "not_author" });
    });

    socket.on("approval:answer", (payload: { proposalId: string; accept: boolean }, ack: Ack = noAck) => {
      const id = author();
      ack(id ? room.answer(id, payload.proposalId, payload.accept === true) : { status: "rejected", code: "not_author" });
    });

    socket.on("history:revert", (payload: { rev: number }, ack: Ack = noAck) => {
      const id = author();
      ack(id ? room.revert(id, Number(payload?.rev)) : { status: "rejected", code: "not_author" });
    });

    socket.on("play:move", (payload: { dir?: unknown }) => {
      if (DIRS.includes(payload?.dir as Direction)) room.move(payload.dir as Direction);
    });

    socket.on("play:restart", () => room.restartPlay());

    socket.on("play:report", (payload: { text?: unknown }, ack: Ack = noAck) => {
      if (!memberId) return ack({ ok: false });
      const report = room.report(memberId, String(payload?.text ?? ""));
      ack(report ? { ok: true, routedTo: report.routedTo.map(room.nameOf), fallsHere: report.fallsHere, spot: report.spot } : { ok: false });
    });

    socket.on("suggestion:apply", (payload: { id: string }, ack: Ack = noAck) => {
      const id = author();
      ack(id ? room.applySuggestion(id, payload?.id) : { status: "rejected", code: "not_author" });
    });

    socket.on("suggestion:dismiss", (payload: { id: string }) => {
      const id = author();
      if (id) room.dismissSuggestion(id, payload?.id);
    });

    socket.on("history:worlds", (_payload: unknown, ack: Ack = noAck) => ack(room.history()));

    socket.on("room:reset", (_payload: unknown, ack: Ack = noAck) => {
      room.reset();
      ack({ ok: true });
    });
  });

  return { http, io, studio };
}
