import Foundation

struct FeishuTaskProviderConfiguration: Equatable, Codable, Sendable {
    var appID: String = ""
    var appSecret: String = ""
    var appToken: String = ""
    var tableID: String = ""
    var titleFieldName: String = "Title"
    var summaryFieldName: String = "Summary"
    var statusFieldName: String = "Status"
    var repoPathFieldName: String = "Repository"
    var todoStatusValue: String = "todo"
    var inProgressStatusValue: String = "in_progress"
    var inReviewStatusValue: String = "in_review"
    var doneStatusValue: String = "done"

    var isConfigured: Bool {
        [appID, appSecret, appToken, tableID, titleFieldName, statusFieldName]
            .allSatisfy { !$0.trimmed.isEmpty }
    }

    var minimumConnectionFieldsArePresent: Bool {
        [appID, appSecret, appToken, tableID]
            .allSatisfy { !$0.trimmed.isEmpty }
    }

    func remoteValue(for status: LooperTask.Status) -> String {
        switch status {
        case .todo:
            todoStatusValue
        case .inProgress:
            inProgressStatusValue
        case .inReview:
            inReviewStatusValue
        case .done:
            doneStatusValue
        }
    }

    func status(for rawValue: String) -> LooperTask.Status? {
        let normalized = rawValue.normalizedFeishuValue

        if normalized == todoStatusValue.normalizedFeishuValue {
            return .todo
        }
        if normalized == inProgressStatusValue.normalizedFeishuValue {
            return .inProgress
        }
        if normalized == inReviewStatusValue.normalizedFeishuValue {
            return .inReview
        }
        if normalized == doneStatusValue.normalizedFeishuValue {
            return .done
        }

        return nil
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedFeishuValue: String {
        trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}
