// The level, drawn on a canvas every frame in a 2.5D style: terrain from the shared rules, who made
// what, what is proposed but not live, the validator's route as a running ghost, the agents' cursors,
// and the player.

import { useEffect, useRef } from "react";
import { cellIndex, rasterize, Terrain } from "../../server/src/game/raster.ts";
import { COLORS, DELTA, type Cell, type Color, type Direction, type Entity, type World } from "../../server/src/game/types.ts";
import type { Op } from "../../server/src/room/ops.ts";
import type { Member, PlayPayload } from "./net.ts";

export type Ghost = { ops: Op[]; color: string };

// The validator's route, run by a ghost. With blockedAt it stops where a proposed change cuts it.
export type Runner = { key: string; path: Direction[]; from: Cell; color: string; blockedAt?: number };

// An agent at work: its cursor glides to what it is changing and says when it is thinking.
export type Cursor = { id: string; label: string; color: string; target?: Cell; thinking?: boolean };

type Props = {
  world: World;
  members: Member[];
  play?: PlayPayload;
  route?: Direction[];
  highlight?: { ids: string[]; color: string; at: number };
  blockerIds?: string[];
  ghosts?: Ghost[];
  trail?: Cell[];
  falls?: Cell[];
  spots?: Cell[];
  runner?: Runner;
  cursors?: Cursor[];
  // Caps how often the board redraws. The landing page's demo uses 30; the room draws every frame.
  maxFps?: number;
};

const INK: Record<Color, string> = { red: "#dc2626", blue: "#2563eb", gold: "#eab308" };
const MEDIATOR = "#7c3aed";
// How tall walls stand, as a share of a cell.
const LIFT = 0.32;

type Rect = { x: number; y: number; w: number; h: number };
const rectOf = (e: Entity): Rect => ({ x: e.x, y: e.y, w: "w" in e ? e.w : 1, h: "h" in e ? e.h : 1 });
const raised = (e: Entity): boolean => e.type === "wall" || e.type === "castle" || e.type === "door";

// Stable per-cell noise, so the ground looks hand-made but never flickers.
function noise(x: number, y: number, k = 0): number {
  let n = (Math.imul(x, 374761393) + Math.imul(y, 668265263) + Math.imul(k, 1274126177)) | 0;
  n = Math.imul(n ^ (n >>> 13), 1274126177);
  return ((n ^ (n >>> 16)) >>> 0) / 4294967296;
}

type Particle = { x: number; y: number; vx: number; vy: number; life: number; max: number; color: string; size: number; glow: boolean };

type Anim = {
  avatar: { x: number; y: number; fromX: number; fromY: number; at: number; deaths: number; deathAt: number; face: number };
  runner: { key: string; start: number; done: boolean };
  cursors: Map<string, { x: number; y: number }>;
  popped: Set<string>;
  particles: Particle[];
  last: number;
};

