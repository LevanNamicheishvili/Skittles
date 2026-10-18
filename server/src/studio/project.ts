// A shared studio project: one scene that several people and their agents change together. The project is the
// single writer: every change gets the next version, an author and a patch that can undo it. Each member has an
// agent; its owner talks to it in their own thread, and teammates can direct it from the team chat with an
// @mention. It acts on such a request right away, says so in its owner's thread, and anyone involved can undo it.
// Agent changes that would make the game unwinnable are held for the person who asked, as in the solo studio.

import { randomBytes } from "node:crypto";
import { aiPlaytest, readRun, replay, type RunResult, type Segment } from "./play.ts";
import type { PlaytestReviewer } from "./playtester.ts";
import type { SceneAssistant, SceneReply } from "./sceneAgent.ts";
import { applyActions, applyPatch, byId, describePatch, diff, freeId, inverse, isEmpty, newErrors, readObject, type Action, type Patch, type Scene, type SceneObject } from "./scene.ts";

export const MEMBER_COLORS = ["#3b82f6", "#f97316", "#10b981", "#e11d48", "#8b5cf6", "#0ea5e9"];

export type AgentState = { status: "idle" | "thinking"; task?: string; for?: string; queued: number };
export type Member = { id: string; name: string; color: string; online: boolean; agent: AgentState };

export type Outcome = "applied" | "held" | "approved" | "discarded" | "undone" | "failed";

/// One problem or idea from the AI playtester, with the objects behind it and the people who made them.
export type PlaytestNote = { text: string; objects: string[]; owners: string[]; kind: "problem" | "idea" };

/// A playtest in the team chat: a person's shared run, or the AI's (from = "ai", for = who asked).
export type Playtest = {
  status: "playing" | "done" | "failed";
  version: number;
  result?: RunResult;
  run?: Segment[];
  note?: string;
  finished?: boolean;
  coinsMissed?: string[];
  summary?: string;
  issues?: PlaytestNote[];
};

/// A line in the team chat: something a member wrote, an agent reporting what it did, or a playtest.
export type TeamMessage = {
  id: string;
  kind: "chat" | "agent" | "playtest";
  playtest?: Playtest;
  from: string; // member id; for "agent", the agent's owner
  text: string;
  at: number;
  agents?: string[]; // chat: the owners of the agents it mentions
  for?: string; // agent: who asked
  task?: string;
  notes?: string[];
  outcome?: Outcome;
  reason?: string;
  change?: number;
  undoneBy?: string;
};

/// A line in one member's thread with their agent.
export type ThreadMessage = {
  id: string;
  owner: string;
  from: "member" | "agent" | "system";
  by?: string; // member: who wrote it, the owner or a teammate
  viaTeam?: boolean;
  text: string;
  at: number;
  task?: string;
  notes?: string[];
  outcome?: Outcome;
  reason?: string;
  change?: number;
  undoneBy?: string;
};

export type Change = {
  v: number;
  by: string;
  agentOf?: string;
  kind: "edit" | "agent" | "undo";
  of?: number; // undo: the change it reverts
  patch: Patch;
  undo: Patch;
  notes: string[];
  seq?: number;
  at: number;
  undone?: boolean;
};

export type ChangeEvent = Omit<Change, "undo">;

export type ProjectEvent =
  | { type: "change"; payload: ChangeEvent }
  | { type: "members"; payload: Member[] }
  | { type: "team"; payload: TeamMessage }
  | { type: "thread"; payload: ThreadMessage }
  | { type: "history"; payload: { member: string; canUndo: boolean; canRedo: boolean } };

type Task = { id: string; owner: string; by: string; text: string; viaTeam: boolean };
type Held = { task: Task; actions: Action[] };

export type Snapshot = {
  project: string;
  you: string;
  version: number;
  scene: Scene;
  members: Member[];
  team: TeamMessage[];
  threads: Record<string, ThreadMessage[]>;
};

const newId = () => randomBytes(6).toString("base64url");

export class StudioProject {
  readonly id: string;
  scene: Scene;
  version = 0;
  readonly members = new Map<string, Member>();
  readonly team: TeamMessage[] = [];
  readonly threads = new Map<string, ThreadMessage[]>();
  readonly changes: Change[] = [];
  onEvent: (e: ProjectEvent) => void = () => {};
  /// Called after anything worth saving changes.
  onDirty: () => void = () => {};

