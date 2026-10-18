// Platformer scenes (spec/scene.md): the document, the rules every change must keep, and the actions people and
// agents change it with. A port of app/lib/studio/{scene,validate,actions}.dart; both pass spec/fixtures/scenes.json
// and spec/fixtures/actions.json, so the room and the studio always agree.

export const OBJECT_TYPES = ["player", "platform", "coin", "enemy", "finish"] as const;
export type ObjectType = (typeof OBJECT_TYPES)[number];
export const THEMES = ["forest", "desert", "night"] as const;

export type Behaviours = Record<string, Record<string, number>>;

export type SceneObject = {
  id: string;
  name: string;
  type: ObjectType;
  x: number;
  y: number;
  w: number;
  h: number;
  behaviours?: Behaviours;
  // The member who created it, in a shared project.
  by?: string;
};

export type Scene = {
  format: "skittles-scene";
  version: 1;
  name: string;
  template: string;
  size: { w: number; h: number };
  theme: string;
  physics: { gravity: number };
  objects: SceneObject[];
  ui: { score: boolean };
};

export const DEFAULT_SIZES: Record<ObjectType, { w: number; h: number }> = {
  player: { w: 32, h: 48 },
  platform: { w: 192, h: 24 },
  coin: { w: 24, h: 24 },
  enemy: { w: 40, h: 36 },
  finish: { w: 60, h: 120 },
};

export function defaultBehaviours(type: ObjectType, x = 0): Behaviours {
  switch (type) {
    case "player":
      return { controller: { speed: 260, jump: 640 } };
    case "coin":
      return { collectible: { points: 10 } };
    case "enemy":
      return { patrol: { from: x, to: x + 200, speed: 90 } };
    default:
      return {};
  }
}

export function blankScene(name = "Untitled"): Scene {
  return { format: "skittles-scene", version: 1, name, template: "platformer", size: { w: 1600, h: 900 }, theme: "forest", physics: { gravity: 1800 }, objects: [], ui: { score: true } };
}

/// Reads a scene a client sent, refusing anything that is not one. Unknown fields are dropped.
export function readScene(raw: unknown): Scene {
  const j = (raw ?? {}) as Record<string, unknown>;
  if (j.format !== "skittles-scene") throw new Error("not a Skittles scene");
  if (j.version !== 1) throw new Error(`scene version ${String(j.version)} is not supported`);
  const size = j.size as { w?: unknown; h?: unknown } | undefined;
  const w = finite(size?.w, 0);
  const h = finite(size?.h, 0);
  if (w < 320 || h < 240 || w > 20000 || h > 20000) throw new Error("the scene size is out of range");
  if (!Array.isArray(j.objects) || j.objects.length > 500) throw new Error("the scene needs at most 500 objects");
  const theme = THEMES.includes(j.theme as never) ? (j.theme as string) : "forest";
  return {
    format: "skittles-scene",
    version: 1,
    name: typeof j.name === "string" && j.name.trim() ? j.name.trim().slice(0, 60) : "Untitled",
    template: "platformer",
    size: { w, h },
    theme,
    physics: { gravity: finite((j.physics as { gravity?: unknown } | undefined)?.gravity, 1800) },
    objects: j.objects.map(readObject),
    ui: { score: (j.ui as { score?: unknown } | undefined)?.score !== false },
  };
}

