import Foundation
import LatrKit

final class InMemoryRepository: RepositoryClient, @unchecked Sendable {
    private var store: [String: (uri: String, cid: String, json: Data)] = [:]
    private var beforeNextApplyWrites: (@Sendable ([RepositoryWrite]) async throws -> Void)?

    func snapshotKeys() -> [String] { Array(store.keys) }

    private func storeKey(collection: LexiconCollection, key: String) -> String {
        "\(collection.identifier):\(key)"
    }

    func listRecords<Value>(
        in repository: String,
        collection: LexiconCollection,
        limit: Int?,
        startingAfter cursor: String?
    ) async throws -> RecordList<Value> where Value: Decodable, Value: Encodable, Value: Sendable {
        let prefix = "\(collection.identifier):"
        let all: [RepositoryRecord<Value>] = try store
            .filter { $0.key.hasPrefix(prefix) }
            .map { _, entry in
                let decoded = try JSONDecoder().decode(Value.self, from: entry.json)
                return RepositoryRecord(uri: entry.uri, cid: entry.cid, value: decoded)
            }
            .sorted { $0.uri < $1.uri }

        let start = cursor.flatMap { Int($0) } ?? 0
        let pageLimit = limit ?? 100
        let page = Array(all.dropFirst(start).prefix(pageLimit))
        let next = start + pageLimit < all.count ? String(start + pageLimit) : nil
        return RecordList(records: page, cursor: next)
    }

    func record<Value>(
        in repository: String,
        collection: LexiconCollection,
        withKey key: String
    ) async throws -> RepositoryRecord<Value>? where Value: Decodable, Value: Encodable, Value: Sendable {
        guard let entry = store[storeKey(collection: collection, key: key)] else { return nil }
        let decoded = try JSONDecoder().decode(Value.self, from: entry.json)
        return RepositoryRecord(uri: entry.uri, cid: entry.cid, value: decoded)
    }

    func createRecord(
        in repository: String,
        collection: LexiconCollection,
        withKey key: String,
        value: some Encodable & Sendable
    ) async throws -> CreateRecordResponse {
        let uri = "at://\(repository)/\(collection.identifier)/\(key)"
        let json = try JSONEncoder().encode(value)
        store[storeKey(collection: collection, key: key)] = (uri: uri, cid: "bafytest", json: json)
        return CreateRecordResponse(uri: uri)
    }

    func updateRecord(
        in repository: String,
        collection: LexiconCollection,
        withKey key: String,
        value: some Encodable & Sendable,
        swapRecord: String?
    ) async throws -> UpdateRecordResponse {
        let uri = "at://\(repository)/\(collection.identifier)/\(key)"
        let json = try JSONEncoder().encode(value)
        store[storeKey(collection: collection, key: key)] = (uri: uri, cid: "bafytest", json: json)
        return UpdateRecordResponse(uri: uri)
    }

    func deleteRecord(
        in repository: String,
        collection: LexiconCollection,
        withKey key: String,
        swapRecord: String?
    ) async throws {
        store.removeValue(forKey: storeKey(collection: collection, key: key))
    }

    func applyWrites(in repository: String, writes: [RepositoryWrite]) async throws {
        if let hook = beforeNextApplyWrites {
            beforeNextApplyWrites = nil
            try await hook(writes)
        }
        var next = store
        for write in writes {
            switch write {
            case let .create(collection, key, value):
                let storeKey = storeKey(collection: collection, key: key)
                guard next[storeKey] == nil else { throw RepositoryClientError.conflict }
                let uri = "at://\(repository)/\(collection.identifier)/\(key)"
                next[storeKey] = (uri, "bafytest", try JSONEncoder().encode(value))
            case let .update(collection, key, value, swapRecord):
                let storeKey = storeKey(collection: collection, key: key)
                guard next[storeKey]?.cid == swapRecord else { throw RepositoryClientError.conflict }
                let uri = "at://\(repository)/\(collection.identifier)/\(key)"
                next[storeKey] = (uri, "bafyupdated", try JSONEncoder().encode(value))
            case let .delete(collection, key, swapRecord):
                let storeKey = storeKey(collection: collection, key: key)
                if let swapRecord, next[storeKey]?.cid != swapRecord { throw RepositoryClientError.conflict }
                next.removeValue(forKey: storeKey)
            }
        }
        store = next
    }

    func hasRecord(collection: LexiconCollection, key: String) -> Bool {
        store[storeKey(collection: collection, key: key)] != nil
    }

    func beforeNextApplyWrites(_ hook: @escaping @Sendable ([RepositoryWrite]) async throws -> Void) {
        beforeNextApplyWrites = hook
    }
}