  private readonly undoStacks = new Map<string, number[]>();
  private readonly redoStacks = new Map<string, number[]>();
  private readonly queues = new Map<string, Task[]>();
  private readonly held = new Map<string, Held>();
  private nextMember = 1;
  private readonly assistant?: SceneAssistant;
  private readonly reviewer?: PlaytestReviewer;
  private aiPlaying = false;

  constructor(id: string, scene: Scene, assistant?: SceneAssistant, reviewer?: PlaytestReviewer) {
    this.id = id;
    this.scene = scene;
    this.assistant = assistant;
    this.reviewer = reviewer;
  }

  // ---- Members -------------------------------------------------------------------------------------------------

  /// Joins as [name]. Someone coming back (the same member id, or an offline member with the same name) gets their
  /// old place, so reconnecting never leaves a ghost behind.
  join(name: string, rejoin?: string): Member {
    const clean = name.trim().slice(0, 24) || "Guest";
    const back = (rejoin && this.members.get(rejoin)) || [...this.members.values()].find((m) => !m.online && m.name.toLowerCase() === clean.toLowerCase());
    if (back) {
      back.online = true;
      this.emitMembers();
      return back;
    }
    const id = `m${this.nextMember++}`;
    const member: Member = { id, name: clean, color: MEMBER_COLORS[(this.members.size) % MEMBER_COLORS.length]!, online: true, agent: { status: "idle", queued: 0 } };
    this.members.set(id, member);
    this.threads.set(id, []);
    this.emitMembers();
    this.onDirty();
    return member;
  }

  leave(memberId: string): void {
    const m = this.members.get(memberId);
    if (!m) return;
    m.online = false;
    this.emitMembers();
  }

  nameOf = (id: string): string => (id.startsWith("agent:") ? `${this.nameOf(id.slice(6))}'s agent` : (this.members.get(id)?.name ?? "someone"));

  snapshot(you: string): Snapshot {
    return {
      project: this.id,
      you,
      version: this.version,
      scene: this.scene,
      members: [...this.members.values()],
      team: this.team.slice(-200),
      threads: Object.fromEntries([...this.threads].map(([owner, list]) => [owner, list.slice(-100)])),
    };
  }

  // ---- Changes -------------------------------------------------------------------------------------------------

  private commit(next: Scene, change: Omit<Change, "v" | "patch" | "undo" | "notes" | "at"> & { notes?: string[] }): Change | null {
    const patch = diff(this.scene, next);
    if (isEmpty(patch)) return null;
    const record: Change = { ...change, v: ++this.version, patch, undo: inverse(this.scene, patch), notes: change.notes ?? describePatch(this.scene, patch), at: Date.now() };
    this.scene = next;
    this.changes.push(record);
    if (this.changes.length > 500) this.changes.shift();
    const { undo: _undo, ...event } = record;
    this.onEvent({ type: "change", payload: event });
    this.onDirty();
    return record;
  }

  private pushUndo(member: string, v: number, clearRedo = true) {
    const stack = this.undoStacks.get(member) ?? [];
    stack.push(v);
    if (stack.length > 200) stack.shift();
    this.undoStacks.set(member, stack);
    if (clearRedo) this.redoStacks.delete(member);
  }