export function Board(props: Props) {
  const wrap = useRef<HTMLDivElement>(null);
  const canvas = useRef<HTMLCanvasElement>(null);
  const latest = useRef(props);
  latest.current = props;
  const anim = useRef<Anim>({
    avatar: { x: -1, y: -1, fromX: 0, fromY: 0, at: 0, deaths: -1, deathAt: -1e9, face: 1 },
    runner: { key: "", start: 0, done: true },
    cursors: new Map(),
    popped: new Set(),
    particles: [],
    last: 0,
  });

  useEffect(() => {
    const el = canvas.current!;
    const ctx = el.getContext("2d")!;
    let cell = 32;
    let frame = 0;
    let size = "";

    const resize = (): void => {
      const { w, h } = latest.current.world.grid;
      const box = wrap.current!.getBoundingClientRect();
      cell = Math.max(12, Math.floor(Math.min(box.width / w, box.height / (h + LIFT))));
      const dpr = window.devicePixelRatio || 1;
      el.width = Math.round(cell * w * dpr);
      el.height = Math.round(cell * (h + LIFT) * dpr);
      el.style.width = `${cell * w}px`;
      el.style.height = `${cell * (h + LIFT)}px`;
      size = `${w}x${h}`;
    };
    const observer = new ResizeObserver(resize);
    observer.observe(wrap.current!);
    resize();
    // Nothing is drawn while the board is scrolled out of view.
    let visible = true;
    const sight = new IntersectionObserver(([entry]) => (visible = entry?.isIntersecting ?? true));
    sight.observe(wrap.current!);
    let drawn = 0;

    const draw = (now: number): void => {
      const p = latest.current;
      if (!visible || (p.maxFps && now - drawn < 1000 / p.maxFps - 2)) {
        frame = requestAnimationFrame(draw);
        return;
      }
      drawn = now;
      const a = anim.current;
      const dt = Math.min(0.05, a.last ? (now - a.last) / 1000 : 0.016);
      a.last = now;
      const { world } = p;
      if (size !== `${world.grid.w}x${world.grid.h}`) resize();
      const dpr = window.devicePixelRatio || 1;
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      ctx.clearRect(0, 0, el.width, el.height);
      ctx.translate(0, cell * LIFT);

      const grid = rasterize(world);
      const t = now / 1000;
      const lift = cell * LIFT;
      const terrainAt = (x: number, y: number): number =>
        x < 0 || y < 0 || x >= grid.w || y >= grid.h ? -1 : grid.terrain[cellIndex(grid, x, y)]!;
      const lavaUnder = new Set<string>();
      const castleRing = new Set<string>();
      const bridgeAcross = new Map<string, boolean>();
      for (const e of world.entities) {
        const r = rectOf(e);
        for (let y = r.y; y < r.y + r.h; y++) {
          for (let x = r.x; x < r.x + r.w; x++) {
            if (e.type === "lava") lavaUnder.add(`${x},${y}`);
            if (e.type === "bridge") bridgeAcross.set(`${x},${y}`, r.w >= r.h);
            if (e.type === "castle" && (x === r.x || y === r.y || x === r.x + r.w - 1 || y === r.y + r.h - 1)) castleRing.add(`${x},${y}`);
          }
        }
      }
      const colorOf = (e: Entity): string | undefined =>
        e.owner.kind === "mediator" ? MEDIATOR : p.members.find((m) => m.id === e.owner.playerId)?.color;
      const letterOf = (e: Entity): string =>
        e.owner.kind === "mediator" ? "M" : (p.members.find((m) => m.id === e.owner.playerId)?.letter ?? "");

      // Ground, lava and bridges: the flat layer.
      const lavaCells: Cell[] = [];
      for (let y = 0; y < grid.h; y++) {
        for (let x = 0; x < grid.w; x++) {
          const tr = terrainAt(x, y);
          const px = x * cell;
          const py = y * cell;
          if (tr === Terrain.lava || (tr === Terrain.bridge && lavaUnder.has(`${x},${y}`))) {
            drawLava(ctx, px, py, cell, t, x, y, (dx, dy) => terrainAt(x + dx, y + dy) === Terrain.lava || terrainAt(x + dx, y + dy) === Terrain.bridge);
            lavaCells.push({ x, y });
          } else drawGround(ctx, px, py, cell, x, y);
          if (tr === Terrain.bridge) drawBridge(ctx, px, py, cell, bridgeAcross.get(`${x},${y}`) ?? true);
        }
      }
      ctx.strokeStyle = "rgba(0,0,0,0.05)";
      ctx.lineWidth = 1;
      ctx.beginPath();
      for (let x = 1; x < grid.w; x++) {
        ctx.moveTo(x * cell, 0);
        ctx.lineTo(x * cell, grid.h * cell);
      }
      for (let y = 1; y < grid.h; y++) {
        ctx.moveTo(0, y * cell);
        ctx.lineTo(grid.w * cell, y * cell);
      }
      ctx.stroke();

      drawStart(ctx, world.start.x, world.start.y, cell, t);

      // Shadows of standing blocks, then the blocks row by row so nearer rows overlap farther ones.
      const standing = (tr: number) => tr === Terrain.wall || tr === Terrain.door;
      ctx.fillStyle = "rgba(20, 30, 20, 0.28)";
      for (let y = 0; y < grid.h; y++) {
        for (let x = 0; x < grid.w; x++) {
          if (!standing(terrainAt(x, y)) || standing(terrainAt(x, y + 1))) continue;
          ctx.fillRect(x * cell + cell * 0.08, (y + 1) * cell, cell, cell * 0.3);
        }
      }
      for (let y = 0; y < grid.h; y++) {
        for (let x = 0; x < grid.w; x++) {
          const tr = terrainAt(x, y);
          if (!standing(tr)) continue;
          const open = !standing(terrainAt(x, y + 1));
          const color = tr === Terrain.door ? COLORS[grid.doorColor[cellIndex(grid, x, y)]!]! : undefined;
          drawBlock(ctx, x * cell, y * cell, cell, lift, open, castleRing.has(`${x},${y}`), color, x, y);
        }
      }

      // Lava light on everything around it, then embers rising.
      if (lavaCells.length) {
        ctx.globalCompositeOperation = "lighter";
        for (const c of lavaCells) {
          const cx = c.x * cell + cell / 2;
          const cy = c.y * cell + cell / 2;
          const g = ctx.createRadialGradient(cx, cy, cell * 0.2, cx, cy, cell * 1.7);
          g.addColorStop(0, `rgba(255, 120, 40, ${0.16 + 0.04 * Math.sin(t * 2 + c.x)})`);
          g.addColorStop(1, "rgba(255, 120, 40, 0)");
          ctx.fillStyle = g;
          ctx.fillRect(cx - cell * 1.7, cy - cell * 1.7, cell * 3.4, cell * 3.4);
        }
        ctx.globalCompositeOperation = "source-over";
        if (Math.random() < Math.min(1, lavaCells.length * 0.03)) {
          const c = lavaCells[Math.floor(Math.random() * lavaCells.length)]!;
          a.particles.push({
            x: (c.x + Math.random()) * cell,
            y: (c.y + Math.random()) * cell,
            vx: (Math.random() - 0.5) * cell * 0.3,
            vy: -cell * (0.6 + Math.random() * 0.8),
            life: 0,
            max: 1 + Math.random() * 1.2,
            color: "255, 170, 70",
            size: 1.2 + Math.random() * 1.6,
            glow: true,
          });
        }
      }

      drawFlag(ctx, world.flag.x, world.flag.y, cell, t);
      for (const e of world.entities) drawItem(ctx, e, cell, 1, t);

      // Who made what: corner brackets and a letter badge in the author's color.
      for (const e of world.entities) {
        const color = colorOf(e);
        if (!color) continue;
        const r = rectOf(e);
        const up = raised(e) ? lift : 0;
        brackets(ctx, r.x * cell + 2, r.y * cell + 2 - up, r.w * cell - 4, r.h * cell - 4, color, Math.min(cell * 0.35, 10));
        badge(ctx, r.x * cell + 2, r.y * cell + 2 - up, letterOf(e), color, cell);
      }

      // Just built: a pop of light and sparks in the author's color.
      if (p.highlight) {
        const age = (Date.now() - p.highlight.at) / 1000;
        for (const e of world.entities) {
          if (!p.highlight.ids.includes(e.id)) continue;
          const r = rectOf(e);
          const up = raised(e) ? lift : 0;
          const key = `${p.highlight.at}:${e.id}`;
          if (age < 1 && !a.popped.has(key)) {
            a.popped.add(key);
            burst(a.particles, (r.x + r.w / 2) * cell, (r.y + r.h / 2) * cell - up, cell, p.highlight.color, 16);
          }
          if (age < 0.8) {
            const k = 1 - age / 0.8;
            ctx.fillStyle = `rgba(255,255,255,${0.55 * k})`;
            const grow = cell * 0.15 * k;
            ctx.fillRect(r.x * cell - grow, r.y * cell - grow - up, r.w * cell + grow * 2, r.h * cell + grow * 2);
          }
          if (age < 2.5) {
            ctx.globalAlpha = 0.35 * (1 - age / 2.5);
            ctx.fillStyle = p.highlight.color;
            ctx.fillRect(r.x * cell, r.y * cell - up, r.w * cell, r.h * cell);
            ctx.globalAlpha = 1;
          }
        }
      }

      // What breaks the level pulses red.
      if (p.blockerIds?.length) {
        ctx.strokeStyle = `rgba(220, 38, 38, ${0.55 + 0.45 * Math.sin(now / 180)})`;
        ctx.lineWidth = 3;
        for (const e of world.entities) {
          if (!p.blockerIds.includes(e.id)) continue;
          const r = rectOf(e);
          ctx.strokeRect(r.x * cell + 1.5, r.y * cell + 1.5 - (raised(e) ? lift : 0), r.w * cell - 3, r.h * cell - 3);
        }
      }

      // Proposed but not live: holograms in the proposer's color.
      for (const ghost of p.ghosts ?? []) {
        for (const op of ghost.ops) {
          let e: Entity | undefined;
          if (op.op === "create") e = op.entity;
          else if (op.op === "update") {
            const base = world.entities.find((en) => en.id === op.id);
            if (base) e = { ...base, ...op.set } as Entity;
          }
          if (e) drawHologram(ctx, e, cell, ghost.color, t, lift);
        }
      }

      if (p.trail?.length) {
        ctx.fillStyle = "rgba(255, 255, 255, 0.55)";
        for (const c of p.trail) {
          ctx.beginPath();
          ctx.arc(c.x * cell + cell / 2, c.y * cell + cell / 2, cell * 0.07, 0, Math.PI * 2);
          ctx.fill();
        }
      }
      if (p.falls?.length) drawFalls(ctx, p.falls, cell);
      for (const c of p.spots ?? []) {
        ctx.strokeStyle = "rgba(245, 158, 11, 0.95)";
        ctx.lineWidth = 3;
        ctx.beginPath();
        ctx.arc(c.x * cell + cell / 2, c.y * cell + cell / 2, cell * (0.62 + 0.12 * Math.sin(now / 220)), 0, Math.PI * 2);
        ctx.stroke();
      }

      if (p.route?.length) {
        ctx.strokeStyle = "rgba(255, 255, 255, 0.85)";
        ctx.lineWidth = 3;
        ctx.setLineDash([2, 7]);
        ctx.lineDashOffset = -now / 40;
        ctx.beginPath();
        let { x, y } = world.start;
        ctx.moveTo(x * cell + cell / 2, y * cell + cell / 2);
        for (const d of p.route) {
          x += DELTA[d].x;
          y += DELTA[d].y;
          ctx.lineTo(x * cell + cell / 2, y * cell + cell / 2);
        }
        ctx.stroke();
        ctx.setLineDash([]);
      }

      if (p.runner) drawRunner(ctx, p.runner, cell, now, a);
      if (p.play) drawPlayer(ctx, p.play, cell, now, a);

      // Particles: embers, sparks, bursts.
      a.particles = a.particles.filter((q) => (q.life += dt) < q.max);
      if (a.particles.length > 400) a.particles.splice(0, a.particles.length - 400);
      for (const q of a.particles) {
        q.x += q.vx * dt;
        q.y += q.vy * dt;
        if (!q.glow) q.vy += cell * 2.5 * dt;
        const k = 1 - q.life / q.max;
        ctx.globalCompositeOperation = q.glow ? "lighter" : "source-over";
        ctx.fillStyle = `rgba(${q.color}, ${k})`;
        ctx.beginPath();
        ctx.arc(q.x, q.y, q.size * (0.5 + k * 0.5), 0, Math.PI * 2);
        ctx.fill();
      }
      ctx.globalCompositeOperation = "source-over";

      // Agents' cursors on top of everything.
      // Idle cursors park along the bottom edge, 170px apart, closer together when the board is small.
      const spacing = Math.min(170, (grid.w * cell - 20) / Math.max(1, (p.cursors ?? []).length));
      (p.cursors ?? []).forEach((c, i) => {
        const park = { x: grid.w * cell - 20 - (i + 1) * spacing, y: grid.h * cell - 40 };
        // Agents aiming at the same spot stack their labels instead of overlapping.
        const goal = c.target ? { x: c.target.x * cell + cell * 0.7, y: c.target.y * cell + cell * 0.7 + i * 26 } : park;
        const pos = a.cursors.get(c.id) ?? { ...park };
        const ease = 1 - Math.exp(-dt * 5);
        pos.x += (goal.x - pos.x) * ease;
        pos.y += (goal.y - pos.y) * ease;
        a.cursors.set(c.id, pos);
        drawCursor(ctx, pos.x, pos.y, c, t);
      });

      frame = requestAnimationFrame(draw);
    };
    frame = requestAnimationFrame(draw);
    return () => {
      cancelAnimationFrame(frame);
      observer.disconnect();
      sight.disconnect();
    };
  }, []);

  return (
    <div className="board" ref={wrap}>
      <canvas ref={canvas} />
    </div>
  );
}

