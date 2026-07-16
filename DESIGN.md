---
version: 1.0
name: Looper-design-system
description: A native macOS 26 Liquid Glass command center for AI development orchestration. Content — tasks, runs, and living terminals — sits on calm system surfaces while all chrome (sidebar, toolbar, inspector) floats above it as translucent glass. One accent color carries every interactive signal; run states speak through five semantic status colors paired with SF Symbols. Typography is the stock macOS SF Pro ladder; the terminal is the only permanently dark surface, framed like a product photograph on a pedestal.

colors:
  accent: "#007AFF"                  # Color.accentColor — dark: #0A84FF. The ONLY interactive tint.
  ink: "#000000D9"                   # Color.primary / labelColor — dark: #FFFFFFD9 (85%)
  ink-secondary: "#0000008C"         # Color.secondary / secondaryLabelColor — dark: #FFFFFF8C (55%)
  ink-tertiary: "#00000042"          # .tertiary / tertiaryLabelColor — dark: #FFFFFF42 (26%)
  ink-quaternary: "#00000019"        # .quaternary — dark: #FFFFFF19 (10%)
  canvas-window: "#ECECEC"           # windowBackgroundColor — dark: #282828
  canvas-content: "#FFFFFF"          # controlBackgroundColor / List background — dark: #1E1E1E
  canvas-under-page: "#F5F5F7"       # alternate content wells, grouped-form background — dark: #232323
  surface-terminal: "#1E1E1E"        # terminal surface — SAME in light and dark; the one mode-invariant surface
  surface-glass: "Material.bar"      # sidebar / toolbar / inspector chrome — system material, never a hex
  status-todo: "#8E8E93"             # Color(.systemGray) — dark: #98989D
  status-in-progress: "#007AFF"      # Color.accentColor — a run actively executing
  status-in-review: "#FF9500"        # Color.orange — dark: #FF9F0A. Agent done, human attention required
  status-done: "#28CD41"             # Color.green — dark: #32D74B
  status-failed: "#FF3B30"           # Color.red — dark: #FF453A
  separator: "#0000001A"             # separatorColor — dark: #FFFFFF1A. Hairlines only
  on-accent: "#FFFFFF"

typography:
  large-title:
    fontFamily: "SF Pro Display (Font.largeTitle)"
    fontSize: 26px
    fontWeight: 400
    use: "Setup wizard hero, empty-window welcome"
  title-1:
    fontFamily: "SF Pro Display (Font.title)"
    fontSize: 22px
    fontWeight: 400
    use: "Settings pane titles, wizard step titles"
  title-2:
    fontFamily: "SF Pro Display (Font.title2)"
    fontSize: 17px
    fontWeight: 400
    use: "Detail panel task title"
  title-3:
    fontFamily: "SF Pro Display (Font.title3)"
    fontSize: 15px
    fontWeight: 400
    use: "Section heads inside detail panel and settings"
  headline:
    fontFamily: "SF Pro Text (Font.headline)"
    fontSize: 13px
    fontWeight: 600
    use: "Task row primary line, run card title, emphasized labels"
  body:
    fontFamily: "SF Pro Text (Font.body)"
    fontSize: 13px
    fontWeight: 400
    use: "Default reading text — task descriptions, form values"
  callout:
    fontFamily: "SF Pro Text (Font.callout)"
    fontSize: 12px
    fontWeight: 400
    use: "Secondary metadata rows, badge labels"
  subheadline:
    fontFamily: "SF Pro Text (Font.subheadline)"
    fontSize: 11px
    fontWeight: 400
    use: "Sidebar section headers (uppercased), timestamps"
  footnote:
    fontFamily: "SF Pro Text (Font.footnote)"
    fontSize: 10px
    fontWeight: 400
    use: "Fine print, version strings; use sparingly"
  terminal-mono:
    fontFamily: "SF Mono (Font.system(.body, design: .monospaced))"
    fontSize: 12px
    fontWeight: 400
    use: "Terminal surface, branch names, paths, task IDs"
  numeric-tabular:
    fontFamily: "SF Pro Text + monospacedDigit()"
    fontSize: 13px
    fontWeight: 400
    use: "Elapsed run timers, counters — digits must not jitter"