  /// A person's own edit, as the objects it touched. Objects listed in [created] are new: one whose id someone else
  /// took meanwhile gets the next free id, which the answer reports. An object someone else removed stays removed.
  edit(memberId: string, raw: { objects?: Record<string, unknown>; scene?: Record<string, unknown> }, created: string[] = [], seq?: number): { ok: boolean; version: number; renamed: Record<string, string>; message?: string } {
    if (!this.members.has(memberId)) return { ok: false, version: this.version, renamed: {}, message: "Join the project first." };
    const objects: Record<string, SceneObject | null> = {};
    const renamed: Record<string, string> = {};
    const isNew = new Set(created);
    try {
      for (const [id, value] of Object.entries(raw?.objects ?? {}).slice(0, 500)) {
        const existing = byId(this.scene, id);
        if (value === null) {
          if (existing) objects[id] = null;
          continue;
        }
        const object = readObject({ ...(value as object), id });
        if (isNew.has(id)) {
          const fresh = existing ? freeId({ ...this.scene, objects: [...this.scene.objects, ...Object.values(objects).filter((o): o is SceneObject => !!o)] }, object.type) : id;
          if (fresh !== id) renamed[id] = fresh;
          objects[fresh] = { ...object, id: fresh, by: memberId };
        } else if (existing) {
          // Who made an object never changes.
          const { by: _by, ...rest } = object;
          objects[id] = existing.by ? { ...rest, by: existing.by } : rest;
        }
      }
    } catch (e) {
      return { ok: false, version: this.version, renamed: {}, message: (e as Error).message };
    }
    const scene = raw?.scene ?? {};
    const patch: Patch = { objects, scene: { name: scene.name as string | undefined, theme: scene.theme as string | undefined, score: scene.score as boolean | undefined } };
    const change = this.commit(applyPatch(this.scene, patch), { by: memberId, kind: "edit", seq });
    if (change) {
      this.pushUndo(memberId, change.v);
      this.emitHistory();
    }
    return { ok: true, version: this.version, renamed };
  }

  /// Reverts one change: each object it touched goes back to how it was before.
  revert(memberId: string, v: number): { ok: boolean; message?: string; version: number } {
    const change = this.changes.find((c) => c.v === v);
    if (!this.members.has(memberId) || !change) return { ok: false, message: "That change is no longer in the history, so it cannot be undone.", version: this.version };
    if (change.undone) return { ok: false, message: "That change is already undone.", version: this.version };
    const undo: Patch = { objects: { ...change.undo.objects }, scene: change.undo.scene };
    // An object the change removed whose id has been reused since comes back under a new id.
    for (const [id, was] of Object.entries(undo.objects)) {
      if (was && change.patch.objects[id] === null && byId(this.scene, id)) {
        delete undo.objects[id];
        const fresh = freeId(this.scene, was.type);
        undo.objects[fresh] = { ...was, id: fresh };
      }
    }
    const notes = [`↶ Undid ${change.kind === "undo" ? "an undo" : (change.notes[0] ?? "a change")}${change.notes.length > 1 ? ` and ${change.notes.length - 1} more` : ""}`];
    const record = this.commit(applyPatch(this.scene, undo), { by: memberId, kind: "undo", of: v, notes });
    change.undone = true;
    this.markUndone(change, memberId);
    this.emitHistory();
    return { ok: true, version: record?.v ?? this.version };
  }

  undo(memberId: string): { ok: boolean; version: number } {
    const stack = this.undoStacks.get(memberId) ?? [];
    while (stack.length) {
      const v = stack.pop()!;
      const change = this.changes.find((c) => c.v === v);
      if (!change || change.undone) continue;
      this.revert(memberId, v);
      const redo = this.redoStacks.get(memberId) ?? [];
      redo.push(this.version);
      this.redoStacks.set(memberId, redo);
      this.emitHistory();
      return { ok: true, version: this.version };
    }
    return { ok: false, version: this.version };
  }

  redo(memberId: string): { ok: boolean; version: number } {
    const stack = this.redoStacks.get(memberId) ?? [];
    while (stack.length) {
      const v = stack.pop()!;
      const change = this.changes.find((c) => c.v === v);
      if (!change || change.undone) continue;
      this.revert(memberId, v);
      this.pushUndo(memberId, this.version, false);
      this.emitHistory();
      return { ok: true, version: this.version };
    }
    return { ok: false, version: this.version };
  }

  /// Whether [member] has something to undo or redo.
  history(member: string): { member: string; canUndo: boolean; canRedo: boolean } {
    const live = (stack?: number[]) => (stack ?? []).some((v) => this.changes.some((c) => c.v === v && !c.undone));
    return { member, canUndo: live(this.undoStacks.get(member)), canRedo: live(this.redoStacks.get(member)) };
  }

  private emitHistory() {
    for (const id of this.members.keys()) this.onEvent({ type: "history", payload: this.history(id) });
  }

  // ---- Chat and agents -----------------------------------------------------------------------------------------

