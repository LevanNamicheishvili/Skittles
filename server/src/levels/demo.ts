// The starting level for the stage demo. It is prepared in advance and we say so on stage.

import type { World } from "../game/types.ts";

const system = { kind: "system" } as const;

export function demoLevel(): World {
  return {
    schemaVersion: 1,
    grid: { w: 24, h: 14 },
    start: { x: 1, y: 7 },
    flag: { x: 22, y: 7 },
    entities: [
      // A border of rocks so the map reads as a place, not an empty sheet.
      { id: "S1", type: "wall", owner: system, x: 0, y: 0, w: 24, h: 1, label: "North cliffs" },
      { id: "S2", type: "wall", owner: system, x: 0, y: 13, w: 24, h: 1, label: "South cliffs" },
      { id: "S3", type: "wall", owner: system, x: 5, y: 3, w: 2, h: 2, label: "Boulders" },
      { id: "S4", type: "wall", owner: system, x: 16, y: 9, w: 3, h: 2, label: "Boulders" },
    ],
    objectives: [],
  };
}
