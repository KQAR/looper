import ComposableArchitecture
import Foundation

@DependencyClient
struct TaskProviderClient {
    var fetchTasks: @Sendable (TaskProviderConfiguration) async throws -> [LooperTask] = { _ in [] }
    var inspectConfiguration: @Sendable (TaskProviderConfiguration) async throws -> TaskProviderInspection = { _ in
        .init(previewTaskCount: 0, discoveredFieldNames: [], detectedStatusValues: [], sampleTaskTitles: [])
    }
    var updateTaskStatus: @Sendable (LooperTask.ID, LooperTask.Status, TaskProviderConfiguration) async throws -> Void = { _, _, _ in }
    var createTask: @Sendable (LocalTaskDraft, TaskProviderConfiguration) async throws -> LooperTask = { _, _ in
        throw TaskProviderFailure(description: "The selected task provider does not support task creation.")
    }
}

extension DependencyValues {
    var taskProviderClient: TaskProviderClient {
        get { self[TaskProviderClient.self] }
        set { self[TaskProviderClient.self] = newValue }
    }
}

extension TaskProviderClient: DependencyKey {
    static let testValue = TaskProviderClient(
        fetchTasks: { _ in [] },
        inspectConfiguration: { _ in
            .init(previewTaskCount: 0, discoveredFieldNames: [], detectedStatusValues: [], sampleTaskTitles: [])
        },
        updateTaskStatus: { _, _, _ in },
        createTask: { _, _ in
            throw TaskProviderFailure(description: "No test task creation stub was provided.")
        }
    )

    static let liveValue = Self(
        fetchTasks: { configuration in
            switch configuration.kind {
            case .local:
                return LocalTaskProvider.fetchTasks()
            case .feishu:
                return try await FeishuTaskProvider.fetchTasks(configuration: configuration.feishu)
            }
        },
        inspectConfiguration: { configuration in
            switch configuration.kind {
            case .local:
                return LocalTaskProvider.inspectConfiguration()
            case .feishu:
                return try await FeishuTaskProvider.inspectConfiguration(configuration: configuration.feishu)
            }
        },
        updateTaskStatus: { taskID, status, configuration in
            switch configuration.kind {
            case .local:
                try LocalTaskProvider.updateTaskStatus(taskID: taskID, status: status)
            case .feishu:
                try await FeishuTaskProvider.updateTaskStatus(
                    recordID: taskID,
                    status: status,
                    configuration: configuration.feishu
                )
            }
        },
        createTask: { draft, configuration in
            switch configuration.kind {
            case .local:
                return try LocalTaskProvider.createTask(draft: draft)
            case .feishu:
                throw TaskProviderFailure(description: "Create tasks from Feishu directly instead of Looper.")
            }
        }
    )
}

struct TaskProviderFailure: LocalizedError, Equatable, Sendable {
    let description: String

    var errorDescription: String? {
        description
    }
}

private enum LocalTaskProvider {
    private static let storageKey = "taskProvider.localTasks"

    static func fetchTasks() -> [LooperTask] {
        storedTasks()
    }

    static func inspectConfiguration() -> TaskProviderInspection {
        let tasks = storedTasks()
        return TaskProviderInspection(
            previewTaskCount: tasks.count,
            discoveredFieldNames: ["title", "summary", "projectPath", "status"],
            detectedStatusValues: Array(Set(tasks.map(\.status.rawValue))).sorted(),
            sampleTaskTitles: Array(tasks.map(\.title).prefix(3))
        )
    }

    static func updateTaskStatus(
        taskID: LooperTask.ID,
        status: LooperTask.Status
    ) throws {
        var tasks = storedTasks()
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else {
            throw TaskProviderFailure(description: "Local task not found.")
        }

        tasks[index].status = status
        save(tasks)
    }

    static func createTask(draft: LocalTaskDraft) throws -> LooperTask {
        guard draft.canCreate else {
            throw TaskProviderFailure(description: "Title and project path are required.")
        }

        var tasks = storedTasks()
        let task = draft.makeTask()
        tasks.insert(task, at: 0)
        save(tasks)
        return task
    }

