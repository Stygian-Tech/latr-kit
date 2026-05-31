import Foundation

public struct CreateRecordResponse: Sendable {
    public let uri: String

    public init(uri: String) {
        self.uri = uri
    }
}
