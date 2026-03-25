import ComposableArchitecture
import XCTest

@testable import Looper

actor PreferencesRecorder {
    private var preferences: WorkspacePreferences?

    func record(_ preferences: WorkspacePreferences) {
        self.preferences = preferences
    }

    func value() -> WorkspacePreferences? {
        preferences
    }
}

@MainActor
final class AppFeatureTests: XCTestCase {
    func testInitialStateHasNoWorkspaces() async {
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        }

        XCTAssertTrue(store.state.workspace.workspaces.isEmpty)
        XCTAssertNil(store.state.workspace.selectedWorkspaceID)
    }

    func testOnAppearLoadsPersistedWorkspaces() async {
        let workspace = CodingWorkspace(
            id: UUID(uuidString: "1C40F2D4-2350-4CD5-AB54-90713D865FE0")!,
            name: "Persisted Workspace",
            repositoryRootPath: "/tmp/repo",
            worktreePath: "/tmp/.looper-worktrees/repo/persisted-workspace",
            branchName: "looper/persisted-workspace",
            baseBranch: "main",
            agentCommand: "claude",
            tmuxSessionName: "repo-looper-persisted-workspace"
        )

        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.workspaceStoreClient.fetchWorkspaces = { [workspace] }
            $0.workspacePreferencesClient.fetchPreferences = {
                WorkspacePreferences(
                    defaultRepositoryPath: "/tmp/repo",
                    defaultBaseBranch: "main",
                    defaultAgentCommand: "claude --dangerously-skip-permissions",
                    lastSelectedWorkspaceID: workspace.id
                )
            }
            $0.terminalWorkspaceClient.upsertSession = { _ in }
        }

        await store.send(.workspace(.onAppear))
        await store.receive(\.workspace.bootstrapResponse.success) {
            $0.workspace.workspaces = [workspace]
            $0.workspace.selectedWorkspaceID = workspace.id
            $0.workspace.preferences = WorkspacePreferences(
                defaultRepositoryPath: "/tmp/repo",
                defaultBaseBranch: "main",
                defaultAgentCommand: "claude --dangerously-skip-permissions",
                lastSelectedWorkspaceID: workspace.id
            )
            $0.workspace.composer = WorkspacePreferences(
                defaultRepositoryPath: "/tmp/repo",
                defaultBaseBranch: "main",
                defaultAgentCommand: "claude --dangerously-skip-permissions",
                lastSelectedWorkspaceID: workspace.id
            ).draft
        }
    }

    func testSelectingWorkspacePersistsSelection() async {
        let firstID = UUID(uuidString: "1C40F2D4-2350-4CD5-AB54-90713D865FE0")!
        let secondID = UUID(uuidString: "9E24E1C8-76FC-4A4C-B8D8-0B5D16F8D61D")!
        let first = CodingWorkspace(
            id: firstID,
            name: "First",
            repositoryRootPath: "/tmp/repo",
            worktreePath: "/tmp/first",
            branchName: "looper/first",
            baseBranch: "main",
            agentCommand: "claude",
            tmuxSessionName: "repo-first"
        )
        let second = CodingWorkspace(
            id: secondID,
            name: "Second",
            repositoryRootPath: "/tmp/repo",
            worktreePath: "/tmp/second",
            branchName: "looper/second",
            baseBranch: "main",
            agentCommand: "claude",
            tmuxSessionName: "repo-second"
        )
        let recorder = PreferencesRecorder()

        let store = TestStore(
            initialState: AppFeature.State(
                workspace: WorkspaceFeature.State(
                    workspaces: [first, second],
                    selectedWorkspaceID: firstID,
                    preferences: WorkspacePreferences(
                        defaultRepositoryPath: "/tmp/repo",
                        defaultBaseBranch: "main",
                        defaultAgentCommand: "claude",
                        lastSelectedWorkspaceID: firstID
                    )
                )
            )
        ) {
            AppFeature()
        } withDependencies: {
            $0.workspacePreferencesClient.savePreferences = { await recorder.record($0) }
            $0.terminalWorkspaceClient.focusSession = { _ in }
        }

        await store.send(.workspace(.selectWorkspace(secondID))) {
            $0.workspace.selectedWorkspaceID = secondID
            $0.workspace.preferences.lastSelectedWorkspaceID = secondID
        }

        let savedPreferences = await recorder.value()
        XCTAssertEqual(savedPreferences?.lastSelectedWorkspaceID, secondID)
    }

    func testWorkspaceBranchNameNormalizesInput() {
        XCTAssertEqual(
            WorkspaceNaming.branchName(
                name: "Payment Hardening",
                explicitBranchName: ""
            ),
            "looper/payment-hardening"
        )
        XCTAssertEqual(
            WorkspaceNaming.branchName(
                name: "Ignored",
                explicitBranchName: "feature/Task Board"
            ),
            "feature/task-board"
        )
    }
}
