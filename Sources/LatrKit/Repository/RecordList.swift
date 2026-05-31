import Foundation

public struct RecordList<Value: Codable & Sendable>: Sendable {
    public let records: [RepositoryRecord<Value>]
    public let cursor: String?

    public init(records: [RepositoryRecord<Value>], cursor: String?) {
        self.records = records
        self.cursor = cursor
    }
}