  private postTeam(message: Omit<TeamMessage, "id" | "at">): TeamMessage {
    const m: TeamMessage = { ...message, id: newId(), at: Date.now() };
    this.team.push(m);
    if (this.team.length > 500) this.team.shift();
    this.onEvent({ type: "team", payload: m });
    this.onDirty();
    return m;
  }

  private postThread(message: Omit<ThreadMessage, "id" | "at">): ThreadMessage {
    const m: ThreadMessage = { ...message, id: newId(), at: Date.now() };
    const list = this.threads.get(message.owner) ?? [];
    list.push(m);
    if (list.length > 300) list.shift();
    this.threads.set(message.owner, list);
    this.onEvent({ type: "thread", payload: m });
    this.onDirty();
    return m;
  }

  /// Updates the agent's answers to [task] in the team chat and the thread.
  private resolve(task: string, update: Partial<TeamMessage & ThreadMessage>) {
    for (const m of this.team) {
      if (m.task === task && m.kind === "agent") {
        Object.assign(m, update);
        this.onEvent({ type: "team", payload: m });
      }
    }
    for (const list of this.threads.values()) {
      for (const m of list) {
        if (m.task === task && m.from === "agent") {
          Object.assign(m, update);
          this.onEvent({ type: "thread", payload: m });
        }
      }
    }
    this.onDirty();
  }

  private markUndone(change: Change, by: string) {
    const task = [...this.team, ...[...this.threads.values()].flat()].find((m) => m.change === change.v)?.task;
    if (task) this.resolve(task, { outcome: "undone", undoneBy: by });
  }

  /// A message to the whole team. Every agent it mentions (in [agents], or written as "@Name's agent") gets the
  /// message as a request.
  say(memberId: string, rawText: string, agents: string[] = []): TeamMessage | null {
    const text = rawText.trim().slice(0, 1000);
    if (!this.members.has(memberId) || !text) return null;
    const mentioned = new Set(agents.filter((a) => this.members.has(a)));
    for (const m of this.members.values()) {
      if (text.toLowerCase().includes(`@${m.name.toLowerCase()}'s agent`)) mentioned.add(m.id);
    }
    const message = this.postTeam({ kind: "chat", from: memberId, text, agents: [...mentioned] });
    for (const owner of mentioned) {
      const request = text.replace(new RegExp(`@${escape(this.members.get(owner)!.name)}'s agent[,:]?\\s*`, "gi"), "").trim() || text;
      this.ask(memberId, owner, request, true);
    }
    return message;
  }

  /// Gives [owner]'s agent a request from [memberId]. It runs after the agent's earlier requests.
  ask(memberId: string, owner: string, rawText: string, viaTeam = false): boolean {
    const text = rawText.trim().slice(0, 1000);
    const agent = this.members.get(owner);
    if (!this.members.has(memberId) || !agent || !text) return false;
    const task: Task = { id: newId(), owner, by: memberId, text, viaTeam };
    this.postThread({ owner, from: "member", by: memberId, viaTeam, text, task: task.id });
    if (!this.assistant) {
      this.postThread({ owner, from: "system", text: "No AI is configured on the server. Sign in to the Claude Code CLI or set ANTHROPIC_API_KEY.", task: task.id });
      return false;
    }
    const queue = this.queues.get(owner) ?? [];
    queue.push(task);
    this.queues.set(owner, queue);
    if (agent.agent.status === "idle") void this.runNext(owner);
    else {
      agent.agent.queued = queue.length;
      this.emitMembers();
    }
    return true;
  }

  /// Settles once every agent is idle (tests).
  async idle(): Promise<void> {
    while ([...this.members.values()].some((m) => m.agent.status !== "idle")) await new Promise((r) => setTimeout(r, 1));
  }

  private async runNext(owner: string): Promise<void> {
    const member = this.members.get(owner)!;
    const queue = this.queues.get(owner) ?? [];
    const task = queue.shift();
    if (!task) {
      member.agent = { status: "idle", queued: 0 };
      this.emitMembers();
      return;
    }
    member.agent = { status: "thinking", task: task.text.slice(0, 80), for: task.by, queued: queue.length };
    this.emitMembers();
    try {
      await this.perform(task);
    } catch (e) {
      const text = `I could not do that: ${(e as Error).message}`;
      this.postThread({ owner, from: "agent", text, task: task.id, outcome: "failed" });
      if (task.viaTeam) this.postTeam({ kind: "agent", from: owner, for: task.by, text, task: task.id, outcome: "failed" });
    }
    await this.runNext(owner);
  }