export function readObject(raw: unknown): SceneObject {
  const o = (raw ?? {}) as Record<string, unknown>;
  if (typeof o.id !== "string" || !o.id || o.id.length > 64) throw new Error("an object needs an id");
  if (!OBJECT_TYPES.includes(o.type as ObjectType)) throw new Error(`${o.id} has an unknown type`);
  const object: SceneObject = {
    id: o.id,
    name: typeof o.name === "string" && o.name ? o.name.slice(0, 40) : o.id,
    type: o.type as ObjectType,
    x: finite(o.x, 0),
    y: finite(o.y, 0),
    w: finite(o.w, 8),
    h: finite(o.h, 8),
  };
  const behaviours: Behaviours = {};
  for (const [name, params] of Object.entries((o.behaviours ?? {}) as Record<string, unknown>)) {
    if (!BEHAVIOUR_KEYS[name] || !params || typeof params !== "object") continue;
    const kept: Record<string, number> = {};
    for (const key of BEHAVIOUR_KEYS[name]) {
      const v = (params as Record<string, unknown>)[key];
      if (typeof v === "number" && Number.isFinite(v)) kept[key] = v;
    }
    behaviours[name] = kept;
  }
  if (Object.keys(behaviours).length) object.behaviours = behaviours;
  if (typeof o.by === "string") object.by = o.by.slice(0, 64);
  return object;
}

function finite(v: unknown, fallback: number): number {
  return typeof v === "number" && Number.isFinite(v) ? v : fallback;
}

const clamp = (v: number, lo: number, hi: number) => Math.min(Math.max(v, lo), Math.max(lo, hi));

export const param = (o: SceneObject, behaviour: string, key: string): number | undefined => o.behaviours?.[behaviour]?.[key];

export function withParam(o: SceneObject, behaviour: string, key: string, value: number): SceneObject {
  return { ...o, behaviours: { ...o.behaviours, [behaviour]: { ...o.behaviours?.[behaviour], [key]: value } } };
}

/// The object moved and sized to lie inside the scene (at least 8 px), with an enemy's patrol kept inside too.
export function fit(scene: Scene, object: SceneObject): SceneObject {
  const w = clamp(object.w, 8, scene.size.w);
  const h = clamp(object.h, 8, scene.size.h);
  let fitted: SceneObject = { ...object, w, h, x: clamp(object.x, 0, scene.size.w - w), y: clamp(object.y, 0, scene.size.h - h) };
  if (object.type === "enemy") {
    const limit = scene.size.w - w;
    fitted = withParam(fitted, "patrol", "from", clamp(param(object, "patrol", "from") ?? object.x, 0, limit));
    fitted = withParam(fitted, "patrol", "to", clamp(param(object, "patrol", "to") ?? object.x, 0, limit));
  }
  return fitted;
}

export const byId = (scene: Scene, id: string | undefined): SceneObject | undefined => scene.objects.find((o) => o.id === id);

const replace = (scene: Scene, object: SceneObject): Scene => ({ ...scene, objects: scene.objects.map((o) => (o.id === object.id ? object : o)) });

// ---------------------------------------------------------------------------------------------------------------
// Validation and reachability (spec/scene.md sections 4 and 5).

export type SceneIssue = { code: string; severity: "error" | "warning"; message: string; objectId?: string };

export type SceneReport = {
  issues: SceneIssue[];
  errors: SceneIssue[];
  finishReachable: boolean;
  reachable: Set<string>;
  start?: string;
  jumpHeight: number;
};

export type Jump = { height: number; reach: (dh: number) => number };

export function jumpOf(speed: number, takeoff: number, gravity: number): Jump {
  return {
    height: (takeoff * takeoff) / (2 * gravity),
    reach: (dh) => {
      const under = takeoff * takeoff - 2 * gravity * dh;
      return under < 0 ? -1 : (0.9 * speed * (takeoff + Math.sqrt(under))) / gravity;
    },
  };
}

type Box = { l: number; t: number; r: number; b: number };
const box = (o: { x: number; y: number; w: number; h: number }): Box => ({ l: o.x, t: o.y, r: o.x + o.w, b: o.y + o.h });
// As Flutter's Rect: touching edges do not overlap, and a point on the right or bottom edge is outside.
const overlaps = (a: Box, b: Box) => !(a.r <= b.l || b.r <= a.l || a.b <= b.t || b.b <= a.t);
const contains = (a: Box, x: number, y: number) => x >= a.l && x < a.r && y >= a.t && y < a.b;