rounded:
  xs: 5px          # menu-adjacent micro controls
  sm: 6px          # inline chips, small text fields (legacy-size controls)
  md: 10px         # task rows (List .inset), run cards, form groups
  lg: 16px         # terminal container, detail panel cards, popover-like panels
  xl: 26px         # floating glass panels (matches window corner concentricity)
  capsule: 9999px  # ALL buttons, status badges, filter chips — the Liquid Glass control grammar

spacing:
  xxs: 4px
  xs: 8px
  sm: 12px
  md: 16px
  lg: 20px         # standard window-edge content margin
  xl: 24px
  xxl: 32px
  section: 40px

components:
  window-shell:
    structure: "NavigationSplitView: sidebar | task list | detail"
    minSize: 960x600
  sidebar:
    backgroundColor: "{colors.surface-glass}"
    width: 220–280 (ideal 240)
    typography: "{typography.body}"
  sidebar-pipeline-row:
    typography: "{typography.body}"
    height: 28px
    rounded: "{rounded.sm}"
  toolbar:
    backgroundColor: "{colors.surface-glass}"
    style: ".toolbar + automatic glass; never custom-drawn"
  task-row:
    backgroundColor: "{colors.canvas-content}"
    typography: "{typography.headline} + {typography.callout}"
    rounded: "{rounded.md}"
    padding: 12px 16px
  status-badge:
    typography: "{typography.callout}"
    rounded: "{rounded.capsule}"
    padding: 2px 8px
    anatomy: "SF Symbol + label, status color at 100% icon / 15% background tint"
  task-detail-panel:
    backgroundColor: "{colors.canvas-window}"
    width: 320–460 (ideal 380)
    padding: "{spacing.lg}"
  run-card:
    backgroundColor: "{colors.canvas-content}"
    rounded: "{rounded.lg}"
    padding: "{spacing.md}"
    border: "1px {colors.separator}"
  terminal-container:
    backgroundColor: "{colors.surface-terminal}"
    rounded: "{rounded.lg}"
    inset: "{spacing.md} from content edges"
    typography: "{typography.terminal-mono}"
  button-primary:
    style: ".buttonStyle(.glassProminent)"
    backgroundColor: "{colors.accent}"
    textColor: "{colors.on-accent}"
    rounded: "{rounded.capsule}"
  button-secondary:
    style: ".buttonStyle(.glass)"
    textColor: "{colors.ink}"
    rounded: "{rounded.capsule}"
  button-destructive:
    style: ".buttonStyle(.glass) + role: .destructive"
    textColor: "{colors.status-failed}"
    rounded: "{rounded.capsule}"
  empty-state:
    component: "ContentUnavailableView — never custom-built"
  settings-form:
    style: "Form(.grouped) inside TabView settings scene"
    backgroundColor: "{colors.canvas-under-page}"
  setup-wizard:
    presentation: "sheet, glass background"
    typography: "{typography.large-title} → {typography.body}"
    rounded: "{rounded.xl}"
---

# Looper Design System

> **Authority**: This document is the single source of truth for all Looper UI work.
> It is derived from the Apple Human Interface Guidelines (macOS 26, Liquid Glass design
> language) — **not** from Looper's current code. Where an existing view disagrees with
> this document, the view is wrong: refactor toward the spec, never propagate legacy styling.

## Overview

Looper is a **command center, not a dashboard**. The user parks long-lived project
pipelines in it and watches AI agents work inside living terminals. The design language
follows from that: the *content layer* (tasks, runs, terminal output) is calm, opaque,
and information-dense in the quiet macOS way; the *chrome layer* (sidebar, toolbar,
inspector) is Liquid Glass — translucent, floating, and deferential. The terminal is
treated the way Apple treats a product photograph: a permanently dark, edge-inset
surface resting on the content canvas, the one object in the app that never changes
with appearance mode.

