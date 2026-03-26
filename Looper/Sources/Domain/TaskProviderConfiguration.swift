import Foundation

struct TaskProviderConfiguration: Equatable, Codable, Sendable {
    var kind: TaskProviderKind = .local
    var feishu: FeishuTaskProviderConfiguration = .init()

    var selectedProviderLabel: String {
        kind.label
    }

    var requiresExternalConnection: Bool {
        kind == .feishu
    }

    var canFetchTasks: Bool {
        switch kind {
        case .local:
            true
        case .feishu:
            feishu.isConfigured
        }
    }
}
