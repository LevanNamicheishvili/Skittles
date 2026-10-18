# Skittles for Mac: the Flutter plan

**What it is:** a multiplayer 2D game studio. You build a game with the editor's tools (draw walls, lava, castles, keys…) or by telling your own AI agent what you want, and both make the same checked changes. Several people build one game at once, each with their own agent, and a solver keeps every change from breaking it.

The Flutter app in `app/` becomes a native client of the same room server as the web. A creator on the Mac app and a creator in the browser work in one room. The server stays the authority: room, agents, mediator and log stay in Node, and the app speaks the events on the docs' **Events** page. The Dart rules already in `app/lib/game/` (they pass the shared fixtures) only drive local previews, like the web's `sim.ts`.

## Rules for the route

1. **One set of design values.** `design/tokens.json` holds the site's colours, radii, sizes, type and motion. `node design/build.ts` writes `app/lib/ui/tokens.dart` and fails if `web/src/styles.css` disagrees.
2. **The docs are the checklist.** Every page of the user guide is a feature with a "done when".
3. **Same messages, same tests.** Recorded server events in `spec/fixtures/protocol/` (phase B) are parsed by the app's tests, as the rules fixtures are today.
4. **Desktop first.** macOS, then Windows (decisions D1 and D2). Only plugins with Swift Package Manager support.

## Phases

| # | What | Done when | Status |
| --- | --- | --- | --- |
| A | Design values and the component kit | A gallery screen matches the site in both themes, with snapshot tests | **Done** |
| B | `RoomClient`, typed models for every event, app state, welcome screen | The app joins the room and shows the same version and status as the web; recorded events parse | **Done** |
| 1 | **Scene format and studio editor.** `spec/scene.md` (scenes, behaviours as data, the jump-reachability check), the studio: tools, canvas with grid, zoom and pan, place, select, drag, resize, hierarchy, inspector, checks, undo, save and open | A platformer scene built by hand, saved, opened again, and the checks say whether the finish can be reached | **Done** |
| 2 | **Playable preview and playtests:** run, jump, gravity, collision, coins, patrolling enemies, score, finish; the AI plays and reviews the level; people share their runs; anyone watches any run | Press Play and play the scene you just built; the AI and teammates test it | **Done** |
| 3 | **AI actions** on scenes: `CREATE_OBJECT`, `UPDATE_OBJECT`, `DELETE_OBJECT`, `ADD_COMPONENT`, `UPDATE_SCENE`, `UPDATE_UI`, sent through the server, checked by the same rules, held for approval when they would break the game | "Make a small forest platformer with three platforms, two coins and an enemy" becomes a playable scene | **Done** (studio, single user) |
| 4 | **Collaboration on scenes:** shared projects on the server, everyone's agent in one team, presence, cursors, team chat, history, then the mediator | Two people edit one scene from two Macs, live, and a conflict gets checked fixes | **In progress**: shared projects, agents and chats done; checked fixes for conflicts next |
| 5 | **More templates:** today's grid adventure (`spec/rules.md`) as the second; Windows build; `.dmg` | A second kind of game in the same studio | |

The 2.5D grid board port (the old phase C) waits for template 5.

## Any 2D game: what it takes

Today the rules (`spec/rules.md`), the solver and both implementations describe one kind of game: a top-down grid adventure with walls, lava, bridges, castles, doors, keys, treasure, coins, a start and a flag. "Any 2D game" is the biggest piece of work on this plan, and it needs decisions before code:

