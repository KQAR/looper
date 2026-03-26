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

    var subtitle: String {
        switch self {
        case .local:
            "Keep tasks inside Looper without relying on any external board."
        case .feishu:
            "Sync tasks from a Feishu Bitable table and write status changes back."
        }
    }
}
