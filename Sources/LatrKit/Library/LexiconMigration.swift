import Foundation

public struct LexiconMigrationSummary: Sendable, Equatable {
    public var externalCopied: Int
    public var itemsCopied: Int
    public var externalDeleted: Int
    public var itemsDeleted: Int

    public init(
        externalCopied: Int = 0,
        itemsCopied: Int = 0,
        externalDeleted: Int = 0,
        itemsDeleted: Int = 0
    ) {
        self.externalCopied = externalCopied
        self.itemsCopied = itemsCopied
        self.externalDeleted = externalDeleted
        self.itemsDeleted = itemsDeleted
    }

    public var changed: Bool {
        externalCopied > 0 || itemsCopied > 0 || externalDeleted > 0 || itemsDeleted > 0
    }
}

extension SavedLibrary {
    /// Copies legacy `com.latr.saved.*` records into `link.latr.saved.*` and deletes the old rows.
    public func migrateLegacyLexiconsIfNeeded() async throws -> LexiconMigrationSummary {
        let legacyExternalProbe: RecordList<ExternalSave> = try await repository.listRecords(
            in: repositoryDID,
            collection: .legacyExternal,
            limit: 1,
            startingAfter: nil
        )
        let legacyItemProbe: RecordList<SavedItem> = try await repository.listRecords(
            in: repositoryDID,
            collection: .legacySavedItem,
            limit: 1,
            startingAfter: nil
        )
        guard !legacyExternalProbe.records.isEmpty || !legacyItemProbe.records.isEmpty else {
            return LexiconMigrationSummary()
        }

        var summary = LexiconMigrationSummary()

        let legacyExternals = try await listAllRecords(collection: .legacyExternal, as: ExternalSave.self)
        for record in legacyExternals {
            guard let key = LexiconURI.recordKey(from: record.uri) else { continue }
            if try await externalSave(withKey: key) == nil {
                var value = record.value
                value.type = LexiconCollection.external.identifier
                _ = try await repository.createRecord(
                    in: repositoryDID,
                    collection: .external,
                    withKey: key,
                    value: value
                )
                summary.externalCopied += 1
            }
            try await repository.deleteRecord(
                in: repositoryDID,
                collection: .legacyExternal,
                withKey: key
            )
            summary.externalDeleted += 1
        }

        let legacyItems = try await listAllRecords(collection: .legacySavedItem, as: SavedItem.self)
        for record in legacyItems {
            guard let key = LexiconURI.recordKey(from: record.uri) else { continue }
            if try await savedItem(withKey: key) == nil {
                var value = record.value
                value.type = LexiconCollection.savedItem.identifier
                value.subjectUri = LexiconURI.remapLegacySubject(
                    value.subjectUri,
                    repositoryDID: repositoryDID
                )
                _ = try await repository.createRecord(
                    in: repositoryDID,
                    collection: .savedItem,
                    withKey: key,
                    value: value
                )
                summary.itemsCopied += 1
            }
            try await repository.deleteRecord(
                in: repositoryDID,
                collection: .legacySavedItem,
                withKey: key
            )
            summary.itemsDeleted += 1
        }

        return summary
    }

    private func listAllRecords<Value>(
        collection: LexiconCollection,
        as _: Value.Type
    ) async throws -> [RepositoryRecord<Value>] where Value: Codable & Sendable {
        var all: [RepositoryRecord<Value>] = []
        var cursor: String?
        repeat {
            let page: RecordList<Value> = try await repository.listRecords(
                in: repositoryDID,
                collection: collection,
                limit: 100,
                startingAfter: cursor
            )
            all.append(contentsOf: page.records)
            cursor = page.cursor
        } while cursor != nil
        return all
    }
}