1. **A general model.** Custom tile types and sprites, entities with behaviours (moving, patrolling, triggers, doors that open on events), and game-wide rules, all as data the room and the agents can change with ops.
2. **Templates.** Start from a kind of game, such as a top-down adventure (today's), a platformer with gravity, or a puzzle, each with its own play engine.
3. **A goal check per template.** Skittles' promise is "nothing breaks the game". The breadth-first solver proves it for grid adventures; a platformer needs a reachability check that knows about jumps, and some games will only get partial checks (every goal reachable, no softlocks). Being honest about which checks a template has matters more than having one for everything.
4. **Agents that know the template.** The agent's instructions and its op schema come from the template, not from one fixed list of objects.

The legacy editor's drawing tools (`app/lib/editor/`) come back in phase D, now sent through the room.

## Phase A: what exists

| Piece | Where |
| --- | --- |
| Tokens, generated | `design/tokens.json` → `app/lib/ui/tokens.dart` (`SkColors` theme extension, `SkTokens`) |
| Theme | `app/lib/ui/sk_theme.dart`: dark by default, system sans, no ripples, `context.sk`, `context.mono()`, `context.sans()` |
| Kit | `app/lib/ui/kit/`: `BrandMark` (with the route draw-in), `SkButton` (primary, secondary, ghost, call to action), `SkToggle`, `SkTextField`, `StatusPill` (breathing dot), `VersionBadge`, `Keycap`, `CardLabel`, `SkAvatar`, `PresenceChip`, `ChatBubble` (you, agent, thinking, system, mediator), `SkPanel`, `ToneCard`, `OptionRow`, `Arrive` (msg, card, dialog, pop), `LiveDot`, `TypingDots` |
| Gallery | `app/lib/screens/gallery_screen.dart`, the app's home until phase B |
| Tests | `test/tokens_test.dart` (Dart tokens equal the JSON), `test/kit_golden_test.dart` (gallery snapshots in both themes with the real San Francisco fonts), `test/widget_test.dart` (opens dark, switches theme, legacy editor still opens) |

The legacy editor (`app/lib/editor/`) is untouched and still tested; it returns in the "Later" phase.

## Step 2: what exists

Press **Play** to play the scene; **AI playtest** to have the AI play it and review it for the team. Every playtest lands in the team chat and can be watched.

| Piece | Where |
| --- | --- |
| Rules | `spec/scene-play.md`: exact steps of 1/120 s (exact for constant gravity, so the jump matches the reachability check), coyote time and a jump buffer, sweeps against platforms, enemies on a closed-form patrol, a safe second after each fall. Runs are stored as their inputs |
| Three implementations | `spec/fixtures/make_scene_runs.py` (writes `scene_runs.json`, 13 runs), `server/src/studio/play.ts`, `app/lib/studio/play.dart`: all agree to 1e-6 |
| The AI player | `play.ts`: a best-first search over short held inputs, never dying, to the finish and then to each coin; it yields to the server every 300 nodes. On the forest example it finishes in about 64 ms of search |
| The AI's review | `server/src/studio/playtester.ts`: the scene and what the AI player found go to the same engine as the agents; it answers with a summary and up to five issues, each naming objects. The project maps them to whoever made those objects (`by`), and the card offers "Ask <name>'s agent" |
| People's runs | The preview records the inputs; "Share with the team" sends them with a note and the scene version. The project replays them on that version (rebuilt from the history), so the numbers shown are the real ones |
| App | `play_view.dart` (session, keys, HUD, result card, watching), play mode in `scene_painter.dart`, playtest cards in `studio_chat.dart` |
| Measured | Real AI playtest on the CLI engine: about 9–11 s from the request to the review, almost all of it the review; the AI's run replays to the same frame on the server and in the app |
| Tests | `server/test/play.test.ts`, `playtester.test.ts`, playtests in `studio.test.ts`; `app/test/scene_runs_conformance_test.dart`, `play_view_test.dart`, the cross-check in `studio_shared_test.dart`, goldens `studio_play_dark` and `studio_playtests_dark` |

Flame was the plan for the preview. The preview runs its own small game loop instead, because the same steps must run on the server for AI playtests and replays, and an exact, shared step function matters more here than an engine.

## Step 4, part 1: what exists

A project lives on the server and starts empty. Each member has an agent: you talk to yours in **My agent**, everyone talks in **Team**, and `@Name's agent` in the team chat gives that agent a request it carries out at once. Its owner sees the request in their thread ("Giorgi → your agent") and anyone can undo the change from its card.

| Piece | Where |
| --- | --- |
| Rules on the server | `server/src/studio/scene.ts`: a port of the Dart scene, validation and actions, run against the same `spec/fixtures/scenes.json` and `actions.json`; patches (`diff`, `applyPatch`, `inverse`) |
| Project | `server/src/studio/project.ts`: the single writer. Versions, a patch and its inverse per change, `by` on every object, undo and redo per member (never a teammate's change), the team chat, a thread per member, the agents' queues. An agent change that would break the game is retried once with the reason, then held for whoever asked |
| Namespace | `server/src/studio/hub.ts`: `/studio` (`join`, `edit`, `undo`, `redo`, `revert`, `say`, `ask`, `approve`, `discard`, `presence`), `GET /api/projects`, saved to `server/data/projects` (`SKITTLES_DATA` moves it). Someone who reconnects gets their old place back |
| App | `studio_link.dart` (the socket), `project.dart` (members, chats, presence), `patch.dart`; `studio_controller.dart` sends each edit as a patch, shows it at once and folds in the project's changes in order |
| Layout | Layers and inspector on the left (`studio_panels.dart`), the canvas with the tools floating under it, people with their agents' status and the two chats on the right (`studio_chat.dart`). Teammates' cursors and selections show in their colours |
| Tests | `server/test/scene.test.ts` (25), `server/test/studio.test.ts` (14), `app/test/studio_shared_test.dart` (two studios on a real server), `app/test/studio_chat_test.dart`, `app/test/patch_test.dart`, goldens `studio_team_dark` and `studio_empty_dark` |

Run two copies of the app: the first with `SKITTLES_SCREEN=studio SKITTLES_NAME=Nino`, then copy its invite code into the second, or start it with `--env SKITTLES_PROJECT=<code>`.

## Step 3: what exists

| Piece | Where |
| --- | --- |
| Server | `server/src/studio/sceneAgent.ts`: instructions, the reply schema, the player's jump numbers in every prompt, cleaning of every action (known types and fields, whole numbers, at most 60); the same engine choice as the room's agents (API key, otherwise the signed-in Claude Code CLI). `POST /api/scene/ask` in `server.ts` takes `{ scene, prompt }` and answers `{ message, actions, ms }` |
| App | `app/lib/studio/actions.dart` applies actions (kept inside the scene, one player, enemies keep their patrol, unknown ids skipped with a note). Since step 4 the agents work inside the shared project; `POST /api/scene/ask` stays for scripts |
| Rule | A reply that adds no error is applied as one undo step. One that would add an error (the finish out of reach, say) is held: Apply anyway or Discard |
| Measured | Real requests on the CLI engine: 5.2 s for two coins and an enemy, 5.1 s in Georgian (answered in Georgian), 12.7 s for a whole new desert level of 23 actions. Both scenes passed every check |
| Tests | `server/test/sceneAgent.test.ts` (9), `app/test/actions_test.dart`, `app/test/actions_conformance_test.dart` |

The studio asks the server set by `SKITTLES_SERVER` (default `http://localhost:3001`). A server started before this step answers without the assistant; restart it.

## Step 1: what exists

| Piece | Where |
| --- | --- |
| Spec and cases | `spec/scene.md`; `spec/fixtures/scenes.json` (12 cases, worked out by hand; regenerate with `python3 spec/fixtures/make_scenes.py spec/fixtures/scenes.json`) |
| Model and checks | `app/lib/studio/scene.dart` (scene, objects, behaviours, JSON), `validate.dart` (errors, warnings, the jump model, breadth-first reachability over platform tops) |
| Editing | `studio_controller.dart`: tools, placing snapped to 8 px, one player per scene, drags as one undo step, enemies take their patrol along, undo and redo, open and save state |
| Studio | `studio_screen.dart` and `scene_painter.dart`: tools (V H P L C E F), hierarchy, canvas (click to place, drag to move, corner to resize, scroll to pan, pinch or ⌘-scroll to zoom, arrows nudge, Delete, ⌘Z, G grid, R reach, 0 fit), inspector (transform and behaviour numbers), checks you can click; white dots above every top the player can stand on, dashed red on the rest, the selected player's jump arcs; ⌘S and ⌘O through `scene_files.dart` (`file_selector`, with the user-selected files entitlement) |
| Tests | `scene_conformance_test.dart`, `studio_controller_test.dart`, `studio_screen_test.dart`, a studio snapshot |

Launch straight into the studio: `flutter run -d macos --dart-define=SKITTLES_SCREEN=studio`.

## Phase B: what exists

| Piece | Where |
| --- | --- |
| Recorded messages | `server/scripts/record-protocol.ts` runs the real room code through a whole session (conflict, negotiation, approval, playtest report, suggested fix, deferred change, restore, reset) and writes `spec/fixtures/protocol/session.json`: 63 events and every submit result |
| Models | `app/lib/net/models.dart`: `Member`, `RoomState`, `LogEntry`, `ChatMessage`, `Proposal` (`Diagnosis`, `FixOption`), `PlayState`, `PlaytestReport`, `Suggestion`, `Snapshot`, and `SubmitResult` (`Committed`, `Deferred`, `Conflict`, `AwaitingApproval`, `Rejected`) |
| State | `app/lib/net/room_store.dart`: a `ChangeNotifier` that folds events in the way `web/src/net.ts` does |
| Client | `app/lib/net/room_client.dart`: `connectAndJoin`, rejoin on reconnect and on `reset`, and every request in the docs' Events page. It drops the string offset that Socket.IO's connection state recovery appends to each broadcast (the browser client ignores it; this Dart library would otherwise hand it over with the payload) |
| Screens | `connect_screen.dart`: the welcome screen, laid out like Conductor's onboarding: the SKITTLES block wordmark (`ui/kit/pixel_wordmark.dart`), three features that advance on their own with a live preview each (the editor's tools and an agent; several builders at once; a conflict and its checked fix, all run through the real Dart solver) and a progress bar, the live glyph sky behind, and the way in. `room_screen.dart`: the site's top bar and a flat level preview (`ui/level_map.dart`), history and room facts, all live |
| Network | `com.apple.security.network.client` in both macOS entitlements; without it the sandbox blocks the socket |
| Tests | `test/protocol_test.dart` (every recorded event and result), `test/live_room_test.dart` (starts its own server, two clients, a change reaches the other), `test/motion_test.dart` (arrivals keep their children's state), widget tests and snapshots of both screens |

Launch settings, like the web's `?role=&name=` links:

```bash
flutter run -d macos --dart-define=SKITTLES_SERVER=http://localhost:3001 --dart-define=SKITTLES_NAME=Nino --dart-define=SKITTLES_ROLE=author
flutter run -d macos --dart-define=SKITTLES_SCREEN=gallery    # the component gallery
```

## Run it

```bash
node design/build.ts                       # after changing design/tokens.json
cd server && node scripts/record-protocol.ts   # after changing what the room sends
cd app && flutter test                     # 154 tests
flutter test --update-goldens test/kit_golden_test.dart   # after a deliberate visual change
flutter run -d macos
```
