import Foundation

public struct RepositoryRecord<Value: Codable & Sendable>: Codable, Sendable {
    public let uri: String
    public let cid: String
    public let value: Value

    public init(uri: String, cid: String, value: Value) {
        self.uri = uri
        self.cid = cid
        self.value = value
    }
}
