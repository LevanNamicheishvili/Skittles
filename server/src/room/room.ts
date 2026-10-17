// The room is the single writer for one level. Every command below is synchronous, so it runs to
// completion on the event loop before the next one starts: the event loop is the room's mailbox and
// two agents can never write at the same moment. Slow work (the LLM) happens outside and comes back
// as a command.

import { PlayEngine, snapshot, type PlaySnapshot, type PlayState } from "../game/play.ts";
import { cellIndex, rasterize, Terrain } from "../game/raster.ts";
import { solve, type SolveResult } from "../game/solver.ts";
import { COLORS, DELTA, type Cell, type Direction, type Entity, type World } from "../game/types.ts";
import { describeDiagnosis, diagnose, proposeFixes, type Diagnosis, type FixOption } from "./mediator.ts";
import { applyOps, describeOps, type ApplyResult, type Op } from "./ops.ts";
import { suspectsNear, type Fall, type PlaytestReport, type Suggestion } from "./playtest.ts";

export type Role = "author" | "player" | "stage";

export type Member = { id: string; name: string; role: Role; letter: string; color: string };

// What a log entry holds besides its position; a deferred change waits in this form.
export type Draft = {
  by: string;
  summary: string;
  ops: Op[];
  fix?: { summary: string; ops: Op[]; approvedBy: string[] };
  revertTo?: number;
};

export type LogEntry = Draft & { rev: number; at: number };

export type ChatMessage = {
  id: string;
  authorId: string;
  from: "you" | "agent" | "system" | "mediator" | "playtest";
  text: string;
  at: number;
  proposalId?: string;
  reportId?: string;
  suggestionId?: string;
};

type ChatRefs = Pick<ChatMessage, "proposalId" | "reportId" | "suggestionId">;

export type Proposal = {
  id: string;
  requesterId: string;
  summary: string;
  ops: Op[];
  diagnosis: Diagnosis;
  text: string;
  options: FixOption[];
  status: "open" | "awaiting_approval" | "done";
  // Authors whose agents are working on a compromise right now.
  negotiating: string[];
  chosen?: string;
  // Owner id -> answer, null while waiting.
  approvals: Record<string, boolean | null>;
};

export type SubmitResult =
  | { status: "committed"; rev: number }
  | { status: "deferred" }
  | { status: "awaiting_approval"; proposal: Proposal }
  | { status: "conflict"; proposal: Proposal }
  | { status: "rejected"; code: string; message: string };

export type SolveSummary = { solvable: boolean; steps?: number; path?: Direction[]; unreachable: string[] };

// solveMs: how long the validator took on this version, shown in the nerd console.
export type StatePayload = { world: World; rev: number; solve: SolveSummary; deferred: number; solveMs: number };

// The player as everyone sees them: the play state plus, for dev mode, the path walked and the falls on this version.
export type PlayPayload = PlaySnapshot & { trail: Cell[]; falls: Fall[] };

export type RoomEvent =
  | { type: "state"; payload: StatePayload }
  | { type: "log"; payload: LogEntry }
  | { type: "chat"; payload: ChatMessage }
  | { type: "proposal"; payload: Proposal }
  | { type: "play"; payload: PlayPayload }
  | { type: "members"; payload: Member[] }
  | { type: "reset"; payload: { rev: number } }
  | { type: "report"; payload: PlaytestReport }
  | { type: "suggestion"; payload: Suggestion };

const AUTHOR_COLORS = ["#3b82f6", "#f97316", "#10b981", "#e11d48"];

const rejected = (code: string, message: string): SubmitResult => ({ status: "rejected", code, message });

export function applyDraft(world: World, draft: Draft): ApplyResult {
  return applyOps(world, [...draft.ops, ...(draft.fix?.ops ?? [])]);
}

export class Room {
  readonly base: World;
  world: World;
  rev = 0;
  log: LogEntry[] = [];
  solveResult: SolveResult;
  readonly members = new Map<string, Member>();
  chats = new Map<string, ChatMessage[]>();
  proposals = new Map<string, Proposal>();
  reports = new Map<string, PlaytestReport>();
  suggestions = new Map<string, Suggestion>();
  onEvent: (e: RoomEvent) => void = () => {};