Nothing in Looper is custom-drawn when a system control exists. Colors are semantic
system colors, type is the stock SF Pro ladder, controls are capsules, materials are
system materials. The app should feel like Apple shipped it in the macOS 26 wave —
closer to Xcode's discipline than to a themed Electron tool.

**Key Characteristics:**

- **Two-layer world.** Opaque content below, glass chrome above. Glass never touches
  the content layer: no glass cards, no glass list rows, no glass inside the detail panel.
- **One accent.** `{colors.accent}` (the system accent color) carries every interactive
  signal — buttons, links, selection, focus, progress. No second brand color exists.
- **Five status voices.** Run/task state is the only place color multiplies:
  gray (todo), accent-blue (in progress), orange (in review), green (done), red (failed).
  Each is always paired with an SF Symbol — color is never the sole indicator.
- **Capsule control grammar.** Every button, badge, and chip is a capsule
  (`{rounded.capsule}`), per the Liquid Glass control language. Rectangular-rounded
  shapes are reserved for *containers* (rows, cards, terminal).
- **The terminal is the hero.** Permanently dark (`{colors.surface-terminal}`),
  inset with `{rounded.lg}` corners, monospaced. Everything around it recedes.
- **System-first.** Semantic colors, Dynamic Type text styles, SF Symbols,
  `ContentUnavailableView`, `.glassEffect()` and system materials. Hex values appear
  in this document as *reference renderings* of semantic tokens, never as literals in code.

## Colors

> **Implementation rule #1**: never write a hex literal in SwiftUI code. Every token
> below names the semantic SwiftUI/AppKit color to use; the hex pairs shown are what
> those semantics resolve to in light/dark and exist only so designers and agents can
> reason about contrast.

### Accent

