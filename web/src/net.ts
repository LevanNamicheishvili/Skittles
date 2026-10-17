// One socket, one store. Every room event lands here; components read the store.

import { useSyncExternalStore } from "react";
import { io } from "socket.io-client";
import type { Direction, World } from "../../server/src/game/types.ts";
import type { Op } from "../../server/src/room/ops.ts";
import type { PlaytestReport, Suggestion } from "../../server/src/room/playtest.ts";
import type { ChatMessage, LogEntry, Member, PlayPayload, Proposal, Role, StatePayload, SubmitResult } from "../../server/src/room/room.ts";

export type { ChatMessage, LogEntry, Member, PlaytestReport, PlayPayload, Proposal, Role, StatePayload, Suggestion };

export type Store = {
  connected: boolean;
  you?: Member;
  members: Member[];
  state?: StatePayload;
  log: LogEntry[];
  chats: Record<string, ChatMessage[]>;
  proposals: Record<string, Proposal>;
  reports: Record<string, PlaytestReport>;
  suggestions: Record<string, Suggestion>;
  play?: PlayPayload;
  // Authors whose agent is working on a request.
  thinking: Record<string, boolean>;
  // Ops shown as a ghost on the board while someone hovers a fix.
  preview?: Op[];
  // Local time the latest log entry arrived, for the change highlight.
  lastLogAt?: number;
  // Bumped to make the board's ghost runner run the route again.
  runnerNonce: number;
  // Time travel: a past version shown on the board while the live room keeps going.
  travel?: { rev: number; world: World; at: number; replaying: boolean };
};

type Snapshot = {
  you: Member;
  members: Member[];
  state: StatePayload;
  log: LogEntry[];
  chats: Record<string, ChatMessage[]>;
  proposals: Proposal[];
  reports: PlaytestReport[];
  suggestions: Suggestion[];
  play: PlayPayload;
};

let store: Store = { connected: false, members: [], log: [], chats: {}, proposals: {}, reports: {}, suggestions: {}, thinking: {}, runnerNonce: 0 };
const listeners = new Set<() => void>();

function set(patch: Partial<Store> | ((s: Store) => Partial<Store>)): void {
  store = { ...store, ...(typeof patch === "function" ? patch(store) : patch) };
  for (const l of listeners) l();
}

export function useStore(): Store {
  return useSyncExternalStore(
    (l) => {
      listeners.add(l);
      return () => listeners.delete(l);
    },
    () => store,
  );
}

const socket = io({ transports: ["websocket"] });
let joined: { name: string; role: Role } | null = null;

function applySnapshot(s: Snapshot): void {
  set({
    you: s.you,
    members: s.members,
    state: s.state,
    log: s.log,
    chats: s.chats,
    proposals: Object.fromEntries(s.proposals.map((p) => [p.id, p])),
    reports: Object.fromEntries(s.reports.map((r) => [r.id, r])),
    suggestions: Object.fromEntries(s.suggestions.map((g) => [g.id, g])),
    play: s.play,
    thinking: {},
    preview: undefined,
  });
}

async function rejoin(): Promise<void> {
  if (joined) applySnapshot(await socket.emitWithAck("join", joined));
}

socket.on("connect", () => {
  set({ connected: true });
  void rejoin();
});
socket.on("disconnect", () => set({ connected: false }));
socket.on("state", (state: StatePayload) => set({ state }));
socket.on("log", (entry: LogEntry) => set((s) => ({ log: [...s.log, entry], lastLogAt: Date.now() })));
socket.on("members", (members: Member[]) => set({ members }));
socket.on("play", (play: PlayPayload) => set({ play }));
socket.on("proposal", (p: Proposal) => set((s) => ({ proposals: { ...s.proposals, [p.id]: p } })));
socket.on("report", (r: PlaytestReport) => set((s) => ({ reports: { ...s.reports, [r.id]: r } })));
socket.on("suggestion", (g: Suggestion) => set((s) => ({ suggestions: { ...s.suggestions, [g.id]: g } })));
socket.on("chat", (m: ChatMessage) =>
  set((s) => ({
    chats: { ...s.chats, [m.authorId]: [...(s.chats[m.authorId] ?? []), m] },
    thinking: m.from === "you" ? s.thinking : { ...s.thinking, [m.authorId]: false },
  })),
);
socket.on("reset", () => void rejoin());

export async function join(name: string, role: Role): Promise<void> {
  joined = { name, role };
  await rejoin();
}

export async function say(text: string): Promise<void> {
  const you = store.you;
  if (!you) return;
  set((s) => ({ thinking: { ...s.thinking, [you.id]: true } }));
  const res: { ok: boolean } = await socket.emitWithAck("agent:say", { text });
  if (!res.ok) set((s) => ({ thinking: { ...s.thinking, [you.id]: false } }));
}

export const choose = (proposalId: string, optionId: string): Promise<SubmitResult> =>
  socket.emitWithAck("proposal:choose", { proposalId, optionId });

export const answer = (proposalId: string, accept: boolean): Promise<SubmitResult> =>
  socket.emitWithAck("approval:answer", { proposalId, accept });

export const revert = (rev: number): Promise<SubmitResult> => socket.emitWithAck("history:revert", { rev });

export const submit = (ops: Op[], summary?: string): Promise<SubmitResult> => socket.emitWithAck("doc:submit", { ops, summary });

export const move = (dir: Direction): void => void socket.emit("play:move", { dir });

export const restart = (): void => void socket.emit("play:restart");

export const resetRoom = (): Promise<unknown> => socket.emitWithAck("room:reset", {});

export const setPreview = (preview: Op[] | undefined): void => set({ preview });

export type ReportAck = { ok: boolean; routedTo?: string[]; fallsHere?: number; spot?: { x: number; y: number } };

export const report = (text: string): Promise<ReportAck> => socket.emitWithAck("play:report", { text });

export const applySuggestion = (id: string): Promise<SubmitResult> => socket.emitWithAck("suggestion:apply", { id });

export const dismissSuggestion = (id: string): void => void socket.emit("suggestion:dismiss", { id });

export const replayRunner = (): void => set((s) => ({ runnerNonce: s.runnerNonce + 1 }));

let replayTimer: ReturnType<typeof setTimeout> | undefined;

const loadHistory = (): Promise<World[]> => socket.emitWithAck("history:worlds", {});

export async function travelTo(rev: number): Promise<void> {
  clearTimeout(replayTimer);
  const worlds = await loadHistory();
  const world = worlds[rev];
  if (world) set({ travel: { rev, world, at: Date.now(), replaying: false } });
}

export function backToLive(): void {
  clearTimeout(replayTimer);
  set({ travel: undefined });
}

// Plays the log from the prepared level to now, one version at a time.
export async function replayHistory(): Promise<void> {
  clearTimeout(replayTimer);
  const worlds = await loadHistory();
  const step = (rev: number): void => {
    if (rev >= worlds.length) {
      replayTimer = setTimeout(backToLive, 1200);
      return;
    }
    set({ travel: { rev, world: worlds[rev]!, at: Date.now(), replaying: true } });
    replayTimer = setTimeout(() => step(rev + 1), rev === 0 ? 900 : 1300);
  };
  step(0);
}

export const fetchHistory = (): Promise<World[]> => socket.emitWithAck("history:worlds", {});