  private snapshots: World[];
  private deferred: Draft[] = [];
  private engine: PlayEngine;
  private play: PlayState;
  private counters = new Map<string, number>();
  private seq = 0;
  private solveMs = 0;
  // Playtest dev mode: the cells walked since the last respawn, every fall, and spots already reported.
  private trail: Cell[] = [];
  private falls: Fall[] = [];
  private signaled = new Set<string>();

  constructor(base: World) {
    this.base = structuredClone(base);
    this.world = structuredClone(base);
    this.snapshots = [structuredClone(base)];
    this.solveResult = solve(this.world);
    this.engine = new PlayEngine(this.world);
    this.play = this.engine.initialState();
  }

  // Rebuilds a world from the base and the log alone. The log is the source of truth.
  static replay(base: World, log: readonly Draft[]): World {
    let world = structuredClone(base);
    for (const entry of log) {
      const applied = applyDraft(world, entry);
      if (!applied.ok) throw new Error(`log does not replay: ${applied.message}`);
      world = applied.world;
    }
    return world;
  }

  nameOf = (memberId: string | undefined): string =>
    memberId === undefined ? "the base level" : (this.members.get(memberId)?.name ?? "someone");

  join(name: string, role: Role): Member {
    const clean = name.trim().slice(0, 24) || (role === "author" ? "Author" : role === "player" ? "Player" : "Stage");
    const existing = [...this.members.values()].find((m) => m.role === role && m.name.toLowerCase() === clean.toLowerCase());
    if (existing) return existing;
    const authors = [...this.members.values()].filter((m) => m.role === "author").length;
    const member: Member = {
      id: `${role}-${++this.seq}`,
      name: clean,
      role,
      letter: role === "author" ? String.fromCharCode(65 + authors) : role === "player" ? "P" : "V",
      color: role === "author" ? AUTHOR_COLORS[authors % AUTHOR_COLORS.length]! : "#64748b",
    };
    this.members.set(member.id, member);
    if (role === "author") this.chats.set(member.id, []);
    this.emit({ type: "members", payload: [...this.members.values()] });
    return member;
  }

  snapshotFor(memberId: string) {
    return {
      you: this.members.get(memberId),
      members: [...this.members.values()],
      state: this.statePayload(),
      log: this.log,
      chats: Object.fromEntries(this.chats),
      proposals: [...this.proposals.values()].filter((p) => p.status !== "done"),
      reports: [...this.reports.values()],
      suggestions: [...this.suggestions.values()],
      play: this.playState(),
    };
  }

  // An author's batch, usually written by their agent. It is checked against the current version
  // even if the agent started from an older one, so a stale batch is re-validated, never merged blindly.
  submit(memberId: string, ops: Op[], summary?: string): SubmitResult {
    const member = this.members.get(memberId);
    if (!member || member.role !== "author") return rejected("not_author", "Only authors can change the level.");
    if (ops.length === 0) return rejected("empty", "There is nothing to change.");
    const owned = this.claim(ops, member.letter, { kind: "assistant", playerId: member.id });
    const applied = applyOps(this.world, owned);
    if (!applied.ok) return rejected(applied.code, applied.message);
    const text = summary?.trim() || describeOps(owned);
    if (this.solveResult.solvable && !solve(applied.world).solvable) {
      return { status: "conflict", proposal: this.openProposal(member, owned, text, applied.world) };
    }
    return this.commit({ by: member.id, summary: text, ops: owned });
  }

  choose(memberId: string, proposalId: string, optionId: string): SubmitResult {
    const p = this.proposals.get(proposalId);
    if (!p || p.status !== "open") return rejected("closed", "This proposal is closed.");
    if (p.requesterId !== memberId) return rejected("not_yours", "Only the author of the change picks the fix.");
    const option = p.options.find((o) => o.id === optionId);
    if (!option) return rejected("no_option", `There is no option ${optionId}.`);
    p.chosen = option.id;
    if (option.kind === "cancel") {
      p.status = "done";
      this.emit({ type: "proposal", payload: p });
      this.say(memberId, "system", "Change cancelled. The level stays as it was.");
      return rejected("cancelled", "The author cancelled the change.");
    }
    if (option.touches.length > 0) {
      p.status = "awaiting_approval";
      p.approvals = Object.fromEntries(option.touches.map((id) => [id, null]));
      this.emit({ type: "proposal", payload: p });
      const requester = this.nameOf(memberId);
      for (const owner of option.touches) {
        this.say(owner, "mediator", `${requester} wants to ${option.title.toLowerCase()}. ${option.detail} It touches your object. Approve?`, { proposalId: p.id });
      }
      this.say(memberId, "system", `Waiting for ${option.touches.map(this.nameOf).join(" and ")} to approve.`, { proposalId: p.id });
      return { status: "awaiting_approval", proposal: p };
    }
    return this.finish(p, option, []);
  }

