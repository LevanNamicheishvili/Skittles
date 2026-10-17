// Document operations (spec/protocol.md section 2). A batch applies atomically or not at all.

import type { CastleDoor, Cell, Color, Entity, Objective, World } from "../game/types.ts";
import { validateWorld } from "../game/validate.ts";
import { checkWorldShape } from "./schema.ts";

export type EntityPatch = {
  x?: number;
  y?: number;
  w?: number;
  h?: number;
  color?: Color;
  door?: CastleDoor;
  label?: string;
  icon?: string;
};

export type Op =
  | { op: "create"; entity: Entity }
  | { op: "update"; id: string; set: EntityPatch }
  | { op: "delete"; id: string }
  | { op: "set_world"; set: { start?: Cell; flag?: Cell } }
  | { op: "set_objectives"; objectives: Objective[] }
  // Internal: a revert replaces the whole document so the log stays replayable.
  | { op: "replace_world"; world: World };

export type ApplyResult = { ok: true; world: World } | { ok: false; code: string; message: string };

const RECT = ["x", "y", "w", "h", "label", "icon"] as const;
const CELL = ["x", "y", "label", "icon"] as const;
const EDITABLE: Record<Entity["type"], readonly string[]> = {
  wall: RECT,
  lava: RECT,
  bridge: RECT,
  castle: [...RECT, "door"],
  door: [...CELL, "color"],
  key: [...CELL, "color"],
  treasure: CELL,
  coin: CELL,
};

const fail = (code: string, message: string): ApplyResult => ({ ok: false, code, message });

export function applyOps(world: World, ops: readonly Op[]): ApplyResult {
  let next: World = structuredClone(world);
  for (const op of ops) {
    switch (op.op) {
      case "create":
        if (next.entities.some((e) => e.id === op.entity.id)) return fail("duplicate_id", `${op.entity.id} already exists`);
        next.entities.push(structuredClone(op.entity));
        break;
      case "update": {
        const i = next.entities.findIndex((e) => e.id === op.id);
        if (i < 0) return fail("unknown_id", `there is no object ${op.id}`);
        const e = next.entities[i]!;
        const bad = Object.keys(op.set).find((k) => !EDITABLE[e.type].includes(k));
        if (bad) return fail("not_editable", `${bad} cannot be changed on a ${e.type}`);
        next.entities[i] = { ...e, ...structuredClone(op.set) } as Entity;
        break;
      }
      case "delete": {
        const i = next.entities.findIndex((e) => e.id === op.id);
        if (i < 0) return fail("unknown_id", `there is no object ${op.id}`);
        next.entities.splice(i, 1);
        // An objective cannot outlive its target.
        next.objectives = next.objectives.filter((o) => !(o.type === "collect" && o.target === op.id));
        break;
      }
      case "set_world":
        if (op.set.start) next.start = { ...op.set.start };
        if (op.set.flag) next.flag = { ...op.set.flag };
        break;
      case "set_objectives":
        next.objectives = structuredClone(op.objectives);
        break;
      case "replace_world":
        next = structuredClone(op.world);
        break;
    }
  }
  const shape = checkWorldShape(next);
  if (shape) return fail("invalid_shape", shape);
  const { errors } = validateWorld(next);
  if (errors.length > 0) return fail(errors[0]!.code, errors[0]!.message);
  return { ok: true, world: next };
}

// A short English description of a batch, used when the author gave none.
export function describeOps(ops: readonly Op[]): string {
  const parts = ops.map((op) => {
    switch (op.op) {
      case "create": {
        const e = op.entity;
        const size = "w" in e ? ` ${e.w}×${e.h}` : "";
        return `added ${e.type}${size} at (${e.x}, ${e.y})`;
      }
      case "update":
        return `changed ${op.id}`;
      case "delete":
        return `removed ${op.id}`;
      case "set_world":
        return op.set.flag ? `moved the flag to (${op.set.flag.x}, ${op.set.flag.y})` : "moved the start";
      case "set_objectives":
        return "changed the objectives";
      case "replace_world":
        return "restored an earlier version";
    }
  });
  return parts.join(", ");
}
