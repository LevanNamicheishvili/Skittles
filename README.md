# Skittles

**Two people, two AI agents, one live game.** Two authors each talk to their own agent and change the same level while a third person plays it. The agents see what the other author changed. A single-writer room checks every change with a deterministic solver. When two valid changes together would break the level, nothing goes live: a mediator offers fixes the solver has already checked, the other author's agent negotiates a compromise, and the humans decide.

Built for **Hacktoberfest Georgia 2026, Track 02: Multiplayer agentic experiences** ("two people work on one thing together, each through their own agent; agents know what the other changed; no conflicts; live like Figma").

> **ქართულად.** ორი ავტორი, თითო თავისი აგენტით, ერთ ცოცხალ თამაშს ცვლის, სანამ მესამე თამაშობს. ოთახი ყველა ცვლილებას სოლვერით ამოწმებს. თუ ორი სწორი ცვლილება ერთად თამაშს ტეხს, მედიატორი შემოწმებულ გამოსავლებს სთავაზობს, მეორე ავტორის აგენტი კომპრომისზე ვაჭრობს, გადაწყვეტილებას კი ადამიანები იღებენ. კვლევა და დასაბუთება: [docs/research.ka.md](docs/research.ka.md). სამუშაო გეგმა, დემოს სცენარი და შემდეგი ნაბიჯები: [docs/skittles-plan.md](docs/skittles-plan.md).

## Documentation

The user guide and reference, in English and Georgian, are at `/docs` on a running server (for example `http://localhost:3001/docs`), and on GitHub: [docs/guide/en.md](docs/guide/en.md) · [docs/guide/ka.md](docs/guide/ka.md) (ქართულად).

## The problem

Syncing bytes between people is solved: Figma, Google Docs, CRDTs. Syncing **intent** is not. When two people edit one artifact through their own agents, the dangerous conflict is not two edits to the same line. It is two edits that are each correct but together break the goal. Nino adds a lava river with one crossing; Giorgi puts a statue in the middle of the map. Each change is fine. Together, the player can no longer reach the flag. Git and CRDTs see no conflict at all.

What we found on the market (details and sources in [docs/research.ka.md](docs/research.ka.md)):

- Roblox Assistant recommends working in one chat at a time "to avoid conflicts", and its plans are not visible to collaborators.
- Lovable coordinates many agents of *one* person with a single exclusive writer and no merging.
- Nilo lets several people build one world and itself warns that fast AI edits can cause broken edits and lost work.
- Bezi, Ziva, Rosebud, Google Playground, nunu.ai, modl.ai and Razer QA Copilot work for a single creator or a QA team.

**Why a game:** a level is the smallest world where "does the goal still hold?" is machine-checkable. A breadth-first solver answers it in well under a millisecond, so the system can prove a conflict instead of guessing.

## What it does

| Feature | What you see |
| --- | --- |
| Personal agents | Each author chats with their own Claude agent, by text or voice, in English or Georgian. The agent writes structured ops, never code, and is told what the other author changed since its last request. |
| Single-writer room | Every change goes through one room in order, gets a version and an author, and lands in an append-only op log. The log alone replays to the live level. |
| Validator | JSON Schema, semantic rules and a BFS solver over (cell, keys, items). A **ghost runner** walks the solver's route after every version: "✓ WINNABLE". |
| Intent conflicts | A change that would make the level unwinnable is held back. The ghost runner crashes into it ("ROUTE BLOCKED"), and the diagnosis names who closed what, e.g. *Giorgi's wall closes the old route, and Nino's lava leaves no way around.* |
| Mediator | Fix options, each checked by the solver before anyone sees them: the bridge that gives the shortest route, moving an unreachable item, adding a missing key, or cancelling. A fix that touches another author's object needs that author's approval. |
| Negotiation | The agent of the author whose work is in the way proposes a compromise (for example "move the statue next to the gap"). The room checks it, and it joins the options. |
| Live play | A third person plays during the edits. A change waits for a safe moment if the player stands where it lands. Changes appear in the running game without a restart. |
| Playtest dev mode | The game records position, path, falls and keys. Falling twice at one cell, or a report (F key or hold V and speak), goes to the owner of the object at the trouble spot. Their agent drafts a fix, the room checks it, and the owner applies it with one click. |
| Figma-style presence | Agent cursors fly to what they are building and show "thinking…". New objects pop in the author's color. Authorship is visible on every object. |
| Time travel | A slider over all versions and **Replay build**, which plays the log from v0 with each author's cursor. |
| Nerd console | Press `` ` `` to see the raw op log as JSON, validator time in ms, and a live check that the log replays to the live state. |

## Demo script (3 minutes)

| Time | Beat |
| --- | --- |
| 0:00 | Stage screen. Click the status: the ghost runner proves the level is winnable. |
| 0:15 | Nino (voice, Georgian): a lava river down the middle with one gap. Her cursor flies over and the lava appears. |
| 0:40 | Giorgi: "a big statue in the middle". His agent sees Nino's gap and keeps it open by itself. |
| 1:00 | Giorgi insists: "right in the gap". ROUTE BLOCKED. Nino's agent proposes a compromise; the mediator offers a bridge. |
| 1:40 | Giorgi picks the bridge, Nino approves, the bridge appears, the runner gets through. |
| 2:00 | Luka plays and falls into the lava twice. Dev mode sends it to Nino's agent, which proposes a fix; Nino applies it while Luka keeps playing. |
| 2:30 | Replay build and the nerd console: "✓ log replays to live state". |

With real agents, the whole scenario runs in about 47 seconds of machine time (`server/scripts/demo-run.ts`).

## Architecture

```
 Author A (browser)        Player (browser)        Author B (browser)
   chat / voice               arrows, F, V            chat / voice
        │  agent:say               │ play:move             │
        ▼                          ▼                       ▼
 ┌──────────────────────────── Socket.IO ─────────────────────────────┐
 │ Room (single writer)  ── ops ──▶ validate ──▶ solver ──▶ commit ───┼──▶ state, log, play → everyone
 │   append-only op log, versions, authorship, safe-point deferral    │
 │   held conflicts ──▶ mediator (diagnosis + checked fixes)          │
 │   playtest reports ──▶ routed to the owner of the trouble spot     │
 └───────▲───────────────────────────▲──────────────────▲─────────────┘
         │ ops                       │ compromise        │ fix draft
   Agent of A                  Agent of B (negotiator)   Agent (suggester)
   Claude API or Claude Code CLI, structured output, never writes code
