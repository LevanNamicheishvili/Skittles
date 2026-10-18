// Playing a scene (spec/scene-play.md): the exact fixed-step game the studio's preview runs too
// (app/lib/studio/play.dart; both pass spec/fixtures/scene_runs.json), and the AI player, which searches for inputs that
// reach a goal without dying. A run is its inputs; replaying them on the same scene gives the same result.

import type { Scene, SceneObject } from "./scene.ts";

export const DT = 1 / 120;
export const LEFT = 1;
export const RIGHT = 2;
export const JUMP = 4;

/// A run: hold `bits` for `frames` steps, segment after segment.
export type Segment = [frames: number, bits: number];

export type RunResult = { won: boolean; time: number; frame: number; score: number; coins: string[]; coinsTotal: number; deaths: number };

type Box = { x: number; y: number; w: number; h: number };
const overlaps = (a: Box, b: Box) => a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h;

/// Where an enemy is after `frame` steps (spec/scene-play.md section 4).
export function enemyX(e: SceneObject, frame: number): number {
  const p = e.behaviours?.patrol ?? {};
  const lo = p.from ?? e.x;
  const hi = p.to ?? e.x;
  const speed = p.speed ?? 90;
  const start = Math.min(Math.max(e.x, lo), hi);
  const length = hi - lo;
  if (length <= 0 || speed <= 0) return start;
  const m = (start - lo + speed * (frame / 120)) % (2 * length);
  return m <= length ? lo + m : lo + 2 * length - m;
}

export class Game {
  readonly scene: Scene;
  readonly player: SceneObject;
  private readonly speed: number;
  private readonly jump: number;
  private readonly g: number;
  private readonly platforms: SceneObject[];
  private readonly coinObjects: SceneObject[];
  readonly enemies: SceneObject[];
  private readonly finishes: SceneObject[];

  x = 0;
  y = 0;
  vx = 0;
  vy = 0;
  grounded = false;
  air = 11;
  buffer = 0;
  prevJump = false;
  safe = 0;
  frame = 0;
  score = 0;
  coins: string[] = [];
  deaths = 0;
  won = false;

  constructor(scene: Scene) {
    const player = scene.objects.find((o) => o.type === "player");
    if (!player) throw new Error("the scene has no player");
    this.scene = scene;
    this.player = player;
    this.speed = player.behaviours?.controller?.speed ?? 260;
    this.jump = player.behaviours?.controller?.jump ?? 640;
    this.g = scene.physics.gravity;
    this.platforms = scene.objects.filter((o) => o.type === "platform");
    this.coinObjects = scene.objects.filter((o) => o.type === "coin");
    this.enemies = scene.objects.filter((o) => o.type === "enemy");
    this.finishes = scene.objects.filter((o) => o.type === "finish");
    this.respawn();
  }

  private respawn() {
    this.x = this.player.x;
    this.y = this.player.y;
    this.vx = 0;
    this.vy = 0;
    this.grounded = false;
    this.air = 11;
    this.buffer = 0;
  }

  private die() {
    this.deaths += 1;
    this.respawn();
    this.safe = 120;
  }

  /// One step of spec/scene-play.md section 3.
  step(bits: number): void {
    if (this.won) return;
    this.frame += 1;
    this.vx = this.speed * ((bits & RIGHT ? 1 : 0) - (bits & LEFT ? 1 : 0));
    const jump = (bits & JUMP) !== 0;
    const pressed = jump && !this.prevJump;
    this.prevJump = jump;
    if (pressed) this.buffer = 12;
    else if (this.buffer > 0) this.buffer -= 1;
    this.air = this.grounded ? 0 : this.air + 1;
    if (this.buffer > 0 && this.air <= 10) {
      this.vy = -this.jump;
      this.buffer = 0;
      this.air = 11;
      this.grounded = false;
    }
    const { x, y } = this;
    const { w, h } = this.player;
    let nx = x + this.vx * DT;
    for (const p of this.platforms) {
      if (!(p.y < y + h && y < p.y + p.h)) continue;
      if (this.vx > 0 && x + w <= p.x && p.x < nx + w) nx = Math.min(nx, p.x - w);
      if (this.vx < 0 && nx < p.x + p.w && p.x + p.w <= x) nx = Math.max(nx, p.x + p.w);
    }
    this.x = Math.min(Math.max(nx, 0), this.scene.size.w - w);
    let ny = y + this.vy * DT + 0.5 * this.g * DT * DT;
    this.vy = this.vy + this.g * DT;
    this.grounded = false;
    if (ny > y) {
      let land: number | undefined;
      for (const p of this.platforms) {
        if (p.x < this.x + w && this.x < p.x + p.w && y + h <= p.y && p.y < ny + h) land = land === undefined ? p.y - h : Math.min(land, p.y - h);
      }
      if (land !== undefined) {
        ny = land;
        this.vy = 0;
        this.grounded = true;
      }
    } else if (ny < y) {
      let bump: number | undefined;
      for (const p of this.platforms) {
        if (p.x < this.x + w && this.x < p.x + p.w && ny < p.y + p.h && p.y + p.h <= y) bump = bump === undefined ? p.y + p.h : Math.max(bump, p.y + p.h);
      }
      if (bump !== undefined) {
        ny = bump;
        this.vy = 0;
      }
    }
    if (ny < 0) {
      ny = 0;
      this.vy = 0;
    }
    this.y = ny;
    if (this.y > this.scene.size.h) return this.die();
    const me = { x: this.x, y: this.y, w, h };
    for (const c of this.coinObjects) {
      if (!this.coins.includes(c.id) && overlaps(me, c)) {
        this.coins.push(c.id);
        this.score += c.behaviours?.collectible?.points ?? 10;
      }
    }
    if (this.safe > 0) this.safe -= 1;
    else {
      for (const e of this.enemies) {
        if (overlaps(me, { x: enemyX(e, this.frame), y: e.y, w: e.w, h: e.h })) return this.die();
      }
    }
    if (this.finishes.some((f) => overlaps(me, f))) this.won = true;
  }

