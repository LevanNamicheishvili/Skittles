// What an author's agent sees before each request, and how its tool input becomes room ops.

import { toAscii } from "../game/raster.ts";
import type { Color, Entity, World } from "../game/types.ts";
import type { Op } from "../room/ops.ts";
import type { LogEntry, Room } from "../room/room.ts";

// One op as the model writes it: a flat record, so the schema stays simple for the model.
export type AgentOp = {
  op: "create" | "update" | "delete" | "set_flag" | "set_start";
  id?: string | null;
  type?: Entity["type"] | null;
  x?: number | null;
  y?: number | null;
  w?: number | null;
  h?: number | null;
  color?: Color | null;
  door_side?: "left" | "right" | "top" | "bottom" | null;
  door_offset?: number | null;
  label?: string | null;
};

export type ChangeInput = { message: string; summary: string; ops: AgentOp[] };

const placeholder = { kind: "system" } as const;

const num = (v: number | null | undefined, fallback: number): number => (typeof v === "number" && Number.isFinite(v) ? Math.round(v) : fallback);

// Throws with a message the model can act on.
export function toOps(input: ChangeInput, world: World): Op[] {
  if (!Array.isArray(input.ops) || input.ops.length === 0) throw new Error("ops must be a non-empty list");
  return input.ops.map((a, i): Op => {
    const where = `ops[${i}]`;
    switch (a.op) {
      case "create": {
        if (!a.type) throw new Error(`${where}: create needs a type`);
        if (a.x == null || a.y == null) throw new Error(`${where}: create needs x and y`);
        const base = { id: a.id || `new${i}`, owner: placeholder, x: num(a.x, 0), y: num(a.y, 0), ...(a.label ? { label: a.label.slice(0, 40) } : {}) };
        if (a.type === "castle") {
          return {
            op: "create",
            entity: {
              ...base,
              type: "castle",
              w: num(a.w, 5),
              h: num(a.h, 5),
              door: { side: a.door_side ?? "left", offset: num(a.door_offset, 0), color: a.color ?? null },
            },
          };
        }
        if (a.type === "wall" || a.type === "lava" || a.type === "bridge") {
          return { op: "create", entity: { ...base, type: a.type, w: num(a.w, 1), h: num(a.h, 1) } };
        }
        if (a.type === "key" || a.type === "door") return { op: "create", entity: { ...base, type: a.type, color: a.color ?? "gold" } };
        if (a.type === "treasure" || a.type === "coin") return { op: "create", entity: { ...base, type: a.type } };
        throw new Error(`${where}: unknown type ${String(a.type)}`);
      }
      case "update": {
        if (!a.id) throw new Error(`${where}: update needs the id of an existing object`);
        const target = world.entities.find((e) => e.id === a.id);
        const set: Record<string, unknown> = {};
        for (const k of ["x", "y", "w", "h"] as const) if (a[k] != null) set[k] = num(a[k], 0);
        if (a.label) set.label = a.label.slice(0, 40);
        if (target?.type === "castle") {
          if (a.door_side != null || a.door_offset != null || a.color !== undefined) {
            set.door = {
              side: a.door_side ?? target.door.side,
              offset: num(a.door_offset, target.door.offset),
              color: a.color === undefined ? target.door.color : a.color,
            };
          }
        } else if (a.color) set.color = a.color;
        if (Object.keys(set).length === 0) throw new Error(`${where}: update changes nothing`);
        return { op: "update", id: a.id, set };
      }
      case "delete":
        if (!a.id) throw new Error(`${where}: delete needs an id`);
        return { op: "delete", id: a.id };
      case "set_flag":
      case "set_start": {
        if (a.x == null || a.y == null) throw new Error(`${where}: ${a.op} needs x and y`);
        const cell = { x: num(a.x, 0), y: num(a.y, 0) };
        return { op: "set_world", set: a.op === "set_flag" ? { flag: cell } : { start: cell } };
      }
      default:
        throw new Error(`${where}: unknown op ${String((a as { op: unknown }).op)}`);
    }
  });
}

function describeEntity(e: Entity, owner: string): string {
  const where = "w" in e ? `x=${e.x} y=${e.y} w=${e.w} h=${e.h}` : `x=${e.x} y=${e.y}`;
  const extra =
    e.type === "castle" ? ` door=${e.door.side}+${e.door.offset} ${e.door.color ?? "open"}` : e.type === "key" || e.type === "door" ? ` ${e.color}` : "";
  return `- ${e.id} ${e.type} ${where}${extra} (by ${owner})${e.label ? ` "${e.label}"` : ""}`;
}

function describeEntry(entry: LogEntry, room: Room): string {
  const parts = [`v${entry.rev} by ${room.nameOf(entry.by)}: ${entry.summary}`];
  if (entry.fix && entry.fix.ops.length > 0) parts.push(`  mediator fix: ${entry.fix.summary}`);
  return parts.join("\n");
}

const ownerName = (e: Entity, room: Room): string =>
  e.owner.kind === "mediator" ? "the mediator" : e.owner.playerId ? room.nameOf(e.owner.playerId) : "the base level";

export function levelContext(room: Room, authorId: string, sinceRev: number): string {
  const { world, rev } = room;
  const me = room.nameOf(authorId);
  const others = [...room.members.values()].filter((m) => m.role === "author" && m.id !== authorId).map((m) => m.name);
  const ascii = toAscii(world);
  const tens = "    " + Array.from({ length: world.grid.w }, (_, x) => (x % 10 === 0 ? String(x / 10) : " ")).join("");
  const ones = "    " + Array.from({ length: world.grid.w }, (_, x) => String(x % 10)).join("");
  const rows = ascii.map((row, y) => `${String(y).padStart(3)} ${row}`);
  const solve = room.solveResult;
  const status = solve.solvable
    ? `winnable in ${solve.steps} steps`
    : `NOT winnable, unreachable: ${solve.unreachable.join(", ")}`;
  const theirs = room.log.filter((e) => e.rev > sinceRev && e.by !== authorId).map((e) => describeEntry(e, room));
  const chat = (room.chats.get(authorId) ?? []).slice(-7, -1).map((m) => `${m.from}: ${m.text}`);
  return [
    `You work for ${me}.${others.length ? ` The other author: ${others.join(", ")}.` : ""}`,
    `Level version v${rev}, grid ${world.grid.w}x${world.grid.h}. Start S=(${world.start.x},${world.start.y}), flag F=(${world.flag.x},${world.flag.y}). Status: ${status}.`,
    "",
    "Map:",
    tens,
    ones,
    ...rows,
    "",
    "Objects:",
    ...world.entities.map((e) => describeEntity(e, ownerName(e, room))),
    "",
    theirs.length ? `Changes by others since your last request:\n${theirs.join("\n")}` : "No changes by others since your last request.",
    chat.length ? `\nRecent conversation with ${me}:\n${chat.join("\n")}` : "",
  ].join("\n");
}
