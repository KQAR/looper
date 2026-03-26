import Foundation

struct TaskBoardInspection: Equatable, Sendable {
    var previewTaskCount: Int
    var discoveredFieldNames: [String]
    var detectedStatusValues: [String]
    var sampleTaskTitles: [String]
}
