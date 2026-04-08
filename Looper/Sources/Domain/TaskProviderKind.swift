import Foundation

enum TaskProviderKind: String, CaseIterable, Codable, Equatable, Sendable {
    case local
    case feishu

    var label: String {
        switch self {
        case .local:
            "Local Tasks"
        case .feishu:
            "Feishu"
        }
    }

    func localizedLabel(bundle: Bundle) -> String {
        switch self {
        case .local:
            String(localized: "settings.taskProvider.kind.local", bundle: bundle)
        case .feishu:
            String(localized: "settings.taskProvider.kind.feishu", bundle: bundle)
        }
    }

    var subtitle: String {
        switch self {
        case .local:
            "Keep tasks inside Looper without relying on any external board."
        case .feishu:
            "Sync tasks from a Feishu Bitable table and write status changes back."
        }
    }
}
