// Semantic validation (spec/rules.md section 7). Shape is checked separately by the JSON schema.

import { cellIndex, inBounds, isBlockedTerrain, rasterize } from "./raster.ts";
import type { Cell, World } from "./types.ts";

export type Issue = { code: string; message: string; id?: string };

export type ValidationResult = { errors: Issue[]; warnings: Issue[] };

const MAX_COLLECTIBLES = 8;

export function validateWorld(world: World): ValidationResult {
  const errors: Issue[] = [];
  const warnings: Issue[] = [];
  const { grid } = world;
  const cellInBounds = (c: Cell): boolean => inBounds(grid, c.x, c.y);

  if (!cellInBounds(world.start)) errors.push({ code: "out_of_bounds", message: "start is outside the grid" });
  if (!cellInBounds(world.flag)) errors.push({ code: "out_of_bounds", message: "flag is outside the grid" });
  if (world.start.x === world.flag.x && world.start.y === world.flag.y) {
    errors.push({ code: "start_equals_flag", message: "start and flag are the same cell" });
  }

  const seen = new Set<string>();
  let collectibles = 0;
  for (const e of world.entities) {
    if (seen.has(e.id)) errors.push({ code: "duplicate_id", message: `duplicate id ${e.id}`, id: e.id });
    seen.add(e.id);

    const w = "w" in e ? e.w : 1;
    const h = "h" in e ? e.h : 1;
    if (!cellInBounds({ x: e.x, y: e.y }) || !cellInBounds({ x: e.x + w - 1, y: e.y + h - 1 })) {
      errors.push({ code: "out_of_bounds", message: `${e.id} extends outside the grid`, id: e.id });
    }
    if (e.type === "castle") {
      const span = e.door.side === "left" || e.door.side === "right" ? e.h : e.w;
      if (e.door.offset > span - 3) {
        errors.push({ code: "invalid_castle_door", message: `${e.id} door offset must be 0..${span - 3}`, id: e.id });
      }
    }
    if (e.type === "treasure" || e.type === "coin") collectibles++;
  }
  if (collectibles > MAX_COLLECTIBLES) {
    errors.push({ code: "collectible_limit", message: `${collectibles} treasures and coins, limit is ${MAX_COLLECTIBLES}` });
  }

  for (const o of world.objectives) {
    if (o.type !== "collect") continue;
    const target = world.entities.find((e) => e.id === o.target);
    if (!target || (target.type !== "treasure" && target.type !== "coin")) {
      errors.push({ code: "objective_target", message: `collect target ${o.target} is not a treasure or coin`, id: o.target });
    }
  }

  // Warnings need a rasterized grid, which is only meaningful once positions are valid.
  if (errors.some((e) => e.code === "out_of_bounds")) return { errors, warnings };
  const raster = rasterize(world);
  for (const [name, c] of [["start", world.start], ["flag", world.flag]] as const) {
    if (isBlockedTerrain(raster.terrain[cellIndex(raster, c.x, c.y)]!)) {
      warnings.push({ code: "protected_cell", message: `${name} is on a wall or lava` });
    }
  }
  for (const e of world.entities) {
    if (e.type !== "key" && e.type !== "treasure" && e.type !== "coin") continue;
    if (isBlockedTerrain(raster.terrain[cellIndex(raster, e.x, e.y)]!)) {
      warnings.push({ code: "item_on_blocked", message: `${e.id} lies on a wall or lava`, id: e.id });
    }
    if (e.x === world.start.x && e.y === world.start.y) {
      warnings.push({ code: "item_on_start", message: `${e.id} lies on the start cell`, id: e.id });
    }
  }
  return { errors, warnings };
}