    private static func storedTasks() -> [LooperTask] {
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: storageKey) else { return [] }
        return (try? JSONDecoder().decode([LooperTask].self, from: data)) ?? []
    }

    private static func save(_ tasks: [LooperTask]) {
        let defaults = UserDefaults.standard
        defaults.set(try? JSONEncoder().encode(tasks), forKey: storageKey)
    }
}

private enum FeishuTaskProvider {
    private static let baseURL = URL(string: "https://open.feishu.cn")!

    static func fetchTasks(configuration: FeishuTaskProviderConfiguration) async throws -> [LooperTask] {
        guard configuration.isConfigured else {
            throw TaskProviderFailure(description: "Configure Feishu task provider settings first.")
        }

        let accessToken = try await tenantAccessToken(configuration: configuration)
        var records: [FeishuRecord] = []
        var pageToken: String?

        repeat {
            let page = try await fetchRecordPage(
                configuration: configuration,
                accessToken: accessToken,
                pageToken: pageToken
            )
            records.append(contentsOf: page.items)
            pageToken = page.hasMore ? page.pageToken : nil
        } while pageToken != nil

        return records.map { task(from: $0, configuration: configuration) }
    }

    static func inspectConfiguration(configuration: FeishuTaskProviderConfiguration) async throws -> TaskProviderInspection {
        guard configuration.minimumConnectionFieldsArePresent else {
            throw TaskProviderFailure(description: "App ID, app secret, app token, and table ID are required.")
        }

        let accessToken = try await tenantAccessToken(configuration: configuration)
        let page = try await fetchRecordPage(
            configuration: configuration,
            accessToken: accessToken,
            pageToken: nil
        )

        let fieldNames = Array(Set(page.items.flatMap { Array($0.fields.keys) }))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        let statusValues = Array(
            Set(page.items.compactMap { $0.fields[configuration.statusFieldName]?.textValue?.trimmed })
        )
        .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        let sampleTitles = page.items.prefix(3).compactMap {
            $0.fields[configuration.titleFieldName]?.textValue?.trimmed
        }

        return TaskProviderInspection(
            previewTaskCount: page.items.count,
            discoveredFieldNames: fieldNames,
            detectedStatusValues: statusValues,
            sampleTaskTitles: sampleTitles
        )
    }

    static func updateTaskStatus(
        recordID: String,
        status: LooperTask.Status,
        configuration: FeishuTaskProviderConfiguration
    ) async throws {
        guard configuration.isConfigured else {
            throw TaskProviderFailure(description: "Configure Feishu task provider settings first.")
        }

        let accessToken = try await tenantAccessToken(configuration: configuration)
        var request = URLRequest(url: recordURL(configuration: configuration, recordID: recordID))
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: [
                "fields": [
                    configuration.statusFieldName: configuration.remoteValue(for: status)
                ]
            ]
        )