export function validateScene(scene: Scene): SceneReport {
  const issues: SceneIssue[] = [];
  const error = (code: string, message: string, objectId?: string) => issues.push({ code, severity: "error", message, objectId });
  const warn = (code: string, message: string, objectId?: string) => issues.push({ code, severity: "warning", message, objectId });
  const done = (finishReachable: boolean, reachable: Set<string>, jumpHeight: number, start?: string): SceneReport => ({
    issues,
    errors: issues.filter((i) => i.severity === "error"),
    finishReachable,
    reachable,
    start,
    jumpHeight,
  });
  const W = scene.size.w;
  const H = scene.size.h;

  const players = scene.objects.filter((o) => o.type === "player");
  const finishes = scene.objects.filter((o) => o.type === "finish");
  const platforms = scene.objects.filter((o) => o.type === "platform");

  if (players.length === 0) error("no_player", "There is no player.");
  if (players.length > 1) error("many_players", "There is more than one player.", players[1]!.id);
  if (finishes.length === 0) error("no_finish", "There is no finish.");

  const seen = new Set<string>();
  for (const o of scene.objects) {
    if (seen.has(o.id)) error("duplicate_id", `Two objects share the id ${o.id}.`, o.id);
    seen.add(o.id);
    if (o.w < 8 || o.h < 8) error("bad_size", `${o.name} is smaller than 8 px.`, o.id);
    if (o.x < 0 || o.y < 0 || o.x + o.w > W || o.y + o.h > H) error("out_of_bounds", `${o.name} is outside the scene.`, o.id);
    if (o.type === "enemy") {
      const from = param(o, "patrol", "from") ?? o.x;
      const to = param(o, "patrol", "to") ?? o.x;
      if (from > to || from < 0 || to + o.w > W) error("bad_patrol", `${o.name}'s patrol runs backwards or leaves the scene.`, o.id);
    }
  }

  if (players.length === 1) {
    const p = players[0]!;
    for (const f of platforms) {
      if (overlaps(box(p), box(f))) warn("player_in_platform", `The player is stuck inside ${f.name}.`, p.id);
    }
    for (const e of scene.objects.filter((o) => o.type === "enemy")) {
      const from = param(e, "patrol", "from") ?? e.x;
      const to = param(e, "patrol", "to") ?? e.x;
      const lane = { l: Math.min(from, to), t: e.y, r: Math.max(from, to) + e.w, b: e.y + e.h };
      if (overlaps(lane, box(p))) warn("enemy_on_start", `${e.name}'s patrol passes through the player's start.`, e.id);
    }
  }

  if (players.length !== 1 || finishes.length === 0) return done(false, new Set(), 0);
  const player = players[0]!;
  const jump = jumpOf(param(player, "controller", "speed") ?? 260, param(player, "controller", "jump") ?? 640, scene.physics.gravity);

  // The start: the nearest platform top at or below the player's feet that overlaps it horizontally.
  const feet = player.y + player.h;
  let start: SceneObject | undefined;
  for (const f of platforms) {
    const under = f.x < player.x + player.w && player.x < f.x + f.w && f.y >= feet;
    if (under && (!start || f.y < start.y)) start = f;
  }
  if (!start) {
    error("player_falls", "Nothing is below the player: it falls out of the world.", player.id);
    return done(false, new Set(), jump.height);
  }

  // Breadth-first search over platform tops.
  const reachable = new Set([start.id]);
  const queue = [start];
  while (queue.length) {
    const a = queue.shift()!;
    for (const b of platforms) {
      if (reachable.has(b.id)) continue;
      const dh = a.y - b.y;
      if (dh > jump.height) continue;
      const gap = Math.max(0, b.x - (a.x + a.w), a.x - (b.x + b.w));
      if (gap <= jump.reach(dh)) {
        reachable.add(b.id);
        queue.push(b);
      }
    }
  }

  const half = jump.reach(0) / 2;
  const touchable = (target: SceneObject) =>
    platforms
      .filter((f) => reachable.has(f.id))
      .some((f) => {
        const zone = { l: f.x - half, t: f.y - jump.height - player.h, r: f.x + f.w + half, b: f.y };
        return overlaps(zone, box(target)) || contains(zone, target.x + target.w / 2, target.y + target.h / 2);
      });

  const finishReachable = finishes.some(touchable);
  if (!finishReachable) error("finish_unreachable", "The finish cannot be reached.", finishes[0]!.id);
  for (const coin of scene.objects.filter((o) => o.type === "coin")) {
    if (!touchable(coin)) warn("coin_unreachable", `${coin.name} cannot be reached.`, coin.id);
  }
  return done(finishReachable, reachable, jump.height, start.id);
}

