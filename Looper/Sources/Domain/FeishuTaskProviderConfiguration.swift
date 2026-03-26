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
    var pendingStatusValue: String = "pending"
    var developingStatusValue: String = "developing"
    var doneStatusValue: String = "done"
    var failedStatusValue: String = "failed"

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
        case .pending:
            pendingStatusValue
        case .developing:
            developingStatusValue
        case .done:
            doneStatusValue
        case .failed:
            failedStatusValue
        }
    }

    func status(for rawValue: String) -> LooperTask.Status? {
        let normalized = rawValue.normalizedFeishuValue

        if normalized == pendingStatusValue.normalizedFeishuValue {
            return .pending
        }
        if normalized == developingStatusValue.normalizedFeishuValue {
            return .developing
        }
        if normalized == doneStatusValue.normalizedFeishuValue {
            return .done
        }
        if normalized == failedStatusValue.normalizedFeishuValue {
            return .failed
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
