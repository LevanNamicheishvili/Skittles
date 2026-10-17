// Types mirror spec/schema/world.schema.json. Semantics: spec/rules.md.

export type Color = "red" | "blue" | "gold";

export const COLORS: readonly Color[] = ["red", "blue", "gold"];

export type Cell = { x: number; y: number };

export type Owner = {
  kind: "player" | "assistant" | "mediator" | "system";
  playerId?: string;
};

type EntityBase = { id: string; owner: Owner; label?: string; icon?: string };

export type RectEntity = EntityBase & {
  type: "wall" | "lava" | "bridge";
  x: number;
  y: number;
  w: number;
  h: number;
};

export type CastleDoor = {
  side: "left" | "right" | "top" | "bottom";
  offset: number;
  color: Color | null;
};

export type CastleEntity = EntityBase & {
  type: "castle";
  x: number;
  y: number;
  w: number;
  h: number;
  door: CastleDoor;
};

export type ItemEntity = EntityBase & { type: "treasure" | "coin"; x: number; y: number };

export type KeyEntity = EntityBase & { type: "key"; x: number; y: number; color: Color };

export type DoorEntity = EntityBase & { type: "door"; x: number; y: number; color: Color };

export type Entity = RectEntity | CastleEntity | ItemEntity | KeyEntity | DoorEntity;

export type Objective =
  | { type: "collect"; target: string }
  | { type: "collect_count"; item: "coin"; count: number };

export type World = {
  schemaVersion: 1;
  grid: { w: number; h: number };
  start: Cell;
  flag: Cell;
  entities: Entity[];
  objectives: Objective[];
};

export type Direction = "up" | "down" | "left" | "right";

export const DIRECTIONS: readonly Direction[] = ["up", "down", "left", "right"];

export const DELTA: Readonly<Record<Direction, Cell>> = {
  up: { x: 0, y: -1 },
  down: { x: 0, y: 1 },
  left: { x: -1, y: 0 },
  right: { x: 1, y: 0 },
};
