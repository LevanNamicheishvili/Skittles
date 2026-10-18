// The studio's projects behind the Socket.IO namespace /studio. Each project is a Socket.IO room of its own; its
// events go to everyone in it. Projects are kept in memory and, with a data directory, saved there as JSON.

import { randomBytes } from "node:crypto";
import { existsSync, mkdirSync, readdirSync, readFileSync, writeFileSync, renameSync } from "node:fs";
import { join } from "node:path";
import type { Server, Socket } from "socket.io";
import { StudioProject } from "./project.ts";
import { blankScene, readScene } from "./scene.ts";
import type { PlaytestReviewer } from "./playtester.ts";
import type { SceneAssistant } from "./sceneAgent.ts";

type Ack = (response: unknown) => void;
const noAck: Ack = () => {};

/// people: the names of whoever is in the project now, so a second window can find its team and join it.
export type ProjectSummary = { id: string; name: string; objects: number; members: number; online: number; people: string[]; version: number };

export class StudioHub {
  readonly projects = new Map<string, StudioProject>();
  private readonly timers = new Map<string, ReturnType<typeof setTimeout>>();
  private readonly options: { assistant?: SceneAssistant; reviewer?: PlaytestReviewer; dataDir?: string };

  constructor(options: { assistant?: SceneAssistant; reviewer?: PlaytestReviewer; dataDir?: string } = {}) {
    this.options = options;
    const dir = options.dataDir;
    if (!dir || !existsSync(dir)) return;
    for (const file of readdirSync(dir).filter((f) => f.endsWith(".json"))) {
      try {
        const project = StudioProject.fromJSON(JSON.parse(readFileSync(join(dir, file), "utf8")), options.assistant, options.reviewer);
        this.add(project);
      } catch (e) {
        console.error(`could not load project ${file}:`, (e as Error).message);
      }
    }
  }

  private add(project: StudioProject) {
    this.projects.set(project.id, project);
    project.onDirty = () => this.save(project);
  }

  create(name?: string, scene?: unknown): StudioProject {
    let id: string;
    do id = randomBytes(4).toString("hex").slice(0, 6);
    while (this.projects.has(id));
    const project = new StudioProject(id, scene ? readScene(scene) : blankScene(name), this.options.assistant, this.options.reviewer);
    this.add(project);
    this.save(project);
    return project;
  }

  /// Every project, the ones with people in them first.
  list(): ProjectSummary[] {
    return [...this.projects.values()]
      .map((p) => {
        const here = [...p.members.values()].filter((m) => m.online);
        return { id: p.id, name: p.scene.name, objects: p.scene.objects.length, members: p.members.size, online: here.length, people: here.map((m) => m.name), version: p.version };
      })
      .sort((a, b) => b.online - a.online);
  }

  // Saves a second after the last change, through a temporary file so a crash never leaves half a project.
  private save(project: StudioProject) {
    const dir = this.options.dataDir;
    if (!dir) return;
    clearTimeout(this.timers.get(project.id));
    this.timers.set(
      project.id,
      setTimeout(() => {
        this.timers.delete(project.id);
        this.flush(project);
      }, 1000),
    );
  }

  private flush(project: StudioProject) {
    const dir = this.options.dataDir!;
    mkdirSync(dir, { recursive: true });
    const file = join(dir, `${project.id}.json`);
    writeFileSync(`${file}.tmp`, JSON.stringify(project));
    renameSync(`${file}.tmp`, file);
  }

  /// Writes every pending save now (on shutdown).
  flushAll() {
    for (const [id, timer] of this.timers) {
      clearTimeout(timer);
      this.flush(this.projects.get(id)!);
    }
    this.timers.clear();
  }

