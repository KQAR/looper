<!-- CLAUDE.md is a symlink to this file. Always update AGENTS.md, not CLAUDE.md. -->
<!-- Rule: every edit to this file must make it MORE CONCISE or MORE USEFUL. Never add fluff. -->

# AGENTS.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Looper is a personal macOS 26+ app for AI-driven development workflow orchestration. Fetches tasks from Feishu, auto-creates git worktrees, launches Claude Code in embedded terminals. Liquid Glass UI style.

**Stack**: SwiftUI + TCA, Tuist, Swift 6, SPM, libghostty-spm, macOS 26+

## Build Commands

```bash
tuist install                 # Install/update SPM dependencies
tuist generate                # Generate Xcode project
tuist build Looper            # Build
tuist test Looper             # Run tests
tuist test Looper -- -only-testing:LooperTests/AppFeatureTests/onAppear  # Single test
tuist clean                   # Clean
tuist edit                    # Edit Tuist manifests in Xcode
```

Use `XcodeBuildMCP` MCP server for Xcode build diagnostics, simulator management, and project inspection.

## MVP Scope

**In scope**: Feishu adapter, Claude Code agent, single repo per task, configurable polling + manual refresh
**Deferred**: TAPD/Linear adapters, Codex, multi-repo tasks, review agent, memory engine, AI coordinator

## Core Concepts

### Task Lifecycle

```
Feishu (task board) ──fetch──▶ Task ──user clicks──▶ auto git worktree add
                                                      ──▶ auto launch Claude Code terminal
                                                      ──▶ status writeback to Feishu
```

States: `pending` → `developing` → `done` / `failed`
- Both agent exit and user action can trigger state transitions
- Agent crash/timeout → `failed` state
- Task completion → worktree destroyed, status written back to Feishu
- Task filter and polling interval are user-configurable
- Feishu status writeback maps to corresponding board columns

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
state.configuration = TerminalSurfaceOptions(backend: .exec, workingDirectory: worktreePath)
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
| **TaskBoard** | Feishu adapter — REST API polling + manual refresh, bidirectional status sync, configurable filters |
| **AgentManager** | Claude Code process lifecycle — auto-spawn on task start, monitor, terminate |
| **Terminal** | libghostty-spm terminal embedding, `TerminalViewState` per agent |
| **RepoManager** | Repository config (user-set paths), git worktree create/destroy tied to task lifecycle |

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
- **Background work**: mark with `@concurrent` (Feishu API calls, git worktree ops, file I/O).
- **Domain models**: value types (`struct`) — automatically `Sendable`.
- **Terminal manager**: `@MainActor @Observable class` outside TCA, communicates via `TerminalClient` dependency (Command/Event `AsyncStream`).
- **Polling**: use `Task` + `AsyncStream` + `Task.sleep(for:)`, not Timer/GCD.
- **Avoid**: `@unchecked Sendable`, `nonisolated(unsafe)`, `DispatchQueue`, semaphores.
- **Deep reference**: use `/swift-concurrency:swift-concurrency` skill when debugging concurrency issues.

### Conventions

- **Side effects**: Always through TCA `Effect` — no async work in views.
- **Testing**: `TestStore` with exhaustive state assertions.
- **Naming**: Reducers named after feature (`TaskBoard`), views suffixed with `View` (`TaskBoardView`).
- **UI**: macOS 26 Liquid Glass style. Use system colors, dynamic type, `.glassEffect()`.
- **Skills for code quality**: When writing/reviewing Swift code, read `~/.claude/skills/{swiftui,swiftdata,swift-concurrency,swift-testing}-pro/*/references/` — especially `api.md` first to avoid deprecated APIs. Also use `/swiftui-expert-skill` for Liquid Glass and macOS patterns.

### Project Structure

```
Project.swift                     # Tuist project manifest
Tuist.swift                       # Tuist config
Tuist/Package.swift               # SPM dependencies
Looper/Sources/
  App/                            # LooperApp, AppFeature, AppView
  Features/TaskBoard/             # Feishu integration
  Features/Terminal/              # libghostty-spm terminal management
  Features/RepoManager/           # Git worktree operations
  Clients/                        # TCA dependency clients
  Domain/                         # Domain models (LooperTask, etc.)
Looper/Resources/
LooperTests/
```

### Known Issues

- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` breaks TCA's `@Reducer` macro with circular reference errors. Do not enable it.
- TCA `TestStore` init is `@MainActor` — all test suites using it must be marked `@MainActor`.