/// The errors [after] has that [before] did not: what a change broke.
export function newErrors(before: Scene, after: Scene): SceneIssue[] {
  const had = new Set(validateScene(before).errors.map((e) => e.code));
  return validateScene(after).errors.filter((e) => !had.has(e.code));
}

// ---------------------------------------------------------------------------------------------------------------
// Actions (spec/scene.md section 3a).

export type Action = { type: string } & Record<string, unknown>;
export type Applied = { scene: Scene; notes: string[]; created: string[] };

const BEHAVIOUR_KEYS: Record<string, readonly string[]> = { controller: ["speed", "jump"], collectible: ["points"], patrol: ["from", "to", "speed"] };
const BEHAVIOUR_OF: Partial<Record<ObjectType, string>> = { player: "controller", coin: "collectible", enemy: "patrol" };

const str = (a: Action, key: string) => (typeof a[key] === "string" ? (a[key] as string) : undefined);
const num = (a: Action, key: string) => (typeof a[key] === "number" && Number.isFinite(a[key]) ? (a[key] as number) : undefined);
const label = (type: ObjectType) => type[0]!.toUpperCase() + type.slice(1);

/// The lowest free `<type>-<n>`.
export function freeId(scene: Scene, type: string): string {
  const ids = new Set(scene.objects.map((o) => o.id));
  let n = 1;
  while (ids.has(`${type}-${n}`)) n++;
  return `${type}-${n}`;
}

/// A given name, or with the lowest free number from 2 when another object has it already.
function freeName(scene: Scene, name: string | undefined): string | undefined {
  if (name === undefined) return undefined;
  const names = new Set(scene.objects.map((o) => o.name));
  if (!names.has(name)) return name;
  let n = 2;
  while (names.has(`${name} ${n}`)) n++;
  return `${name} ${n}`;
}