  answer(memberId: string, proposalId: string, accept: boolean): SubmitResult {
    const p = this.proposals.get(proposalId);
    if (!p || p.status !== "awaiting_approval" || !(memberId in p.approvals)) return rejected("closed", "Nothing to approve.");
    const option = p.options.find((o) => o.id === p.chosen)!;
    if (!accept) {
      // The fix is off the table; the author picks again from what is left.
      p.status = "open";
      p.options = p.options.filter((o) => o.id !== option.id);
      p.approvals = {};
      delete p.chosen;
      this.emit({ type: "proposal", payload: p });
      this.say(p.requesterId, "mediator", `${this.nameOf(memberId)} declined "${option.title}". Pick another fix.`, { proposalId: p.id });
      return rejected("declined", "The owner declined the fix.");
    }
    p.approvals[memberId] = true;
    if (Object.values(p.approvals).every((v) => v === true)) return this.finish(p, option, Object.keys(p.approvals));
    this.emit({ type: "proposal", payload: p });
    return { status: "awaiting_approval", proposal: p };
  }

  revert(memberId: string, toRev: number): SubmitResult {
    const member = this.members.get(memberId);
    if (!member || member.role !== "author") return rejected("not_author", "Only authors can restore versions.");
    const target = this.snapshots[toRev];
    if (!target) return rejected("unknown_rev", `There is no version ${toRev}.`);
    if (toRev === this.rev) return rejected("same_rev", "That is already the current version.");
    return this.commit({
      by: member.id,
      summary: `Restored version ${toRev}`,
      ops: [{ op: "replace_world", world: structuredClone(target) }],
      revertTo: toRev,
    });
  }

  move(dir: Direction): void {
    const target = { x: this.play.x + DELTA[dir].x, y: this.play.y + DELTA[dir].y };
    const deaths = this.play.deaths;
    this.play = this.engine.step(this.play, dir);
    if (this.play.deaths > deaths) {
      this.falls.push({ ...target, rev: this.rev, at: Date.now() });
      this.trail = [];
    } else if (this.trail.at(-1)?.x !== this.play.x || this.trail.at(-1)?.y !== this.play.y) {
      this.trail = [...this.trail, { x: this.play.x, y: this.play.y }].slice(-24);
    }
    this.emit({ type: "play", payload: this.playState() });
    this.flushDeferred();
    if (this.play.deaths > deaths) this.watchFalls(target);
  }

  restartPlay(): void {
    this.trail = [];
    this.play = this.engine.initialState();
    this.emit({ type: "play", payload: this.playState() });
    this.flushDeferred();
  }

  // Back to the prepared level for the next rehearsal. Members stay; everything they made goes.
  reset(): void {
    this.world = structuredClone(this.base);
    this.rev = 0;
    this.log = [];
    this.snapshots = [structuredClone(this.base)];
    this.solveResult = solve(this.world);
    this.proposals = new Map();
    this.reports = new Map();
    this.suggestions = new Map();
    this.trail = [];
    this.falls = [];
    this.signaled = new Set();
    this.chats = new Map([...this.chats.keys()].map((id) => [id, []]));
    this.deferred = [];
    this.counters = new Map();
    this.engine = new PlayEngine(this.world);
    this.play = this.engine.initialState();
    this.emit({ type: "reset", payload: { rev: 0 } });
  }

  say(authorId: string, from: ChatMessage["from"], text: string, refs: ChatRefs = {}): void {
    const list = this.chats.get(authorId);
    if (!list) return;
    const msg: ChatMessage = { id: `C${++this.seq}`, authorId, from, text, at: Date.now(), ...refs };
    list.push(msg);
    this.emit({ type: "chat", payload: msg });
  }

