import AppKit
import ComposableArchitecture
import Foundation

@DependencyClient
struct ProjectDirectoryPickerClient {
    var pickDirectory: @Sendable () async -> String?
}

extension DependencyValues {
    var projectDirectoryPickerClient: ProjectDirectoryPickerClient {
        get { self[ProjectDirectoryPickerClient.self] }
        set { self[ProjectDirectoryPickerClient.self] = newValue }
    }
}

extension ProjectDirectoryPickerClient: DependencyKey {
    static let liveValue = Self(
        pickDirectory: {
            await MainActor.run {
                let panel = NSOpenPanel()
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                panel.allowsMultipleSelection = false
                panel.prompt = "Open Project"
                panel.message = "Choose a project directory to add to the sidebar."

                guard panel.runModal() == .OK else {
                    return nil
                }

                return panel.url?.path(percentEncoded: false)
            }
        }
    )
}
