<!-- CLAUDE.md is a symlink to this file. Always update AGENTS.md, not CLAUDE.md. -->
<!-- Rule: every edit to this file must make it MORE CONCISE or MORE USEFUL. Never add fluff. -->

# AGENTS.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Looper is a personal macOS 26+ app for task-driven local AI development orchestration. It keeps long-lived project pipelines warm, accepts tasks from pluggable providers, and runs Claude Code in embedded terminals. Liquid Glass UI style.

**Stack**: SwiftUI + TCA, Tuist, Swift 6, SPM, libghostty-spm, macOS 26+

## Build Commands

```bash
tuist install                 # Install/update SPM dependencies
tuist generate                # Generate Xcode project
tuist build Looper            # Build
./scripts/test.sh             # Run tests
./scripts/test.sh -only-testing:LooperTests/AppFeatureTests/testOnAppearShowsSetupWizardWhenSetupIncomplete  # Single test
tuist clean                   # Clean
tuist edit                    # Edit Tuist manifests in Xcode
```

Use `XcodeBuildMCP` MCP server for Xcode build diagnostics, simulator management, and project inspection.

## MVP Scope

**In scope**: Local Tasks provider, Feishu provider, Claude Code agent, single repo per pipeline, manual refresh + configurable polling, automatic task status writeback
**Deferred**: TAPD/Linear providers, Codex, multi-repo tasks, review agent, memory engine, AI coordinator, visual workflow builder

## Core Concepts

### Domain Model

- **Pipeline**: long-lived project workstation. Holds project path, default agent command, active runs, and execution preferences (including `maxConcurrentRuns`).
- **Task**: unit of work from a provider (`Local Tasks`, `Feishu`, later others).
- **Run**: one execution of one task inside one pipeline. Each Run has its own git worktree, terminal, and status. Can succeed, fail, or be resumed.
- **Task Provider**: fetches tasks, inspects configuration, and writes status changes back.

### Runtime Flow

```
Pipeline (project workstation, persists across tasks)
  ├── Task A → Run → git worktree + Terminal ← active
  ├── Task B → Run → git worktree + Terminal ← active
  └── Task C → Run → git worktree + Terminal ← active
      (up to maxConcurrentRuns, default 3)

Task Provider ──fetch──▶ Task ──routed into──▶ Pipeline
                                            └─▶ Run starts in own worktree + terminal
                                                └─▶ status writeback to provider
```

**Concurrency model**: multiple Tasks run in parallel within a Pipeline (each in its own worktree). Retries of the same Task are serial.

States: `todo` → `inProgress` → `inReview` → `done`
- Both agent exit and user action can trigger state transitions
- Agent exit 0 → `inReview`; agent crash/timeout → back to `todo`
- `inReview` can be returned to `todo` (rollback) or approved to `done`
- Task provider decides how tasks are loaded and where status writes back
- Pipeline persists across tasks; runs are short-lived
- Task filter and polling interval are user-configurable per provider when supported

### Execution Environment

Each Run gets an isolated execution environment:
- **Git worktree**: `git worktree add` from pipeline repo, one branch per Run
- **Context injection**: `TASK.md` written into worktree with task description and metadata (Claude Code discovers it via CLAUDE.md conventions)
- **Cleanup**: on success, worktree removed; on failure, preserved for debugging

### Terminal Integration (libghostty-spm)

SPM dependency: `GhosttyTerminal` from `https://github.com/Lakr233/libghostty-spm.git`

Uses `.exec` backend (direct PTY).

```
TerminalSurfaceView (SwiftUI)           ← drop into any SwiftUI layout
  └─ TerminalViewState (@Observable)    ← observable: title, isFocused, surfaceSize
       └─ TerminalController            ← config + ghostty_app_t lifecycle
            └─ TerminalSurface          ← ghostty_surface_t wrapper (sendText, focus, free)
```

**Usage pattern**:
```swift
let controller = TerminalController { $0.withFontSize(13) }
let state = TerminalViewState(controller: controller)
state.configuration = TerminalSurfaceOptions(backend: .exec, workingDirectory: pipelinePath)
state.onClose = { processAlive in /* handle agent exit */ }

// SwiftUI
TerminalSurfaceView(context: state)

// Launch agent (command template is user-configurable)
surface.sendText("claude --task \"...\"\n")
```

**Delegates**: `TerminalSurfaceTitleDelegate`, `TerminalSurfaceCloseDelegate`, `TerminalSurfaceFocusDelegate`, `TerminalSurfaceGridResizeDelegate`

### Key Modules

| Module | Responsibility |
|--------|---------------|
| **TaskProvider** | Provider abstraction and adapters (`Local Tasks`, `Feishu`, later others) |
| **Pipeline** | Persistent project workstation state |
| **Terminal** | libghostty-spm terminal embedding and session lifecycle |
| **PipelineManager** | Local project validation plus optional execution-strategy support |

