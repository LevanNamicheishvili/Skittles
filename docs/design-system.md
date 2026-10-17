# Skittles design system

The web client (`web/src/styles.css`) follows the design system of the Conductor marketing site: calm warm
neutrals, hairline borders, small radii, system type, mono only for machine-ish text, and one quiet accent.
The canvas (`Board.tsx`) is the only loud thing on screen, so the chrome around it stays out of the way.

We took Conductor's **rules** (tokens, shapes, component patterns, motion). We did not take its brand: no logo,
copy, photos, avatars or animated assets. The Skittles mark is our favicon.

## Principles

1. **Neutral chrome, loud canvas.** UI is warm grey and near-black. Colour is reserved for data: author colours,
   the mediator, status.
2. **One shape.** Panels are `1px` border + `12px` radius on `--background`. Controls are `6px`. No heavy shadows;
   only toasts, dialogs and the board get one.
3. **Machine text is mono.** Versions, positions, the dev bar, history revisions, the console. Everything else is system sans.
4. **State is a dot.** Live, blocked, waiting and connected are a small dot beside plain text, not a coloured block.
5. **Motion is short and purposeful.** Things arrive (rise, sharpen, settle) in 300-500 ms and never loop for decoration.
   Every UI animation stops under `prefers-reduced-motion` (the canvas is animated in JS and is not affected).
6. **Keys are shown.** Shortcuts are real keycaps (`<kbd>`), as in Conductor's download dialog.

## Tokens

Defined once on `:root`, overridden on `:root[data-theme="dark"]`. Components never use raw colours.

| Token | Light | Dark | Use |
| --- | --- | --- | --- |
| `--background` | `#fff` | `#141110` | page, panels |
| `--foreground` | `#2c2826` | `#eae8e6` | text, primary buttons |
| `--muted` | `#fafaf9` | `#211e1c` | stage surface, agent bubbles, hover |
| `--muted-foreground` | `#756f6c` | `#a5a09c` | secondary text |
| `--border` | `#eae8e6` | `#ffffff1a` | every hairline |
| `--highlight` / `-foreground` | `#faf7f5` / `#594545` | `#2a1e1d` / `#f3ece7` | your chat bubble |
| `--tip-secondary` / `-border` / `-muted` | `#f8f7f6` / `#f3ece7` / `#7d5e59` | `#795f5d` / `#a4847f` / `#f0edea` | version badge |
| `--positive` | `#16a249` | `#16a249` | winnable, connected, applied |
| `--destructive` | `#dc2626` | `#f87171` | blocked, recording |
| `--warning` | `#b45309` | `#fbbf24` | waiting, playtest, approval needed |
| `--mediator` | `#7c3aed` | `#a78bfa` | mediator and negotiation (also drawn on the canvas) |

Author colours come from the room and are never tokens. `--brand` and `--terminal-bg` are the only Skittles-specific additions.

## Type and shape

- Sans: `ui-sans-serif, system-ui, sans-serif`. Mono: `ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas, monospace`.
- Body 14 px, secondary 12-13 px, panel titles 13 px / 500, the join heading 24 px / 600 with `-0.025em` tracking.
- Radius: badges `2px`, controls `6px`, bubbles and dialogs `8px`, panels `12px`.

## Components

| Component | Class | Notes |
| --- | --- | --- |
| Button | `button`, `.secondary`, `.ghost` | Default is inverted (foreground on background), 32 px. Secondary is outlined. Ghost is text. Focus is a 2 px ring. |
| Toggle | `.toggle`, `.toggle.on` | Outlined; on is filled. |
| Status | `.status`, `.status.bad` | Dot + text. Click replays the ghost runner. |
| Version badge | `.version` | Conductor's changelog badge: mono, tracked, tinted. |
| Presence chip | `.chip` | Author-coloured avatar, name, green dot (everyone listed is connected). |
| Bubbles | `.msg.you`, `.msg.agent`, `.msg.system`, `.msg.thinking` | You: highlight, right. Agent: muted surface. System: centred text. Thinking: pulsing dots. |
| Card | `.card`, `.card.report`, `.card.suggestion` | One shape, tone via `--tone`: mediator violet, playtest amber, suggested fix green. Label is `.card-head`. |
| Option | `.option`, `.option.agent`, `.option.cancel` | Outlined row; agent proposals get a 3 px left edge in the author's colour; cancel is dashed. |
| History row | `.history li` | Mono revision, avatar, summary. Current row is `--muted`. |
| Landing | `Landing.tsx`, `.landing` | Conductor's homepage layout, always dark: sticky header, hero (live glyph sky, headline with a scrambling second line, lede, join form, quote), the app window running the scripted demo with a 5-step story bar, the mission ("two fine changes, broken together"), measured numbers, four feature sections with looping demos, a call to action, footer. Shown to anyone without `?role=`. |
| Live sky | `LiveSky` in `Landing.tsx` | Digits and symbols drift and flicker in the brand colours, bronze `#9a6b3f` at the edges and red-orange `#ef4f23` where clouds are thick, over twinkling stars. Drawn from a glyph sheet at about 20 fps, paused off screen, static under reduced motion. No source art. |
| Toast | `.toast` | Inverted tooltip. |
| Dialog | `.report-panel` | `8px` radius, `--shadow-lg`, scales in from 95%. |
| Keycap | `kbd` | 20 px mono keycap. |
| Terminal | `.devbar`, `.nerd` | Dev bar is a muted mono strip; the nerd console is always dark, whatever the theme. |

## Motion

| Pattern | Used for | Timing |
| --- | --- | --- |
| `msg-in` (fade + 4 px rise) | chat bubbles, history rows | 300 ms ease-out |
| `card-in` (fade + 8 px rise + blur 4 px to 0) | cards, join card | 500 ms `cubic-bezier(.2,0,0,1)` |
| `dialog-in` (fade + scale from .95) | report panel, console | 200 ms |
| `live` (halo breathing) | status and waiting dots | 2 s loop |
| Arrow nudge (`translateX(4px)` on hover) | join buttons | 200 ms |

## Theme

Dark by default, like conductor.build. `?theme=light|dark|system` picks another and is remembered in `localStorage`
(`skittles-theme`). The join screen is always dark, as Conductor's hero is: it carries the `.dark` class, which
applies the dark tokens whatever the page theme.

## Adding UI

1. Use tokens only. If you need a new colour, it is data, not chrome: say why.
2. Reuse a class above before adding one. A new panel is a bordered `12px` surface; a new control is `6px`.
3. Put machine text in mono, secondary text in `--muted-foreground`, and show state as a dot.
4. Animate arrivals with the existing keyframes; do not add looping motion.
5. Check both themes and `1280x720`, `1440x900`, `1920x1080`.

## Preview

`cd web && npm run dev` (hot reload, proxies to the room on :3000). The server on :3001/:3000 serves `web/dist`,
so the new look appears there after `cd web && npm run build`.