```

| Part | Where |
| --- | --- |
| Rules, raster, solver, play engine (shared with the browser) | `server/src/game/` |
| Ops, room, mediator, playtest dev mode | `server/src/room/` |
| Agents: change, negotiate, suggest fixes | `server/src/agent/` |
| HTTP + Socket.IO server | `server/src/server.ts`, `server/src/index.ts` |
| Prepared demo level | `server/src/levels/demo.ts` |
| Web client (Vite, React, canvas) | `web/src/` |
| Normative rules, JSON schemas, shared fixtures | `spec/` |
| Rehearsal and test scripts | `server/scripts/` |
| macOS level editor (Flutter, Dart port of the rules and solver) | `app/` |

## Run it

Requirements: Node 24 or newer (tested on 26), and either the Claude Code CLI signed in on this machine (`claude`) or an `ANTHROPIC_API_KEY`.

```bash
cd server && npm install && npm test
```

```bash
cd web && npm install && npm run build
```

```bash
cd server && PORT=3001 npm start
```

`http://localhost:3001/` is the landing page; you can join from there. Or open three windows directly:

- `http://localhost:3001/?role=author&name=Nino`
- `http://localhost:3001/?role=author&name=Giorgi`
- `http://localhost:3001/?role=player&name=Luka`

Add `http://localhost:3001/?role=stage` for the projector; it has a **Reset demo** button. Voice input needs Chrome or Edge.

For development, run `npm run dev` in `server/` (restarts on change, port 3000) and `npm run dev` in `web/` (Vite on 5173, proxied to the server).

If port 3000 is taken, start the server with `PORT=3001 npm run dev` and Vite with `SKITTLES_ROOM=http://localhost:3001 npm run dev`.

| Variable | Meaning |
| --- | --- |
| `PORT` | Server port, default 3000 |
| `ANTHROPIC_API_KEY` | If set, agents use the Claude API directly (put it in `server/.env`, which git ignores) |
| `SKITTLES_AGENT` | `api` or `cli` to force an engine; default is `api` with a key, otherwise `cli` |
| `SKITTLES_MODEL` | API model, default `claude-sonnet-5-5` |
| `SKITTLES_CLI_MODEL` | CLI model alias, default `sonnet` |
| `SKITTLES_EFFORT` | `low` (default), `medium` or `high` |
| `SKITTLES_CLAUDE_BIN` | Path to the `claude` binary if it is not on `PATH` |

## Rehearsal tools

```bash
cd server && node scripts/demo-run.ts http://localhost:3001
```

`demo-run.ts` plays the whole stage scenario with the real agents and prints the timing of each beat. `agent-check.ts` sends ten varied requests and reports results and latency. `simulate.ts` plays scripted moves without an LLM (`river`, `statue`, `castle`, `reset`).

## Tests and measurements

- 96 tests (`cd server && npm test`): the shared rule fixtures, ops, room, mediator, approvals, safe point, revert and replay, socket server, agents with fake engines, negotiation, and playtest dev mode.
- 43 tests in the Flutter app (`cd app && flutter test`): the same shared rule fixtures against the Dart port, the editor controller, and the editor screen.
- 10 real agent requests: 9 changes done correctly and 1 correctly declined (no enemies in v1), 3.9 to 8 s each, 5.7 s on average. A Georgian request got a Georgian answer in 3.8 s. The first request after a cold start takes about 10 s.
- Validator time per version: about 0.2 ms.

## Honest limits

- The starting level is prepared in advance; we say so on stage. Every change during the demo is generated live.
- We have not interviewed users; the problem is supported by how existing tools avoid it, not by user research.
- Agents are not deterministic. In one run Giorgi's agent avoided the conflict by itself, which the demo script covers.
- v1 has walls, lava, bridges, castles with doors, doors, keys, treasure, coins, start and flag. No enemies or physics.
- `app/` is a separate macOS level editor in Flutter. Its Dart rules pass the same shared fixtures as the server, but the live demo runs in the browser and does not use it.

## Status and next steps

Done: everything in the tables above, tested end to end with real agents.

Next:

1. Three full rehearsals with three people, using voice in Chrome.
2. Test on the venue network or a phone hotspot (agents need internet).
3. Record a backup video of one full run.
4. Write the submission text and a 3-slide pitch: problem, live demo, why it is trustworthy (validator, log, human approval).