function drawGround(ctx: CanvasRenderingContext2D, px: number, py: number, cell: number, x: number, y: number): void {
  const n = noise(x, y);
  ctx.fillStyle = n < 0.33 ? "#7fb35f" : n < 0.66 ? "#78ac58" : "#86b965";
  ctx.fillRect(px, py, cell, cell);
  if (noise(x, y, 1) < 0.45) {
    ctx.strokeStyle = "rgba(52, 96, 40, 0.55)";
    ctx.lineWidth = 1.2;
    const tx = px + cell * (0.2 + 0.6 * noise(x, y, 2));
    const ty = py + cell * (0.3 + 0.5 * noise(x, y, 3));
    ctx.beginPath();
    ctx.moveTo(tx - 3, ty - 4);
    ctx.lineTo(tx, ty);
    ctx.lineTo(tx + 2, ty - 5);
    ctx.stroke();
  }
  if (noise(x, y, 4) < 0.07) {
    ctx.fillStyle = noise(x, y, 5) < 0.5 ? "#fde68a" : "#fef3c7";
    ctx.beginPath();
    ctx.arc(px + cell * noise(x, y, 6), py + cell * noise(x, y, 7), cell * 0.06, 0, Math.PI * 2);
    ctx.fill();
  }
}

function drawLava(ctx: CanvasRenderingContext2D, px: number, py: number, cell: number, t: number, x: number, y: number, lavaAt: (dx: number, dy: number) => boolean): void {
  ctx.fillStyle = "#b8320b";
  ctx.fillRect(px, py, cell, cell);
  for (let k = 0; k < 2; k++) {
    const cx = px + cell * (0.5 + 0.32 * Math.sin(t * 0.8 + x * 1.3 + k * 2.1));
    const cy = py + cell * (0.5 + 0.32 * Math.cos(t * 0.6 + y * 1.7 + k * 1.4));
    const g = ctx.createRadialGradient(cx, cy, 0, cx, cy, cell * 0.55);
    g.addColorStop(0, "rgba(253, 224, 71, 0.9)");
    g.addColorStop(0.45, "rgba(249, 115, 22, 0.6)");
    g.addColorStop(1, "rgba(249, 115, 22, 0)");
    ctx.fillStyle = g;
    ctx.fillRect(px, py, cell, cell);
  }
  // A dark crust where the lava meets ground.
  ctx.fillStyle = "rgba(68, 20, 6, 0.75)";
  const rim = Math.max(2, cell * 0.08);
  if (!lavaAt(0, -1)) ctx.fillRect(px, py, cell, rim);
  if (!lavaAt(0, 1)) ctx.fillRect(px, py + cell - rim, cell, rim);
  if (!lavaAt(-1, 0)) ctx.fillRect(px, py, rim, cell);
  if (!lavaAt(1, 0)) ctx.fillRect(px + cell - rim, py, rim, cell);
}

