# INTERACTION.md

Single source of truth for Looper's **interaction architecture** — how information reaches the user and how the user intervenes in running loops. Sits beside [`DESIGN.md`](DESIGN.md) (visual system: colors, type, materials) and [`ROADMAP.md`](ROADMAP.md) (positioning, iteration order). When a view's structure or flow conflicts with this doc, the view is wrong.

## First Principle: Attention Routing over Navigation

With N pipelines × M parallel Runs, the scarce resource is the owner's attention, not screen space. Most Runs need nothing; a few are waiting on human judgment. Navigation-first UI ("pick project → pick task → inspect") makes the user patrol. Looper inverts this:

> **Things that need the human come to the human. Navigation is the fallback, not the spine.**

The human is *on* the loop, not *in* it: their judgment is inserted at the highest-value points — never full-time watching, never full hands-off.

## Three Altitudes, One Window

| Altitude | Surface | Question it answers | Role |
|----------|---------|--------------------|------|
| 3000 ft | **Inbox** | "What needs me right now?" | Default landing surface |
| 300 ft | **Live Wall** | "Is everything healthy?" | Ambient situational awareness |
| 3 ft | **Run Cockpit** | "What exactly is this Run doing?" | Drill-down and deep intervention |

Plus one non-altitude surface: **Manage** — the legacy sidebar + list + detail layout, repurposed as the home of everything that is *configuration rather than supervision* (see "The Manage Surface" below). Navigation lives there — as the fallback, not the spine.

### Altitude 1 — Inbox (default landing)

A cross-pipeline queue of pending decisions, sorted by urgency. **Inbox zero = all loops healthy.**

```
⚠ NEEDS YOU (3)
┌──────────────────────────────────────────────────┐
│ 🟠 looper-app · Fix login timeout                 │
│    verify passed, awaiting review · diff +214/−89 │
│    [Evidence] [Approve ✓] [Send back ↩]           │
├──────────────────────────────────────────────────┤
│ ❓ web-console · Rework payment page              │
│    Agent asks: payment SDK v3 or v2 compat?       │
│    ( v3 · recommended )  ( v2 )  [Open terminal]  │
├──────────────────────────────────────────────────┤
│ 🔴 data-sync · Incremental sync                   │
│    gate failed ×3, retry budget exhausted          │
│    [Failure report] [Grant 2 retries] [Take over] │
└──────────────────────────────────────────────────┘
── RUNNING QUIETLY (5) · QUEUED (2) ── collapsed ──
```

**Cards are a reverse issue system**: machine-generated decision requests filed *to* the human. Card types (≈ issue templates), each with a fixed resolution set:

| Type | Trigger | Resolutions |
|------|---------|-------------|
| Review request | verify passed, Run entered `inReview` | approve / send back (reason **required**) / open evidence / open PR |
| Question | agent asks for a business judgment (intercepted from SDK event stream, rendered with option buttons) | pick option / open terminal to discuss |
| Failure escalation | retry budget exhausted, back to `todo` | view report / grant more retries / open worktree (Finder · editor · terminal) / take over |
| Checkpoint arrival | a user-placed gate was reached (see Interventions L3) | release / roll back / take over |
| System | fault not tied to any Run: agent CLI missing, provider auth expired, worktree creation failed, gate command not found | open fix flow / dismiss |

Card rules — where this deliberately differs from issues:

1. **Minutes-level lifespan → resolution happens ON the card.** One click. Any "open detail then act" flow is a design failure.
2. **Cards self-heal.** If the situation resolves itself (agent recovers, retry succeeds), the card auto-withdraws and archives as "self-resolved". No zombies.
3. **Cards are not discussion threads.** No comment trails; escalation = open the Cockpit.
4. **Resolved cards archive onto the Run's timeline** and become failure-signal data (ROADMAP M3). Inbox and observability are the same data in two tenses: *pending = inbox, resolved = history.*

**Bidirectional**: the Inbox also carries a quick-capture entry (⌘N / top input) — the user "files an issue" to a pipeline, which enqueues as a Local Task. Decisions flow down to the human; intent flows up to the machine, in one surface.

#### Review cards: closing the loop

