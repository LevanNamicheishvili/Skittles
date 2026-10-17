import { useEffect, useMemo, useRef, useState, type FormEvent, type ReactNode } from "react";
import type { Cell, Direction, World } from "../../server/src/game/types.ts";
import type { Op } from "../../server/src/room/ops.ts";
import { Board, type Cursor, type Ghost, type Runner } from "./Board.tsx";
import { BrandMark, Landing } from "./Landing.tsx";
import { blockedAt, previewWorld, routeOf } from "./sim.ts";
import { loadLang, saveLang, useSpeech, type Lang } from "./speech.ts";
import { play as playSound, setSound, soundOn } from "./sound.ts";

function MicIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" aria-hidden>
      <rect x="9" y="3" width="6" height="11" rx="3" />
      <path d="M5 11a7 7 0 0 0 14 0M12 18v3" />
    </svg>
  );
}

function LangToggle({ lang, onChange }: { lang: Lang; onChange: (l: Lang) => void }) {
  return (
    <div className="lang">
      {(["en-US", "ka-GE"] as const).map((l) => (
        <button
          key={l}
          type="button"
          className={lang === l ? "on" : ""}
          onClick={() => {
            saveLang(l);
            onChange(l);
          }}
        >
          {l === "en-US" ? "EN" : "KA"}
        </button>
      ))}
    </div>
  );
}
import {
  answer,
  applySuggestion,
  backToLive,
  choose,
  dismissSuggestion,
  fetchHistory,
  join,
  move,
  replayHistory,
  replayRunner,
  report,
  resetRoom,
  restart,
  revert,
  say,
  setPreview,
  travelTo,
  useStore,
  type ChatMessage,
  type LogEntry,
  type Member,
  type PlaytestReport,
  type Proposal,
  type ReportAck,
  type Role,
  type Store,
  type Suggestion,
} from "./net.ts";

const MEDIATOR = "#7c3aed";

// Sounds follow what happens in the room: a build pops, a conflict thuds, a fix chimes.
function useSoundEffects(store: Store) {
  const seen = useRef<{ log: number; proposals: Set<string>; reports: number; deaths: number; won: boolean; travel?: number } | null>(null);
  useEffect(() => {
    if (!store.state || !store.you) return;
    const now = {
      log: store.log.length,
      proposals: new Set(Object.keys(store.proposals)),
      reports: Object.keys(store.reports).length,
      deaths: store.play?.deaths ?? 0,
      won: store.play?.won ?? false,
      travel: store.travel?.rev,
    };
    const before = seen.current;
    seen.current = now;
    if (!before) return;
    if (now.log > before.log) playSound(store.log.at(-1)?.fix?.ops.length ? "fix" : "build");
    if ([...now.proposals].some((id) => !before.proposals.has(id))) playSound("blocked");
    if (now.reports > before.reports) playSound("report");
    if (now.deaths > before.deaths) playSound("fall");
    if (now.won && !before.won) playSound("win");
    if (now.travel !== undefined && now.travel !== before.travel && now.travel > 0) playSound("build");
  }, [store]);
}

