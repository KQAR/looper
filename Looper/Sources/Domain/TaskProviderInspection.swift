import Foundation

struct TaskProviderInspection: Equatable, Sendable {
    var previewTaskCount: Int
    var discoveredFieldNames: [String]
    var detectedStatusValues: [String]
    var sampleTaskTitles: [String]
}