  private async perform(task: Task): Promise<void> {
    const assistant = this.assistant!;
    const context = this.contextFor(task);
    let reply: SceneReply = await assistant(this.scene, task.text, context);
    let applied = applyActions(this.scene, reply.actions, `agent:${task.owner}`);
    let broken = newErrors(this.scene, applied.scene);
    // One more try, told what the first answer would have broken.
    if (broken.length && reply.actions.length) {
      const retry = await assistant(this.scene, `${task.text}\n\nYour previous actions would have broken the game: ${broken[0]!.message} Return actions that keep it playable, or none and say why.`, context);
      const again = applyActions(this.scene, retry.actions, `agent:${task.owner}`);
      const stillBroken = newErrors(this.scene, again.scene);
      if (retry.actions.length) {
        reply = retry;
        applied = again;
        broken = stillBroken;
      }
    }
    const answer = { from: "agent" as const, text: reply.message, task: task.id, notes: applied.notes };
    const team = { kind: "agent" as const, from: task.owner, for: task.by, text: reply.message, task: task.id, notes: applied.notes };
    // Actions that change nothing (the theme it already has) leave no lines that suggest otherwise.
    if (!reply.actions.length || isEmpty(diff(this.scene, applied.scene))) {
      this.postThread({ owner: task.owner, ...answer, notes: [] });
      if (task.viaTeam) this.postTeam({ ...team, notes: [] });
      return;
    }
    if (broken.length) {
      this.held.set(task.id, { task, actions: reply.actions });
      this.postThread({ owner: task.owner, ...answer, outcome: "held", reason: broken[0]!.message });
      this.postTeam({ ...team, outcome: "held", reason: broken[0]!.message });
      return;
    }
    const change = this.commit(applied.scene, { by: task.by, agentOf: task.owner, kind: "agent", notes: applied.notes });
    if (change) this.pushUndo(task.by, change.v);
    this.emitHistory();
    this.postThread({ owner: task.owner, ...answer, outcome: "applied", change: change?.v });
    this.postTeam({ ...team, outcome: "applied", change: change?.v });
  }

  /// Applies held actions anyway, to the scene as it is now. The agent's owner or whoever asked may decide.
  approve(memberId: string, task: string): { ok: boolean; message?: string } {
    const held = this.held.get(task);
    if (!held || (memberId !== held.task.owner && memberId !== held.task.by)) return { ok: false, message: "Nothing is waiting for you there." };
    this.held.delete(task);
    const applied = applyActions(this.scene, held.actions, `agent:${held.task.owner}`);
    const change = this.commit(applied.scene, { by: memberId, agentOf: held.task.owner, kind: "agent", notes: applied.notes });
    if (change) this.pushUndo(memberId, change.v);
    this.emitHistory();
    this.resolve(task, { outcome: "approved", change: change?.v, notes: applied.notes });
    return { ok: true };
  }

  discard(memberId: string, task: string): { ok: boolean; message?: string } {
    const held = this.held.get(task);
    if (!held || (memberId !== held.task.owner && memberId !== held.task.by)) return { ok: false, message: "Nothing is waiting for you there." };
    this.held.delete(task);
    this.resolve(task, { outcome: "discarded" });
    return { ok: true };
  }