export function App() {
  const store = useStore();
  useSoundEffects(store);
  const params = new URLSearchParams(location.search);
  const [pending, setPending] = useState(false);

  useEffect(() => {
    const role = params.get("role") as Role | null;
    const name = params.get("name");
    if (role && (role === "stage" || name)) void join(name ?? "Stage", role);
    // Only on first load: the URL decides the role of this window.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  if (!store.you || !store.state) {
    return (
      <Landing
        busy={pending}
        onJoin={async (name, role) => {
          setPending(true);
          const url = new URL(location.href);
          url.searchParams.set("role", role);
          url.searchParams.set("name", name);
          history.replaceState(null, "", url);
          await join(name, role);
          setPending(false);
        }}
      />
    );
  }
  if (store.you.role === "player") return <PlayerView store={store} />;
  if (store.you.role === "stage") return <StageView store={store} />;
  return <AuthorView store={store} />;
}

// The middle of what a batch touches, where an agent's cursor goes.
function centerOf(ops: Op[], world: World): Cell | undefined {
  const boxes = ops.flatMap((op) => {
    const e = op.op === "create" ? op.entity : op.op === "update" ? { ...world.entities.find((x) => x.id === op.id), ...op.set } : undefined;
    if (!e || e.x === undefined || e.y === undefined) return [];
    const w = "w" in e && typeof e.w === "number" ? e.w : 1;
    const h = "h" in e && typeof e.h === "number" ? e.h : 1;
    return [{ x: e.x + (w - 1) / 2, y: e.y + (h - 1) / 2 }];
  });
  if (boxes.length === 0) return undefined;
  return { x: boxes.reduce((s, b) => s + b.x, 0) / boxes.length, y: boxes.reduce((s, b) => s + b.y, 0) / boxes.length };
}

// The ghost runner: the validator's route after each version, the old route crashing into a
// proposed change, or the route a hovered fix would give.
function useRunner(store: Store): Runner | undefined {
  const state = store.state;
  const open = Object.values(store.proposals).find((p) => p.status !== "done");
  const preview = store.preview;
  return useMemo(() => {
    if (!state) return undefined;
    const world = state.world;
    if (preview) {
      const after = previewWorld(world, [...(open?.ops ?? []), ...preview]);
      const path = routeOf(after);
      if (path) return { key: `preview:${JSON.stringify(preview)}`, path, from: after.start, color: "#7c3aed" };
    }
    if (open && state.solve.path) {
      const at = blockedAt(previewWorld(world, open.ops), world.start, state.solve.path);
      return { key: `blocked:${open.id}:${store.runnerNonce}`, path: state.solve.path, from: world.start, color: "#dc2626", blockedAt: at };
    }
    if (state.solve.path) return { key: `rev:${state.rev}:${store.runnerNonce}`, path: state.solve.path, from: world.start, color: "#22c55e" };
    return undefined;
  }, [state, open, preview, store.runnerNonce]);
}

function useCursors(store: Store): Cursor[] {
  const world = store.state?.world;
  if (!world) return [];
  return store.members
    .filter((m) => m.role === "author")
    .map((m) => {
      const drafting = Object.values(store.suggestions).filter((g) => g.authorId === m.id && (g.status === "drafting" || g.status === "open")).at(-1);
      const negotiating = Object.values(store.proposals).find((p) => p.status !== "done" && p.negotiating.includes(m.id));
      const proposal = Object.values(store.proposals).filter((p) => p.requesterId === m.id && p.status !== "done").at(-1);
      const last = [...store.log].reverse().find((e) => e.by === m.id);
      const target = negotiating
        ? centerOf(negotiating.ops, world)
        : drafting
          ? store.reports[drafting.reportId]?.spot
        : proposal
          ? centerOf(proposal.ops, world)
          : last
            ? centerOf([...last.ops, ...(last.fix?.ops ?? [])], world)
            : undefined;
      const thinking = !!store.thinking[m.id] || drafting?.status === "drafting" || !!negotiating;
      return { id: m.id, label: `${m.name}'s agent`, color: m.color, target, thinking };
    });
}

// Time travel: a past version, its author's cursor on what they built, and that version's route.
function useTravelOverlays(store: Store) {
  const travel = store.travel;
  return useMemo(() => {
    if (!travel) return undefined;
    const entry = store.log.find((e) => e.rev === travel.rev);
    const author = entry ? store.members.find((m) => m.id === entry.by) : undefined;
    const ids = (ops: Op[]) => ops.flatMap((op) => (op.op === "create" ? [op.entity.id] : op.op === "update" ? [op.id] : []));
    const path = routeOf(travel.world);
    return {
      world: travel.world,
      highlight: entry ? { ids: [...ids(entry.ops), ...ids(entry.fix?.ops ?? [])], color: author?.color ?? "#64748b", at: travel.at } : undefined,
      runner: path ? { key: `travel:${travel.rev}:${travel.at}`, path, from: travel.world.start, color: "#22c55e" } : undefined,
      cursors: store.members
        .filter((m) => m.role === "author")
        .map((m) => ({
          id: m.id,
          label: `${m.name}'s agent`,
          color: m.color,
          target: entry && m.id === entry.by ? centerOf([...entry.ops, ...(entry.fix?.ops ?? [])], travel.world) : undefined,
        })),
    };
  }, [travel, store.log, store.members]);
}

// What every board shows: the latest change glowing, what breaks the level, and proposed changes.
function useBoardOverlays(store: Store) {
  const last = store.log.at(-1);
  const open = Object.values(store.proposals).filter((p) => p.status !== "done");
  const colorOf = (id: string) => store.members.find((m) => m.id === id)?.color ?? "#64748b";
  const ids = (ops: Op[]) => ops.flatMap((op) => (op.op === "create" ? [op.entity.id] : op.op === "update" ? [op.id] : []));
  const highlight =
    last && store.lastLogAt
      ? { ids: [...ids(last.ops), ...ids(last.fix?.ops ?? [])], color: colorOf(last.by), at: store.lastLogAt }
      : undefined;
  const ghosts: Ghost[] = open.map((p) => ({ ops: p.ops, color: colorOf(p.requesterId) }));
  if (store.preview) ghosts.push({ ops: store.preview, color: MEDIATOR });
  const chosen = open.flatMap((p) => (p.status === "awaiting_approval" ? (p.options.find((o) => o.id === p.chosen)?.ops ?? []) : []));
  if (chosen.length) ghosts.push({ ops: chosen, color: MEDIATOR });
  const blockerIds = open.flatMap((p) => p.diagnosis.blockers.map((b) => b.id));
  // Dev mode: report spots stay marked while they are fresh or a fix is still pending.
  const now = Date.now();
  const pending = (r: PlaytestReport) =>
    Object.values(store.suggestions).some((g) => g.reportId === r.id && (g.status === "drafting" || g.status === "open"));
  const spots = Object.values(store.reports)
    .filter((r) => r.rev === store.state?.rev && (now - r.at < 180_000 || pending(r)))
    .map((r) => r.spot);
  const runner = useRunner(store);
  const cursors = useCursors(store);
  const travel = useTravelOverlays(store);
  if (travel) return { ...travel, ghosts: [], blockerIds: [], trail: undefined, falls: undefined, spots: [] };
  return { world: store.state!.world, highlight, ghosts, blockerIds, trail: store.play?.trail, falls: store.play?.falls, spots, runner, cursors };
}

function TopBar({ store, showRoute, onToggleRoute, onToggleConsole }: { store: Store; showRoute: boolean; onToggleRoute: () => void; onToggleConsole?: () => void }) {
  const s = store.state!;
  const [sound, setSoundState] = useState(soundOn);
  return (
    <header className="topbar">
      <div className="brand">
        <BrandMark />
        Skittles
      </div>
      <div className={`status ${s.solve.solvable ? "ok" : "bad"}`} onClick={replayRunner} title="Run the validator's route again">
        {s.solve.solvable ? `Winnable · ${s.solve.steps} steps` : `Blocked · ${s.solve.unreachable.join(", ")} unreachable`}
      </div>
      <div className="version">v{s.rev}</div>
      {s.deferred > 0 && <div className="waiting">{s.deferred} change waiting for the player to step away</div>}
      <div className="spacer" />
      {onToggleConsole && (
        <button className="toggle" onClick={onToggleConsole} title="Nerd console (`)">
          {"{ }"}
        </button>
      )}
      <button
        className={`toggle ${sound ? "on" : ""}`}
        onClick={() => {
          setSound(!sound);
          setSoundState(!sound);
        }}
      >
        Sound {sound ? "on" : "off"}
      </button>
      <button className={`toggle ${showRoute ? "on" : ""}`} onClick={onToggleRoute}>
        Show route
      </button>
      <div className="members">
        {store.members
          .filter((m) => m.role !== "stage")
          .map((m) => (
            <span key={m.id} className="chip">
              <i style={{ background: m.color }}>{m.letter}</i>
              {m.name}
            </span>
          ))}
      </div>
      <span className={`dot ${store.connected ? "on" : ""}`} title={store.connected ? "Connected" : "Reconnecting"} />
    </header>
  );
}

function AuthorView({ store }: { store: Store }) {
  const [showRoute, setShowRoute] = useState(false);
  const [showConsole, setShowConsole] = useConsoleToggle();
  const overlays = useBoardOverlays(store);
  return (
    <div className="app author">
      <TopBar store={store} showRoute={showRoute} onToggleRoute={() => setShowRoute(!showRoute)} onToggleConsole={() => setShowConsole(!showConsole)} />
      <main>
        <section className="stage-area">
          <Board members={store.members} play={store.travel ? undefined : store.play} route={showRoute && !store.travel ? store.state!.solve.path : undefined} {...overlays} />
          <TravelBanner store={store} />
          {showConsole && <NerdConsole store={store} />}
        </section>
        <aside className="side">
          <Chat store={store} author={store.you!} canAct />
          <History store={store} canRevert />
        </aside>
      </main>
    </div>
  );
}

function StageView({ store }: { store: Store }) {
  const [showRoute, setShowRoute] = useState(false);
  const [showConsole, setShowConsole] = useConsoleToggle();
  const overlays = useBoardOverlays(store);
  // The two authors who spoke most recently get the projector.
  const lastSaid = (id: string) => store.chats[id]?.at(-1)?.at ?? 0;
  const authors = store.members
    .filter((m) => m.role === "author")
    .sort((a, b) => lastSaid(b.id) - lastSaid(a.id))
    .slice(0, 2);
  return (
    <div className="app stage">
      <TopBar store={store} showRoute={showRoute} onToggleRoute={() => setShowRoute(!showRoute)} onToggleConsole={() => setShowConsole(!showConsole)} />
      <main>
        <section className="stage-area">
          <Board members={store.members} play={store.travel ? undefined : store.play} route={showRoute && !store.travel ? store.state!.solve.path : undefined} {...overlays} />
          <TravelBanner store={store} />
          {showConsole && <NerdConsole store={store} />}
          <PlayHud store={store} />
        </section>
        <aside className="side two">
          {authors.map((a) => (
            <Chat key={a.id} store={store} author={a} canAct={false} />
          ))}
          <History store={store} canRevert={false} />
          <button
            className="reset"
            onClick={() => {
              if (confirm("Reset the room to the prepared level?")) void resetRoom();
            }}
          >
            Reset demo
          </button>
        </aside>
      </main>
    </div>
  );
}

function PlayerView({ store }: { store: Store }) {
  const overlays = useBoardOverlays(store);
  const [toast, setToast] = useState<string | null>(null);
  const [reporting, setReporting] = useState(false);
  const reportingRef = useRef(false);
  reportingRef.current = reporting;
  const seen = useRef(store.log.length);

  const [lang, setLang] = useState<Lang>(loadLang);
  const speech = useSpeech(lang, (said) => void report(said).then(sent));
  const speechRef = useRef(speech);
  speechRef.current = speech;

  const sent = (ack: ReportAck) => {
    if (!ack.ok) return;
    const falls = ack.fallsHere ? ` and ${ack.fallsHere} fall${ack.fallsHere > 1 ? "s" : ""} here` : "";
    setToast(`Sent to ${ack.routedTo?.join(" and ")} with your position, path${falls}.`);
    setTimeout(() => setToast(null), 3500);
  };

  useEffect(() => {
    const keys: Record<string, Direction> = {
      ArrowUp: "up", ArrowDown: "down", ArrowLeft: "left", ArrowRight: "right",
      w: "up", s: "down", a: "left", d: "right",
    };
    const onKey = (e: KeyboardEvent) => {
      if (reportingRef.current) return;
      if (e.key === "v" && !e.repeat) {
        e.preventDefault();
        speechRef.current.start();
        return;
      }
      if (e.key === "f") {
        e.preventDefault();
        setReporting(true);
        return;
      }
      const dir = keys[e.key];
      if (dir) {
        e.preventDefault();
        move(dir);
      } else if (e.key === "r") restart();
    };
    const onUp = (e: KeyboardEvent) => {
      if (e.key === "v") speechRef.current.stop();
    };
    window.addEventListener("keydown", onKey);
    window.addEventListener("keyup", onUp);
    return () => {
      window.removeEventListener("keydown", onKey);
      window.removeEventListener("keyup", onUp);
    };
  }, []);

  useEffect(() => {
    if (store.log.length <= seen.current) return;
    seen.current = store.log.length;
    const entry = store.log.at(-1)!;
    const who = store.members.find((m) => m.id === entry.by)?.name ?? "Someone";
    setToast(`${who} changed the level: ${entry.summary}`);
    const t = setTimeout(() => setToast(null), 3500);
    return () => clearTimeout(t);
  }, [store.log, store.members]);

  return (
    <div className="app player">
      <TopBar store={store} showRoute={false} onToggleRoute={() => {}} />
      <DevBar store={store} onReport={() => setReporting(true)} voice={speech.supported ? <LangToggle lang={lang} onChange={setLang} /> : null} />
      <main>
        <section className="stage-area">
          <Board world={store.state!.world} members={store.members} play={store.play} highlight={overlays.highlight} falls={overlays.falls} cursors={overlays.cursors} />
          <PlayHud store={store} />
          {toast && <div className="toast">{toast}</div>}
          {reporting && <ReportPanel onClose={() => setReporting(false)} onSent={sent} />}
          {speech.listening && (
            <div className="listening">
              <MicIcon /> {speech.interim || "Listening… say what's wrong"}
            </div>
          )}
        </section>
      </main>
      <footer className="hint">
        <kbd>↑</kbd>
        <kbd>←</kbd>
        <kbd>↓</kbd>
        <kbd>→</kbd> or <kbd>WASD</kbd> to move · <kbd>R</kbd> to restart · <kbd>F</kbd> to report a problem · hold <kbd>V</kbd> to say it
      </footer>
    </div>
  );
}

// Playtest dev mode: the context the game captures by itself, shown so the player knows what a report carries.
function DevBar({ store, onReport, voice }: { store: Store; onReport: () => void; voice: ReactNode }) {
  const play = store.play;
  if (!play) return null;
  return (
    <div className="devbar">
      <b>DEV MODE</b>
      <span>
        position ({play.x}, {play.y})
      </span>
      <span>version v{store.state!.rev}</span>
      <span>{play.deaths} falls</span>
      <span>{play.trail.length} steps tracked</span>
      <div className="spacer" />
      {voice && <span className="voice">Hold V to talk {voice}</span>}
      <button onClick={onReport}>Report a problem (F)</button>
    </div>
  );
}

function ReportPanel({ onClose, onSent }: { onClose: () => void; onSent: (ack: ReportAck) => void }) {
  const [text, setText] = useState("");
  const send = async (t: string) => {
    if (!t.trim()) return;
    onClose();
    onSent(await report(t.trim()));
  };
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && onClose();
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose]);
  return (
    <div className="report-panel">
      <h3>Report from inside the game</h3>
      <p className="muted">Your position, path, falls and the objects around you are attached. It goes to whoever made them.</p>
      <div className="quick">
        {["I keep falling here", "I'm stuck", "This part is too easy", "I can't find the way"].map((q) => (
          <button key={q} className="secondary" onClick={() => void send(q)}>
            {q}
          </button>
        ))}
      </div>
      <form
        onSubmit={(e) => {
          e.preventDefault();
          void send(text);
        }}
      >
        <input autoFocus value={text} onChange={(e) => setText(e.target.value)} placeholder="Or say it in your words" />
        <button disabled={!text.trim()}>Send</button>
      </form>
    </div>
  );
}

