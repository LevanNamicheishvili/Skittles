// Shape checks against the shared JSON schemas in spec/schema.

import { readFileSync } from "node:fs";
import { join } from "node:path";
import { Ajv2020 } from "ajv/dist/2020.js";

const specDir = join(import.meta.dirname, "..", "..", "..", "spec");
const load = (path: string): object => JSON.parse(readFileSync(join(specDir, path), "utf8")) as object;

const ajv = new Ajv2020({ strict: true });
ajv.addSchema(load("schema/world.schema.json"));
const worldValidator = ajv.getSchema("https://github.com/LevanNamicheishvili/Skittles/blob/main/spec/schema/world.schema.json")!;

// Returns null when the world matches the schema, otherwise a short reason.
export function checkWorldShape(world: unknown): string | null {
  if (worldValidator(world)) return null;
  const err = worldValidator.errors?.[0];
  return err ? `${err.instancePath || "world"} ${err.message ?? "is invalid"}` : "world is invalid";
}