- **Evidence** opens the Cockpit's evidence panel: gate results and verify verdict as structured summaries, the diff rendered inline (native diff viewer). No detour through external tools just to decide.
- **PR link**: the post-run git workflow pushes the branch and auto-creates a PR; the PR link appears on the review card and as a marker on the Run timeline. *Approve* marks the task `done` and cleans up the worktree — merging stays on the PR (GitHub is the merge surface; Looper does not duplicate it).
- **Send back requires a reason.** The reason is automatically delivered to the retry Run as a boundary steering note — human judgment becomes machine-consumable context, never a bare rejection. Rollbacks are recorded as process escapes (ROADMAP M3).

#### Failure forensics

A failed Run's preserved worktree is reachable from its escalation card and from any failure marker on the timeline — open in Finder, editor, or a Looper terminal tab. The Manage surface lists preserved worktrees per pipeline with age, for one-click cleanup once forensics are done.

### Altitude 2 — Live Wall

Mission-Control-style grid of live Run tiles across all pipelines:

```
┌─ looper-app ─────────┐ ┌─ web-console ────────┐
│ Fix login timeout    │ │ Payment page rework  │
│ ●●●○ verify          │ │ ●○○○ implement       │
│ "Running E2E, 12/14" │ │ "Reading PayService" │
│ ⏱ 14:32  ↻ 1         │ │ ⏱ 02:03  ↻ 0         │
└──────────────────────┘ └──────────────────────┘
```

- **Live activity digest** (the quoted line): the agent's current action compressed into one human sentence from the AgentSDK event stream — far denser than a mini terminal thumbnail. This is the killer use of the existing `AgentEvent` pipeline.
- `●●●○` = lifecycle progress (implement → gate → verify → review); `↻ n` = retry count; tile edge color = the five semantic status colors from DESIGN.md.
- **The loop is the visual motif** (the product is named Looper): retries render as an actual small loop glyph — which lap, which arc it's stuck on — not a bare number. This motif recurs across all three altitudes.
- **Density rules**: above ~8 live tiles, group by pipeline with collapsible headers. Sort is attention-first — tiles with a pending card float to the top, then by lifecycle stage. Filter chips: pipeline, status. Queued (not yet started) tasks render as flat ghost tiles at the end of their pipeline group.

### Altitude 3 — Run Cockpit

Full view of one Run. Terminal on the left (existing capability); on the right:

- **Loop timeline**: the Run's lifecycle on a horizontal axis — implement / gate / verify segments, retries drawn as loop-back arcs, each failure a clickable marker (opens the failure report), steering notes and checkpoints as markers. This is also ROADMAP M3's per-run observability view — one design, two uses.
- **Evidence panel**: gate results, diff summary, verify verdict (the M1 evidence bundle).
- **Intervention bar**: the five levels below.

### The Manage Surface (fallback navigation)

The legacy sidebar + list + detail layout, repurposed. Organized by pipeline; owns everything that is configuration rather than supervision:

