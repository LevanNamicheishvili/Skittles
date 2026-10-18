<!-- page: intro; group: Getting started -->
# What is Skittles

Skittles is a live room where a team builds one game world together. Each person talks to their own AI agent in plain words, by text or voice, in English or Georgian. Every agent sees what the others changed, a solver checks every change before it goes live, and someone can play the world while it changes.

## The problem it solves

Syncing bytes between people is solved: Figma, Google Docs and CRDTs do it well. Syncing **intent** is not. When several people edit one thing through their own agents, the dangerous conflict is rarely two edits to the same line. It is two edits that are each correct and together break the goal.

| Nino's change | Giorgi's change | Together |
| --- | --- | --- |
| A lava river with one gap | A statue in the middle | The statue lands in the gap |
| ✓ winnable | ✓ winnable | ✗ the flag is unreachable |

Git sees no conflict here, and neither does a CRDT: the two changes never touch the same bytes. Skittles sees it, because in a game level "does the goal still hold?" is a question a machine can answer, in well under a millisecond.

## What happens instead

1. The change that would break the level is held back. Nothing goes live.
2. The board shows where the route breaks and names who closed what.
3. A mediator offers fixes the solver has already checked, such as a bridge.
4. The agent of the author whose work is in the way proposes a compromise.
5. The humans decide. A fix that touches someone's work needs their approval.

## Who it is for

- **Creators**, any number of them, who build together, each with their own agent.
- **Playtesters**, who play the world while it changes and report trouble from inside the game.
- **Presenters**, who put the whole room on a projector.

Skittles was built for Hacktoberfest Georgia 2026, Track 02: multiplayer agentic experiences.

<!-- page: quickstart -->
# Quickstart

## Requirements

- Node 24 or newer.
- Either the Claude Code CLI signed in on this machine (`claude`), or an `ANTHROPIC_API_KEY`.
- Chrome or Edge, if you want to talk to your agent by voice.

## Run it

```bash
cd server && npm install && npm test
cd ../web && npm install && npm run build
cd ../server && PORT=3001 npm start
```

The server prints `Skittles room on http://localhost:3001`.

## Open the room

Open `http://localhost:3001/`, type your name and press **Start creating**. Everyone who opens the same address joins the same room. On one network, send your team this machine's IP address instead of `localhost`.

You can also join straight from a link:

| Who | Link |
| --- | --- |
| A creator | `http://localhost:3001/?role=author&name=Nino` |
| A playtester | `http://localhost:3001/?role=player&name=Luka` |
| The projector | `http://localhost:3001/?role=stage` |

## Your first change

Type a request to your agent and press Enter, for example:

> Add a lava river across the middle with one gap.

In a few seconds your agent's cursor flies to the spot, the lava appears in your colour, and the status at the top still says **Winnable**. Now ask a teammate to add something next to it, and watch their agent work around your river.

<!-- page: agent; group: Using Skittles -->
# Talking to your agent

Your agent is yours: only you talk to it, and it builds what you ask for. It never writes code. It turns your words into a few structured changes, called ops, and the room checks them before anything goes live.

## Asking

Type in the box under **Your agent** and press Enter or **Send**. To speak instead, click the microphone, talk, and click it again. Pick **EN** or **KA** for voice. Your agent answers in the language you used.

Good requests say what and roughly where:

- "A lava river down the middle, leave one gap."
- "Lock the flag in a castle with a red door, and hide the red key in the top-left corner."
- "Move my statue two cells to the right."
- "შუაში ლავის მდინარე გააკეთე, ერთი გასასვლელი დატოვე."

## What you can build

| Object | Shape | What it does |
| --- | --- | --- |
| Wall | Rectangle | Blocks the way |
| Lava | Rectangle | Sends the player back to the start |
| Bridge | Rectangle | Makes the lava under it walkable |
| Castle | Rectangle, at least 3×3 | Its outline is walls with one door: an open gateway, or locked in red, blue or gold |
| Door | One cell | Locked; opens with the key of its colour |
| Key | One cell | Red, blue or gold; picked up by walking onto it |
| Treasure, coin | One cell | Items to collect |

Your agent can also move the start and the flag, move or resize an object, and delete one.

## What it declines

Skittles v1 has no enemies, physics, sounds or new object types. If you ask for one, your agent says so and suggests what is possible instead. Nothing changes.

## While it works

