/// Abstraction over ATProto `com.atproto.repo.*` operations.
public protocol RepositoryClient: Sendable {
    func listRecords<Value>(
        in repository: String,
        collection: LexiconCollection,
        limit: Int?,
        startingAfter cursor: String?
    ) async throws -> RecordList<Value> where Value: Codable & Sendable

    func record<Value>(
        in repository: String,
        collection: LexiconCollection,
        withKey key: String
    ) async throws -> RepositoryRecord<Value>? where Value: Codable & Sendable

    func createRecord(
        in repository: String,
        collection: LexiconCollection,
        withKey key: String,
        value: some Encodable & Sendable
    ) async throws -> CreateRecordResponse

    func updateRecord(
        in repository: String,
        collection: LexiconCollection,
        withKey key: String,
        value: some Encodable & Sendable,
        swapRecord: String?
    ) async throws -> UpdateRecordResponse

    func deleteRecord(
        in repository: String,
        collection: LexiconCollection,
        withKey key: String,
        swapRecord: String?
    ) async throws
}

public extension RepositoryClient {
    func updateRecord(
        in repository: String, collection: LexiconCollection, withKey key: String,
        value: some Encodable & Sendable
    ) async throws -> UpdateRecordResponse {
        try await updateRecord(in: repository, collection: collection, withKey: key, value: value, swapRecord: nil)
    }

    func deleteRecord(in repository: String, collection: LexiconCollection, withKey key: String) async throws {
        try await deleteRecord(in: repository, collection: collection, withKey: key, swapRecord: nil)
    }
}

public enum RepositoryClientError: Error, Sendable, Equatable {
    case conflict
    case invalidStoredRecord(uri: String)
}
