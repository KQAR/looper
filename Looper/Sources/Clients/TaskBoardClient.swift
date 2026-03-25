import ComposableArchitecture
import Foundation

@DependencyClient
struct TaskBoardClient {
    var fetchTasks: @Sendable (TaskBoardConfiguration) async throws -> [LooperTask] = { _ in [] }
    var updateTaskStatus: @Sendable (LooperTask.ID, LooperTask.Status, TaskBoardConfiguration) async throws -> Void = { _, _, _ in }
}

extension DependencyValues {
    var taskBoardClient: TaskBoardClient {
        get { self[TaskBoardClient.self] }
        set { self[TaskBoardClient.self] = newValue }
    }
}

extension TaskBoardClient: DependencyKey {
    static let liveValue = Self(
        fetchTasks: { configuration in
            try await FeishuTaskBoardAPI.fetchTasks(configuration: configuration)
        },
        updateTaskStatus: { taskID, status, configuration in
            try await FeishuTaskBoardAPI.updateTaskStatus(
                recordID: taskID,
                status: status,
                configuration: configuration
            )
        }
    )
}

struct TaskBoardFailure: LocalizedError, Equatable, Sendable {
    let description: String

    var errorDescription: String? {
        description
    }
}

private enum FeishuTaskBoardAPI {
    private static let baseURL = URL(string: "https://open.feishu.cn")!

    static func fetchTasks(configuration: TaskBoardConfiguration) async throws -> [LooperTask] {
        guard configuration.isConfigured else {
            throw TaskBoardFailure(description: "Configure Feishu task board settings first.")
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

    static func updateTaskStatus(
        recordID: String,
        status: LooperTask.Status,
        configuration: TaskBoardConfiguration
    ) async throws {
        guard configuration.isConfigured else {
            throw TaskBoardFailure(description: "Configure Feishu task board settings first.")
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

    private static func tenantAccessToken(configuration: TaskBoardConfiguration) async throws -> String {
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
        configuration: TaskBoardConfiguration,
        accessToken: String,
        pageToken: String?
    ) async throws -> RecordPagePayload {
        var components = URLComponents(
            url: recordsURL(configuration: configuration),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "page_size", value: "200")
        ]

        if let pageToken, !pageToken.isEmpty {
            components?.queryItems?.append(URLQueryItem(name: "page_token", value: pageToken))
        }

        guard let url = components?.url else {
            throw TaskBoardFailure(description: "Unable to build Feishu records URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        return try await perform(request, decoding: RecordPagePayload.self)
    }

    private static func task(
        from record: FeishuRecord,
        configuration: TaskBoardConfiguration
    ) -> LooperTask {
        let title = record.fields[configuration.titleFieldName]?.textValue?.trimmed
        let summary = record.fields[configuration.summaryFieldName]?.textValue?.trimmed ?? ""
        let rawStatus = record.fields[configuration.statusFieldName]?.textValue?.trimmed ?? ""
        let repoPath = record.fields[configuration.repoPathFieldName]?.textValue?.trimmed

        return LooperTask(
            id: record.recordID,
            title: title?.ifEmpty(fallback: "Untitled Task") ?? "Untitled Task",
            summary: summary,
            status: configuration.status(for: rawStatus) ?? .pending,
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
            throw TaskBoardFailure(description: "Feishu returned a non-HTTP response.")
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            let message = String(decoding: data, as: UTF8.self).trimmed
            throw TaskBoardFailure(
                description: message.ifEmpty(
                    fallback: "Feishu request failed with status code \(httpResponse.statusCode)."
                )
            )
        }

        let envelope = try JSONDecoder().decode(FeishuEnvelope<Response>.self, from: data)
        guard envelope.code == 0 else {
            throw TaskBoardFailure(
                description: envelope.msg.ifEmpty(fallback: "Feishu request failed.")
            )
        }
        guard let payload = envelope.data else {
            throw TaskBoardFailure(description: "Feishu returned an empty payload.")
        }

        return payload
    }

    private static func recordsURL(configuration: TaskBoardConfiguration) -> URL {
        baseURL.appending(
            path: "/open-apis/bitable/v1/apps/\(configuration.appToken.pathEscaped)/tables/\(configuration.tableID.pathEscaped)/records"
        )
    }

    private static func recordURL(
        configuration: TaskBoardConfiguration,
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
