import Foundation

public struct UpdateRecordResponse: Sendable {
    public let uri: String

    public init(uri: String) {
        self.uri = uri
    }
}