  attach(io: Server) {
    const nsp = io.of("/studio");
    const wired = new Set<string>();

    const wire = (project: StudioProject) => {
      if (wired.has(project.id)) return;
      wired.add(project.id);
      const room = `project:${project.id}`;
      project.onEvent = (e) => {
        if (e.type === "history") nsp.to(`${room}:${e.payload.member}`).emit("history", e.payload);
        else nsp.to(room).emit(e.type, e.payload);
      };
    };

    nsp.on("connection", (socket: Socket) => {
      let project: StudioProject | null = null;
      let member: string | null = null;
      const joined = (ack: Ack) => {
        if (!project || !member) ack({ ok: false, message: "Join a project first." });
        return project && member ? { project, member } : null;
      };

      // { project?, name, member?, scene? }: joins a project, or with no project id creates one (blank, or from scene).
      socket.on("join", (payload: { project?: unknown; name?: unknown; member?: unknown; scene?: unknown; sceneName?: unknown }, ack: Ack = noAck) => {
        try {
          const id = typeof payload?.project === "string" ? payload.project : "";
          const found = id ? this.projects.get(id) : this.create(typeof payload?.sceneName === "string" ? payload.sceneName : undefined, payload?.scene);
          if (!found) return ack({ ok: false, message: `There is no project ${id}.` });
          if (project && member) {
            project.leave(member);
            void socket.leave(`project:${project.id}`);
            void socket.leave(`project:${project.id}:${member}`);
          }
          project = found;
          wire(project);
          const m = project.join(String(payload?.name ?? ""), typeof payload?.member === "string" ? payload.member : undefined);
          member = m.id;
          void socket.join(`project:${project.id}`);
          void socket.join(`project:${project.id}:${m.id}`);
          ack({ ok: true, ...project.snapshot(m.id), history: project.history(m.id) });
          socket.to(`project:${project.id}`).emit("presence", { member: m.id, cursor: null, selected: null });
        } catch (e) {
          ack({ ok: false, message: (e as Error).message });
        }
      });

      socket.on("edit", (payload: { objects?: Record<string, unknown>; scene?: Record<string, unknown>; created?: unknown; seq?: unknown }, ack: Ack = noAck) => {
        const j = joined(ack);
        if (!j) return;
        const created = Array.isArray(payload?.created) ? payload.created.filter((x): x is string => typeof x === "string") : [];
        ack(j.project.edit(j.member, { objects: payload?.objects, scene: payload?.scene }, created, typeof payload?.seq === "number" ? payload.seq : undefined));
      });

      socket.on("undo", (_p: unknown, ack: Ack = noAck) => {
        const j = joined(ack);
        if (j) ack(j.project.undo(j.member));
      });

      socket.on("redo", (_p: unknown, ack: Ack = noAck) => {
        const j = joined(ack);
        if (j) ack(j.project.redo(j.member));
      });

      socket.on("revert", (payload: { change?: unknown }, ack: Ack = noAck) => {
        const j = joined(ack);
        if (j) ack(j.project.revert(j.member, Number(payload?.change)));
      });

      // The team chat. agents: the owners of the agents the message is for.
      socket.on("say", (payload: { text?: unknown; agents?: unknown }, ack: Ack = noAck) => {
        const j = joined(ack);
        if (!j) return;
        const agents = Array.isArray(payload?.agents) ? payload.agents.filter((x): x is string => typeof x === "string") : [];
        const message = j.project.say(j.member, String(payload?.text ?? ""), agents);
        ack(message ? { ok: true, id: message.id } : { ok: false, message: "Type a message." });
      });

      // A request to one agent: your own (agent omitted) or a teammate's.
      socket.on("ask", (payload: { text?: unknown; agent?: unknown }, ack: Ack = noAck) => {
        const j = joined(ack);
        if (!j) return;
        const owner = typeof payload?.agent === "string" ? payload.agent : j.member;
        ack({ ok: j.project.ask(j.member, owner, String(payload?.text ?? "")) });
      });

      socket.on("approve", (payload: { task?: unknown }, ack: Ack = noAck) => {
        const j = joined(ack);
        if (j) ack(j.project.approve(j.member, String(payload?.task ?? "")));
      });

      socket.on("discard", (payload: { task?: unknown }, ack: Ack = noAck) => {
        const j = joined(ack);
        if (j) ack(j.project.discard(j.member, String(payload?.task ?? "")));
      });

      // Playtests: the AI plays the scene now; a person shares a run they played on a version; the scene at a version,
      // to watch a run on.
      socket.on("playtest:ai", (_p: unknown, ack: Ack = noAck) => {
        const j = joined(ack);
        if (j) ack(j.project.playtestAi(j.member));
      });

      socket.on("playtest:share", (payload: { version?: unknown; run?: unknown; note?: unknown }, ack: Ack = noAck) => {
        const j = joined(ack);
        if (j) ack(j.project.shareRun(j.member, Number(payload?.version), payload?.run, payload?.note));
      });

      socket.on("scene:at", (payload: { version?: unknown }, ack: Ack = noAck) => {
        const j = joined(ack);
        if (!j) return;
        const scene = j.project.sceneAt(Number(payload?.version));
        ack(scene ? { ok: true, scene } : { ok: false, message: "That version is no longer in the history." });
      });

      // Where someone points and what they have selected, in scene pixels. Not kept.
      socket.on("presence", (payload: { cursor?: { x?: unknown; y?: unknown } | null; selected?: unknown }) => {
        if (!project || !member) return;
        const c = payload?.cursor;
        const cursor = c && typeof c.x === "number" && typeof c.y === "number" && Number.isFinite(c.x) && Number.isFinite(c.y) ? { x: Math.round(c.x), y: Math.round(c.y) } : null;
        socket.volatile.to(`project:${project.id}`).emit("presence", { member, cursor, selected: typeof payload?.selected === "string" ? payload.selected : null });
      });

      socket.on("disconnect", () => {
        if (!project || !member) return;
        const stillHere = [...(nsp.adapter.rooms.get(`project:${project.id}:${member}`) ?? [])].length > 0;
        if (!stillHere) {
          project.leave(member);
          nsp.to(`project:${project.id}`).emit("presence", { member, cursor: null, selected: null });
        }
      });
    });
  }
}