function PlayHud({ store }: { store: Store }) {
  const play = store.play;
  if (!play) return null;
  return (
    <div className="hud">
      <span>Falls: {play.deaths}</span>
      <span>
        Keys:{" "}
        {play.keys.length === 0 ? "none" : play.keys.map((k) => <i key={k} className={`key ${k}`} title={`${k} key`} />)}
      </span>
      {play.won && <strong className="won">Finished!</strong>}
    </div>
  );
}

function Chat({ store, author, canAct }: { store: Store; author: Member; canAct: boolean }) {
  const [text, setText] = useState("");
  const list = useRef<HTMLDivElement>(null);
  const messages = store.chats[author.id] ?? [];
  const thinking = store.thinking[author.id];

  useEffect(() => {
    list.current?.scrollTo({ top: list.current.scrollHeight, behavior: "smooth" });
  }, [messages.length, thinking]);

  // A proposal is drawn as a card once, at the first message that mentions it.
  const firstMention = useMemo(() => {
    const seen = new Set<string>();
    const first = new Set<string>();
    for (const m of messages) {
      if (m.proposalId && !seen.has(m.proposalId)) {
        seen.add(m.proposalId);
        first.add(m.id);
      }
    }
    return first;
  }, [messages]);

  const send = (e: FormEvent) => {
    e.preventDefault();
    const t = text.trim();
    if (!t || thinking) return;
    setText("");
    void say(t);
  };
  const [lang, setLang] = useState<Lang>(loadLang);
  const speech = useSpeech(lang, (said) => void say(said));

  return (
    <div className="chat">
      <div className="chat-head">
        <i style={{ background: author.color }}>{author.letter}</i>
        {canAct ? "Your agent" : `${author.name}'s agent`}
      </div>
      <div className="messages" ref={list}>
        {messages.length === 0 && canAct && (
          <p className="empty">Tell your agent what to change. It sees what the other author does.</p>
        )}
        {messages.map((m) => (
          <Message key={m.id} m={m} store={store} author={author} canAct={canAct} showCard={firstMention.has(m.id)} />
        ))}
        {thinking && <div className="msg agent thinking">Thinking…</div>}
      </div>
      {canAct && (
        <form className="composer" onSubmit={send}>
          {speech.supported && <LangToggle lang={lang} onChange={setLang} />}
          <input
            value={speech.listening ? speech.interim || "Listening…" : text}
            onChange={(e) => setText(e.target.value)}
            placeholder={lang === "ka-GE" ? "მაგ. შუაში ლავის მდინარე გააკეთე" : "e.g. Add a lava river across the middle with one gap"}
            disabled={thinking || speech.listening}
          />
          {speech.supported && (
            <button
              type="button"
              className={`mic ${speech.listening ? "on" : ""}`}
              disabled={thinking}
              title="Speak to your agent"
              onClick={() => (speech.listening ? speech.stop() : speech.start())}
            >
              <MicIcon />
            </button>
          )}
          <button disabled={thinking || !text.trim()}>Send</button>
        </form>
      )}
    </div>
  );
}

