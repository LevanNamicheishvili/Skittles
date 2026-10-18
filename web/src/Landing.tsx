// The landing page, laid out like conductor.build: sticky header, a hero over a live sky of glyphs in the
// Skittles colours, the real board running a scripted demo, measured numbers, four feature sections with
// small looping demos, a call to action and a footer. Joining happens right in the hero.

import { useEffect, useMemo, useRef, useState, type FormEvent, type ReactNode } from "react";
import type { Cell, Entity, World } from "../../server/src/game/types.ts";
import { demoLevel } from "../../server/src/levels/demo.ts";
import type { Op } from "../../server/src/room/ops.ts";
import { Board, type Cursor, type Ghost, type Runner } from "./Board.tsx";
import type { Member, Role } from "./net.ts";
import { blockedAt, previewWorld, routeOf } from "./sim.ts";

export const REPO = "https://github.com/LevanNamicheishvili/Skittles";
// The two colours of the Skittles mark: red-orange and bronze.
const BRAND = [239, 79, 35] as const;
const BRONZE = [154, 107, 63] as const;

// The mark: an S drawn as a route through a 3×3 level, from the runner's start (round) to the goal cell (square),
// the shortest path the solver proves. With draw, the route traces itself in once, like the ghost runner.
export function BrandMark({ size = 20, draw = false }: { size?: number; draw?: boolean }) {
  return (
    <svg width={size} height={size} viewBox="0 0 32 32" aria-hidden className={draw ? "mark mark-draw" : "mark"}>
      <rect width="32" height="32" rx="8" fill="#ef4f23" />
      <g fill="#fff" fillOpacity="0.14">
        {[5, 13, 21].flatMap((y) => [5, 13, 21].map((x) => <rect key={`${x},${y}`} x={x} y={y} width="6" height="6" rx="1.6" />))}
      </g>
      <path className="mark-route" pathLength={1} d="M24 8H8v8h16v8H8" fill="none" stroke="#fff4ea" strokeWidth="3.4" strokeLinecap="round" strokeLinejoin="round" />
      <rect className="mark-goal" x="5.6" y="21.6" width="4.8" height="4.8" rx="1.2" fill="#9a6b3f" stroke="#fff4ea" strokeWidth="1.4" />
      <circle className="mark-start" cx="24" cy="8" r="3" fill="#9a6b3f" stroke="#fff4ea" strokeWidth="1.4" />
    </svg>
  );
}

const reducedMotion = (): boolean => matchMedia("(prefers-reduced-motion: reduce)").matches;