Your agent's cursor flies to where it is building and shows "thinking…". New objects pop in your colour, and the history gets a line in your name.

<!-- page: together -->
# Building with others

A room has no fixed number of creators. Each one gets a letter and a colour: A blue, B orange, C green, D red, and then the colours repeat. Everything they build carries that colour and letter.

## What your agent knows

Before every request, your agent gets the current level and every change the others made since your last request, with their names. So it can tell you "that corner is behind Nino's lava" before you find out the hard way.

Your agent respects other people's work. It does not move or delete their objects unless you ask it to, and then it tells you.

## Presence

- **Chips** at the top list everyone who has joined the room.
- **Cursors** labelled with each agent's name, such as "Nino's agent", fly to where that agent is building, live.
- **Authorship** stays on every object: its colour and letter tell you who made it.

## Changes in order

Two agents can answer at the same moment. The room takes their changes one at a time and checks each against the newest level, so nobody overwrites anybody by accident.

<!-- page: conflicts -->
# When changes conflict

A change is a conflict when the level was winnable before it and is not after it. Such a change is held back. It never goes live on its own.

## What you see

- The status at the top turns red: **Blocked · flag unreachable**.
- The ghost runner, which walks the solver's route after every version, crashes into the problem: **ROUTE BLOCKED**.
- The objects in the way pulse red, and the held change shows as a hologram in its author's colour.
- A **Mediator** card names who closed what, for example: Giorgi's statue closes the old route, and Nino's lava leaves no way around.

## Your options

The author whose change is held picks one. Hover an option to preview it on the board.

| Option | What it does |
| --- | --- |
| Build a stone bridge | Bridges the lava where it gives the shortest route |
| Move an item | Puts a key, treasure or coin that cannot be reached where the player can reach it |
| Add a key | Adds a key of the colour a locked door needs, on the player's side |
| A compromise | Proposed by the agent of the author whose work is in the way |
| Cancel my change | Keeps the level as it is |

The solver has checked every option before you see it. The mediator never offers a fix that does not work.

## Approval

If a fix covers or changes someone else's object, a bridge over their lava for example, they are asked to approve it. If they decline, that option disappears and you pick again. When everyone has approved, your change and the fix go live together, as one version.

<!-- page: history -->
# History and time travel

Every change that goes live becomes a version: v1, v2, v3 and so on. Each one records who made it and a one-line summary. The history only grows.

## Going back

Press **Restore** on an earlier version in **History**. Restoring erases nothing: it adds a new version equal to the old one, so you can always go forward again.

## Time travel

Drag the **TIME TRAVEL** slider to look at any past version without changing the live level. **Back to live** returns to now.

## Replay build

**Replay build** plays the whole log from v0, with each author's cursor building their part in order. It is a good way to show how a level came together.

<!-- page: playtest -->
# Playtesting

A playtester plays the live world while the creators keep building. Changes appear in the running game without a restart.

## Playing

Move with the arrow keys or WASD, and press **R** to start over. Lava sends you back to the start and puts every item back in its place. Keys are never used up, so a door of that colour always lets you through.

If a change would put a wall, lava or a locked door right where you stand, it waits until you step away. The creator sees: "The player is standing where this change lands. It goes live as soon as they step away."

## Reporting a problem

- Press **F** or **Report a problem**, and type what is wrong.
- Or hold **V** and say it.
- Fall into lava twice at the same spot, and dev mode reports it for you.

Each report carries your position, recent path, falls, keys and the version, plus the objects at the trouble spot. It goes to the creator who owns the closest object there, not to everyone.

## Fixes

That creator's agent drafts a fix straight away, and the room checks it. The creator sees a **Suggested fix** card, hovers it to preview the change on the board, and applies it with one click, while you keep playing.

<!-- page: presenting -->
# Presenting

Open `?role=stage` on the projector. The stage screen shows the board large, the chats of the two authors who spoke most recently, and the history. It does not edit anything itself.

