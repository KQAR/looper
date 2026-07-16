# ROADMAP.md

Single source of truth for Looper's **positioning** and **iteration order**. When a scope or prioritization question arises, this doc wins over legacy assumptions in code or older notes. Derived from Loop Engineering principles: an inner machine loop (implement → verify → fix) and an outer human loop (diagnose failures, harden the system). The user-facing shape of these phases is specified in [`INTERACTION.md`](INTERACTION.md).

## Positioning

Looper is **not** a task scheduler that happens to run Claude Code in parallel. Parallel throughput is table stakes.

Looper is a **Loop Engineering workbench**: the outer-loop workstation for a single owner driving AI-native development. Its job is to (1) make every inner loop's result *trustworthy* and (2) turn every failure into an input for system improvement.

Value hierarchy (higher beats lower when they conflict):

1. **Trustworthy completion** — a Run is done when evidence says so, never because the agent exited 0.
2. **Failure signals** — every failure (gate failure, verify rejection, human rollback) is captured, classified, and surfaced. Looper is the meta harness.
3. **Knowledge sedimentation** — pipeline-level engineering knowledge is injected into every Run; failure analysis flows back into that knowledge.
4. **Throughput** — parallel Runs, warm pipelines. Necessary, not differentiating.

Guiding principle: **"more trustworthy" beats "faster"**. Extra tokens and wall-clock time spent on verification are a necessary quality investment, not overhead to optimize away first.

## Target Run Lifecycle

Replaces exit-code-only promotion. The current `exit 0 → inReview` behavior is interim (see AGENTS.md States).

```
implement (agent in worktree)
   → gate      pipeline-configured commands run in the worktree (UT / Lint / Build / E2E)
   → verify    independent agent, fresh context, reviews the diff against TASK.md
   → inReview  with an evidence bundle: gate results, diff summary, verify verdict
```

- Gate or verify failure → structured failure report written into the worktree → auto-resume the same Run (inner loop), serial, bounded by a per-pipeline retry budget → on exhaustion, back to `todo` with the failure report attached for the human.
- `inReview → todo` rollback by the human counts as a **process escape** and is recorded as a failure signal.

## Iteration Phases

### M1 — Evidence-gated completion

- Per-pipeline **gate command templates** (test / lint / build / e2e), runnable in any Run worktree.
- After agent exit: run gates, capture structured results; promotion to `inReview` requires gates green.
- **Verify agent** (pulled forward from deferred): independent agent with fresh context reviews the diff against TASK.md and emits a structured verdict.
- **Evidence bundle** attached to each Run and shown in the detail panel.

### M2 — Inner-loop automation

- On gate/verify failure, write the failure output into the worktree and auto-resume the agent (implement→verify inner loop).
- Configurable retry budget per pipeline; on exhaustion, escalate to human with the accumulated failure reports.

### M3 — Outer-loop observability (meta harness)

- Per-Run metrics: duration, retry count, failure stage (implement / gate / verify), failure class (code vs environment).
- Per-pipeline trends: failure patterns, escape count (`inReview → todo` rollbacks), flaky gates.
- Goal: the owner's outer-loop decisions ("where is it slow, what context is missing, which rule to add") are backed by data, not anecdotes.

### M4 — Knowledge assets

- Pipeline-level knowledge files (test conventions, login/auth strategy for E2E, mock strategy, module boundaries) injected into every worktree alongside TASK.md.
- **Sediment as rule**: one action turns a failure analysis into a pipeline knowledge entry, injected into subsequent Runs.

## Structured Channel — decided

Filesystem JSON contract, effective M1 (do not wait for MCP):

- Agent and gate runner write structured reports to a fixed path inside the worktree (e.g. `.looper/report.json`).
- Looper watches that path; it is the transport for gate results, verify verdicts, and failure reports.
- MCP can replace the transport later without changing the domain model.

## Still Deferred

TAPD/Linear providers, Codex agent, multi-repo tasks, AI coordinator, visual workflow builder.

(No longer deferred: review/verify agent → M1; memory engine → minimal slice shipped as M4 knowledge assets.)