  result(): RunResult {
    return { won: this.won, time: this.frame / 120, frame: this.frame, score: this.score, coins: [...this.coins], coinsTotal: this.coinObjects.length, deaths: this.deaths };
  }

  /// Copies the moving parts (for the search).
  clone(): Game {
    const copy = Object.create(Game.prototype) as Game;
    Object.assign(copy, this);
    copy.coins = [...this.coins];
    return copy;
  }
}

/// Plays a run on a scene from the start. Runs longer than ten minutes are cut there.
export function replay(scene: Scene, run: Segment[]): Game {
  const game = new Game(scene);
  let left = 120 * 600;
  for (const [frames, bits] of run) {
    for (let i = 0; i < frames && left > 0 && !game.won; i++, left--) game.step(bits);
  }
  return game;
}

/// Reads a run a client sent: at most 20 000 segments, whole frames, known bits.
export function readRun(raw: unknown): Segment[] {
  if (!Array.isArray(raw)) throw new Error("a run is a list of [frames, bits]");
  return raw.slice(0, 20000).map((s) => {
    const [frames, bits] = Array.isArray(s) ? s : [];
    if (!Number.isInteger(frames) || frames < 1 || frames > 120 * 600 || !Number.isInteger(bits) || bits < 0 || bits > 7) throw new Error("a run segment is [frames, bits]");
    return [frames, bits] as Segment;
  });
}

// ---------------------------------------------------------------------------------------------------------------
// The AI player: a best-first search over short held inputs.

const MOVES = [RIGHT, RIGHT | JUMP, LEFT, LEFT | JUMP, 0, JUMP];
const MOVE_FRAMES = 8;

export type Search = { found: boolean; run: Segment[]; game: Game; expanded: number };

/// Searches for inputs that make [goal] true without dying. Each move holds one input for 8 steps (jump pressed on
/// the first). The cost is time; the estimate is the straight distance to [target] at run speed.
export function search(scene: Scene, goal: (g: Game) => boolean, target: Box, budget = 40000): Search {
  const steps = searching(scene, goal, target, budget);
  for (;;) {
    const next = steps.next();
    if (next.done) return next.value;
  }
}

/// The same search, letting the server handle other requests every few hundred nodes.
export async function searchAsync(scene: Scene, goal: (g: Game) => boolean, target: Box, budget = 40000): Promise<Search> {
  const steps = searching(scene, goal, target, budget);
  for (;;) {
    const next = steps.next();
    if (next.done) return next.value;
    await new Promise((r) => setImmediate(r));
  }
}

function* searching(scene: Scene, goal: (g: Game) => boolean, target: Box, budget: number): Generator<void, Search> {
  const start = new Game(scene);
  const speed = start.player.behaviours?.controller?.speed ?? 260;
  const tx = target.x + target.w / 2;
  const ty = target.y + target.h / 2;
  const estimate = (g: Game) => Math.hypot(g.x + g.player.w / 2 - tx, g.y + g.player.h / 2 - ty) / speed;
  const timed = start.enemies.length > 0;
  type Node = { game: Game; moves: number[]; cost: number };
  const open = new Heap<Node>((a, b) => a.cost < b.cost);
  let best: Node = { game: start, moves: [], cost: estimate(start) };
  open.push(best);
  const seen = new Set<string>();
  let expanded = 0;
  while (open.size && expanded < budget) {
    const node = open.pop()!;
    if (++expanded % 300 === 0) yield;
    for (const move of MOVES) {
      const g = node.game.clone();
      for (let f = 0; f < MOVE_FRAMES; f++) {
        g.step(f === 0 ? move : move & ~JUMP);
        if (g.deaths > 0 || goal(g)) break;
      }
      if (g.deaths > 0) continue;
      const moves = [...node.moves, move];
      if (goal(g)) return { found: true, run: toRun(moves, g.frame), game: g, expanded };
      const key = `${Math.round(g.x / 6)},${Math.round(g.y / 6)},${Math.round(g.vy / 90)},${g.grounded ? 1 : 0},${timed ? Math.floor(g.frame / 30) : 0}`;
      if (seen.has(key)) continue;
      seen.add(key);
      const next = { game: g, moves, cost: g.frame / 120 + estimate(g) * 1.5 };
      if (estimate(g) < estimate(best.game)) best = next;
      open.push(next);
    }
  }
  return { found: false, run: toRun(best.moves, best.game.frame), game: best.game, expanded };
}