/// Applies a batch in order. Objects it creates are marked as made [by] that member.
export function applyActions(scene: Scene, actions: Action[], by?: string): Applied {
  let s = scene;
  const notes: string[] = [];
  const created: string[] = [];

  const withNumbers = (o: SceneObject, a: Action, behaviour: string | undefined) => {
    if (!behaviour) return o;
    let out = o;
    for (const key of BEHAVIOUR_KEYS[behaviour]!) {
      const v = num(a, key);
      if (v !== undefined) out = withParam(out, behaviour, key, v);
    }
    return out;
  };

  for (const a of actions) {
    switch (a.type) {
      case "CREATE_OBJECT": {
        const type = OBJECT_TYPES.find((t) => t === a.objectType);
        if (!type) continue;
        const size = DEFAULT_SIZES[type];
        const w = num(a, "w") ?? size.w;
        const h = num(a, "h") ?? size.h;
        const x = num(a, "x") ?? (s.size.w - w) / 2;
        const y = num(a, "y") ?? (s.size.h - h) / 2;
        // One player per scene: creating a player moves the one there is.
        const existing = type === "player" ? s.objects.find((o) => o.type === "player") : undefined;
        if (existing) {
          const moved = fit(s, withNumbers({ ...existing, x, y }, a, "controller"));
          s = replace(s, moved);
          notes.push(`~ Moved ${moved.name} to (${Math.round(moved.x)}, ${Math.round(moved.y)})`);
          continue;
        }
        // A given id is used when it is free (undo restores a deleted object this way).
        const wanted = str(a, "id");
        const id = wanted && !byId(s, wanted) ? wanted : freeId(s, type);
        const count = s.objects.filter((o) => o.type === type).length + 1;
        let behaviours = defaultBehaviours(type, x);
        if (type === "enemy") behaviours = { patrol: { from: x, to: Math.min(x + 200, s.size.w - w), speed: 90 } };
        let object: SceneObject = { id, name: freeName(s, str(a, "name")) ?? (count === 1 ? label(type) : `${label(type)} ${count}`), type, x, y, w, h };
        if (Object.keys(behaviours).length) object.behaviours = behaviours;
        if (by) object.by = by;
        object = fit(s, withNumbers(object, a, BEHAVIOUR_OF[type]));
        s = { ...s, objects: [...s.objects, object] };
        created.push(object.id);
        notes.push(`+ ${object.name} at (${Math.round(object.x)}, ${Math.round(object.y)})`);
        break;
      }
      case "UPDATE_OBJECT": {
        const o = byId(s, str(a, "id"));
        if (!o) {
          notes.push(`· Skipped: there is no ${str(a, "id")}`);
          continue;
        }
        let changed: SceneObject = { ...o, name: str(a, "name") ?? o.name, x: num(a, "x") ?? o.x, y: num(a, "y") ?? o.y, w: num(a, "w") ?? o.w, h: num(a, "h") ?? o.h };
        // Moving an enemy takes its patrol along, as a drag does.
        if (o.type === "enemy" && changed.x !== o.x) {
          const shift = changed.x - o.x;
          changed = withParam(changed, "patrol", "from", (param(o, "patrol", "from") ?? o.x) + shift);
          changed = withParam(changed, "patrol", "to", (param(o, "patrol", "to") ?? o.x) + shift);
        }
        changed = fit(s, changed);
        s = replace(s, changed);
        notes.push(`~ Changed ${changed.name}`);
        break;
      }
      case "DELETE_OBJECT": {
        const o = byId(s, str(a, "id"));
        if (!o) {
          notes.push(`· Skipped: there is no ${str(a, "id")}`);
          continue;
        }
        s = { ...s, objects: s.objects.filter((x) => x.id !== o.id) };
        notes.push(`− Removed ${o.name}`);
        break;
      }
      case "ADD_COMPONENT": {
        const o = byId(s, str(a, "id"));
        const behaviour = str(a, "component");
        if (!o || !behaviour || !BEHAVIOUR_KEYS[behaviour]) {
          notes.push("· Skipped a behaviour change");
          continue;
        }
        const changed = fit(s, withNumbers(o, a, behaviour));
        s = replace(s, changed);
        notes.push(`~ Set ${changed.name}'s ${behaviour}`);
        break;
      }
      case "UPDATE_SCENE": {
        const theme = str(a, "theme");
        const name = str(a, "sceneName");
        s = { ...s, name: name ?? s.name, theme: theme && THEMES.includes(theme as never) ? theme : s.theme };
        notes.push(`~ Scene${name !== undefined ? ` renamed to ${name}` : ""}${theme !== undefined ? ` · ${theme} theme` : ""}`);
        break;
      }
      case "UPDATE_UI": {
        if (typeof a.score === "boolean") {
          s = { ...s, ui: { score: a.score } };
          notes.push(`~ Score ${a.score ? "shown" : "hidden"}`);
        }
        break;
      }
    }
  }
  return { scene: s, notes, created };
}

// ---------------------------------------------------------------------------------------------------------------
// Patches: what a change did, object by object, so it can be shown, sent and undone.

