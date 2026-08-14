import Foundation

public extension SavedLibrary {
    func bookmarks(limit: Int = 50, startingAfter cursor: String? = nil) async throws -> BookmarkList {
        let page: RecordList<CommunityBookmark> = try await repository.listRecords(
            in: repositoryDID,
            collection: .bookmark,
            limit: min(max(limit, 1), 100),
            startingAfter: cursor
        )
        var metadataByKey: [String: RepositoryRecord<BookmarkMetadata>] = [:]
        var metadataCursor: String?
        repeat {
            let metadataPage: RecordList<BookmarkMetadata> = try await repository.listRecords(
                in: repositoryDID,
                collection: .bookmarkMetadata,
                limit: 100,
                startingAfter: metadataCursor
            )
            for metadata in metadataPage.records {
                if let key = LexiconURI.recordKey(from: metadata.uri) {
                    metadataByKey[key] = metadata
                }
            }
            metadataCursor = metadataPage.cursor
        } while metadataCursor != nil
        var views: [BookmarkView] = []
        for record in page.records {
            guard let key = LexiconURI.recordKey(from: record.uri) else {
                throw SavedLibraryError.invalidStoredRecord(uri: record.uri)
            }
            views.append(BookmarkView(record: record, metadataRecord: metadataByKey[key]))
        }
        return BookmarkList(records: views, cursor: page.cursor)
    }

    func bookmark(subject rawSubject: String) async throws -> BookmarkView? {
        let subject = try validatedBookmarkSubject(rawSubject)
        var matches: [RepositoryRecord<CommunityBookmark>] = []
        var cursor: String?
        repeat {
            let page: RecordList<CommunityBookmark> = try await repository.listRecords(
                in: repositoryDID, collection: .bookmark, limit: 100, startingAfter: cursor
            )
            matches.append(contentsOf: page.records.filter { $0.value.subject == subject })
            cursor = page.cursor
        } while cursor != nil
        guard let selected = canonicalBookmark(from: matches) else { return nil }
        guard let key = LexiconURI.recordKey(from: selected.uri) else {
            throw SavedLibraryError.invalidStoredRecord(uri: selected.uri)
        }
        let metadata: RepositoryRecord<BookmarkMetadata>? = try await repository.record(
            in: repositoryDID, collection: .bookmarkMetadata, withKey: key
        )
        return BookmarkView(record: selected, metadataRecord: metadata)
    }

    @discardableResult
    func saveBookmark(subject rawSubject: String, tags: [String]? = nil) async throws -> BookmarkView {
        let subject = try validatedBookmarkSubject(rawSubject)
        let stableTags = tags.map { Array(Set($0)).sorted() }
        if let existing = try await bookmark(subject: subject) {
            guard let key = LexiconURI.recordKey(from: existing.uri) else {
                throw SavedLibraryError.invalidStoredRecord(uri: existing.uri)
            }
            var writes: [RepositoryWrite] = []
            var nextBookmark = existing.value
            if let stableTags {
                nextBookmark.tags = Array(Set((nextBookmark.tags ?? []) + stableTags)).sorted()
                if nextBookmark.tags != existing.value.tags {
                    writes.append(try .updating(collection: .bookmark, key: key, value: nextBookmark, swapRecord: existing.cid))
                }
            }
            if existing.metadataRecord == nil {
                let metadata = BookmarkMetadata(bookmarkUri: existing.uri, subject: subject, state: .unread)
                writes.append(try .creating(collection: .bookmarkMetadata, key: key, value: metadata))
            }
            if !writes.isEmpty { try await repository.applyWrites(in: repositoryDID, writes: writes) }
            return try await bookmark(subject: subject) ?? existing
        }

        let key = TID.now()
        let uri = "at://\(repositoryDID)/\(LexiconCollection.bookmark.identifier)/\(key)"
        let bookmark = CommunityBookmark(subject: subject, createdAt: Timestamp.iso8601Now(), tags: stableTags)
        let metadata = BookmarkMetadata(bookmarkUri: uri, subject: subject, state: .unread)
        try await repository.applyWrites(
            in: repositoryDID,
            writes: [
                try .creating(collection: .bookmark, key: key, value: bookmark),
                try .creating(collection: .bookmarkMetadata, key: key, value: metadata),
            ]
        )
        guard let created = try await self.bookmark(subject: subject) else {
            throw SavedLibraryError.invalidStoredRecord(uri: uri)
        }
        return created
    }

    func setState(ofBookmarkURI uri: String, to state: SavedItemState) async throws {
        guard let key = LexiconURI.recordKey(from: uri) else { throw SavedLibraryError.bookmarkNotFound }
        let bookmark: RepositoryRecord<CommunityBookmark>? = try await repository.record(
            in: repositoryDID, collection: .bookmark, withKey: key
        )
        guard let bookmark else { throw SavedLibraryError.bookmarkNotFound }
        let current: RepositoryRecord<BookmarkMetadata>? = try await repository.record(
            in: repositoryDID, collection: .bookmarkMetadata, withKey: key
        )
        if let current {
            var next = current.value
            next.state = state
            try await repository.applyWrites(in: repositoryDID, writes: [
                try .updating(collection: .bookmarkMetadata, key: key, value: next, swapRecord: current.cid),
            ])
        } else {
            let metadata = BookmarkMetadata(bookmarkUri: bookmark.uri, subject: bookmark.value.subject, state: state)
            try await repository.applyWrites(in: repositoryDID, writes: [
                try .creating(collection: .bookmarkMetadata, key: key, value: metadata),
            ])
        }
    }

    func removeBookmark(uri: String) async throws {
        guard let key = LexiconURI.recordKey(from: uri) else { throw SavedLibraryError.bookmarkNotFound }
        guard let bookmark: RepositoryRecord<CommunityBookmark> = try await repository.record(
            in: repositoryDID, collection: .bookmark, withKey: key
        ) else { throw SavedLibraryError.bookmarkNotFound }
        let metadata: RepositoryRecord<BookmarkMetadata>? = try await repository.record(
            in: repositoryDID, collection: .bookmarkMetadata, withKey: key
        )
        var writes: [RepositoryWrite] = [
            .delete(collection: .bookmark, key: key, swapRecord: bookmark.cid),
        ]
        if let metadata {
            writes.append(.delete(collection: .bookmarkMetadata, key: key, swapRecord: metadata.cid))
        }
        try await repository.applyWrites(in: repositoryDID, writes: writes)
    }

    private func validatedBookmarkSubject(_ raw: String) throws -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.utf8.count <= 8192 else { throw SavedLibraryError.invalidURL }
        if value.hasPrefix("at://") {
            guard value.split(separator: "/").count >= 4 else { throw SavedLibraryError.invalidURL }
            return value
        }
        guard let scheme = URLComponents(string: value)?.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
            throw SavedLibraryError.invalidURL
        }
        return value
    }

    private func canonicalBookmark(from records: [RepositoryRecord<CommunityBookmark>]) -> RepositoryRecord<CommunityBookmark>? {
        records.sorted {
            if $0.value.createdAt != $1.value.createdAt { return $0.value.createdAt < $1.value.createdAt }
            return $0.uri < $1.uri
        }.first
    }
}