function drawBridge(ctx: CanvasRenderingContext2D, px: number, py: number, cell: number, across: boolean): void {
  ctx.fillStyle = "rgba(0,0,0,0.3)";
  ctx.fillRect(px + 2, py + 4, cell, cell - 4);
  ctx.fillStyle = "#a16207";
  if (across) ctx.fillRect(px, py + cell * 0.12, cell, cell * 0.76);
  else ctx.fillRect(px + cell * 0.12, py, cell * 0.76, cell);
  ctx.strokeStyle = "#713f12";
  ctx.lineWidth = 1.5;
  for (let k = 1; k < 4; k++) {
    ctx.beginPath();
    if (across) {
      ctx.moveTo(px + (k * cell) / 4, py + cell * 0.12);
      ctx.lineTo(px + (k * cell) / 4, py + cell * 0.88);
    } else {
      ctx.moveTo(px + cell * 0.12, py + (k * cell) / 4);
      ctx.lineTo(px + cell * 0.88, py + (k * cell) / 4);
    }
    ctx.stroke();
  }
  ctx.fillStyle = "#57340f";
  if (across) {
    ctx.fillRect(px, py + cell * 0.08, cell, cell * 0.08);
    ctx.fillRect(px, py + cell * 0.84, cell, cell * 0.08);
  } else {
    ctx.fillRect(px + cell * 0.08, py, cell * 0.08, cell);
    ctx.fillRect(px + cell * 0.84, py, cell * 0.08, cell);
  }
}