  /// What a shared project tells an agent besides the scene: who asks, the team, others' recent work.
  contextFor(task: Task): string {
    const owner = this.members.get(task.owner)!;
    const roster = [...this.members.values()].map((m) => `${m.id} = ${m.name}${m.id === task.owner ? " (your owner)" : ""}`).join(", ");
    const lines = [
      `You are ${owner.name}'s agent in a shared project. Members: ${roster}.`,
      task.by === task.owner ? `${owner.name} asks you directly.` : `${this.nameOf(task.by)}, a teammate, asks you from the team chat; ${owner.name} sees what you do and can undo it.`,
    ];
    const others = this.changes.filter((c) => !c.undone && c.kind !== "undo" && c.agentOf !== task.owner && !(c.by === task.owner && !c.agentOf)).slice(-8);
    if (others.length) lines.push("Recent changes by others:", ...others.map((c) => `- ${c.agentOf ? `${this.nameOf(c.agentOf)}'s agent for ${this.nameOf(c.by)}` : this.nameOf(c.by)}: ${c.notes.slice(0, 4).join("; ")}${c.notes.length > 4 ? "; …" : ""}`));
    const playtests = this.playtestLines();
    if (playtests.length) lines.push("Recent playtests:", ...playtests);
    const chat = this.team.filter((m) => m.kind === "chat").slice(-8);
    if (chat.length) lines.push("Team chat, latest last:", ...chat.map((m) => `- ${this.nameOf(m.from)}: ${m.text.slice(0, 300)}`));
    const thread = (this.threads.get(task.owner) ?? []).filter((m) => m.task !== task.id && m.from !== "system").slice(-6);
    if (thread.length) lines.push("Your conversation, latest last:", ...thread.map((m) => `- ${m.from === "agent" ? "you" : this.nameOf(m.by ?? task.owner)}: ${m.text.slice(0, 300)}`));
    return lines.join("\n");
  }

  private emitMembers() {
    this.onEvent({ type: "members", payload: [...this.members.values()] });
  }

  // ---- Playtests ------------------------------------------------------------------------------------------------

  /// The scene as it was at [version], rebuilt from the history; null when that is older than the history.
  sceneAt(version: number): Scene | null {
    if (version === this.version) return this.scene;
    if (!Number.isInteger(version) || version < 0 || version > this.version) return null;
    const oldest = this.changes[0]?.v ?? this.version + 1;
    if (version < oldest - 1) return null;
    let s = this.scene;
    for (let i = this.changes.length - 1; i >= 0 && this.changes[i]!.v > version; i--) s = applyPatch(s, this.changes[i]!.undo);
    return s;
  }

  /// A person shares a run they played on [version]. The project replays it there, so the result is the real one.
  shareRun(memberId: string, version: number, rawRun: unknown, rawNote?: unknown): { ok: boolean; message?: string; result?: RunResult } {
    if (!this.members.has(memberId)) return { ok: false, message: "Join the project first." };
    const scene = this.sceneAt(version);
    if (!scene) return { ok: false, message: "That version is no longer in the history." };
    let run: Segment[];
    try {
      run = readRun(rawRun);
    } catch (e) {
      return { ok: false, message: (e as Error).message };
    }
    if (!scene.objects.some((o) => o.type === "player")) return { ok: false, message: "That scene has no player." };
    const result = replay(scene, run).result();
    const note = typeof rawNote === "string" && rawNote.trim() ? rawNote.trim().slice(0, 500) : undefined;
    this.postTeam({ kind: "playtest", from: memberId, text: note ?? "", playtest: { status: "done", version, result, run, note } });
    return { ok: true, result };
  }

  /// The AI plays the scene as it is now, then reviews what it found. One AI playtest at a time.
  playtestAi(memberId: string): { ok: boolean; message?: string } {
    if (!this.members.has(memberId)) return { ok: false, message: "Join the project first." };
    if (this.aiPlaying) return { ok: false, message: "The AI is already playing." };
    if (!this.scene.objects.some((o) => o.type === "player") || !this.scene.objects.some((o) => o.type === "finish")) return { ok: false, message: "The AI needs a player and a finish to play." };
    this.aiPlaying = true;
    const scene = this.scene;
    const version = this.version;
    const message = this.postTeam({ kind: "playtest", from: "ai", for: memberId, text: "", playtest: { status: "playing", version } });
    const update = (playtest: Playtest, text = "") => {
      Object.assign(message, { text, playtest });
      this.onEvent({ type: "team", payload: message });
      this.onDirty();
    };
    void (async () => {
      try {
        const facts = await aiPlaytest(scene);
        const base: Playtest = { status: "done", version, result: facts.result, run: facts.run, finished: facts.finished, coinsMissed: facts.coinsMissed };
        let review = { summary: "", issues: [] as { text: string; objects: string[]; kind: "problem" | "idea" }[] };
        if (this.reviewer) {
          try {
            review = await this.reviewer(scene, facts, this.chatContext());
          } catch (e) {
            review.summary = `The review did not come: ${(e as Error).message}`;
          }
        }
        const owners = (ids: string[]) => [...new Set(ids.flatMap((id) => (byId(scene, id)?.by ? [byId(scene, id)!.by!.replace(/^agent:/, "")] : [])))].filter((m) => this.members.has(m));
        update({ ...base, summary: review.summary, issues: review.issues.map((i) => ({ ...i, owners: owners(i.objects) })) }, review.summary);
      } catch (e) {
        update({ status: "failed", version }, `The AI could not play: ${(e as Error).message}`);
      } finally {
        this.aiPlaying = false;
      }
    })();
    return { ok: true };
  }

  /// Settles once the AI has stopped playing (tests).
  async playtestsIdle(): Promise<void> {
    while (this.aiPlaying) await new Promise((r) => setTimeout(r, 2));
  }

  private chatContext(): string {
    const chat = this.team.filter((m) => m.kind === "chat").slice(-6);
    return chat.length ? ["Team chat, latest last:", ...chat.map((m) => `- ${this.nameOf(m.from)}: ${m.text.slice(0, 300)}`)].join("\n") : "";
  }

  /// One line per recent playtest, for the agents.
  private playtestLines(): string[] {
    return this.team
      .filter((m) => m.kind === "playtest" && m.playtest?.status === "done")
      .slice(-3)
      .map((m) => {
        const p = m.playtest!;
        const r = p.result!;
        const who = m.from === "ai" ? "The AI player" : this.nameOf(m.from);
        const outcome = r.won ? `finished in ${r.time.toFixed(1)} s` : "did not finish";
        const extra = [p.coinsMissed?.length ? `could not reach ${p.coinsMissed.join(", ")}` : "", r.deaths ? `${r.deaths} deaths` : "", p.note ? `said "${p.note}"` : "", ...(p.issues ?? []).map((i) => `${i.kind}: ${i.text}`)].filter(Boolean);
        return `- ${who} (v${p.version}): ${outcome}, ${r.score} points${extra.length ? `; ${extra.join("; ")}` : ""}`;
      });
  }

  // ---- Saving --------------------------------------------------------------------------------------------------

  toJSON() {
    return {
      id: this.id,
      version: this.version,
      scene: this.scene,
      members: [...this.members.values()].map(({ id, name, color }) => ({ id, name, color })),
      team: this.team,
      threads: Object.fromEntries(this.threads),
      // The recent history, so undo and the Undo on a report still work after a restart.
      changes: this.changes.slice(-200),
      undo: Object.fromEntries(this.undoStacks),
      redo: Object.fromEntries(this.redoStacks),
    };
  }

  static fromJSON(data: Omit<ReturnType<StudioProject["toJSON"]>, "changes" | "undo" | "redo"> & Partial<Pick<ReturnType<StudioProject["toJSON"]>, "changes" | "undo" | "redo">>, assistant?: SceneAssistant, reviewer?: PlaytestReviewer): StudioProject {
    const p = new StudioProject(data.id, data.scene, assistant, reviewer);
    p.version = data.version;
    for (const m of data.members) {
      p.members.set(m.id, { ...m, online: false, agent: { status: "idle", queued: 0 } });
      p.nextMember = Math.max(p.nextMember, Number(m.id.slice(1)) + 1);
    }
    p.team.push(...data.team);
    for (const [owner, list] of Object.entries(data.threads)) {
      // Held requests do not survive a restart.
      p.threads.set(owner, list.map((m) => (m.outcome === "held" ? { ...m, outcome: "discarded" as const } : m)));
    }
    for (const m of p.team) {
      if (m.outcome === "held") m.outcome = "discarded";
      // An AI playtest cut short by a restart.
      if (m.playtest?.status === "playing") Object.assign(m, { text: "The AI was stopped by a server restart.", playtest: { ...m.playtest, status: "failed" } });
    }
    p.changes.push(...(data.changes ?? []));
    for (const [member, stack] of Object.entries(data.undo ?? {})) p.undoStacks.set(member, stack);
    for (const [member, stack] of Object.entries(data.redo ?? {})) p.redoStacks.set(member, stack);
    return p;
  }
}

const escape = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