export type SceneFields = { name: string; theme: string; score: boolean };
export type Patch = {
  // Each touched object as it ends up; null when the change removes it.
  objects: Record<string, SceneObject | null>;
  scene?: Partial<SceneFields>;
};

const fieldsOf = (s: Scene): SceneFields => ({ name: s.name, theme: s.theme, score: s.ui.score });
const same = (a: unknown, b: unknown) => JSON.stringify(a) === JSON.stringify(b);

/// The patch that turns [before] into [after]. Objects keep the order they have in [after].
export function diff(before: Scene, after: Scene): Patch {
  const objects: Record<string, SceneObject | null> = {};
  const old = new Map(before.objects.map((o) => [o.id, o]));
  for (const o of after.objects) {
    if (!same(old.get(o.id), o)) objects[o.id] = o;
    old.delete(o.id);
  }
  for (const id of old.keys()) objects[id] = null;
  const a = fieldsOf(before);
  const b = fieldsOf(after);
  const scene: Partial<SceneFields> = {};
  for (const key of ["name", "theme", "score"] as const) if (a[key] !== b[key]) (scene as Record<string, unknown>)[key] = b[key];
  return Object.keys(scene).length ? { objects, scene } : { objects };
}

export const isEmpty = (p: Patch) => Object.keys(p.objects).length === 0 && !p.scene;

/// Sets each object in the patch to its state there (null removes it), kept inside the scene. New objects go last.
export function applyPatch(scene: Scene, patch: Patch): Scene {
  const pending = new Map(Object.entries(patch.objects));
  const objects: SceneObject[] = [];
  for (const o of scene.objects) {
    if (!pending.has(o.id)) objects.push(o);
    else {
      const next = pending.get(o.id);
      pending.delete(o.id);
      if (next) objects.push(fit(scene, { ...next, id: o.id }));
    }
  }
  for (const [id, next] of pending) if (next) objects.push(fit(scene, { ...next, id }));
  const f = patch.scene ?? {};
  return {
    ...scene,
    name: typeof f.name === "string" && f.name.trim() ? f.name.trim().slice(0, 60) : scene.name,
    theme: THEMES.includes(f.theme as never) ? f.theme! : scene.theme,
    ui: { score: typeof f.score === "boolean" ? f.score : scene.ui.score },
    objects,
  };
}

/// The patch that puts back what [patch] changed in [before]: undo.
export function inverse(before: Scene, patch: Patch): Patch {
  const objects: Record<string, SceneObject | null> = {};
  for (const id of Object.keys(patch.objects)) objects[id] = byId(before, id) ?? null;
  if (!patch.scene) return { objects };
  const was = fieldsOf(before);
  const scene: Partial<SceneFields> = {};
  for (const key of Object.keys(patch.scene) as (keyof SceneFields)[]) (scene as Record<string, unknown>)[key] = was[key];
  return { objects, scene };
}

/// Lines for people to read about a patch, in the words of the actions.
export function describePatch(before: Scene, patch: Patch): string[] {
  const notes: string[] = [];
  for (const [id, next] of Object.entries(patch.objects)) {
    const old = byId(before, id);
    if (!next) {
      if (old) notes.push(`− Removed ${old.name}`);
    } else if (!old) notes.push(`+ ${next.name} at (${Math.round(next.x)}, ${Math.round(next.y)})`);
    else if (old.x !== next.x || old.y !== next.y) notes.push(`~ Moved ${next.name} to (${Math.round(next.x)}, ${Math.round(next.y)})`);
    else notes.push(`~ Changed ${next.name}`);
  }
  const f = patch.scene;
  if (f?.name !== undefined || f?.theme !== undefined) notes.push(`~ Scene${f.name !== undefined ? ` renamed to ${f.name}` : ""}${f.theme !== undefined ? ` · ${f.theme} theme` : ""}`);
  if (f?.score !== undefined) notes.push(`~ Score ${f.score ? "shown" : "hidden"}`);
  return notes;
}