function drawBlock(
  ctx: CanvasRenderingContext2D, px: number, py: number, cell: number, lift: number,
  open: boolean, castle: boolean, door: Color | undefined, x: number, y: number,
): void {
  if (open) {
    ctx.fillStyle = door ? shade(INK[door], -0.35) : castle ? "#57534e" : "#4b5563";
    ctx.fillRect(px, py + cell - lift, cell, lift);
    ctx.strokeStyle = "rgba(0,0,0,0.25)";
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.moveTo(px, py + cell - lift / 2);
    ctx.lineTo(px + cell, py + cell - lift / 2);
    const off = (x + y) % 2 === 0 ? cell / 2 : cell / 4;
    ctx.moveTo(px + off, py + cell - lift);
    ctx.lineTo(px + off, py + cell - lift / 2);
    ctx.stroke();
  }
  const top = py - lift;
  const n = noise(x, y, 9);
  ctx.fillStyle = door ? INK[door] : castle ? (n < 0.5 ? "#a8a29e" : "#a29c97") : n < 0.5 ? "#6b7280" : "#64748b";
  ctx.fillRect(px, top, cell, cell);
  ctx.fillStyle = "rgba(255,255,255,0.14)";
  ctx.fillRect(px, top, cell, cell * 0.12);
  ctx.strokeStyle = "rgba(0,0,0,0.22)";
  ctx.lineWidth = 1;
  ctx.strokeRect(px + 0.5, top + 0.5, cell - 1, cell - 1);
  if (castle && !door) {
    ctx.fillStyle = "#78716c";
    ctx.fillRect(px + cell * 0.1, top + cell * 0.1, cell * 0.28, cell * 0.28);
    ctx.fillRect(px + cell * 0.62, top + cell * 0.1, cell * 0.28, cell * 0.28);
  }
  if (door) {
    ctx.fillStyle = "rgba(0,0,0,0.25)";
    ctx.fillRect(px + cell * 0.12, top + cell * 0.12, cell * 0.76, cell * 0.76);
    ctx.fillStyle = INK[door];
    ctx.fillRect(px + cell * 0.18, top + cell * 0.18, cell * 0.64, cell * 0.64);
    ctx.fillStyle = "#1f2937";
    ctx.beginPath();
    ctx.arc(px + cell / 2, top + cell * 0.45, cell * 0.09, 0, Math.PI * 2);
    ctx.fill();
    ctx.fillRect(px + cell * 0.46, top + cell * 0.45, cell * 0.08, cell * 0.2);
  } else if (!castle && noise(x, y, 11) < 0.4) {
    ctx.fillStyle = "rgba(255,255,255,0.08)";
    ctx.beginPath();
    ctx.arc(px + cell * 0.35, top + cell * 0.6, cell * 0.12, 0, Math.PI * 2);
    ctx.fill();
  }
}

function shade(hex: string, amount: number): string {
  const n = parseInt(hex.slice(1), 16);
  const f = (c: number) => Math.max(0, Math.min(255, Math.round(c * (1 + amount))));
  return `rgb(${f(n >> 16)}, ${f((n >> 8) & 255)}, ${f(n & 255)})`;
}

function brackets(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number, color: string, len: number): void {
  ctx.strokeStyle = color;
  ctx.lineWidth = 2.5;
  ctx.beginPath();
  for (const [cx, cy, sx, sy] of [[x, y, 1, 1], [x + w, y, -1, 1], [x, y + h, 1, -1], [x + w, y + h, -1, -1]] as const) {
    ctx.moveTo(cx + sx * len, cy);
    ctx.lineTo(cx, cy);
    ctx.lineTo(cx, cy + sy * len);
  }
  ctx.stroke();
}

function badge(ctx: CanvasRenderingContext2D, x: number, y: number, letter: string, color: string, cell: number): void {
  if (!letter) return;
  const s = Math.max(12, cell * 0.36);
  ctx.fillStyle = color;
  ctx.beginPath();
  ctx.roundRect(x - 3, y - 3, s, s, 4);
  ctx.fill();
  ctx.fillStyle = "#fff";
  ctx.font = `800 ${Math.round(s * 0.7)}px -apple-system, sans-serif`;
  ctx.textAlign = "center";
  ctx.textBaseline = "middle";
  ctx.fillText(letter, x - 3 + s / 2, y - 3 + s / 2 + 1);
}

function burst(parts: Particle[], x: number, y: number, cell: number, hex: string, count: number): void {
  const n = parseInt(hex.slice(1), 16);
  const color = `${n >> 16}, ${(n >> 8) & 255}, ${n & 255}`;
  for (let i = 0; i < count; i++) {
    const angle = (i / count) * Math.PI * 2 + Math.random() * 0.4;
    const speed = cell * (2 + Math.random() * 2.5);
    parts.push({ x, y, vx: Math.cos(angle) * speed, vy: Math.sin(angle) * speed - cell, life: 0, max: 0.7 + Math.random() * 0.4, color, size: 2 + Math.random() * 2, glow: false });
  }
}

function drawStart(ctx: CanvasRenderingContext2D, x: number, y: number, cell: number, t: number): void {
  const cx = x * cell + cell / 2;
  const cy = y * cell + cell / 2;
  ctx.fillStyle = "#d6d3d1";
  ctx.beginPath();
  ctx.arc(cx, cy, cell * 0.42, 0, Math.PI * 2);
  ctx.fill();
  ctx.strokeStyle = "#16a34a";
  ctx.lineWidth = 2.5;
  ctx.setLineDash([4, 4]);
  ctx.lineDashOffset = -t * 12;
  ctx.beginPath();
  ctx.arc(cx, cy, cell * 0.36, 0, Math.PI * 2);
  ctx.stroke();
  ctx.setLineDash([]);
}