  // A playtester's report. It carries the game's own context and goes to the authors whose objects
  // sit at the trouble spot, or to every author when the spot belongs to the base level.
  report(memberId: string, text: string, kind: PlaytestReport["kind"] = "player"): PlaytestReport | undefined {
    const member = this.members.get(memberId);
    if (!member) return undefined;
    const now = Date.now();
    const recent = this.falls.filter((f) => f.rev === this.rev && now - f.at < 60_000).at(-1);
    const spot = recent ? { x: recent.x, y: recent.y } : { x: this.play.x, y: this.play.y };
    const suspects = suspectsNear(this.world, spot);
    const authors = [...this.members.values()].filter((m) => m.role === "author").map((m) => m.id);
    // The report goes to whoever owns the closest object at the spot, not to everyone nearby.
    const owned = suspects.filter((s) => s.ownerId && authors.includes(s.ownerId));
    const nearest = Math.min(...owned.map((s) => s.distance));
    const owners = [...new Set(owned.filter((s) => s.distance === nearest).map((s) => s.ownerId!))];
    const report: PlaytestReport = {
      id: `R${++this.seq}`,
      by: memberId,
      kind,
      text: text.trim().slice(0, 300) || "Something is wrong here.",
      at: now,
      rev: this.rev,
      spot,
      position: { x: this.play.x, y: this.play.y },
      keys: [...this.play.keys].sort(),
      fallsHere: this.falls.filter((f) => f.rev === this.rev && f.x === spot.x && f.y === spot.y).length,
      falls: this.play.deaths,
      trail: this.trail.slice(-12),
      suspects,
      routedTo: owners.length > 0 ? owners : authors,
    };
    this.reports.set(report.id, report);
    this.emit({ type: "report", payload: report });
    for (const id of report.routedTo) {
      this.say(id, "playtest", kind === "player" ? `${member.name}: "${report.text}"` : report.text, { reportId: report.id });
    }
    return report;
  }

  // Dry run: would these ops apply, and would the level stay winnable? Nothing changes.
  preview(ops: Op[]): { ok: true; breaks: boolean } | { ok: false; message: string } {
    const applied = applyOps(this.world, ops);
    if (!applied.ok) return { ok: false, message: applied.message };
    return { ok: true, breaks: this.solveResult.solvable && !solve(applied.world).solvable };
  }

  startSuggestion(authorId: string, reportId: string): Suggestion {
    const s: Suggestion = { id: `G${++this.seq}`, authorId, reportId, status: "drafting" };
    this.suggestions.set(s.id, s);
    this.emit({ type: "suggestion", payload: s });
    return s;
  }

  completeSuggestion(id: string, message: string, summary: string, ops: Op[]): void {
    const s = this.suggestions.get(id);
    if (!s || s.status !== "drafting") return;
    Object.assign(s, { status: "open", message, summary, ops });
    this.emit({ type: "suggestion", payload: s });
    this.say(s.authorId, "agent", message, { suggestionId: s.id });
  }

  failSuggestion(id: string, note: string): void {
    const s = this.suggestions.get(id);
    if (!s || s.status !== "drafting") return;
    Object.assign(s, { status: "failed", note });
    this.emit({ type: "suggestion", payload: s });
    this.say(s.authorId, "agent", note, { suggestionId: s.id });
  }

  // The author decides; the fix then goes through submit like any other change.
  applySuggestion(memberId: string, id: string): SubmitResult {
    const s = this.suggestions.get(id);
    if (!s || s.status !== "open" || !s.ops) return rejected("closed", "This suggestion is closed.");
    if (s.authorId !== memberId) return rejected("not_yours", "Only the author it was made for can apply it.");
    const result = this.submit(memberId, s.ops, s.summary);
    if (result.status === "rejected") Object.assign(s, { status: "failed", note: result.message });
    else s.status = "applied";
    this.emit({ type: "suggestion", payload: s });
    return result;
  }

  dismissSuggestion(memberId: string, id: string): void {
    const s = this.suggestions.get(id);
    if (!s || s.authorId !== memberId || s.status !== "open") return;
    s.status = "dismissed";
    this.emit({ type: "suggestion", payload: s });
  }

  // The other side's agent works on a compromise; the humans see it is coming.
  startNegotiation(proposalId: string, ownerId: string): boolean {
    const p = this.proposals.get(proposalId);
    if (!p || p.status !== "open" || p.negotiating.includes(ownerId)) return false;
    p.negotiating = [...p.negotiating, ownerId];
    this.emit({ type: "proposal", payload: p });
    return true;
  }