- Click the status, for example **Winnable · 21 steps**, to run the ghost runner again.
- **Show route** draws the solver's route on the board.
- **Reset demo** returns the room to the prepared level and clears the log and the chats. People stay in the room.
- Press `` ` `` or **{ }** for the nerd console: the raw op log as JSON, the validator's time in milliseconds, and a live check that the log replays to the live state.
- **Sound on** turns the sound effects on and off.

<!-- page: room; group: How it works -->
# The room

Every change goes through one room, one at a time.

```text
 Creator A (browser)       Playtester (browser)       Creator B (browser)
   chat / voice               arrows, F, V              chat / voice
        │ agent:say                │ play:move               │
        ▼                          ▼                         ▼
 ┌──────────────────────────── Socket.IO ─────────────────────────────┐
 │ Room (single writer) ── ops ──▶ validate ──▶ solver ──▶ commit ────┼──▶ everyone
 │   append-only log, versions, authorship, safe-point deferral       │
 │   held conflicts ──▶ mediator (diagnosis + checked fixes)          │
 │   playtest reports ──▶ the owner of the trouble spot               │
 └───────▲───────────────────────────▲──────────────────▲─────────────┘
         │ ops                       │ compromise        │ fix draft
   each creator's agent      agent of the author      agent of the owner
                             in the way
