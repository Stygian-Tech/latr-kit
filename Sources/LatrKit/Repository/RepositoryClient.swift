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
        value: some Encodable & Sendable
    ) async throws -> UpdateRecordResponse

    func deleteRecord(
        in repository: String,
        collection: LexiconCollection,
        withKey key: String
    ) async throws
}