function Message({ m, store, author, canAct, showCard }: { m: ChatMessage; store: Store; author: Member; canAct: boolean; showCard: boolean }) {
  const playtest = m.reportId ? store.reports[m.reportId] : undefined;
  if (playtest) return <ReportCard r={playtest} store={store} author={author} />;
  const suggestion = m.suggestionId ? store.suggestions[m.suggestionId] : undefined;
  if (suggestion) return <SuggestionCard g={suggestion} canAct={canAct} />;
  const proposal = m.proposalId ? store.proposals[m.proposalId] : undefined;
  if (proposal && showCard) return <ProposalCard p={proposal} store={store} author={author} canAct={canAct} />;
  return <div className={`msg ${m.from}`}>{m.text}</div>;
}

function ReportCard({ r, store, author }: { r: PlaytestReport; store: Store; author: Member }) {
  const name = (id?: string) => store.members.find((m) => m.id === id)?.name ?? "the base level";
  const drafting = Object.values(store.suggestions).some((g) => g.reportId === r.id && g.authorId === author.id && g.status === "drafting");
  return (
    <div className="card report">
      <div className="card-head">{r.kind === "player" ? `Playtest report · ${name(r.by)}` : "Dev mode signal"}</div>
      <p>{r.kind === "player" ? `"${r.text}"` : r.text}</p>
      <ul className="facts">
        <li>
          At ({r.spot.x}, {r.spot.y}) on v{r.rev}
        </li>
        <li>
          {r.fallsHere > 0 ? `Fell here ${r.fallsHere}×` : "No falls here"} · {r.falls} this run
        </li>
        {r.suspects.length > 0 && (
          <li>Near {r.suspects.map((s) => `${s.ownerId === author.id ? "your" : s.mediator ? "the mediator's" : `${name(s.ownerId)}'s`} ${s.type} ${s.id}`).join(", ")}</li>
        )}
      </ul>
      {drafting && <p className="muted">Your agent is drafting a fix…</p>}
    </div>
  );
}

function SuggestionCard({ g, canAct }: { g: Suggestion; canAct: boolean }) {
  return (
    <div className="card suggestion" onMouseEnter={() => g.status === "open" && setPreview(g.ops)} onMouseLeave={() => setPreview(undefined)}>
      <div className="card-head">Suggested fix</div>
      <p>{g.message ?? g.note}</p>
      {g.status === "open" && (
        <div className="approve">
          <button
            disabled={!canAct}
            onClick={() => {
              setPreview(undefined);
              void applySuggestion(g.id);
            }}
          >
            Apply
          </button>
          <button className="secondary" disabled={!canAct} onClick={() => dismissSuggestion(g.id)}>
            Dismiss
          </button>
        </div>
      )}
      {g.status === "applied" && <p className="muted">Applied. It goes live at the next safe moment.</p>}
      {g.status === "dismissed" && <p className="muted">Dismissed.</p>}
      {g.status === "failed" && g.message && g.note && <p className="muted">{g.note}</p>}
    </div>
  );
}

function ProposalCard({ p, store, author, canAct }: { p: Proposal; store: Store; author: Member; canAct: boolean }) {
  const name = (id: string) => store.members.find((m) => m.id === id)?.name ?? "someone";
  const chosen = p.options.find((o) => o.id === p.chosen);
  const mine = p.requesterId === author.id;
  const asked = p.status === "awaiting_approval" && author.id in p.approvals && p.approvals[author.id] === null;
  return (
    <div className="card">
      <div className="card-head">Mediator</div>
      {mine ? <p>{p.text}</p> : <p>{name(p.requesterId)}'s change: {p.summary}. {p.text}</p>}
      {p.status === "open" && mine && (
        <div className="options">
          {p.options.map((o) => (
            <button
              key={o.id}
              className={o.kind === "cancel" ? "option cancel" : o.kind === "agent" ? "option agent" : "option"}
              style={o.kind === "agent" ? { borderLeftColor: store.members.find((m) => m.id === o.from)?.color } : undefined}
              disabled={!canAct}
              onMouseEnter={() => setPreview(o.ops.length ? o.ops : undefined)}
              onMouseLeave={() => setPreview(undefined)}
              onClick={() => {
                setPreview(undefined);
                void choose(p.id, o.id);
              }}
            >
              <strong>{o.title}</strong>
              <span>{o.detail}</span>
              {o.touches.length > 0 && <em>Needs {o.touches.map(name).join(" and ")} to approve</em>}
            </button>
          ))}
        </div>
      )}
      {p.status === "open" && p.negotiating.length > 0 && (
        <p className="negotiating">{p.negotiating.map(name).join(" and ")}'s agent is proposing a compromise…</p>
      )}
      {p.status === "open" && !mine && <p className="muted">Waiting for {name(p.requesterId)} to pick a fix.</p>}
      {p.status === "awaiting_approval" && chosen && (
        <>
          <p>
            <strong>{chosen.title}.</strong> {chosen.detail}
          </p>
          {asked && canAct ? (
            <div className="approve">
              <button onClick={() => void answer(p.id, true)}>Approve</button>
              <button className="secondary" onClick={() => void answer(p.id, false)}>
                Decline
              </button>
            </div>
          ) : (
            <p className="muted">
              Waiting for {Object.keys(p.approvals).filter((id) => p.approvals[id] === null).map(name).join(" and ")} to approve.
            </p>
          )}
        </>
      )}
      {p.status === "done" && <p className="muted">{chosen && chosen.kind !== "cancel" ? `Resolved: ${chosen.title}.` : "Cancelled."}</p>}
    </div>
  );
}

function useConsoleToggle(): [boolean, (on: boolean) => void] {
  const [on, setOn] = useState(false);
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "`" && !(e.target instanceof HTMLInputElement)) setOn((v) => !v);
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, []);
  return [on, setOn];
}

// For the technical jury: the raw op log as it streams, validator timing, and proof that the
// log alone rebuilds the live level.
function NerdConsole({ store }: { store: Store }) {
  const s = store.state!;
  const [replay, setReplay] = useState<"checking" | "ok" | "mismatch">("checking");
  useEffect(() => {
    let alive = true;
    setReplay("checking");
    void fetchHistory().then((worlds) => {
      if (!alive || !worlds[0]) return;
      let world = worlds[0];
      for (const e of store.log) world = previewWorld(world, [...e.ops, ...(e.fix?.ops ?? [])]);
      setReplay(JSON.stringify(world) === JSON.stringify(s.world) ? "ok" : "mismatch");
    });
    return () => {
      alive = false;
    };
  }, [s.rev, store.log, s.world]);
  const name = (id: string) => store.members.find((m) => m.id === id)?.name ?? id;
  const short = (v: unknown) => {
    const t = JSON.stringify(v);
    return t.length > 150 ? `${t.slice(0, 147)}...` : t;
  };
  return (
    <div className="nerd">
      <div className="nerd-head">
        <span>rev v{s.rev}</span>
        <span>validator {s.solveMs} ms</span>
        <span>route {s.solve.solvable ? `${s.solve.steps} steps` : "none"}</span>
        <span>{s.world.entities.length} objects</span>
        <span className={replay}>{replay === "ok" ? "✓ log replays to live state" : replay === "checking" ? "replaying log…" : "✗ replay mismatch"}</span>
      </div>
      <ol>
        {[...store.log].reverse().slice(0, 8).map((e) => (
          <li key={e.rev}>
            <b>v{e.rev}</b> <i>{name(e.by)}</i> {short(e.ops)}
            {e.fix && e.fix.ops.length > 0 && <em> + fix {short(e.fix.ops)}</em>}
          </li>
        ))}
        <li>
          <b>v0</b> <i>base</i> prepared level
        </li>
      </ol>
    </div>
  );
}

function TravelBanner({ store }: { store: Store }) {
  if (!store.travel) return null;
  const entry = store.log.find((e) => e.rev === store.travel!.rev);
  const who = entry ? store.members.find((m) => m.id === entry.by) : undefined;
  return (
    <div className="travel-banner">
      <b>TIME TRAVEL</b> v{store.travel.rev} of v{store.state!.rev}
      {entry ? (
        <span>
          · <i style={{ color: who?.color }}>{who?.name}</i>: {entry.summary}
        </span>
      ) : (
        <span>· the prepared level</span>
      )}
      <button onClick={backToLive}>Back to live</button>
    </div>
  );
}

function History({ store, canRevert }: { store: Store; canRevert: boolean }) {
  const name = (id: string) => store.members.find((m) => m.id === id);
  const current = store.state!.rev;
  const entries: (LogEntry | null)[] = [...store.log].reverse();
  entries.push(null);
  return (
    <div className="history">
      <div className="history-head">
        History
        <div className="spacer" />
        <button className="travel-btn" onClick={() => (store.travel?.replaying ? backToLive() : void replayHistory())}>
          {store.travel?.replaying ? "Stop" : "▶ Replay build"}
        </button>
      </div>
      {current > 0 && (
        <div className="scrub">
          <input
            type="range"
            min={0}
            max={current}
            value={store.travel?.rev ?? current}
            onChange={(e) => {
              const rev = Number(e.target.value);
              if (rev === current) backToLive();
              else void travelTo(rev);
            }}
          />
          <span>{store.travel ? `v${store.travel.rev} of v${current}` : `live v${current}`}</span>
        </div>
      )}
      <ol>
        {entries.map((e) => {
          const rev = e ? e.rev : 0;
          const who = e ? name(e.by) : undefined;
          return (
            <li key={rev} className={rev === current ? "current" : ""}>
              <span className="rev">v{rev}</span>
              <span className="who" style={{ background: who?.color ?? "#94a3b8" }}>
                {who?.letter ?? "·"}
              </span>
              <span className="what">
                {e ? e.summary : "Prepared level"}
                {e?.fix && e.fix.ops.length > 0 && (
                  <small>
                    Mediator: {e.fix.summary}
                    {e.fix.approvedBy.length > 0 && ` Approved by ${e.fix.approvedBy.map((id) => name(id)?.name).join(" and ")}.`}
                  </small>
                )}
              </span>
              {canRevert && rev !== current && (
                <button className="restore" onClick={() => void revert(rev)}>
                  Restore
                </button>
              )}
            </li>
          );
        })}
      </ol>
    </div>
  );
}