```

## One writer

The room is the only thing that changes the level. Requests from every creator wait in one queue, and each change gets a version number and an author. Two agents can never write at the same moment.

## Agents propose, the room decides

An agent's call to Claude runs outside the queue. When its ops come back, the room checks them against the level as it is then, not as it was when the agent started thinking.

## Names

The server names new objects after their author: A1, A2 for author A, B1 for author B, M1 for the mediator.

## The log

Every version is a log entry: who, a summary, and the ops. Replaying the log from v0 gives exactly the live level, and the nerd console checks this live. Restoring an old version is a new entry, so the log is append-only.

## Safe point

A change that would turn the playtester's cell into a wall, lava or a locked door waits until they step away, then goes live by itself.

<!-- page: proof -->
# Proving every change

Three checks run on every change, in this order.

1. **Shape.** JSON Schema checks the ops and the level they produce (`spec/schema/`).
2. **Meaning.** Semantic rules: everything inside the grid, unique ids, start and flag on different cells, castle doors on their outline, at most 8 treasures and coins together.
3. **Winnable.** A breadth-first search over (cell, keys held, important items collected) finds the shortest route from the start to the flag that completes every objective. It never steps on lava.

The solver answers in about 0.2 ms, so it runs on every version and on every fix the mediator considers.

## The ghost runner

After every version, a ghost walks the solver's route on the board and shows **✓ WINNABLE**. When a change is held back, the ghost runs the old route and crashes where the change would cut it.

## Why you can trust it

- There is no AI in the checks. They are deterministic.
- 24 solver cases and 11 play cases in `spec/fixtures/` were worked out by hand before the code was written. Both implementations, the TypeScript server and the Dart app, pass them.
- 400 random levels compare the solver with a separate search that only uses the play rules.
- The server has 96 tests in total.

<!-- page: rules; group: Reference -->
# Objects and rules

The level is a grid. x grows to the right from 0, y grows down from 0. The demo level is 24 × 14. The full rules are in `spec/rules.md`.

## Terrain

Each cell has exactly one terrain. Where objects overlap, the higher one wins:

1. Door (a door object or a castle's coloured door)
2. Wall (a wall or a castle outline)
3. Bridge
4. Lava
5. Ground

Keys, treasure and coins are items on a separate layer. One cell can hold several.

| Terrain | Can the player enter? |
| --- | --- |
| Ground, bridge | Yes |
| Wall | No |
| Door of colour C | Only with a key of colour C |
| Lava | Yes, and they fall: back to the start, items back in place |

## Play

The player starts on the start cell with empty pockets, moves one cell per step, and picks up every item on a cell they enter. Walls, locked doors and the edge of the grid leave them where they are. They win on the flag once every objective is done.

## Objectives

| Type | Done when |
| --- | --- |
| `collect` (`target`) | That treasure or coin has been picked up |
| `collect_count` (`item: "coin"`, `count`) | At least `count` coins have been picked up |

Reaching the flag is always the last objective. With no objectives, reaching the flag is enough.

## Validation errors

These stop a change.

| Code | Meaning |
| --- | --- |
| `out_of_bounds` | An object, the start or the flag is outside the grid |
| `duplicate_id` | Two objects share an id |
| `start_equals_flag` | The start and the flag are the same cell |
| `invalid_castle_door` | A castle door offset is out of range |
| `objective_target` | A `collect` target is not an existing treasure or coin |
| `collectible_limit` | More than 8 treasures and coins together |

## Warnings

These do not stop a change.

| Code | Meaning |
| --- | --- |
| `protected_cell` | The start or the flag is on impassable terrain |
| `item_on_blocked` | An item lies on a wall or on lava |
| `item_on_start` | An item lies on the start |

<!-- page: ops -->
# Ops

A change is a batch of ops. A batch applies completely or not at all.

| Op | Fields | What it does |
| --- | --- | --- |
| `create` | `entity` | Adds an object. The server sets its id and owner. |
| `update` | `id`, `set` | Changes editable properties of an object |
| `delete` | `id` | Removes an object, and any objective that targets it |
| `set_world` | `set: { start?, flag? }` | Moves the start or the flag |
| `set_objectives` | `objectives` | Replaces the list of objectives |

A restore uses a sixth op internally, `replace_world`, so the log stays replayable.

## Editable properties

| Type | Properties `update` can change |
| --- | --- |
| wall, lava, bridge | `x`, `y`, `w`, `h`, `label`, `icon` |
| castle | the same, plus `door` |
| door, key | `x`, `y`, `color`, `label`, `icon` |
| treasure, coin | `x`, `y`, `label`, `icon` |

## Example

```json
[
  { "op": "create", "entity": { "id": "new", "type": "lava", "owner": { "kind": "assistant" },
    "x": 11, "y": 1, "w": 2, "h": 3, "label": "Lava river" } },
  { "op": "update", "id": "A1", "set": { "x": 12 } },
  { "op": "delete", "id": "B1" }
]
```

## When a batch is rejected

| Code | Meaning |
| --- | --- |
| `not_author` | Only creators can change the level |
| `empty` | The batch has no ops |
| `duplicate_id` | `create` used an id that exists |
| `unknown_id` | `update` or `delete` named an object that does not exist |
| `not_editable` | `update` tried to change a property that type does not allow |

The validation errors from **Objects and rules** reject a batch too.

<!-- page: events -->
# Events

Browsers talk to the room over Socket.IO. Requests that expect an answer use an acknowledgement callback.

## Client to server

| Event | Payload | Answer |
| --- | --- | --- |
| `join` | `{ name, role }`, role is `author`, `player` or `stage` | The full state for this member |
| `agent:say` | `{ text }`, up to 500 characters | `{ ok }` |
| `doc:submit` | `{ ops, summary? }`, direct edits for tests and debugging | A submit result |
| `proposal:choose` | `{ proposalId, optionId }` | A submit result |
| `approval:answer` | `{ proposalId, accept }` | A submit result |
| `history:revert` | `{ rev }` | A submit result |
| `history:worlds` | none | The level at every version, for time travel |
| `play:move` | `{ dir }`: `up`, `down`, `left` or `right` | none |
| `play:restart` | none | none |
| `play:report` | `{ text }` | `{ ok, routedTo, fallsHere, spot }` |
| `suggestion:apply` | `{ id }` | A submit result |
| `suggestion:dismiss` | `{ id }` | none |
| `room:reset` | none | Done |

## Server to everyone

| Event | Payload |
| --- | --- |
| `state` | The level, version, solver result, waiting changes, validator time |
| `log` | A new log entry with its author |
| `chat` | A message for one author's chat: theirs, their agent's, the mediator's, a playtest report or the system's |
| `proposal` | A held conflict: diagnosis, options, approvals, status |
| `play` | The player: position, keys, items, falls, recent path |
| `members` | Everyone in the room, with letter and colour |
| `report` | A playtest report and who it was sent to |
| `suggestion` | A fix an agent drafted for a report |
| `reset` | The room went back to the prepared level |

## Submit results

| Status | Meaning |
| --- | --- |
| `committed` | Live, with the new version number `rev` |
| `deferred` | Waiting for the playtester to step away |
| `conflict` | Held back; the `proposal` lists the fixes |
| `awaiting_approval` | A fix was picked and waits for the owners |
| `rejected` | Not applied, with a `code` and a `message` |

<!-- page: config -->
# Configuration

Put variables in the environment, or in `server/.env`, which git ignores.

| Variable | Default | Meaning |
| --- | --- | --- |
| `PORT` | `3000` | The server's port |
| `ANTHROPIC_API_KEY` | none | If set, agents call the Claude API directly |
| `SKITTLES_AGENT` | `api` with a key, otherwise `cli` | Forces an engine: `api` or `cli` |
| `SKITTLES_MODEL` | `claude-sonnet-5-5` | The model for the API engine |
| `SKITTLES_CLI_MODEL` | `sonnet` | The model alias for the CLI engine |
| `SKITTLES_EFFORT` | `low` | `low`, `medium` or `high` |
| `SKITTLES_CLAUDE_BIN` | `claude` | Path to the `claude` binary if it is not on `PATH` |
| `SKITTLES_ROOM` | `http://localhost:3000` | Web development only: where Vite sends room traffic |