- **Accent** (`{colors.accent}` — `Color.accentColor`, #007AFF / #0A84FF): the single
  interactive color. Prominent buttons, selection highlight, links, progress bars, the
  in-progress status. Looper does not override the user's system accent choice —
  the app tints with whatever the user picked in System Settings. Design against the
  default blue; verify against graphite (the low-chroma worst case).

### Text (ink ladder)

- **Ink** (`{colors.ink}` — `Color.primary`): all primary text and icons.
- **Ink Secondary** (`{colors.ink-secondary}` — `.secondary` / `.foregroundStyle(.secondary)`):
  metadata, timestamps, descriptions in rows.
- **Ink Tertiary / Quaternary** (`.tertiary` / `.quaternary`): placeholder text,
  disabled states, faint glyphs. Always use the hierarchical styles — never manual opacity.
- Text on accent fills is `{colors.on-accent}` (white) — provided automatically by
  `.glassProminent` / `.borderedProminent`.

### Surfaces

- **Window Canvas** (`{colors.canvas-window}` — `windowBackgroundColor`): the base
  canvas behind the detail panel and any non-list content region.
- **Content Canvas** (`{colors.canvas-content}` — `controlBackgroundColor`): list and
  card fill. `List` provides it automatically; never repaint it.
- **Under-page** (`{colors.canvas-under-page}`): grouped-form wells in Settings and
  the setup wizard. Comes free with `Form(.grouped)`.
- **Terminal** (`{colors.surface-terminal}` — #1E1E1E in *both* modes): the only
  mode-invariant surface in the app. The terminal keeps its own theme; the app never
  recolors PTY content.
- **Glass** (`{colors.surface-glass}`): sidebar, toolbar, inspector chrome. This is a
  *system material* (`NavigationSplitView` sidebar material, toolbar glass,
  `.glassEffect()` for custom floating elements) — it has no hex and must never be
  simulated with a translucent fill.

### Status

The five run/task states are the only sanctioned use of non-accent chromatic color:

| State | Token | System color | SF Symbol |
|---|---|---|---|
| `todo` | `{colors.status-todo}` | `Color(.systemGray)` | `circle.dashed` |
| `inProgress` | `{colors.status-in-progress}` | `Color.accentColor` | `play.circle.fill` (or `ProgressView` when live) |
| `inReview` | `{colors.status-in-review}` | `Color.orange` | `eye.circle.fill` |
| `done` | `{colors.status-done}` | `Color.green` | `checkmark.circle.fill` |
| `failed` | `{colors.status-failed}` | `Color.red` | `xmark.circle.fill` |

Status color is applied to the symbol and (at ~15% opacity) to the badge capsule fill.
It never colors row text, and never appears outside a status context — orange means
"needs review" everywhere or nowhere.

### Hairlines

- **Separator** (`{colors.separator}` — `separatorColor`): 1px hairlines on run cards
  and between detail-panel sections. Lists use their built-in separators. No other
  borders exist in the system.

### Gradients

**None.** Depth comes from the glass material and surface changes, never from
decorative gradients or tinted overlays.

## Typography

### Font Family

- **UI text**: SF Pro (Display ≥ 20pt, Text < 20pt) — obtained exclusively through
  SwiftUI text styles (`.largeTitle`, `.title` … `.caption`). Never `Font.system(size:)`
  with a fixed number for UI copy; text styles keep Dynamic Type and the automatic
  Display/Text optical switch working.
- **Monospace**: SF Mono via `.monospaced()` design — terminal, branch names, file
  paths, task IDs. Timers and counters use `.monospacedDigit()` on the body style.

### Hierarchy

| Token | Style | Size | Weight | Use |
|---|---|---|---|---|
| `{typography.large-title}` | `.largeTitle` | 26 | 400 | Wizard hero, welcome screen |
| `{typography.title-1}` | `.title` | 22 | 400 | Settings pane / wizard step titles |
| `{typography.title-2}` | `.title2` | 17 | 400 | Detail panel task title |
| `{typography.title-3}` | `.title3` | 15 | 400 | Section heads in panels/forms |
| `{typography.headline}` | `.headline` | 13 | 600 | Task row primary line, run card title |
| `{typography.body}` | `.body` | 13 | 400 | Default text everywhere |
| `{typography.callout}` | `.callout` | 12 | 400 | Metadata, badge labels |
| `{typography.subheadline}` | `.subheadline` | 11 | 400 | Sidebar section headers (uppercased) |
| `{typography.footnote}` | `.footnote` | 10 | 400 | Fine print only |
| `{typography.terminal-mono}` | `.body.monospaced()` | 12–13 | 400 | Terminal & code-like strings |
| `{typography.numeric-tabular}` | `.body.monospacedDigit()` | 13 | 400 | Elapsed timers, counters |

### Principles

- **The weight ladder is 400 / 600.** Regular for reading, semibold (`.headline` or
  `.bold()` in context) for emphasis. No `.medium`, no `.heavy`, no scattered
  `fontWeight()` calls — use `bold()` so the system picks the right weight for context.
- **Hierarchy by ink, not size.** Prefer `primary` vs `secondary` foreground styles
  over adding font sizes. A task row is `.headline` + `.callout.secondary`, not three
  font sizes.
- **`.caption`/`.caption2` are near-banned.** At macOS sizes they are 10pt; use
  `.footnote` sparingly and nothing below it.
- **Truncate, don't wrap, in rows.** Task titles truncate with `.lineLimit(1)` middle/tail
  truncation; full text lives in the detail panel.

## Layout

### Structure

Looper is a three-column `NavigationSplitView`:

```
┌──────────┬──────────────────────┬───────────────┐
│ Sidebar  │  Content             │ Detail        │
│ (glass)  │  task list / runs /  │ (inspector)   │
│ pipelines│  terminal            │ task + run    │
│ 220–280  │  flexible, ≥ 460     │ 320–460       │
└──────────┴──────────────────────┴───────────────┘
```

- **Sidebar**: pipelines as a source list; glass material comes free from
  `NavigationSplitView`. Sections (`Pipelines`, `Providers`) use
  `{typography.subheadline}` uppercased headers.
- **Content**: the task list, or the terminal grid when a run is focused.
- **Detail**: task metadata, run history, and actions. Collapsible; the content column
  is never sacrificed to keep it open.
- **Minimum window**: 960 × 600. Below-threshold layouts collapse detail first,
  sidebar second (system behavior — do not fight it).

### Spacing System

- **Base unit 4pt**, structural rhythm on 8pt: `{spacing.xs}` 8 · `{spacing.sm}` 12 ·
  `{spacing.md}` 16 · `{spacing.lg}` 20 · `{spacing.xl}` 24.
- **Window-edge content margin**: `{spacing.lg}` (20pt) — the standard macOS margin.
- **List row internal padding**: 12pt vertical × 16pt horizontal.
- **Between cards / sections in the detail panel**: `{spacing.md}` (16pt); between
  major sections `{spacing.section}` (40pt) in wizard/settings.
- Avoid hard-coded one-off values; if a spacing isn't a token, it's probably wrong.

### Whitespace Philosophy

Desktop-dense, not web-airy. Rows are 28–44pt tall, panels breathe with 16–20pt
padding, and the terminal gets the most generous framing in the app
(`{spacing.md}` inset on all sides) — it is the artifact on the pedestal.

## Elevation & Depth

| Level | Treatment | Use |
|---|---|---|
| Content | Opaque semantic surface, no shadow, no border | Lists, cards, detail panel, terminal |
| Hairline | 1px `{colors.separator}` | Run cards, section splits |
| Glass | System material + automatic shadow | Sidebar, toolbar, inspector chrome, floating action clusters |
| Overlay | Sheet / popover with system glass background | Setup wizard, confirmations, popovers |

**Shadow philosophy**: Looper never draws a manual `shadow()`. The only shadows on
screen are the ones the system casts under glass chrome and overlays. Elevation inside
the content layer is expressed by surface change (`{colors.canvas-window}` →
`{colors.canvas-content}`) and hairlines — exactly like Finder and Xcode.

**Glass rules** (Liquid Glass discipline):

- Glass is for the *navigation/control layer only*. Never put `.glassEffect()` on list
  rows, cards, badges, or anything that scrolls with content.
- Custom floating controls (e.g. a floating "New Task" cluster over the terminal) use
  `.glassEffect()` in a `GlassEffectContainer`; prefer `.buttonStyle(.glass)` /
  `.glassProminent` before reaching for raw `glassEffect`.
- Never simulate glass with `Color.white.opacity(n)` or a blur — accessibility's
  Reduce Transparency must be able to swap the material automatically.

## Shapes

### Border Radius Scale

| Token | Value | Use |
|---|---|---|
| `{rounded.sm}` | 6px | Inline chips, sidebar row selection highlight |
| `{rounded.md}` | 10px | Task rows (inset list style), form groups |
| `{rounded.lg}` | 16px | Run cards, terminal container, detail-panel cards |
| `{rounded.xl}` | 26px | Sheets and floating glass panels |
| `{rounded.capsule}` | ∞ | All buttons, status badges, filter chips, search fields |

### Principles

- **Capsule = control, rounded-rect = container.** If it's clickable and standalone,
  it's a capsule. If it holds content, it's `{rounded.md}`/`{rounded.lg}`.
- **Concentricity.** Nested radii shrink by the inset: a `{rounded.lg}` (16) card with
  12pt padding gives inner elements ~4–6pt radii. Use `ConcentricRectangle` /
  `.rect(corners: .concentric)` when nesting against window or panel corners rather
  than hand-picking numbers.
- `RoundedRectangle` default `.continuous` curvature everywhere; never `.circular`.

## Components

### Window Chrome

**`window-shell`** — `NavigationSplitView` with three columns (see Layout). Title bar
merges with toolbar (`.toolbar` items only; no custom title bar drawing). Window
supports full-screen; the terminal grid expands, chrome stays glass.

**`toolbar`** — System toolbar with SF Symbol items: refresh (manual provider fetch),
new task, run/stop, detail toggle. Primary action may be `.glassProminent`; everything
else is plain toolbar items. Never draw toolbar backgrounds.

**`sidebar` / `sidebar-pipeline-row`** — Source-list style. Each pipeline row: SF Symbol
+ name in `{typography.body}` + trailing badge count of active runs (system badge).
Selection is the system accent capsule/rounded highlight. Status dots on pipelines use
the status colors at 8pt diameter.

### Buttons

**`button-primary`** — `.buttonStyle(.glassProminent)` (accent-filled capsule). One per
context, maximum: "Start Run", "Approve", wizard "Continue". Everything else steps down.

**`button-secondary`** — `.buttonStyle(.glass)` (neutral glass capsule): "Retry",
"Open in Finder", "View Diff".

**`button-destructive`** — `.glass` with `role: .destructive` (red label on neutral
capsule): "Delete Pipeline", "Discard Worktree". Always behind a `confirmationDialog`.

Press/hover/focus states are system-provided — never hand-rolled. Minimum click target
24×24pt; every action reachable by keyboard and surfaced in menus where idiomatic.

### Content

**`task-row`** — One task in the list. Anatomy, left → right: status symbol
(`{components.status-badge}` icon-only form) · title in `{typography.headline}`
(1 line, truncating) over metadata line (`provider · age · branch`) in
`{typography.callout}` + `.secondary` · trailing elapsed timer in
`{typography.numeric-tabular}` when running. Inset list style gives the
`{rounded.md}` selection shape. No custom hover effects, no shadows.

**`status-badge`** — Capsule chip: SF Symbol + label in `{typography.callout}`,
symbol in full status color, capsule fill at ~15% of the same color, text in
`{colors.ink}`. Icon-only variant (symbol alone, no capsule) in dense rows.
`inProgress` may replace the symbol with a 12pt `ProgressView` while a run is live.

**`run-card`** — One run in the detail panel's history. `{colors.canvas-content}` fill,
1px `{colors.separator}` border, `{rounded.lg}`, `{spacing.md}` padding. Header: run
number + status badge + elapsed time. Body: branch name in `{typography.terminal-mono}`,
worktree path, exit summary. Footer actions: `button-secondary` row ("Resume",
"Open PR", "Reveal Worktree").

**`task-detail-panel`** — Inspector column on `{colors.canvas-window}`. Stack:
task title (`{typography.title-2}`) → status badge → description (`{typography.body}`,
selectable) → metadata table (`LabeledContent` rows) → run history (`run-card` stack)
→ pinned action bar at bottom with the context's single `button-primary`.

**`terminal-container`** — The hero. `{colors.surface-terminal}` fill in both modes,
`{rounded.lg}` clip, inset `{spacing.md}` from the content region on all sides.
Hosts `TerminalSurfaceView`; the app draws nothing inside it. Header strip above the
surface (not glass — opaque content layer): run title + status badge + elapsed timer
+ stop button. Multiple concurrent terminals tile in a grid with `{spacing.sm}` gutters,
up to `maxConcurrentRuns`.

**`empty-state`** — Always `ContentUnavailableView` with an SF Symbol, one-line title,
one-line guidance, and at most one action button. Never a custom illustration stack.
(No pipelines → "Add a Pipeline"; no tasks → provider hint; provider error →
`ContentUnavailableView` with retry.)

### Forms & Overlays

**`settings-form`** — Standard macOS Settings scene: `TabView` toolbar-style tabs
(General, Providers, Agents, Advanced), each a `Form(.grouped)` on
`{colors.canvas-under-page}`. Controls wrapped in `LabeledContent`. No custom form
layouts.

**`setup-wizard`** — Sheet with `{rounded.xl}` system corners. One decision per step:
hero SF Symbol → `{typography.large-title}` → one paragraph `{typography.body}`
`.secondary` → the step's control → `button-primary` ("Continue") with plain "Back".
Progress via system `ProgressView` or step dots; no custom chrome.

**Dialogs** — `confirmationDialog` for destructive confirmation, `alert` for errors
that block. Sheet for anything with more than two controls.

## Do's and Don'ts

### Do

- Use semantic system colors and materials for every surface; the hexes in this file
  are reference renderings, not values to type.
- Route every interactive signal through `{colors.accent}` and system selection styles.
- Pair every status color with its SF Symbol — state must survive grayscale.
- Keep glass on the chrome layer (sidebar/toolbar/inspector/floating controls) and
  content opaque.
- Use text styles (`.body`, `.headline` …) so Dynamic Type and the SF Display/Text
  switch work for free.
- Use `ContentUnavailableView`, `LabeledContent`, `Label`, `confirmationDialog` —
  system vocabulary before custom vocabulary.
- Test every screen in light, dark, increased-contrast, and Reduce Transparency;
  the design must hold in all four without branches in code.
- Keep the terminal surface untouched — its theme belongs to Ghostty/the user.

### Don't

- Don't hardcode hex/RGB anywhere in SwiftUI code — no `Color(red:green:blue:)`,
  no `#1E1E1E` literals (the terminal container uses the terminal theme's background
  via the terminal API, not a painted rect).
- Don't introduce a second accent or decorate with gradients.
- Don't apply `.shadow()` manually, anywhere.
- Don't put `.glassEffect()` on scrolling content, rows, or cards.
- Don't use `fontWeight(.medium)`/`.semibold` scatter — the ladder is 400/600 via
  text styles and `bold()`.
- Don't fix font sizes with `Font.system(size:)` for UI text.
- Don't build custom empty states, custom toolbars, custom window chrome, or custom
  button shapes when the system provides one.
- Don't use color as the only differentiator of run state.
- Don't let AI-slop patterns in: no emoji in UI copy, no gratuitous SF Symbol
  decoration on every label, no card-inside-card-inside-card nesting.

## Window & Resizing Behavior

| Width | Behavior |
|---|---|
| ≥ 1280pt | All three columns visible; terminal grid up to 3 tiles wide |
| 1080–1279pt | Detail panel narrows to 320; terminal grid 2 tiles |
| 960–1079pt | Detail collapses (toggle from toolbar); content column keeps ≥ 460 |
| < 960pt | Not supported — window minimum is 960 × 600 |

- Column resize handles are system-provided; ideal/min/max via
  `navigationSplitViewColumnWidth(min:ideal:max:)` with the values in Layout.
- Full screen: content column and terminal grid absorb all extra width; text measure
  in the detail panel caps at ~640pt.
- All layouts must survive 2× Dynamic Type without clipping — rows grow, grids reflow.

## Iteration Guide

1. Change ONE component at a time; reference its YAML key (`{components.task-row}`,
   `{components.terminal-container}`) in commits and reviews.
2. New states of an existing component are new YAML entries with a `-suffix`
   (`status-badge-icon-only`), not prose forks.
3. Use `{token.refs}` in specs and shared constants in code (a `DesignTokens` enum
   mirroring this file) — never inline values.
4. Prefer deleting custom styling over adding it: the target implementation of most
   components is "system control + tokens + nothing else."
5. When emphasis is needed, step the ink ladder or the surface — add chrome only as
   a last resort.
6. Any deviation from HIG must be argued in the PR description and recorded here in
   Known Gaps; silent divergence is a bug.

## Known Gaps

- Liquid Glass API surface (`glassEffect`, `GlassEffectContainer`, `.glass` button
  styles) is macOS 26-only and still evolving; verify exact modifier signatures against
  the current SDK (`swiftui-pro` skill references) before use.
- Terminal theming beyond background (ANSI palette, cursor) is delegated to
  libghostty configuration and intentionally out of scope here.
- Menu bar / Dock / notification surfaces are not yet specified; add them here before
  building.
- App icon and any brand mark are unspecified; the in-app design deliberately carries
  zero branding until then.
