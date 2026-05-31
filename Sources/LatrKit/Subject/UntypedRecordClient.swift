import Foundation

/// Optional hook for arbitrary public PDS records (`com.atproto.repo.getRecord`).
public protocol UntypedRecordClient: Sendable {
    func recordValue(in repository: String, collection: String, withKey key: String) async -> [String: Any]?
}