- **Pipeline settings**: project path, agent command template, `maxConcurrentRuns`, gate command templates (M1), retry budget (M2), knowledge asset files (M4).
- **Provider configuration**: auth, polling interval, task filter, manual refresh.
- **Task backlog**: provider-fetched tasks not yet started. This is where start order is decided — reorder (jump the queue), reroute a task to a different pipeline, start now. When active Runs hit `maxConcurrentRuns`, the queue state is visible here in full and summarized elsewhere ("3 running · 2 queued" in the Inbox's collapsed line, ghost tiles on the Live Wall).
- **History**: past tasks/runs with their archived cards and timelines; preserved failure worktrees with cleanup.

Scope boundary: app-level preferences (language, updates, appearance) stay in a **standard macOS Settings scene**. Do not inbox-ify configuration; do not settings-ify decisions.

## Interventions: Five Escalating Levels

| Level | Interaction | Mechanism | Interrupts agent? |
|-------|-------------|-----------|-------------------|
| 1. Steering note | Type a sentence on any Run card/tile ("don't touch the legacy dir") | See delivery modes below | No |
| 2. Answer | Agent question surfaces as an Inbox card with options | Intercept SDK question event, inject the answer back | No |
| 3. Checkpoint gate | "Stop before verify and wait for me" — place a gate on the timeline | Stage boundaries are natural safe pause points (reuses M1 gate architecture); arrival files an Inbox card; user reviews diff, then releases | At boundary only |
| 4. Append requirement | Edit/append acceptance criteria on the task card mid-flight | Appends to TASK.md + a steering note; agent absorbs next iteration | No |
| 5. Take over | Open the terminal and type | PTY is bidirectional (existing capability) | Yes |

Levels 1 and 3 are the essence: notes steer a loop without breaking it; gates let the human ambush at the exact high-value position.

### Steering Note Delivery — two timings, forked by send action

One input box, no settings:

| Action | Timing | Mechanism | Use for |
|--------|--------|-----------|---------|
| `Enter` (default) | Next **loop boundary** (end of current implement pass, before gate) | Written to `.looper/inbox.md` in the worktree; agent reads at the boundary | Constraints, reminders, preferences — preserves reasoning coherence |
| `⌘Enter` (urgent) | Next **tool-call gap**, immediately | Inject a user message into the session stream via ClaudeAgentSDK (we own the agent loop) | "Stop, wrong direction" — a minute of earlier correction saves a minute of burned tokens |

Feedback contract:

- A sent note appears on the Run timeline with state `pending → delivered → acknowledged` (acknowledgment detected from the SDK event stream).
- **Pending notes can be edited or recalled** — boundary delivery buys a regret window; another reason it is the default.
- Urgent notes render visually heavier (orange marker) so the timeline distinguishes gentle steering from emergency correction in hindsight.
- **Urgent-note frequency is itself a failure signal**: a pipeline that keeps needing emergency steering has a gap in TASK.md or its knowledge base (feeds ROADMAP M3/M4).

## Empty & Degraded States

An empty Inbox has **three distinct meanings** and must never look the same:

| State | Condition | Inbox shows |
|-------|-----------|-------------|
| Unconfigured | no pipelines exist | Day-0 guidance: create a pipeline / connect a provider. The Setup wizard lands here on completion |
| Idle | pipelines exist, nothing running, backlog empty | "All quiet" + quick-capture affordance front and center (the next action is *feeding* the system) |
| Healthy | Runs active, no pending decisions | **Inbox zero** — the earned state: "N runs proceeding" with the collapsed quiet list |

Degraded environment (agent CLI missing, provider auth expired, disk/git faults) surfaces as **system cards** — the Inbox is the single front door for "something needs you", whether it comes from a Run or from the environment. System cards float above all Run cards.

## Decision Efficiency Layer (keyboard)

The Inbox is a high-frequency decision surface; it must be operable without the mouse:

- `↑/↓` or `j/k` — move between cards; `Space` — expand/collapse evidence inline
- `Enter` — primary resolution of the focused card (approve / pick recommended option / release)
- `R` — send back (opens the mandatory reason field) · `T` — open the Run's terminal · `N` — steering note to the focused Run
- `⌘N` — quick capture · `⌘1/2/3` — switch Inbox / Live Wall / Manage

**Parked**: a ⌘K command palette (jump to any run, fire interventions by typing) — revisit once all three altitudes exist; it must not become a crutch for weak surface design.

## Menu Bar & Notifications — add-on, not first-class

- Menu bar icon + pending-card count (icon tints when an urgent item exists); click opens the main window at the Inbox. No further interaction lives there.
- macOS rich notifications carry quick actions (approve / send back / view) that map 1:1 onto card resolution sets — covers "away from the window", introduces no new interaction concepts.

The main window is the only first-class citizen. Picture-in-picture pinned tiles and similar ideas are explicitly parked.

## Build Order (mapped to ROADMAP)

1. **Now (needs only the AgentSDK event stream + existing state)**: Inbox with question cards + system cards + empty states, steering notes (both timings), Manage surface carved out of the legacy layout (pipeline settings, backlog with queue visibility), keyboard layer for the Inbox.
2. **With M1**: review-request cards with evidence panel + PR link + mandatory send-back reason, checkpoint gates, failure-escalation cards with worktree forensics.
3. **With M3**: loop timeline in the Cockpit, Live Wall trends, self-resolved/urgent-note analytics, preserved-worktree aging in Manage.
4. **Parked**: ⌘K palette, picture-in-picture pinned tiles.
