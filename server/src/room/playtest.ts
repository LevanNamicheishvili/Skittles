// Playtest dev mode: what the room records while someone plays, and the report it builds from it.
// The player never has to explain where they are: position, falls, keys and the objects around the
// trouble spot come from the running game, and the report goes to the authors who own those objects.

import type { Cell, Color, Entity, World } from "../game/types.ts";
import type { Op } from "./ops.ts";

export type Fall = { x: number; y: number; rev: number; at: number };

export type Suspect = { id: string; type: Entity["type"]; ownerId?: string; mediator?: boolean; label?: string; distance: number };

export type PlaytestReport = {
  id: string;
  by: string;
  kind: "player" | "signal";
  text: string;
  at: number;
  rev: number;
  // Where the trouble is: the last recent fall, otherwise where the player stands.
  spot: Cell;
  position: Cell;
  keys: Color[];
  fallsHere: number;
  falls: number;
  trail: Cell[];
  suspects: Suspect[];
  routedTo: string[];
};

export type Suggestion = {
  id: string;
  authorId: string;
  reportId: string;
  status: "drafting" | "open" | "applied" | "dismissed" | "failed";
  message?: string;
  summary?: string;
  ops?: Op[];
  note?: string;
};

// How far a rectangle is from a cell, in steps; 0 when it covers the cell.
function distanceTo(e: Entity, c: Cell): number {
  const w = "w" in e ? e.w : 1;
  const h = "h" in e ? e.h : 1;
  const dx = Math.max(e.x - c.x, 0, c.x - (e.x + w - 1));
  const dy = Math.max(e.y - c.y, 0, c.y - (e.y + h - 1));
  return dx + dy;
}

const TROUBLE: Entity["type"][] = ["lava", "wall", "castle", "door", "bridge", "key"];

// The objects most likely behind a problem at `spot`: close ones first, the authors' own before the base level's.
export function suspectsNear(world: World, spot: Cell, radius = 2): Suspect[] {
  return world.entities
    .filter((e) => TROUBLE.includes(e.type))
    .map((e) => ({ id: e.id, type: e.type, ownerId: e.owner.playerId, mediator: e.owner.kind === "mediator", label: e.label, distance: distanceTo(e, spot) }))
    .filter((s) => s.distance <= radius)
    .sort((a, b) => a.distance - b.distance || Number(b.ownerId !== undefined) - Number(a.ownerId !== undefined))
    .slice(0, 3);
}

// Everything a report says, as text an agent can act on.
export function describeReport(r: PlaytestReport, nameOf: (id: string | undefined) => string): string {
  const lines = [
    r.kind === "player" ? `${nameOf(r.by)} reported while playing version v${r.rev}: "${r.text}"` : `Dev mode noticed while ${nameOf(r.by)} was playing v${r.rev}: ${r.text}`,
    `Trouble spot: (${r.spot.x}, ${r.spot.y}). Player now at (${r.position.x}, ${r.position.y}), keys: ${r.keys.join(", ") || "none"}.`,
    `Falls into lava this run: ${r.falls}, at the trouble spot: ${r.fallsHere}.`,
    `Recent path: ${r.trail.map((c) => `(${c.x},${c.y})`).join(" ") || "none"}.`,
    r.suspects.length
      ? `Objects at the spot: ${r.suspects.map((s) => `${s.id} ${s.type}${s.label ? ` "${s.label}"` : ""} by ${s.mediator ? "the mediator" : nameOf(s.ownerId)}, ${s.distance} steps away`).join("; ")}.`
      : "No objects near the spot.",
  ];
  return lines.join("\n");
}