// Counts 0..count-1, holding each step for its duration, while the element is on screen.
// Without loop it stops on the last step. Reduced motion pins the last step.
function useSteps(holds: number[], loop = true): [number, (el: HTMLElement | null) => void] {
  const [step, setStep] = useState(0);
  const [el, setEl] = useState<HTMLElement | null>(null);
  useEffect(() => {
    if (!el) return;
    if (reducedMotion()) return setStep(holds.length - 1);
    let timer = 0;
    let current = 0;
    const tick = () => {
      if (!loop && current === holds.length - 1) return;
      timer = window.setTimeout(() => {
        current = (current + 1) % holds.length;
        setStep(current);
        tick();
      }, holds[current]);
    };
    const io = new IntersectionObserver(
      ([entry]) => {
        clearTimeout(timer);
        if (entry?.isIntersecting) tick();
      },
      { threshold: 0.3 },
    );
    io.observe(el);
    return () => {
      clearTimeout(timer);
      io.disconnect();
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [el]);
  return [step, setEl];
}

const TAGLINES = ["one agent each.", "agents that see each other.", "no broken changes.", "humans make the call."];
const LETTERS = "abcdefghijklmnopqrstuvwxyz";

// Cycles the phrases every 3 s. Each change scrambles in left to right, as Conductor's hero headline does.
function Scramble({ phrases }: { phrases: string[] }) {
  const [text, setText] = useState(phrases[0]!);
  useEffect(() => {
    if (reducedMotion()) return;
    let index = 0;
    let frame = 0;
    const timer = setInterval(() => {
      const from = phrases[index]!;
      index = (index + 1) % phrases.length;
      const to = phrases[index]!;
      const length = Math.max(from.length, to.length);
      const start = performance.now();
      const step = (now: number) => {
        const settled = Math.floor((now - start) / 24);
        if (settled >= length) return setText(to);
        let out = "";
        for (let i = 0; i < length; i++) {
          const target = to[i] ?? "";
          if (i < settled) out += target;
          else if (i < settled + 4 && target !== "" && target !== " " && target !== ".") out += LETTERS[Math.floor(Math.random() * LETTERS.length)];
          else out += from[i] ?? "";
        }
        setText(out);
        frame = requestAnimationFrame(step);
      };
      frame = requestAnimationFrame(step);
    }, 3000);
    return () => {
      clearInterval(timer);
      cancelAnimationFrame(frame);
    };
  }, [phrases]);
  return <span className="accent">{text}</span>;
}

// Smooth value noise, so the glyph clouds have soft edges.
function hash(x: number, y: number): number {
  const s = Math.sin(x * 127.1 + y * 311.7) * 43758.5453;
  return s - Math.floor(s);
}
function noise(x: number, y: number): number {
  const xi = Math.floor(x);
  const yi = Math.floor(y);
  const u = (x - xi) ** 2 * (3 - 2 * (x - xi));
  const v = (y - yi) ** 2 * (3 - 2 * (y - yi));
  const a = hash(xi, yi);
  const b = hash(xi + 1, yi);
  const c = hash(xi, yi + 1);
  const d = hash(xi + 1, yi + 1);
  return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v;
}

// The live sky behind the hero: clouds of digits and symbols drift and flicker in the Skittles colours
// (bronze at the edges, red-orange in the thick of them) over twinkling stars.
function LiveSky() {
  const ref = useRef<HTMLCanvasElement>(null);
  useEffect(() => {
    const canvas = ref.current!;
    const g = canvas.getContext("2d")!;
    const glyphs = "0123456789?%#*+=<>/$&";
    // 4 colour steps from bronze to red-orange, 6 opacity steps each.
    const palette: string[][] = [0, 1, 2, 3].map((k) => {
      const mix = (i: number) => Math.round(BRONZE[i]! + (BRAND[i]! - BRONZE[i]!) * (k / 3));
      return [0.12, 0.2, 0.3, 0.42, 0.56, 0.72].map((a) => `rgba(${mix(0)}, ${mix(1)}, ${mix(2)}, ${a})`);
    });
    const CW = 8;
    const CH = 12;
    // Every glyph in every palette colour, drawn once: copying from this sheet is far cheaper than fillText per cell.
    const atlas = document.createElement("canvas");
    let w = 0;
    let h = 0;
    let dpr = 1;
    let stars: { x: number; y: number; size: number; alpha: number; phase: number }[] = [];
    let sparkles: Cell[] = [];
    // Where the hero text sits, relative to the canvas: the clouds thin out there so the copy stays readable.
    let clear = { x0: 0, y0: 0, x1: 0, y1: 0 };

    const resize = () => {
      // The sky is a dim backdrop: 1.5x is sharp enough on retina screens and draws about half the pixels of 2x.
      dpr = Math.min(1.5, devicePixelRatio || 1);
      w = canvas.clientWidth;
      h = canvas.clientHeight;
      canvas.width = Math.round(w * dpr);
      canvas.height = Math.round(h * dpr);
      g.setTransform(dpr, 0, 0, dpr, 0, 0);
      atlas.width = glyphs.length * CW * dpr;
      atlas.height = 24 * CH * dpr;
      const a = atlas.getContext("2d")!;
      a.setTransform(dpr, 0, 0, dpr, 0, 0);
      a.font = "10px ui-monospace, SFMono-Regular, Menlo, monospace";
      a.textBaseline = "top";
      palette.flat().forEach((style, row) => {
        a.fillStyle = style;
        for (let i = 0; i < glyphs.length; i++) a.fillText(glyphs[i]!, i * CW, row * CH);
      });
      let seed = 7;
      const rand = () => (seed = (seed * 16807) % 2147483647) / 2147483647;
      const copy = canvas.parentElement?.querySelector(".hero-copy")?.getBoundingClientRect();
      const box = canvas.getBoundingClientRect();
      clear = copy ? { x0: copy.left - box.left - 24, y0: copy.top - box.top - 24, x1: copy.right - box.left + 24, y1: copy.bottom - box.top + 24 } : clear;
      stars = Array.from({ length: Math.round((w * h) / 6500) }, () => ({ x: rand() * w, y: rand() * h, size: rand() < 0.1 ? 2 : 1, alpha: 0.2 + rand() * 0.6, phase: rand() * 6.28 }));
      // Sparkles stay out of the headline column.
      sparkles = Array.from({ length: 9 }, () => {
        const side = rand() < 0.5 ? -1 : 1;
        return { x: Math.round(w / 2 + side * (w * 0.22 + rand() * w * 0.28)), y: Math.round(rand() * h * 0.75) };
      });
    };

    const draw = (now: number) => {
      const t = now / 1000;
      g.clearRect(0, 0, w, h);
      const sw = CW * dpr;
      const sh = CH * dpr;
      // The mask hides the bottom of the canvas, so the clouds stop there.
      for (let y = 0; y < h * 0.92; y += CH) {
        for (let x = 0; x < w; x += CW) {
          // Clouds gather toward the sides, and dim (but stay) behind the hero text.
          const edge = 0.3 + 0.7 * Math.min(1, Math.abs(x - w / 2) / (w * 0.34));
          const n = (noise(x / 180 + t * 0.05, y / 100 + t * 0.018) * 0.7 + noise(x / 46 - t * 0.09, y / 30) * 0.3) * edge;
          if (n < 0.46) continue;
          const away = Math.max(clear.x0 - x, x - clear.x1, clear.y0 - y, y - clear.y1, 0);
          const dim = 0.25 + 0.75 * Math.min(1, away / 80);
          const strength = Math.min(1, (n - 0.46) / 0.3);
          const row = Math.min(3, Math.floor(strength * 4)) * 6 + Math.min(5, Math.floor(strength * 6 * dim));
          // Each cell swaps its glyph now and then, at its own pace.
          const cx = x / CW;
          const cy = y / CH;
          const flip = Math.floor(t * (0.6 + hash(cx, cy) * 2.4) + hash(cy, cx) * 10);
          const glyph = Math.floor(hash(cx + flip * 17.3, cy) * glyphs.length);
          g.drawImage(atlas, glyph * sw, row * sh, sw, sh, x, y, CW, CH);
        }
      }
      for (const s of stars) {
        g.fillStyle = `rgba(255, 244, 236, ${s.alpha * (0.65 + 0.35 * Math.sin(t * 1.5 + s.phase))})`;
        g.fillRect(s.x, s.y, s.size, s.size);
      }
      g.fillStyle = "rgba(255, 244, 236, 0.85)";
      for (const s of sparkles) {
        g.fillRect(s.x - 3, s.y, 7, 1);
        g.fillRect(s.x, s.y - 3, 1, 7);
      }
    };

    resize();
    let frame = 0;
    let last = 0;
    let visible = true;
    const loop = (now: number) => {
      frame = requestAnimationFrame(loop);
      if (!visible || document.hidden || now - last < 50) return; // about 20 frames a second: the clouds drift slowly
      last = now;
      draw(now);
    };
    if (reducedMotion()) draw(0);
    else frame = requestAnimationFrame(loop);
    const io = new IntersectionObserver(([entry]) => (visible = entry?.isIntersecting ?? true));
    io.observe(canvas);
    const onResize = () => {
      resize();
      draw(performance.now());
    };
    addEventListener("resize", onResize);
    return () => {
      cancelAnimationFrame(frame);
      io.disconnect();
      removeEventListener("resize", onResize);
    };
  }, []);
  return <canvas ref={ref} className="sky" aria-hidden />;
}

// The demo, scripted on the real board and both agents' chats: Nino's lava river, Giorgi's statue in its only
// gap, the room holding it back, the mediator's checked bridge, both humans approving.
const NINO: Member = { id: "nino", name: "Nino", role: "author", letter: "A", color: "#3b82f6", online: true };
const GIORGI: Member = { id: "giorgi", name: "Giorgi", role: "author", letter: "B", color: "#f97316", online: true };
const ANA: Member = { id: "ana", name: "Ana", role: "author", letter: "C", color: "#10b981", online: true };
const DATO: Member = { id: "dato", name: "Dato", role: "author", letter: "D", color: "#e11d48", online: true };
const by = (m: Member) => ({ kind: "player" as const, playerId: m.id });
const RIVER: Entity[] = [
  { id: "A1", type: "lava", owner: by(NINO), x: 11, y: 1, w: 2, h: 3, label: "Lava river" },
  { id: "A2", type: "lava", owner: by(NINO), x: 11, y: 5, w: 2, h: 8, label: "Lava river" },
];
const COINS: Entity[] = [19, 20, 21].map((x, i) => ({ id: `C${i + 1}`, type: "coin", owner: by(ANA), x, y: 3, label: "Coin trail" }));
const STATUE: Entity = { id: "B1", type: "wall", owner: by(GIORGI), x: 11, y: 4, w: 2, h: 1, label: "Statue" };
const BRIDGE: Entity = { id: "M1", type: "bridge", owner: { kind: "mediator" }, x: 11, y: 9, w: 2, h: 1, label: "Bridge" };
const withEntities = (extra: Entity[]): World => {
  const world = demoLevel();
  world.entities.push(...extra);
  return world;
};

type Beat = { world: World; version: number; ghosts?: Ghost[]; blockers?: string[]; fresh?: Member; freshIds?: string[]; working?: Member; target?: Cell };
const BEATS: Beat[] = [
  { world: withEntities([]), version: 0, working: ANA, target: { x: 20, y: 3 } },
  { world: withEntities(COINS), version: 1, fresh: ANA, freshIds: ["C1", "C2", "C3"], working: NINO, target: { x: 11, y: 6 } },
  { world: withEntities([...COINS, ...RIVER]), version: 2, fresh: NINO, freshIds: ["A1", "A2"] },
  { world: withEntities([...COINS, ...RIVER]), version: 2, working: GIORGI, target: { x: 11, y: 4 } },
  {
    world: withEntities([...COINS, ...RIVER]),
    version: 2,
    ghosts: [{ ops: [{ op: "create", entity: STATUE }] as Op[], color: GIORGI.color }],
    blockers: ["A1", "A2"],
  },
  { world: withEntities([...COINS, ...RIVER, STATUE, BRIDGE]), version: 3, fresh: GIORGI, freshIds: ["B1", "M1"] },
];
const BEAT_HOLDS = [2600, 2600, 3400, 3600, 4800, 4600];

// The story bar under the window: which beat is which step of the mission.
const STORY = [
  { beat: 1, title: "Nino asks her agent", note: "plain words, no code" },
  { beat: 2, title: "The room checks it", note: "solver: still winnable" },
  { beat: 3, title: "Giorgi asks his", note: "it knows what Nino did" },
  { beat: 4, title: "Conflict caught", note: "nothing goes live" },
  { beat: 5, title: "Checked fix, humans decide", note: "both approve, v3 is live" },
];

type Line = { at: number; until?: number; from: "you" | "agent" | "system" | "thinking"; text: string };
const NINO_CHAT: Line[] = [
  { at: 1, from: "you", text: "Add a lava river down the middle. Leave one gap." },
  { at: 1, until: 2, from: "thinking", text: "Thinking…" },
  { at: 2, from: "agent", text: "Done: a river at column 11 with one gap at row 4. Still winnable, 27 steps." },
  { at: 4, from: "agent", text: "Giorgi's statue would close my only gap. Compromise: keep his statue, add a bridge at row 9." },
  { at: 5, from: "system", text: "You approved the bridge · v3" },
];
const GIORGI_CHAT: Line[] = [
  { at: 3, from: "you", text: "Put a big statue right in the gap." },
  { at: 3, from: "agent", text: "That gap is the only way across Nino's river. Sending it to the room to check." },
  { at: 4, from: "system", text: "Held back: the flag would be unreachable" },
  { at: 5, from: "agent", text: "You picked the bridge and Nino approved. Statue and bridge are live." },
];
const HISTORY = [
  { at: 0, rev: "v0", who: undefined, text: "Prepared level" },
  { at: 1, rev: "v1", who: ANA, text: "Coin trail" },
  { at: 2, rev: "v2", who: NINO, text: "Lava river" },
  { at: 5, rev: "v3", who: GIORGI, text: "Statue + bridge" },
];

function ChatPanel({ member, lines, beat, empty }: { member: Member; lines: Line[]; beat: number; empty: string }) {
  const shown = lines.filter((l) => l.at <= beat && (l.until === undefined || beat < l.until));
  return (
    <div className="chat">
      <div className="chat-head">
        <i style={{ background: member.color }}>{member.letter}</i>
        {member.name}'s agent
      </div>
      <div className="messages">
        {shown.length === 0 && <div className="empty">{empty}</div>}
        {shown.map((l) => (
          <div key={l.text} className={`msg ${l.from === "thinking" ? "agent thinking" : l.from}`}>
            {l.text}
          </div>
        ))}
      </div>
    </div>
  );
}

function MediatorCard({ beat }: { beat: number }) {
  const decided = beat >= 5;
  return (
    <div className="card-tone showcase-mediator">
      <div className="card-label">Mediator · solver-checked fixes</div>
      <div className={`opt ${decided ? "picked" : ""}`}>
        <span>Bridge at (11, 9)</span>
        <small>shortest route · 25 steps</small>
      </div>
      <div className="opt agent">
        <span>Move the statue next to the gap</span>
        <small>proposed by Nino's agent</small>
      </div>
      {decided && <div className="approval">✓ Giorgi picked · Nino approved</div>}
    </div>
  );
}

function Showcase() {
  const [beat, setRef] = useSteps(BEAT_HOLDS);
  const b = BEATS[beat]!;
  // New objects pop in their author's colour once per beat.
  const at = useMemo(() => Date.now(), [beat]);
  const runner = useMemo<Runner | undefined>(() => {
    const path = routeOf(b.world);
    if (!path) return undefined;
    const proposed = b.ghosts ? previewWorld(b.world, b.ghosts.flatMap((g) => g.ops)) : undefined;
    // Blocked: the ghost runs the old route and crashes into the proposal.
    const stop = proposed ? blockedAt(proposed, b.world.start, path) : undefined;
    return { key: `beat-${beat}`, path, from: b.world.start, color: stop === undefined ? "#38bdf8" : "#f87171", blockedAt: stop };
  }, [b, beat]);
  const blocked = runner?.blockedAt !== undefined;
  const cursors: Cursor[] = [NINO, GIORGI, ANA].map((m) => ({
    id: m.id,
    label: `${m.name}'s agent`,
    color: m.color,
    target: b.working === m ? b.target : undefined,
    thinking: b.working === m,
  }));
  const steps = routeOf(b.world)?.length ?? 0;

  return (
    <div className="window" ref={setRef}>
      <div className="window-bar">
        <span className="window-dots" aria-hidden>
          <i />
          <i />
          <i />
        </span>
        <span className="brand">
          <BrandMark size={16} />
          Skittles
        </span>
        <span className={`status ${blocked ? "bad" : "ok"}`}>{blocked ? "Blocked · flag unreachable" : `Winnable · ${steps} steps`}</span>
        <span className="version">v{b.version}</span>
        {/* A scripted demo, not the live room: no presence dots on these people. */}
        <span className="demo-tag">Scripted demo</span>
        <span className="spacer" />
        {[NINO, GIORGI, ANA, DATO].map((m) => (
          <span key={m.id} className="chip demo">
            <i style={{ background: m.color }}>{m.letter}</i>
            {m.name}
          </span>
        ))}
      </div>
      <div className="window-body">
        <ChatPanel member={NINO} lines={NINO_CHAT} beat={beat} empty="Nino talks to her own agent." />
        <div className="window-center">
          <div className="stage-area">
            <Board
              world={b.world}
              members={[NINO, GIORGI, ANA, DATO]}
              ghosts={b.ghosts}
              blockerIds={b.blockers}
              runner={runner}
              cursors={cursors}
              maxFps={30}
              highlight={b.fresh && b.freshIds ? { ids: b.freshIds, color: b.fresh.color, at } : undefined}
            />
          </div>
          <div className="window-history">
            {HISTORY.filter((h) => h.at <= beat).map((h) => (
              <span key={h.rev} className="history-chip">
                <code>{h.rev}</code>
                {h.who && <i style={{ background: h.who.color }}>{h.who.letter}</i>}
                {h.text}
              </span>
            ))}
          </div>
        </div>
        <div className="window-right">
          <ChatPanel member={GIORGI} lines={GIORGI_CHAT} beat={beat} empty="Giorgi talks to his own agent." />
          {beat >= 4 && <MediatorCard beat={beat} />}
        </div>
      </div>
      <ol className="story">
        {STORY.map((s, i) => (
          <li key={s.beat} className={s.beat === beat ? "now" : s.beat < beat ? "done" : ""}>
            <span className="num">{i + 1}</span>
            <span>
              <b>{s.title}</b>
              <small>{s.note}</small>
            </span>
          </li>
        ))}
      </ol>
    </div>
  );
}

// The mission in one picture: two changes that are each fine, and break the goal together.
function Mission() {
  return (
    <section className="mission">
      <h2>Syncing bytes is solved. Syncing intent is not.</h2>
      <p>
        When people edit one thing through their own agents, the dangerous conflict is not two edits to the same line. It is edits that are each correct, and together
        break the goal. Git and CRDTs see nothing wrong. Skittles proves it with a solver, before anything goes live.
      </p>
      <div className="equation">
        <div className="eq-card">
          <span className="eq-who" style={{ color: NINO.color }}>
            Nino's change
          </span>
          <b>A lava river with one gap</b>
          <span className="eq-ok">✓ winnable on its own</span>
        </div>
        <span className="eq-op">+</span>
        <div className="eq-card">
          <span className="eq-who" style={{ color: GIORGI.color }}>
            Giorgi's change
          </span>
          <b>A statue in the middle</b>
          <span className="eq-ok">✓ winnable on its own</span>
        </div>
        <span className="eq-op">=</span>
        <div className="eq-card bad">
          <span className="eq-who">Together</span>
          <b>The flag is unreachable</b>
          <span className="eq-bad">✗ held back, a mediator offers fixes</span>
        </div>
      </div>
    </section>
  );
}

// Feature demos. Each loops through a few steps while it is on screen.
function PresenceDemo() {
  const [step, setRef] = useSteps([1200, 2400, 1200, 2400, 1200, 2400, 1200, 2400]);
  const rows: { m: Member; doing: string }[] = [
    { m: NINO, doing: "building a lava river with one gap" },
    { m: GIORGI, doing: "placing a statue, keeping Nino's gap open" },
    { m: ANA, doing: "laying a coin trail by the flag" },
    { m: DATO, doing: "raising a castle with a gold door" },
  ];
  const active = Math.floor(step / 2) % rows.length;
  const showing = step % 2 === 1;
  return (
    <div className="demo presence" ref={setRef}>
      {rows.map(({ m, doing }, i) => (
        <div key={m.id} className="presence-row" style={{ animationDelay: `${i * 180}ms` }}>
          <span className="avatar" style={{ background: m.color }}>
            {m.letter}
            <b />
          </span>
          <span className="name">{m.name}'s agent</span>
          {showing && i === active && <span className="bubble">{doing}</span>}
        </div>
      ))}
    </div>
  );
}

/// Who is in the room right now: real people only, as the server reports them.
function Crowd({ people }: { people: Member[] }) {
  if (!people.length) {
    return (
      <div className="crowd">
        <span className="crowd-text">
          Nobody is building right now. <b>Be the first.</b>
        </span>
      </div>
    );
  }
  const names = people.map((p) => p.name);
  const who = names.length === 1 ? `${names[0]} is` : names.length === 2 ? `${names[0]} and ${names[1]} are` : `${names.slice(0, 2).join(", ")} and ${names.length - 2} more are`;
  return (
    <div className="crowd">
      <span className="crowd-stack">
        {people.slice(0, 6).map((p) => (
          <span key={p.id} className="crowd-face" style={{ background: p.color }} title={p.role === "author" ? `${p.name} and their agent` : `${p.name}, playing`}>
            {p.name[0]?.toUpperCase()}
            {p.role === "author" && <i aria-hidden>✦</i>}
          </span>
        ))}
      </span>
      <span className="crowd-text">
        <b>{people.length} here now</b> · {who} in the room
      </span>
    </div>
  );
}

const LOG_LINES: { rev: string; who: string; color?: string; what: string; result: string; tone: "ok" | "bad" | "muted" }[] = [
  { rev: "v1", who: "Nino", color: NINO.color, what: "lava river, one gap", result: "✓ winnable · 27 steps · 0.2 ms", tone: "ok" },
  { rev: "v2?", who: "Giorgi", color: GIORGI.color, what: "statue in the gap", result: "✗ flag unreachable", tone: "bad" },
  { rev: "", who: "room", what: "held back, nothing went live", result: "mediator opened", tone: "muted" },
  { rev: "v2", who: "Nino", color: NINO.color, what: "approved the bridge", result: "✓ winnable · 25 steps · 0.2 ms", tone: "ok" },
  { rev: "", who: "log", what: "replays v0 → v2", result: "✓ matches live state", tone: "ok" },
];

function ValidatorDemo() {
  const [step, setRef] = useSteps([700, 900, 900, 900, 900, 2800]);
  return (
    <div className="demo terminal" ref={setRef}>
      {LOG_LINES.map((l, i) => (
        <div key={i} className={`log-line ${l.tone}`} style={{ visibility: i < step ? "visible" : "hidden" }}>
          <span className="rev">{l.rev}</span>
          <span className="by" style={{ color: l.color }}>
            {l.who}
          </span>
          <span className="what">{l.what}</span>
          <span className="result">{l.result}</span>
        </div>
      ))}
      <div className="log-line muted cursor-line" style={{ visibility: step === 0 ? "visible" : "hidden" }}>
        waiting for a change…
      </div>
    </div>
  );
}

function MediatorDemo() {
  const [step, setRef] = useSteps([1600, 1400, 1400, 3000]);
  const options = [
    { title: "Build a bridge at (11, 9)", note: "shortest route · checked by the solver", agent: false },
    { title: "Move the statue next to the gap", note: "proposed by Nino's agent", agent: true },
    { title: "Cancel Giorgi's change", note: "", agent: false },
  ];
  return (
    <div className="demo mediator" ref={setRef}>
      <div className="card-tone">
        <div className="card-label">Mediator</div>
        <p>
          <b style={{ color: GIORGI.color }}>Giorgi's</b> statue closes the only gap in <b style={{ color: NINO.color }}>Nino's</b> lava river.
        </p>
        {options.map((o, i) => (
          <div key={o.title} className={`opt ${o.agent ? "agent" : ""} ${step >= 1 && i === 0 ? "picked" : ""} ${i === 2 ? "cancel" : ""}`}>
            <span>{o.title}</span>
            {o.note && <small>{o.note}</small>}
          </div>
        ))}
        <div className="approval" style={{ visibility: step >= 2 ? "visible" : "hidden" }}>
          {step >= 3 ? "✓ Nino approved · bridge is live · v2" : "Waiting for Nino: the bridge touches her lava…"}
        </div>
      </div>
    </div>
  );
}

function PlaytestDemo() {
  const [step, setRef] = useSteps([1200, 1300, 1300, 1300, 3000]);
  const lines = [
    { label: "Signal", text: "Luka fell into lava at (11, 8), 2 times" },
    { label: "Routed", text: "to Nino, who owns the lava there" },
    { label: "Draft", text: "Nino's agent: shorten the river by one row" },
    { label: "Applied", text: "v3 is live, Luka never stopped playing" },
  ];
  return (
    <div className="demo playtest" ref={setRef}>
      <div className="devbar-mini">
        <span className="tag">DEV MODE</span>
        <span>position (10, 8)</span>
        <span>falls {step >= 1 ? 2 : 1}</span>
        <span>version v{step >= 4 ? 3 : 2}</span>
      </div>
      {lines.map((l, i) => (
        <div key={l.label} className="trail-line" style={{ visibility: i < step ? "visible" : "hidden" }}>
          <span className="tag">{l.label}</span>
          {l.text}
        </div>
      ))}
    </div>
  );
}

function Feature({ title, children, demo }: { title: ReactNode; children: ReactNode; demo: ReactNode }) {
  return (
    <section className="feature">
      <h2>{title}</h2>
      <p>{children}</p>
      {demo}
    </section>
  );
}

const STATS = [
  { value: "96", label: "tests on every rule, op and agent path" },
  { value: "0.2 ms", label: "for the solver to check a version" },
  { value: "5.7 s", label: "average agent change, real requests" },
  { value: "47 s", label: "the whole demo, end to end, real agents" },
];

export function Landing({ onJoin, busy, people }: { onJoin: (name: string, role: Role) => void; busy: boolean; people: Member[] }) {
  const [name, setName] = useState("");
  const input = useRef<HTMLInputElement>(null);
  const pick = (role: Role) => (e: FormEvent) => {
    e.preventDefault();
    if (role !== "stage" && !name.trim()) return input.current?.focus();
    onJoin(name.trim() || "Stage", role);
  };
  const openRoom = () => {
    scrollTo({ top: 0, behavior: reducedMotion() ? "auto" : "smooth" });
    input.current?.focus({ preventScroll: true });
  };

  return (
    <div className="landing dark">
      <header className="site-header">
        <a className="site-brand" href="#top" onClick={openRoom}>
          <BrandMark size={24} draw />
          Skittles
        </a>
        <nav>
          <a href="#download">Download</a>
          <a href="#how">How it works</a>
          <a href="#demo">Demo</a>
          <a href="/docs">Docs</a>
          <a href={REPO} target="_blank" rel="noreferrer">
            GitHub
          </a>
        </nav>
        <button onClick={openRoom}>Open the room</button>
      </header>

      <div className="hero" id="top">
        <LiveSky />
        <div className="hero-copy">
          <div className="hero-intro">
            <h1>
              Build together,
              <br />
              <Scramble phrases={TAGLINES} />
            </h1>
            <p className="hero-lede">
              A live room where your whole team builds one world, each person by talking to their own AI agent. Every agent knows what the others changed, and every
              change is proved before it goes live, so nobody's work breaks anybody else's.
            </p>
            <Crowd people={people} />
          </div>
          <form className="hero-join">
            <input ref={input} autoFocus placeholder="Your name" value={name} onChange={(e) => setName(e.target.value)} />
            <div className="hero-actions">
              <button disabled={busy} onClick={pick("author")}>
                Start creating
              </button>
              <button
                className="secondary"
                onClick={(e) => {
                  e.preventDefault();
                  document.getElementById("demo")?.scrollIntoView({ behavior: reducedMotion() ? "auto" : "smooth" });
                }}
              >
                Watch the demo
              </button>
            </div>
            <p className="hero-links">
              Testing a level?{" "}
              <button disabled={busy} className="link" onClick={pick("player")}>
                Join as a playtester
              </button>{" "}
              · On a projector?{" "}
              <button disabled={busy} className="link" onClick={pick("stage")}>
                Open the stage screen
              </button>
            </p>
            <blockquote>
              <p>“Figma taught people to draw together. Skittles teaches their agents to build together, without breaking each other's work.”</p>
              <footer>
                <BrandMark size={16} />
                <span>
                  <b>The Skittles team</b>, Hacktoberfest Georgia 2026
                </span>
              </footer>
            </blockquote>
          </form>
        </div>
        <div className="hero-window" id="demo">
          <Showcase />
        </div>
      </div>

      <Mission />

      <section className="stats">
        <h2>Measured, not promised.</h2>
        <div className="stats-grid">
          {STATS.map((s) => (
            <div key={s.value}>
              <strong>{s.value}</strong>
              <span>{s.label}</span>
            </div>
          ))}
        </div>
      </section>

      <div className="features" id="how">
        <Feature title="Everyone brings their own agent." demo={<PresenceDemo />}>
          Invite as many people as you like. Each one talks to their own agent, by text or voice, in English or Georgian. Before every request, each agent is told what the
          others changed, and live cursors show who is building what.
        </Feature>
        <Feature title="Every change is proved, not guessed." demo={<ValidatorDemo />}>
          One room applies changes in order. Each one gets a version and an author, and a breadth-first solver checks the flag can still be reached. Agents write
          structured ops, <em>never code</em>.
        </Feature>
        <Feature title="Conflicts become choices." demo={<MediatorDemo />}>
          Two valid changes can break the level together, and Git would never notice. Skittles holds the change back and offers fixes the solver has already checked. The
          other author's agent negotiates, and the humans decide.
        </Feature>
        <Feature title="Playtest while you build." demo={<PlaytestDemo />}>
          Anyone can play the world while it changes. When someone gets stuck, the report goes to whoever built that spot, their agent drafts a fix, and it lands in the
          running game without a restart.
        </Feature>
      </div>

      <Downloads />

      <section className="cta">
        <h2>Open the room.</h2>
        <p>Invite your team. Everyone brings their own agent.</p>
        <button onClick={openRoom}>Start creating</button>
      </section>

      <footer className="site-footer">
        <span className="site-brand">
          <BrandMark size={16} />
          Skittles
        </span>
        <span>Built for Hacktoberfest Georgia 2026, Track 02: multiplayer agentic experiences.</span>
        <span className="spacer" />
        <a href="/docs">Docs</a>
        <a href={REPO} target="_blank" rel="noreferrer">
          GitHub
        </a>
        <a href={`${REPO}/blob/main/docs/research.ka.md`} target="_blank" rel="noreferrer">
          Research
        </a>
      </footer>
    </div>
  );
}

// The desktop studio. The files sit next to the site; the Windows one only once its build is in (VITE_WINDOWS_READY).
const DOWNLOADS = {
  mac: "/download/Skittles-mac.dmg",
  windows: import.meta.env.VITE_WINDOWS_READY ? "/download/Skittles-windows.zip" : null,
};

function Downloads() {
  return (
    <section className="downloads" id="download">
      <h2>Get the studio.</h2>
      <p className="downloads-lede">
        Build a 2D platformer with the tools or by asking your agent, press Play, and let the AI playtest it. Projects are shared: invite your team with the code in the
        title bar.
      </p>
      <div className="downloads-grid">
        <div className="download-card">
          <h3>macOS</h3>
          <p className="download-meta">macOS 12 or newer · Apple silicon and Intel · 20 MB</p>
          <a className="button" href={DOWNLOADS.mac} download>
            Download for Mac
          </a>
          <ol>
            <li>Open the downloaded file and drag Skittles into Applications.</li>
            <li>
              The first time, macOS says it cannot check the app (it is not from the App Store). Open <b>System Settings → Privacy &amp; Security</b> and choose{" "}
              <b>Open Anyway</b>. Once is enough.
            </li>
          </ol>
        </div>
        <div className="download-card">
          <h3>Windows</h3>
          <p className="download-meta">Windows 10 or 11 · 64-bit</p>
          {DOWNLOADS.windows ? (
            <a className="button" href={DOWNLOADS.windows} download>
              Download for Windows
            </a>
          ) : (
            <span className="button disabled">Windows build coming soon</span>
          )}
          <ol>
            <li>Unzip the folder anywhere and open Skittles.exe inside it.</li>
            <li>
              If Windows SmartScreen warns about an unknown app, choose <b>More info → Run anyway</b>.
            </li>
          </ol>
        </div>
      </div>
      <p className="downloads-note">Agents and shared projects need the Skittles server to be up; without it the studio still edits and plays on its own.</p>
    </section>
  );
}