## Development

Run `npm run dev` in `server/` (port 3000, restarts on change) and `npm run dev` in `web/` (Vite on port 5173). If port 3000 is taken, start the server with `PORT=3001 npm run dev` and Vite with `SKITTLES_ROOM=http://localhost:3001 npm run dev`.

## Theme

The web client is dark by default. Add `?theme=light`, `?theme=dark` or `?theme=system` to any address to change it; the choice is remembered.

## Rehearsal scripts

| Script | What it does |
| --- | --- |
| `server/scripts/demo-run.ts` | Plays the whole stage scenario with real agents and times each beat |
| `server/scripts/agent-check.ts` | Sends ten varied requests and reports results and latency |
| `server/scripts/simulate.ts` | Plays scripted moves without an LLM: `river`, `statue`, `castle`, `reset` |

<!-- page: shortcuts -->
# Keyboard shortcuts

| Key | Where | What it does |
| --- | --- | --- |
| Arrow keys or W A S D | Playtester | Move one cell |
| R | Playtester | Start over |
| F | Playtester | Report a problem |
| Hold V | Playtester | Say the problem out loud |
| Esc | Report panel | Close it |
| Enter | Chat | Send to your agent |
| `` ` `` | Creator, stage | Open or close the nerd console |

<!-- page: limits; group: More -->
# Limits and FAQ

## Honest limits

- The demo's starting level is prepared in advance. Every change after that is generated live.
- Agents are not deterministic. The same words can give a slightly different level, and sometimes an agent avoids a conflict on its own.
- v1 has walls, lava, bridges, castles, doors, keys, treasure, coins, a start and a flag. No enemies or physics.
- Agents need internet. The first request after a start takes about 10 s; later ones take 4 to 8 s, 5.7 s on average.
- One server runs one room, and the level lives in memory: restarting the server starts over.
- People stay listed in the room after they close their window, until the server restarts.
- Voice input needs Chrome or Edge.

## FAQ

**Do agents write code?**
No. They write ops, and the room checks every one.

**What if two people send a request at the same moment?**
The room queues them. The second is checked against the level after the first.

**Can I bring my own agent, like Claude Code or Cursor?**
Not in v1. The room's ops are a small, checked interface, so exposing them as an MCP server is the natural next step.

**Does this only work for games?**
The same idea works anywhere a goal can be checked by a machine: a schedule, a budget, a configuration. A game is the smallest world where that check is fast and easy to see.

**Is there a desktop app?**
`app/` holds a macOS level editor in Flutter. Its Dart rules pass the same shared tests as the server, but the live demo runs in the browser.

<!-- page: track -->
# Track 02 checklist

Hacktoberfest Georgia 2026, Track 02 asks for a multiplayer agentic experience. This is where Skittles shows each requirement.

| The track asks | Where Skittles shows it |
| --- | --- |
| People work on one thing together, each through their own agent | Every creator has a personal agent; a room takes any number of creators |
| The agent knows what the other agent changed | Before every request, an agent gets the others' changes since its last turn, with names |
| No conflicts | Structural: one writer, in order. Semantic: the solver holds back changes that break the goal, and the mediator offers checked fixes |
| Live, like Figma | Agent cursors, author colours, changes landing in the running game without a restart |
| Two people demo it live on stage | The three-minute script below |

## The three-minute demo

| Time | What happens |
| --- | --- |
| 0:00 | The stage screen. Click the status: the ghost runner proves the level is winnable. |
| 0:15 | Nino, by voice in Georgian: a lava river down the middle with one gap. |
| 0:40 | Giorgi: "a big statue in the middle". His agent sees Nino's gap and keeps it open. |
| 1:00 | Giorgi insists: "right in the gap". ROUTE BLOCKED. Nino's agent proposes a compromise; the mediator offers a bridge. |
| 1:40 | Giorgi picks the bridge, Nino approves, the ghost runner gets through. |
| 2:00 | Luka plays and falls into the lava twice. Nino's agent proposes a fix, and Nino applies it while Luka plays. |
| 2:30 | Replay build and the nerd console: "✓ log replays to live state". |