        _ = try await perform(request, decoding: EmptyPayload.self)
    }

    private static func tenantAccessToken(configuration: FeishuTaskProviderConfiguration) async throws -> String {
        var request = URLRequest(
            url: baseURL.appending(path: "/open-apis/auth/v3/tenant_access_token/internal")
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            TenantAccessTokenRequest(
                app_id: configuration.appID.trimmed,
                app_secret: configuration.appSecret.trimmed
            )
        )

        let payload = try await perform(request, decoding: TenantAccessTokenPayload.self)
        return payload.tenantAccessToken
    }

    private static func fetchRecordPage(
        configuration: FeishuTaskProviderConfiguration,
        accessToken: String,
        pageToken: String?
    ) async throws -> RecordPagePayload {
        var components = URLComponents(
            url: recordsURL(configuration: configuration),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "page_size", value: "200")]

        if let pageToken, !pageToken.isEmpty {
            components?.queryItems?.append(URLQueryItem(name: "page_token", value: pageToken))
        }

        guard let url = components?.url else {
            throw TaskProviderFailure(description: "Unable to build Feishu records URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        return try await perform(request, decoding: RecordPagePayload.self)
    }

    private static func task(
        from record: FeishuRecord,
        configuration: FeishuTaskProviderConfiguration
    ) -> LooperTask {
        let title = record.fields[configuration.titleFieldName]?.textValue?.trimmed
        let summary = record.fields[configuration.summaryFieldName]?.textValue?.trimmed ?? ""
        let rawStatus = record.fields[configuration.statusFieldName]?.textValue?.trimmed ?? ""
        let repoPath = record.fields[configuration.repoPathFieldName]?.textValue?.trimmed

        return LooperTask(
            id: record.recordID,
            title: title?.ifEmpty(fallback: "Untitled Task") ?? "Untitled Task",
            summary: summary,
            status: configuration.status(for: rawStatus) ?? .todo,
            source: "Feishu",
            repoPath: repoPath.flatMap(makeRepoURL(path:))
        )
    }

    private static func makeRepoURL(path: String) -> URL? {
        let trimmedPath = path.trimmed
        guard !trimmedPath.isEmpty else { return nil }
        let expandedPath = NSString(string: trimmedPath).expandingTildeInPath
        return URL(fileURLWithPath: expandedPath).standardizedFileURL
    }

    private static func perform<Response: Decodable>(
        _ request: URLRequest,
        decoding: Response.Type
    ) async throws -> Response {
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TaskProviderFailure(description: "Feishu returned a non-HTTP response.")
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            let message = String(decoding: data, as: UTF8.self).trimmed
            throw TaskProviderFailure(
                description: message.ifEmpty(
                    fallback: "Feishu request failed with status code \(httpResponse.statusCode)."
                )
            )
        }

        let envelope = try JSONDecoder().decode(FeishuEnvelope<Response>.self, from: data)
        guard envelope.code == 0 else {
            throw TaskProviderFailure(
                description: envelope.msg.ifEmpty(fallback: "Feishu request failed.")
            )
        }
        guard let payload = envelope.data else {
            throw TaskProviderFailure(description: "Feishu returned an empty payload.")
        }

        return payload
    }

    private static func recordsURL(configuration: FeishuTaskProviderConfiguration) -> URL {
        baseURL.appending(
            path: "/open-apis/bitable/v1/apps/\(configuration.appToken.pathEscaped)/tables/\(configuration.tableID.pathEscaped)/records"
        )
    }

    private static func recordURL(
        configuration: FeishuTaskProviderConfiguration,
        recordID: String
    ) -> URL {
        baseURL.appending(
            path: "/open-apis/bitable/v1/apps/\(configuration.appToken.pathEscaped)/tables/\(configuration.tableID.pathEscaped)/records/\(recordID.pathEscaped)"
        )
    }
}

private struct FeishuEnvelope<Payload: Decodable>: Decodable {
    let code: Int
    let msg: String
    let data: Payload?
}

private struct EmptyPayload: Decodable {}

private struct TenantAccessTokenRequest: Encodable {
    let app_id: String
    let app_secret: String
}

private struct TenantAccessTokenPayload: Decodable {
    let tenantAccessToken: String

    enum CodingKeys: String, CodingKey {
        case tenantAccessToken = "tenant_access_token"
    }
}

private struct RecordPagePayload: Decodable {
    let hasMore: Bool
    let items: [FeishuRecord]
    let pageToken: String?

    enum CodingKeys: String, CodingKey {
        case hasMore = "has_more"
        case items
        case pageToken = "page_token"
    }
}

private struct FeishuRecord: Decodable {
    let recordID: String
    let fields: [String: FeishuFieldValue]

    enum CodingKeys: String, CodingKey {
        case recordID = "record_id"
        case fields
    }
}

private enum FeishuFieldValue: Decodable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([FeishuFieldValue])
    case object([String: FeishuFieldValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode([String: FeishuFieldValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([FeishuFieldValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported Feishu field value."
            )
        }
    }

    var textValue: String? {
        switch self {
        case let .string(value):
            return value
        case let .number(value):
            return String(value)
        case let .bool(value):
            return String(value)
        case let .array(values):
            let texts = values.compactMap(\.textValue).filter { !$0.trimmed.isEmpty }
            return texts.isEmpty ? nil : texts.joined(separator: ", ")
        case let .object(values):
            for key in ["text", "name", "value"] {
                if let value = values[key]?.textValue, !value.trimmed.isEmpty {
                    return value
                }
            }
            return values.values.compactMap(\.textValue).first { !$0.trimmed.isEmpty }
        case .null:
            return nil
        }
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var pathEscaped: String {
        addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? self
    }

    func ifEmpty(fallback: String) -> String {
        trimmed.isEmpty ? fallback : self
    }
}