/// A binary min-heap.
class Heap<T> {
  private readonly items: T[] = [];
  private readonly less: (a: T, b: T) => boolean;
  constructor(less: (a: T, b: T) => boolean) {
    this.less = less;
  }
  get size() {
    return this.items.length;
  }
  push(item: T) {
    const a = this.items;
    a.push(item);
    let i = a.length - 1;
    while (i > 0) {
      const parent = (i - 1) >> 1;
      if (!this.less(a[i]!, a[parent]!)) break;
      [a[i], a[parent]] = [a[parent]!, a[i]!];
      i = parent;
    }
  }
  pop(): T | undefined {
    const a = this.items;
    const top = a[0];
    const last = a.pop();
    if (a.length && last !== undefined) {
      a[0] = last;
      let i = 0;
      for (;;) {
        const l = 2 * i + 1;
        const r = l + 1;
        let m = i;
        if (l < a.length && this.less(a[l]!, a[m]!)) m = l;
        if (r < a.length && this.less(a[r]!, a[m]!)) m = r;
        if (m === i) break;
        [a[i], a[m]] = [a[m]!, a[i]!];
        i = m;
      }
    }
    return top;
  }
}

/// Moves as a run: the first step of each move with its jump, the rest without, merged.
function toRun(moves: number[], frames: number): Segment[] {
  const run: Segment[] = [];
  const push = (n: number, bits: number) => {
    const last = run[run.length - 1];
    if (last && last[1] === bits) last[0] += n;
    else run.push([n, bits]);
  };
  let left = frames;
  for (const move of moves) {
    if (left <= 0) break;
    push(1, move);
    const rest = Math.min(MOVE_FRAMES - 1, left - 1);
    if (rest > 0) push(rest, move & ~JUMP);
    left -= 1 + rest;
  }
  return run;
}

export type AiPlaytest = {
  result: RunResult;
  run: Segment[];
  finished: boolean;
  coinsReached: string[];
  coinsMissed: string[];
  // The platforms the run stood on, in order (a platform once per visit).
  route: string[];
  ms: number;
};

/// The AI player's playtest: a run to the finish, then a try for each coin.
export async function aiPlaytest(scene: Scene): Promise<AiPlaytest> {
  const started = Date.now();
  const finish = scene.objects.find((o) => o.type === "finish");
  if (!finish || !scene.objects.some((o) => o.type === "player")) {
    return { result: { won: false, time: 0, frame: 0, score: 0, coins: [], coinsTotal: 0, deaths: 0 }, run: [], finished: false, coinsReached: [], coinsMissed: [], route: [], ms: 0 };
  }
  const toFinish = await searchAsync(scene, (g) => g.won, finish);
  const coins = scene.objects.filter((o) => o.type === "coin");
  const reached = new Set(toFinish.game.coins);
  for (const coin of coins) {
    if (reached.has(coin.id)) continue;
    if ((await searchAsync(scene, (g) => g.coins.includes(coin.id), coin, 15000)).found) reached.add(coin.id);
  }
  const game = replay(scene, toFinish.run);
  return {
    result: game.result(),
    run: toFinish.run,
    finished: toFinish.found,
    coinsReached: coins.filter((c) => reached.has(c.id)).map((c) => c.id),
    coinsMissed: coins.filter((c) => !reached.has(c.id)).map((c) => c.id),
    route: routeOf(scene, toFinish.run),
    ms: Date.now() - started,
  };
}

/// The platforms a run lands on, in order.
export function routeOf(scene: Scene, run: Segment[]): string[] {
  const game = new Game(scene);
  const platforms = scene.objects.filter((o) => o.type === "platform");
  const route: string[] = [];
  for (const [frames, bits] of run) {
    for (let i = 0; i < frames && !game.won; i++) {
      game.step(bits);
      if (!game.grounded) continue;
      const under = platforms.find((p) => p.x < game.x + game.player.w && game.x < p.x + p.w && p.y === game.y + game.player.h);
      if (under && route[route.length - 1] !== under.id) route.push(under.id);
    }
  }
  return route;
}