### Data Pipeline (Agent <-> App)

- **PTY output** — terminal rendering and user interaction via libghostty-spm
- **Structured channel** (MCP / filesystem / TBD) — agent status, task progress

## Architecture

### TCA (The Composable Architecture)

- **Reducer**: `@Reducer` macro with `State`, `Action`, `body`
- **View**: SwiftUI view with `StoreOf<Feature>`, `@Bindable` store
- **State**: `@ObservableState` struct, `Equatable`
- **Action**: `ViewAction` for view-initiated, `DelegateAction` for parent communication
- **Dependencies**: `@DependencyClient` + `DependencyValues` extension

### Concurrency (Swift 6)

**Note**: `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (SE-466) is **incompatible** with TCA's `@Reducer` macro (causes circular reference). Use explicit `@MainActor` instead.

- **Use explicit `@MainActor`** on views, view models, and UI-bound classes.
- **Background work**: mark with `@concurrent` (provider API calls, process execution, file I/O).
- **Domain models**: value types (`struct`) — automatically `Sendable`.
- **Terminal manager**: `@MainActor @Observable class` outside TCA, communicates via `TerminalClient` dependency (Command/Event `AsyncStream`).
- **Polling**: use `Task` + `AsyncStream` + `Task.sleep(for:)`, not Timer/GCD.
- **Avoid**: `@unchecked Sendable`, `nonisolated(unsafe)`, `DispatchQueue`, semaphores.
- **Deep reference**: use `/swift-concurrency:swift-concurrency` skill when debugging concurrency issues.

### Conventions

- **Side effects**: Always through TCA `Effect` — no async work in views.
- **Testing**: `TestStore` with exhaustive state assertions.
- **Naming**: Prefer provider-agnostic names (`TaskProvider`, `Pipeline`, `Run`). Do not introduce new `Workspace*` or `TaskBoard*` symbols.
- **UI**: macOS 26 Liquid Glass style. Use system colors, dynamic type, `.glassEffect()`.
- **Skills for code quality**: When writing/reviewing Swift code, read `~/.claude/skills/{swiftui,swiftdata,swift-concurrency,swift-testing}-pro/*/references/` — especially `api.md` first to avoid deprecated APIs. Also use `/swiftui-expert-skill` for Liquid Glass and macOS patterns.

### Project Structure

```
Project.swift                     # Tuist project manifest
Tuist.swift                       # Tuist config
Tuist/Package.swift               # SPM dependencies
Looper/Sources/
  App/                            # LooperApp, AppFeature, AppView
  Features/Pipeline/              # Pipeline state and lifecycle
  Features/Terminal/              # libghostty-spm terminal management
  Clients/                        # TCA dependency clients
  Domain/                         # Domain models (task, provider config, pipeline state)
Looper/Resources/
LooperTests/
```

## Release & Auto-Update (Sparkle)

**Config**: `SUFeedURL` and `SUPublicEDKey` in `Project.swift` infoPlist. EdDSA private key lives in macOS Keychain (generated by Sparkle `generate_keys`).

**Sparkle tools** (in repo):
```
Tuist/.build/artifacts/sparkle/Sparkle/bin/generate_keys    # EdDSA key management
Tuist/.build/artifacts/sparkle/Sparkle/bin/sign_update       # Sign .dmg/.zip
Tuist/.build/artifacts/sparkle/Sparkle/bin/generate_appcast  # Regenerate appcast.xml
```

**Release flow**:
```bash
# 1. Archive the app, export as .dmg or .zip
# 2. Sign the artifact
Tuist/.build/artifacts/sparkle/Sparkle/bin/sign_update Looper.dmg

# 3. Regenerate appcast from a directory of signed artifacts
Tuist/.build/artifacts/sparkle/Sparkle/bin/generate_appcast /path/to/artifacts/

# 4. Upload artifact + appcast.xml to GitHub release
gh release create vX.Y.Z Looper.dmg appcast.xml --title "vX.Y.Z" --notes "..."
```

**Feed URL**: `https://github.com/KQAR/looper/releases/latest/download/appcast.xml`
**Public key**: stored in `Project.swift` → `SUPublicEDKey`. Regenerate with `generate_keys` only if rotating keys.

### Known Issues

- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` breaks TCA's `@Reducer` macro with circular reference errors. Do not enable it.
- TCA `TestStore` init is `@MainActor` — all test suites using it must be marked `@MainActor`.
- `tuist test` on Tuist `4.108.1` drops `Testables` from generated schemes for this project. Use [`scripts/test.sh`](/Users/jarvis/Documents/GitHub/looper/scripts/test.sh) instead.
