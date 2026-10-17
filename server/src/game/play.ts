// Play-mode rules (spec/rules.md sections 4 and 5).

import { cellIndex, inBounds, rasterize, Terrain, type Grid } from "./raster.ts";
import { COLORS, DELTA, type Color, type Direction, type World } from "./types.ts";

export type PlayState = {
  x: number;
  y: number;
  keys: ReadonlySet<Color>;
  // Ids of collected treasures and coins.
  collected: ReadonlySet<string>;
  // Ids of every item taken off the map, keys included.
  taken: ReadonlySet<string>;
  deaths: number;
  won: boolean;
};

export type PlaySnapshot = {
  x: number;
  y: number;
  keys: Color[];
  collected: string[];
  deaths: number;
  won: boolean;
};

export class PlayEngine {
  readonly world: World;
  readonly grid: Grid;

  constructor(world: World) {
    this.world = world;
    this.grid = rasterize(world);
  }

  initialState(deaths = 0): PlayState {
    const spawn: PlayState = {
      x: this.world.start.x,
      y: this.world.start.y,
      keys: new Set(),
      collected: new Set(),
      taken: new Set(),
      deaths,
      won: false,
    };
    return this.pickUp(spawn);
  }

  step(state: PlayState, dir: Direction): PlayState {
    if (state.won) return state;
    const x = state.x + DELTA[dir].x;
    const y = state.y + DELTA[dir].y;
    if (!inBounds(this.grid, x, y)) return state;

    const i = cellIndex(this.grid, x, y);
    const terrain = this.grid.terrain[i];
    if (terrain === Terrain.wall) return state;
    if (terrain === Terrain.door && !state.keys.has(COLORS[this.grid.doorColor[i]!]!)) return state;
    if (terrain === Terrain.lava) return this.initialState(state.deaths + 1);

    const moved = this.pickUp({ ...state, x, y });
    const won = x === this.world.flag.x && y === this.world.flag.y && this.objectivesDone(moved.collected);
    return won ? { ...moved, won } : moved;
  }

  run(inputs: readonly Direction[], from: PlayState = this.initialState()): PlayState {
    return inputs.reduce((s, d) => this.step(s, d), from);
  }

  objectivesDone(collected: ReadonlySet<string>): boolean {
    return this.world.objectives.every((o) => {
      if (o.type === "collect") return collected.has(o.target);
      const coins = this.world.entities.filter((e) => e.type === "coin" && collected.has(e.id)).length;
      return coins >= o.count;
    });
  }

  private pickUp(state: PlayState): PlayState {
    const items = this.grid.items[cellIndex(this.grid, state.x, state.y)]!.filter((it) => !state.taken.has(it.id));
    if (items.length === 0) return state;
    const keys = new Set(state.keys);
    const collected = new Set(state.collected);
    const taken = new Set(state.taken);
    for (const it of items) {
      taken.add(it.id);
      if (it.kind === "key") keys.add(it.color);
      else collected.add(it.id);
    }
    return { ...state, keys, collected, taken };
  }
}

export function snapshot(state: PlayState): PlaySnapshot {
  return {
    x: state.x,
    y: state.y,
    keys: [...state.keys].sort(),
    collected: [...state.collected].sort(),
    deaths: state.deaths,
    won: state.won,
  };
}