  // A compromise from another author's agent joins the options, checked like every other option.
  addAgentOption(proposalId: string, ownerId: string, title: string, detail: string, ops: Op[]): boolean {
    const p = this.proposals.get(proposalId);
    if (!p) return false;
    p.negotiating = p.negotiating.filter((id) => id !== ownerId);
    const check = p.status === "open" ? this.preview([...p.ops, ...ops]) : undefined;
    if (!check || !check.ok || check.breaks) {
      this.emit({ type: "proposal", payload: p });
      return false;
    }
    // Changing the owner's own objects needs the owner's yes; changing the requester's pending objects does not.
    const theirs = new Set(this.world.entities.filter((e) => e.owner.playerId === ownerId).map((e) => e.id));
    const touchesOwner = ops.some((op) => (op.op === "update" || op.op === "delete") && theirs.has(op.id));
    const option: FixOption = {
      id: `agent-${ownerId}`,
      kind: "agent",
      from: ownerId,
      title: `${this.nameOf(ownerId)}'s agent: ${title}`,
      detail,
      ops,
      touches: touchesOwner ? [ownerId] : [],
    };
    p.options = [...p.options.filter((o) => o.id !== option.id && o.kind !== "cancel"), option, ...p.options.filter((o) => o.kind === "cancel")];
    this.emit({ type: "proposal", payload: p });
    this.say(p.requesterId, "mediator", `${this.nameOf(ownerId)}'s agent proposes a compromise: ${detail}`, { proposalId: p.id });
    this.say(ownerId, "agent", `${this.nameOf(p.requesterId)}'s change would have broken your work. I proposed a compromise: ${detail}`);
    return true;
  }

  endNegotiation(proposalId: string, ownerId: string): void {
    const p = this.proposals.get(proposalId);
    if (!p || !p.negotiating.includes(ownerId)) return;
    p.negotiating = p.negotiating.filter((id) => id !== ownerId);
    this.emit({ type: "proposal", payload: p });
  }

  // Dev mode raises a report on its own when the player keeps falling at the same cell.
  private watchFalls(cell: Cell): void {
    const here = this.falls.filter((f) => f.rev === this.rev && f.x === cell.x && f.y === cell.y).length;
    const key = `${this.rev}:${cell.x},${cell.y}`;
    if (here < 2 || this.signaled.has(key)) return;
    this.signaled.add(key);
    const player = [...this.members.values()].find((m) => m.role === "player");
    if (player) this.report(player.id, `${player.name} fell into lava at (${cell.x}, ${cell.y}) ${here} times.`, "signal");
  }

  // Every version the log has produced, oldest first: what time travel scrubs through.
  history(): World[] {
    return structuredClone(this.snapshots);
  }

  statePayload(): StatePayload {
    const { solvable, steps, path, unreachable } = this.solveResult;
    return { world: this.world, rev: this.rev, solve: { solvable, steps, path, unreachable }, deferred: this.deferred.length, solveMs: Math.round(this.solveMs * 100) / 100 };
  }

  playState(): PlayPayload {
    return { ...snapshot(this.play), trail: this.trail, falls: this.falls.filter((f) => f.rev === this.rev) };
  }

  private emit(e: RoomEvent): void {
    this.onEvent(e);
  }

  private nextId(letter: string): string {
    const n = (this.counters.get(letter) ?? 0) + 1;
    this.counters.set(letter, n);
    return `${letter}${n}`;
  }

  // New objects get server ids in the author's letter. Ids the agent used as references are rewritten.
  private claim(ops: Op[], letter: string, owner: Entity["owner"]): Op[] {
    const out = structuredClone(ops);
    const renamed = new Map<string, string>();
    for (const op of out) {
      if (op.op !== "create") continue;
      const id = this.nextId(letter);
      if (op.entity.id) renamed.set(op.entity.id, id);
      op.entity.id = id;
      op.entity.owner = owner;
    }
    for (const op of out) {
      if ((op.op === "update" || op.op === "delete") && renamed.has(op.id)) op.id = renamed.get(op.id)!;
      if (op.op === "set_objectives") {
        op.objectives = op.objectives.map((o) => (o.type === "collect" && renamed.has(o.target) ? { ...o, target: renamed.get(o.target)! } : o));
      }
    }
    return out;
  }

