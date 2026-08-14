import Foundation

public struct BookmarkMigrationSummary: Codable, Sendable, Equatable {
    public var ok = true
    public var scanned = 0
    public var created = 0
    public var reused = 0
    public var duplicates = 0
    public var skippedConflict = 0
    public var cached = 0
    public var retired = 0
    public var cursor: String?

    public init() {}
}

private struct LegacyItemSource: Sendable {
    let collection: LexiconCollection
    let record: RepositoryRecord<SavedItem>
}

private struct LegacyExternalSource: Sendable {
    let collection: LexiconCollection
    let record: RepositoryRecord<ExternalSave>
}

public extension SavedLibrary {
    func migrateBookmarks(limit rawLimit: Int = 25, cursor rawCursor: String? = nil) async throws -> BookmarkMigrationSummary {
        let limit = min(max(rawLimit, 1), 100)
        let subjectCursor = rawCursor?.trimmingCharacters(in: .whitespacesAndNewlines)
        let externalSources = try await allExternalMigrationSources()
        let externalByURI = Dictionary(uniqueKeysWithValues: externalSources.map { ($0.record.uri, $0) })
        let itemSources = try await allItemMigrationSources().sorted { $0.record.uri < $1.record.uri }

        let candidates = itemSources.compactMap { source -> (LegacyItemSource, String)? in
            guard let subject = migrationSubject(for: source.record.value, externalByURI: externalByURI) else { return nil }
            return (source, subject)
        }
        let grouped = Dictionary(grouping: candidates, by: { $0.1 })
            .sorted { $0.key < $1.key }
        let remaining = grouped.filter { subjectCursor == nil || $0.key > subjectCursor! }
        let page = Array(remaining.prefix(limit))
        var summary = BookmarkMigrationSummary()

        for (subject, entries) in page {
            summary.scanned += entries.count
            if entries.count > 1 { summary.duplicates += entries.count - 1 }
            let items = entries.map(\.0)
            let wrappers = Set(items.map(\.record.value.subjectUri)).compactMap { externalByURI[$0] }
            let notes = Set(items.compactMap { $0.record.value.note?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
            let hasUnknownFields = items.contains { !$0.record.value.unknownFields.isEmpty }
                || wrappers.contains { !$0.record.value.unknownFields.isEmpty }
            if notes.count > 1 || hasUnknownFields {
                summary.skippedConflict += entries.count
                continue
            }

            let existing = try await bookmark(subject: subject)
            let key = existing.flatMap { LexiconURI.recordKey(from: $0.uri) } ?? TID.now()
            let bookmarkURI = existing?.uri ?? "at://\(repositoryDID)/\(LexiconCollection.bookmark.identifier)/\(key)"
            let tags = Array(Set(items.flatMap { $0.record.value.tags ?? [] })).sorted()
            let createdAt = items.map(\.record.value.savedAt).min() ?? Timestamp.iso8601Now()
            let state: SavedItemState = items.contains { $0.record.value.state != .archived } ? .unread : .archived
            let lastOpenedAt = items.compactMap(\.record.value.lastOpenedAt).max()
            let legacyURIs = items.map(\.record.uri).sorted()
            let note = notes.first
            let nextBookmark = CommunityBookmark(
                subject: subject,
                createdAt: min(existing?.value.createdAt ?? createdAt, createdAt),
                tags: Array(Set((existing?.value.tags ?? []) + tags)).sorted(),
                unknownFields: existing?.value.unknownFields ?? [:]
            )
            let currentMetadata = existing?.metadataRecord
            if let currentNote = currentMetadata?.value.note?.trimmingCharacters(in: .whitespacesAndNewlines),
               !currentNote.isEmpty, let note, currentNote != note {
                summary.skippedConflict += entries.count
                continue
            }
            var nextMetadata = currentMetadata?.value ?? BookmarkMetadata(bookmarkUri: bookmarkURI, subject: subject)
            nextMetadata.state = currentMetadata?.value.state ?? state
            nextMetadata.note = currentMetadata?.value.note ?? note
            nextMetadata.lastOpenedAt = max(currentMetadata?.value.lastOpenedAt ?? "", lastOpenedAt ?? "").nilIfEmpty
            nextMetadata.legacyItemUris = Array(Set((nextMetadata.legacyItemUris ?? []) + legacyURIs)).sorted()

            var writes: [RepositoryWrite] = []
            if let existing {
                writes.append(try .updating(collection: .bookmark, key: key, value: nextBookmark, swapRecord: existing.cid))
                summary.reused += 1
            } else {
                writes.append(try .creating(collection: .bookmark, key: key, value: nextBookmark))
                summary.created += 1
            }
            if let currentMetadata {
                writes.append(try .updating(collection: .bookmarkMetadata, key: key, value: nextMetadata, swapRecord: currentMetadata.cid))
            } else {
                writes.append(try .creating(collection: .bookmarkMetadata, key: key, value: nextMetadata))
            }
            for item in items {
                guard let itemKey = LexiconURI.recordKey(from: item.record.uri) else { continue }
                writes.append(.delete(collection: item.collection, key: itemKey, swapRecord: item.record.cid))
            }
            for wrapper in wrappers {
                guard let wrapperKey = LexiconURI.recordKey(from: wrapper.record.uri) else { continue }
                writes.append(.delete(collection: wrapper.collection, key: wrapperKey, swapRecord: wrapper.record.cid))
            }
            do {
                try await repository.applyWrites(in: repositoryDID, writes: writes)
                summary.retired += items.count + wrappers.count
            } catch RepositoryClientError.conflict {
                summary.skippedConflict += entries.count
                if existing == nil { summary.created -= 1 } else { summary.reused -= 1 }
            }
        }

        summary.cursor = page.count < remaining.count ? page.last?.key : nil
        return summary
    }

    private func migrationSubject(
        for item: SavedItem,
        externalByURI: [String: LegacyExternalSource]
    ) -> String? {
        if let wrapper = externalByURI[item.subjectUri] {
            let original = wrapper.record.value.url.trimmingCharacters(in: .whitespacesAndNewlines)
            if original.hasPrefix("https://") || original.hasPrefix("http://") { return original }
            return wrapper.record.value.normalizedUrl
        }
        if let linked = item.linkedWebUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
           linked.hasPrefix("https://") || linked.hasPrefix("http://") { return linked }
        return item.subjectUri
    }

    private func allItemMigrationSources() async throws -> [LegacyItemSource] {
        var result: [LegacyItemSource] = []
        for collection in [LexiconCollection.savedItem, .legacySavedItem] {
            var cursor: String?
            repeat {
                let page: RecordList<SavedItem> = try await repository.listRecords(in: repositoryDID, collection: collection, limit: 100, startingAfter: cursor)
                result.append(contentsOf: page.records.map { LegacyItemSource(collection: collection, record: $0) })
                cursor = page.cursor
            } while cursor != nil
        }
        return result
    }

    private func allExternalMigrationSources() async throws -> [LegacyExternalSource] {
        var result: [LegacyExternalSource] = []
        for collection in [LexiconCollection.external, .legacyExternal] {
            var cursor: String?
            repeat {
                let page: RecordList<ExternalSave> = try await repository.listRecords(in: repositoryDID, collection: collection, limit: 100, startingAfter: cursor)
                result.append(contentsOf: page.records.map { LegacyExternalSource(collection: collection, record: $0) })
                cursor = page.cursor
            } while cursor != nil
        }
        return result
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
