# Scenes, version 1

A scene is the document the Skittles studio edits: a 2D world of objects with positions, sizes and behaviours. This spec is normative for every implementation (the Flutter studio today, the room server next). Shared cases live in `fixtures/scenes.json`. If code and this document disagree, the code is wrong.

The grid levels in `rules.md` stay as they are; they become the "grid adventure" template later. This document is the "platformer" template.

## 1. Coordinates

Pixels. x grows to the right from 0, y grows down from 0. An object's `x`, `y` is its top-left corner; `w`, `h` its size. Everything lies inside the scene's `size`.

## 2. The document

```json
{
  "format": "skittles-scene",
  "version": 1,
  "name": "Forest platformer",
  "template": "platformer",
  "size": { "w": 1600, "h": 900 },
  "theme": "forest",
  "physics": { "gravity": 1800 },
  "objects": [
    { "id": "player", "name": "Player", "type": "player", "x": 80, "y": 772, "w": 32, "h": 48,
      "behaviours": { "controller": { "speed": 260, "jump": 640 } } }
  ],
  "ui": { "score": true }
}
```

| Field | Meaning |
| --- | --- |
| `format`, `version` | Always `"skittles-scene"` and `1` |
| `name` | Shown in the studio's title bar |
| `template` | `"platformer"` in version 1 |
| `size` | The world, in pixels |
| `theme` | `forest`, `desert` or `night`: only the look |
| `physics.gravity` | Pixels per second², default 1800 |
| `objects` | Drawn in order: later objects are on top |
| `ui.score` | Show the score in the preview |

## 3. Objects and behaviours

Game logic is data: each type comes with behaviours whose numbers can be changed, never with code.

| Type | Default size | Behaviour | Parameters (defaults) |
| --- | --- | --- | --- |
| `player` | 32 × 48 | `controller`: moves and jumps | `speed` 260 px/s, `jump` 640 px/s (take-off speed) |
| `platform` | 192 × 24 | `solid`: stands still, the player stands on it | none |
| `coin` | 24 × 24 | `collectible`: disappears when touched, adds points | `points` 10 |
| `enemy` | 40 × 36 | `patrol`: walks between two x positions; touching it sends the player back to the start | `from`, `to` (x of its left edge), `speed` 90 px/s |
| `finish` | 60 × 120 | `goal`: touching it wins | none |

Each object has a unique `id` and a `name` (shown in the hierarchy). In a shared project it may also carry `by`, the member id of whoever created it, so the studio can show authorship.

## 3a. Actions

People's tools and the AI change a scene with the same actions. A batch applies in order; an action that names a missing object is skipped with a note, the rest still apply. Every result is kept inside the scene (section 1) and to its rules.

| Action | Fields | What it does |
| --- | --- | --- |
| `CREATE_OBJECT` | `objectType`, `x`, `y`, optional `w`, `h`, `name` and behaviour numbers | Adds an object with the type's default size and behaviours. Its id is the `id` given when that is free, otherwise `<type>-<n>` (the lowest free n); its name is the `name` given, otherwise the type, numbered from the second one on. A given name another object already has gets the lowest free number from 2 (`Coin 2`, `Coin 3`). Creating a player when there is one moves that player instead |
| `UPDATE_OBJECT` | `id` and any of `name`, `x`, `y`, `w`, `h` | Moving an enemy moves its patrol by the same amount |
| `DELETE_OBJECT` | `id` | Removes it |
| `ADD_COMPONENT` | `id`, `component` and its numbers | `controller`: `speed`, `jump`; `collectible`: `points`; `patrol`: `from`, `to`, `speed` |
| `UPDATE_SCENE` | `sceneName`, `theme` | Renames the scene, changes its look |
| `UPDATE_UI` | `score` | Shows or hides the score |

Each applied action leaves one line for people to read; `fixtures/actions.json` fixes their wording.

## 4. Validation

**Errors** stop a change.

| Code | Error |
| --- | --- |
| `no_player` | There is no player |
| `many_players` | There is more than one player |
| `no_finish` | There is no finish |
| `duplicate_id` | Two objects share an id |
| `out_of_bounds` | An object is not entirely inside the scene |
| `bad_size` | An object's width or height is below 8 px |
| `bad_patrol` | An enemy's `from` is greater than its `to`, or its range leaves the scene |
| `player_falls` | Below the player there is no platform: it falls out of the world |
| `finish_unreachable` | No sequence of runs and jumps gets the player to the finish (section 5) |

**Warnings** do not stop a change; the studio shows them.

| Code | Warning |
| --- | --- |
| `coin_unreachable` | The player cannot reach this coin |
| `player_in_platform` | The player overlaps a platform |
| `enemy_on_start` | An enemy's patrol passes through where the player starts |

## 5. Reachability

The promise of Skittles, for platformers: no change goes live that makes the finish unreachable. The check is deliberately simple and conservative.

**Jump.** With take-off speed `v`, run speed `s` and gravity `g`:

- the highest jump is `H = v² / (2g)`;
- to land `dh` pixels higher (`dh ≤ H`; negative means lower), the player is in the air for `t = (v + √(v² − 2g·dh)) / g`;
- in that time it covers `s · t` horizontally; reachability uses 90% of that, `reach(dh) = 0.9 · s · t`.

**Surfaces.** The top edge of each platform is a surface: from its left `x` to its right `x + w`, at height `y`. The player starts on the first surface straight below it (the one whose top is nearest below the player's feet and that overlaps it horizontally); if there is none, that is `player_falls`.

**Moves.** From surface A the player can get to surface B when B's top is at most `H` above A's (`A.y − B.y ≤ H`) and the horizontal gap between them, `max(0, B.left − A.right, A.left − B.right)`, is at most `reach(A.y − B.y)`. Walking off an edge onto anything lower is covered by the same rule. Reachable surfaces are found by a breadth-first search from the start surface.

**Touching.** From a reachable surface the player can touch any point whose x lies within `reach(0) / 2` of the surface's ends and whose y lies between the surface and `H + player height` above it. The finish is reachable when its rectangle contains such a point for some reachable surface; a coin likewise.

**When it runs.** Only with exactly one player and at least one finish. If the player falls (`player_falls`), the check stops there: nothing is reachable and `finish_unreachable` is not added. Other errors do not stop it. Coins are checked only when it runs.

**What it does not model yet:** ceilings that cut a jump short, enemies (they never block reachability), and moving platforms. The studio says so in the docs; the preview remains the final word.

## 6. Shared projects

A project is one scene on the server, which is its only writer.

- **Changes.** Every change gets the next version, its author and a patch: each object it touched as it ends up, or null when it removed it, and the scene fields it set (`name`, `theme`, `score`). A person's tool sends a patch; an agent's actions are applied on the server (section 3a) and recorded as a patch. Objects a person creates are listed as new; if a teammate took the id meanwhile, the next free one is used.
- **Authorship.** A new object's `by` is its creator's member id, or `agent:<id>` for that member's agent. It never changes.
- **Undo** reverts your own last change, never a teammate's: each object it touched goes back to how it was. Any change can also be reverted by name (the Undo on an agent's report).
- **Agents.** Each member has one. A request comes from its owner or, as `@Name's agent` in the team chat, from a teammate; it is carried out at once and shown in the owner's thread. A change that would add an error (section 4) is retried once with the reason, then held until the owner or whoever asked applies or discards it.

