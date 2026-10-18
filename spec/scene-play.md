# Playing a scene, version 1

How a platformer scene (`scene.md`) plays (the grid adventure's Play mode is `rules.md` section 4): the same steps in the studio's preview, on the server when it checks a playtest, and for the AI player. It is exact on purpose: a run is stored as its inputs, and replaying those inputs on the same scene must give the same result everywhere. Shared cases live in `fixtures/scene_runs.json`. If code and this document disagree, the code is wrong.

## 1. Time and input

The game advances in fixed steps of `DT = 1/120` s. Each step reads one input: three bits, `left` = 1, `right` = 2, `jump` = 4.

A run is stored as segments `[frames, bits]`: hold `bits` for `frames` steps. Replaying the segments from the start gives the run again.

## 2. The player's state

`x`, `y` (top-left corner), `vx`, `vy` (px/s), `grounded`, `air` (steps since it last stood on something), `buffer` (steps left on a jump press), `prevJump` (whether jump was held last step), `safe` (steps left in which enemies cannot hurt it), `frame` (steps taken), `score`, the coins collected, `deaths`, `won`.

At the start, and after each death: the player's position in the scene, `vx = vy = 0`, `grounded = false`, `air = 11`, `buffer = 0`. `safe` is 0 at the start and 120 (one second) after a death, so a player who comes back next to an enemy is not caught again at once. `frame`, `score`, the coins, `deaths` and `prevJump` carry on through a death.

The player's numbers come from its `controller` (`speed`, `jump`, defaults 260 and 640); `g` is the scene's gravity; `W`, `H` the scene's size; `w`, `h` the player's size.

## 3. One step

Nothing changes once `won`. Otherwise, in this order:

1. `frame += 1`.
2. **Run.** `vx = speed × ((right ? 1 : 0) − (left ? 1 : 0))`.
3. **Jump press.** `pressed = jump and not prevJump`, then `prevJump = jump`. If `pressed`, `buffer = 12`; otherwise, if `buffer > 0`, `buffer −= 1`.
4. **Air time.** If `grounded`, `air = 0`; otherwise `air += 1`.
5. **Take off.** If `buffer > 0` and `air ≤ 10`: `vy = −jump`, `buffer = 0`, `air = 11`, `grounded = false`. A press up to 0.1 s before landing still jumps on landing, and so does a press up to 10 steps after walking off an edge.
6. **Move across.** `nx = x + vx × DT`. Moving right, each platform that overlaps the player vertically (`p.y < y + h` and `y < p.y + p.h`) with `x + w ≤ p.x < nx + w` stops it: `nx = min(nx, p.x − w)`. Moving left, likewise with `nx < p.x + p.w ≤ x`: `nx = max(nx, p.x + p.w)`. Then `x = nx` clamped to `[0, W − w]`: the scene's sides are walls.
7. **Fall.** `ny = y + vy × DT + 0.5 × g × DT × DT`, then `vy = vy + g × DT`, `grounded = false`. Moving down (`ny > y`), each platform that overlaps the player horizontally (`p.x < x + w` and `x < p.x + p.w`) with `y + h ≤ p.y < ny + h` is landed on: `ny` becomes the smallest `p.y − h` among them, `vy = 0`, `grounded = true`. Moving up (`ny < y`), each such platform with `ny < p.y + p.h ≤ y` bumps the head: `ny` becomes the largest `p.y + p.h`, `vy = 0`. The top of the scene is a ceiling: if `ny < 0`, `ny = 0` and `vy = 0`. Then `y = ny`.
8. **Fall out.** If `y > H`, the player dies (section 5) and the step ends.
9. **Coins.** Each coin not yet collected that overlaps the player is collected: `score += points`.
10. **Enemies.** If `safe > 0`, `safe −= 1`. Otherwise, if an enemy at its position for this `frame` (section 4) overlaps the player, the player dies and the step ends.
11. **Finish.** If a finish overlaps the player, `won = true`.

Two rectangles overlap when `a.x < b.x + b.w`, `b.x < a.x + a.w`, `a.y < b.y + b.h` and `b.y < a.y + a.h`: touching edges do not count. Only platforms are solid.

The move is exact for constant gravity, so the jump reaches the height `H = v²/2g` of `scene.md` section 5, and a jump that the reachability check allows can be made.

## 4. Enemies

An enemy patrols between `from` and `to` (the x of its left edge) at `speed`, starting at its own `x` clamped to `[from, to]` and walking right first. At `t = frame / 120`, with `L = to − from`: if `L ≤ 0` or `speed ≤ 0` it stands at the start. Otherwise `p = (start − from) + speed × t`, `m = p mod 2L`, and its x is `from + m` while `m ≤ L`, `from + 2L − m` after. Its y never changes.

## 5. Dying, winning, results

Dying adds one to `deaths` and puts the player back at the start (section 2). Coins stay collected; time runs on.

A run's result: `won`, `time = frame / 120` (frozen at the winning step), `score`, the coins collected out of all coins, and `deaths`.

## 6. Playtests

- **A person** plays in the studio's preview and may share the run with the team: its inputs, the scene version it was played on and a note. The project replays the inputs on that version to get the result it shows, so a shared result is always the real one, and anyone can watch the run.
- **The AI player** searches for inputs that reach the finish without dying, from the start, using these same steps, and then for each coin. Its report says whether it finished and how fast, which coins it reached, and what it could not do; the AI then reviews the scene with those facts and names the objects behind each problem, so each goes to the person who made them. Like a person's, the AI's run can be watched.