function drawFlag(ctx: CanvasRenderingContext2D, x: number, y: number, cell: number, t: number): void {
  const px = x * cell;
  const py = y * cell;
  ctx.fillStyle = "rgba(0,0,0,0.25)";
  ctx.beginPath();
  ctx.ellipse(px + cell * 0.32, py + cell * 0.88, cell * 0.16, cell * 0.06, 0, 0, Math.PI * 2);
  ctx.fill();
  ctx.fillStyle = "#374151";
  ctx.fillRect(px + cell * 0.28, py - cell * 0.1, cell * 0.07, cell * 0.98);
  const cols = 5;
  const rows = 3;
  const fw = cell * 0.55;
  const fh = cell * 0.36;
  for (let i = 0; i < cols; i++) {
    const wave = Math.sin(t * 5 - i * 0.9) * cell * 0.04 * (i / cols);
    for (let j = 0; j < rows; j++) {
      ctx.fillStyle = (i + j) % 2 === 0 ? "#111827" : "#f9fafb";
      ctx.fillRect(px + cell * 0.35 + (i * fw) / cols, py - cell * 0.08 + (j * fh) / rows + wave, fw / cols + 0.5, fh / rows + 0.5);
    }
  }
}

function drawItem(ctx: CanvasRenderingContext2D, e: Entity, cell: number, alpha: number, t: number): void {
  const cx = e.x * cell + cell / 2;
  const cy = e.y * cell + cell / 2;
  ctx.globalAlpha = alpha;
  if (e.type === "key") {
    const bob = Math.sin(t * 3 + e.x) * cell * 0.05;
    ctx.fillStyle = "rgba(0,0,0,0.2)";
    ctx.beginPath();
    ctx.ellipse(cx, cy + cell * 0.3, cell * 0.2, cell * 0.06, 0, 0, Math.PI * 2);
    ctx.fill();
    ctx.strokeStyle = INK[e.color];
    ctx.fillStyle = INK[e.color];
    ctx.lineWidth = Math.max(2, cell * 0.1);
    ctx.beginPath();
    ctx.arc(cx - cell * 0.14, cy + bob, cell * 0.14, 0, Math.PI * 2);
    ctx.stroke();
    ctx.fillRect(cx, cy - cell * 0.04 + bob, cell * 0.32, cell * 0.08);
    ctx.fillRect(cx + cell * 0.2, cy + bob, cell * 0.06, cell * 0.13);
    if ((t * 0.7 + e.y) % 2 < 0.25) {
      ctx.fillStyle = "#fff";
      ctx.beginPath();
      ctx.arc(cx - cell * 0.2, cy - cell * 0.08 + bob, cell * 0.04, 0, Math.PI * 2);
      ctx.fill();
    }
  } else if (e.type === "coin") {
    const sx = Math.abs(Math.cos(t * 3 + e.x * 0.7));
    ctx.fillStyle = "#facc15";
    ctx.beginPath();
    ctx.ellipse(cx, cy, cell * 0.2 * Math.max(0.15, sx), cell * 0.2, 0, 0, Math.PI * 2);
    ctx.fill();
    ctx.strokeStyle = "#a16207";
    ctx.lineWidth = 1.5;
    ctx.stroke();
  } else if (e.type === "treasure") {
    ctx.fillStyle = "rgba(0,0,0,0.2)";
    ctx.fillRect(cx - cell * 0.28, cy + cell * 0.2, cell * 0.6, cell * 0.08);
    ctx.fillStyle = "#92400e";
    ctx.fillRect(cx - cell * 0.3, cy - cell * 0.14, cell * 0.6, cell * 0.36);
    ctx.fillStyle = "#b45309";
    ctx.fillRect(cx - cell * 0.3, cy - cell * 0.22, cell * 0.6, cell * 0.12);
    ctx.fillStyle = "#facc15";
    ctx.fillRect(cx - cell * 0.3, cy - cell * 0.1, cell * 0.6, cell * 0.05);
    ctx.fillRect(cx - cell * 0.05, cy - cell * 0.12, cell * 0.1, cell * 0.14);
  }
  ctx.globalAlpha = 1;
}

function drawHologram(ctx: CanvasRenderingContext2D, e: Entity, cell: number, color: string, t: number, lift: number): void {
  const r = rectOf(e);
  const up = raised(e) ? lift : 0;
  const cells: Cell[] = [];
  for (let y = r.y; y < r.y + r.h; y++) {
    for (let x = r.x; x < r.x + r.w; x++) {
      if (e.type === "castle" && !(x === r.x || y === r.y || x === r.x + r.w - 1 || y === r.y + r.h - 1)) continue;
      cells.push({ x, y });
    }
  }
  const base: Record<string, string> = { lava: "#f97316", bridge: "#a16207", wall: "#64748b", castle: "#a8a29e" };
  const fill = e.type === "door" ? INK[e.color] : base[e.type];
  if (fill) {
    ctx.globalAlpha = 0.5 + 0.12 * Math.sin(t * 4);
    ctx.fillStyle = fill;
    for (const c of cells) ctx.fillRect(c.x * cell, c.y * cell - up, cell, cell);
    ctx.globalAlpha = 1;
  }
  // Moving scanlines read as "not real yet".
  ctx.strokeStyle = color;
  ctx.globalAlpha = 0.35;
  ctx.lineWidth = 1;
  const offset = (t * 18) % 6;
  ctx.beginPath();
  for (const c of cells) {
    for (let k = offset; k < cell; k += 6) {
      ctx.moveTo(c.x * cell, c.y * cell - up + k);
      ctx.lineTo(c.x * cell + cell, c.y * cell - up + k);
    }
  }
  ctx.stroke();
  ctx.globalAlpha = 1;
  drawItem(ctx, e, cell, 0.85, t);
  ctx.strokeStyle = color;
  ctx.lineWidth = 2.5;
  ctx.setLineDash([6, 4]);
  ctx.lineDashOffset = -t * 20;
  ctx.strokeRect(r.x * cell + 1.5, r.y * cell + 1.5 - up, r.w * cell - 3, r.h * cell - 3);
  ctx.setLineDash([]);
}