  private openProposal(member: Member, ops: Op[], summary: string, after: World): Proposal {
    const diagnosis = diagnose(after, this.world);
    const touchedIds = ops.flatMap((op) => (op.op === "create" ? [op.entity.id] : op.op === "update" || op.op === "delete" ? [op.id] : []));
    const options = proposeFixes({ after, touchedIds, requesterId: member.id, nameOf: this.nameOf, newId: () => this.nextId("M") });
    const proposal: Proposal = {
      id: `P${++this.seq}`,
      requesterId: member.id,
      summary,
      ops,
      diagnosis,
      text: describeDiagnosis(diagnosis, this.nameOf),
      options,
      status: "open",
      negotiating: [],
      approvals: {},
    };
    this.proposals.set(proposal.id, proposal);
    this.emit({ type: "proposal", payload: proposal });
    this.say(member.id, "mediator", `${proposal.text} Nothing has changed yet. Pick a fix.`, { proposalId: proposal.id });
    return proposal;
  }

  private finish(p: Proposal, option: FixOption, approvedBy: string[]): SubmitResult {
    p.status = "done";
    this.emit({ type: "proposal", payload: p });
    const draft: Draft = {
      by: p.requesterId,
      summary: p.summary,
      ops: p.ops,
      fix: { summary: `${option.title}. ${option.detail}`, ops: option.ops, approvedBy },
    };
    // People took time to decide; the level may have moved on, so check again on the current version.
    const applied = applyDraft(this.world, draft);
    if (!applied.ok) {
      this.say(p.requesterId, "system", `The level changed meanwhile and this fix no longer applies: ${applied.message}`);
      return rejected(applied.code, applied.message);
    }
    if (this.solveResult.solvable && !solve(applied.world).solvable) {
      this.say(p.requesterId, "system", "The level changed meanwhile and this fix no longer keeps it winnable. Ask again.");
      return rejected("stale_fix", "The fix no longer keeps the level winnable.");
    }
    return this.commit(draft);
  }

  private commit(draft: Draft): SubmitResult {
    const applied = applyDraft(this.world, draft);
    if (!applied.ok) return rejected(applied.code, applied.message);
    if (this.blocksPlayer(applied.world)) {
      this.deferred.push(draft);
      this.say(draft.by, "system", "The player is standing where this change lands. It goes live as soon as they step away.");
      this.emit({ type: "state", payload: this.statePayload() });
      return { status: "deferred" };
    }
    this.apply(draft, applied.world);
    return { status: "committed", rev: this.rev };
  }

  private apply(draft: Draft, world: World): void {
    this.world = world;
    this.rev++;
    const entry: LogEntry = { ...draft, rev: this.rev, at: Date.now() };
    this.log.push(entry);
    this.snapshots.push(structuredClone(world));
    const started = performance.now();
    this.solveResult = solve(world);
    this.solveMs = performance.now() - started;
    this.engine = new PlayEngine(world);
    this.emit({ type: "log", payload: entry });
    this.emit({ type: "state", payload: this.statePayload() });
    // Fall markers belong to a version; the player's view of them resets with the new one.
    this.emit({ type: "play", payload: this.playState() });
  }

  // A change waits while the player stands on a cell it would make impassable.
  private blocksPlayer(world: World): boolean {
    if (![...this.members.values()].some((m) => m.role === "player")) return false;
    const grid = rasterize(world);
    const i = cellIndex(grid, this.play.x, this.play.y);
    const t = grid.terrain[i];
    if (t === Terrain.wall || t === Terrain.lava) return true;
    return t === Terrain.door && !this.play.keys.has(COLORS[grid.doorColor[i]!]!);
  }

  private flushDeferred(): void {
    if (this.deferred.length === 0) return;
    const waiting = this.deferred;
    this.deferred = [];
    for (const draft of waiting) {
      const applied = applyDraft(this.world, draft);
      if (!applied.ok) {
        this.say(draft.by, "system", `A waiting change no longer fits the level: ${applied.message}`);
        continue;
      }
      if (this.blocksPlayer(applied.world)) {
        this.deferred.push(draft);
        continue;
      }
      this.apply(draft, applied.world);
      this.say(draft.by, "system", "The player stepped away, so your change is live now.");
    }
    this.emit({ type: "state", payload: this.statePayload() });
  }
}