function drawFalls(ctx: CanvasRenderingContext2D, falls: Cell[], cell: number): void {
  const counts = new Map<string, { c: Cell; n: number }>();
  for (const c of falls) {
    const k = `${c.x},${c.y}`;
    counts.set(k, { c, n: (counts.get(k)?.n ?? 0) + 1 });
  }
  for (const { c, n } of counts.values()) {
    const px = c.x * cell;
    const py = c.y * cell;
    const m = cell * 0.25;
    ctx.strokeStyle = "#fff";
    ctx.lineWidth = 3.5;
    ctx.beginPath();
    ctx.moveTo(px + m, py + m);
    ctx.lineTo(px + cell - m, py + cell - m);
    ctx.moveTo(px + cell - m, py + m);
    ctx.lineTo(px + m, py + cell - m);
    ctx.stroke();
    if (n > 1) {
      ctx.fillStyle = "#111827";
      ctx.beginPath();
      ctx.arc(px + cell * 0.82, py + cell * 0.18, cell * 0.18, 0, Math.PI * 2);
      ctx.fill();
      ctx.fillStyle = "#fff";
      ctx.font = `800 ${Math.round(cell * 0.24)}px -apple-system, sans-serif`;
      ctx.textAlign = "center";
      ctx.textBaseline = "middle";
      ctx.fillText(`${n}×`, px + cell * 0.82, py + cell * 0.19);
    }
  }
}

function label(ctx: CanvasRenderingContext2D, text: string, x: number, y: number, bg: string, size: number): void {
  ctx.font = `800 ${size}px -apple-system, sans-serif`;
  const w = ctx.measureText(text).width + size;
  ctx.fillStyle = bg;
  ctx.beginPath();
  ctx.roundRect(x - w / 2, y - size, w, size * 1.7, size * 0.5);
  ctx.fill();
  ctx.fillStyle = "#fff";
  ctx.textAlign = "center";
  ctx.textBaseline = "middle";
  ctx.fillText(text, x, y - size * 0.15);
}

function drawRunner(ctx: CanvasRenderingContext2D, r: Runner, cell: number, now: number, a: Anim): void {
  if (a.runner.key !== r.key) a.runner = { key: r.key, start: now, done: false };
  const stop = r.blockedAt ?? r.path.length;
  const speed = 16; // cells per second
  const elapsed = (now - a.runner.start) / 1000;
  const progress = elapsed * speed;
  const at = Math.min(progress, stop);
  const finished = progress >= stop;
  const after = finished ? elapsed - stop / speed : 0;
  if (after > 2.6) return;

  const pos = (i: number): { x: number; y: number } => {
    let { x, y } = r.from;
    const whole = Math.floor(i);
    for (let k = 0; k < whole && k < r.path.length; k++) {
      x += DELTA[r.path[k]!].x;
      y += DELTA[r.path[k]!].y;
    }
    const d = r.path[whole];
    const f = i - whole;
    return d ? { x: x + DELTA[d].x * f, y: y + DELTA[d].y * f } : { x, y };
  };
  const blocked = r.blockedAt !== undefined;
  // A blocked runner bumps into the obstacle and shakes.
  const bump = blocked && finished ? Math.max(0, 0.35 - after * 2) : 0;
  const here = pos(at + bump);
  const shake = blocked && finished && after < 0.5 ? Math.sin(after * 60) * cell * 0.05 : 0;
  for (let k = 6; k >= 1; k--) {
    const back = pos(Math.max(0, at - k * 0.35));
    ctx.fillStyle = r.color;
    ctx.globalAlpha = 0.08 * (7 - k);
    ctx.beginPath();
    ctx.arc(back.x * cell + cell / 2, back.y * cell + cell / 2, cell * 0.22, 0, Math.PI * 2);
    ctx.fill();
  }
  ctx.globalAlpha = finished ? Math.max(0, 1 - after / 2.6) : 0.9;
  ctx.fillStyle = r.color;
  ctx.beginPath();
  ctx.arc(here.x * cell + cell / 2 + shake, here.y * cell + cell / 2, cell * 0.28, 0, Math.PI * 2);
  ctx.fill();
  ctx.strokeStyle = "#fff";
  ctx.lineWidth = 2;
  ctx.stroke();
  ctx.globalAlpha = 1;

  const tip = pos(stop);
  if (finished && !a.runner.done) {
    a.runner.done = true;
    burst(a.particles, tip.x * cell + cell / 2, tip.y * cell + cell / 2, cell, blocked ? "#dc2626" : "#22c55e", 18);
  }
  if (finished && after < 2.2) {
    if (blocked) {
      const target = pos(stop + 1);
      ctx.strokeStyle = `rgba(220, 38, 38, ${1 - after / 2.2})`;
      ctx.lineWidth = 4;
      ctx.beginPath();
      ctx.arc(target.x * cell + cell / 2, target.y * cell + cell / 2, cell * (0.4 + after * 0.6), 0, Math.PI * 2);
      ctx.stroke();
    }
    ctx.globalAlpha = Math.min(1, (2.2 - after) * 2);
    label(ctx, blocked ? "ROUTE BLOCKED" : "✓ WINNABLE", tip.x * cell + cell / 2, tip.y * cell - cell * 0.55 - after * cell * 0.3, blocked ? "#dc2626" : "#16a34a", Math.max(11, cell * 0.38));
    ctx.globalAlpha = 1;
  }
}

function drawPlayer(ctx: CanvasRenderingContext2D, play: PlayPayload, cell: number, now: number, a: Anim): void {
  const av = a.avatar;
  if (av.deaths < 0) av.deaths = play.deaths;
  if (play.deaths > av.deaths) {
    av.deaths = play.deaths;
    av.deathAt = now;
    if (av.x >= 0) {
      for (let i = 0; i < 24; i++) {
        a.particles.push({
          x: av.x * cell + cell / 2,
          y: av.y * cell + cell / 2,
          vx: (Math.random() - 0.5) * cell * 3,
          vy: -cell * (1 + Math.random() * 2.5),
          life: 0,
          max: 0.6 + Math.random() * 0.6,
          color: "249, 115, 22",
          size: 2 + Math.random() * 2.5,
          glow: true,
        });
      }
    }
    av.x = play.x;
    av.y = play.y;
    av.fromX = play.x;
    av.fromY = play.y;
  }
  if (av.x !== play.x || av.y !== play.y) {
    if (av.x >= 0 && play.x !== av.x) av.face = play.x > av.x ? 1 : -1;
    av.fromX = av.x < 0 ? play.x : av.x;
    av.fromY = av.y < 0 ? play.y : av.y;
    av.x = play.x;
    av.y = play.y;
    av.at = now;
  }
  const k = Math.min(1, (now - av.at) / 110);
  const groundY = (av.fromY + (av.y - av.fromY) * k) * cell;
  const x = (av.fromX + (av.x - av.fromX) * k) * cell + cell / 2;
  const y = groundY + cell / 2 - (k < 1 ? Math.sin(k * Math.PI) * cell * 0.12 : 0);
  const flash = now - av.deathAt < 500;
  const s = cell;
  ctx.fillStyle = "rgba(0,0,0,0.25)";
  ctx.beginPath();
  ctx.ellipse(x, groundY + cell * 0.88, s * 0.24, s * 0.07, 0, 0, Math.PI * 2);
  ctx.fill();
  ctx.fillStyle = flash ? "#dc2626" : play.won ? "#16a34a" : "#0f766e";
  ctx.beginPath();
  ctx.roundRect(x - s * 0.2, y - s * 0.05, s * 0.4, s * 0.38, s * 0.1);
  ctx.fill();
  ctx.fillStyle = "#f5d0a9";
  ctx.beginPath();
  ctx.arc(x, y - s * 0.17, s * 0.19, 0, Math.PI * 2);
  ctx.fill();
  ctx.fillStyle = "#3f2a14";
  ctx.beginPath();
  ctx.arc(x, y - s * 0.22, s * 0.19, Math.PI, Math.PI * 2);
  ctx.fill();
  ctx.fillStyle = "#111827";
  ctx.beginPath();
  ctx.arc(x + av.face * s * 0.07, y - s * 0.15, s * 0.03, 0, Math.PI * 2);
  ctx.arc(x + av.face * s * 0.15, y - s * 0.15, s * 0.03, 0, Math.PI * 2);
  ctx.fill();
  if (play.won) label(ctx, "FINISHED!", x, y - s * 0.6, "#16a34a", Math.max(11, s * 0.36));
}

function drawCursor(ctx: CanvasRenderingContext2D, x: number, y: number, c: Cursor, t: number): void {
  ctx.save();
  ctx.translate(x, y);
  ctx.fillStyle = c.color;
  ctx.strokeStyle = "#fff";
  ctx.lineWidth = 1.5;
  ctx.beginPath();
  ctx.moveTo(0, 0);
  ctx.lineTo(0, 18);
  ctx.lineTo(5, 14);
  ctx.lineTo(9, 22);
  ctx.lineTo(12.5, 20.5);
  ctx.lineTo(8.5, 12.5);
  ctx.lineTo(14, 12.5);
  ctx.closePath();
  ctx.fill();
  ctx.stroke();
  const text = c.thinking ? `${c.label} thinking${".".repeat(1 + (Math.floor(t * 3) % 3))}` : c.label;
  ctx.font = "700 12px -apple-system, sans-serif";
  const w = ctx.measureText(c.thinking ? `${c.label} thinking...` : text).width + 14;
  ctx.fillStyle = c.color;
  ctx.beginPath();
  ctx.roundRect(12, 20, w, 20, 6);
  ctx.fill();
  ctx.fillStyle = "#fff";
  ctx.textAlign = "left";
  ctx.textBaseline = "middle";
  ctx.fillText(text, 19, 30.5);
  ctx.restore();
}
