import Foundation

public extension SavedLibrary {
    func bookmarks(
        limit: Int = 50,
        startingAfter cursor: String? = nil,
        taggedWith rawTag: String? = nil
    ) async throws -> BookmarkList {
        let tag = try rawTag.map(BookmarkTags.normalized)
        let page: RecordList<CommunityBookmark> = try await repository.listRecords(
            in: repositoryDID,
            collection: .bookmark,
            limit: min(max(limit, 1), 100),
            startingAfter: cursor
        )
        let metadataByKey = try await bookmarkMetadataByKey()
        var views: [BookmarkView] = []
        let matchingRecords = tag.map { selectedTag in
            page.records.filter { $0.value.tags?.contains(selectedTag) == true }
        } ?? page.records
        for record in matchingRecords {
            guard let key = LexiconURI.recordKey(from: record.uri) else {
                throw SavedLibraryError.invalidStoredRecord(uri: record.uri)
            }
            let metadata = metadataByKey[key].flatMap { bookmarkMetadata($0, matches: record) ? $0 : nil }
            views.append(BookmarkView(record: record, metadataRecord: metadata))
        }
        return BookmarkList(records: views, cursor: page.cursor)
    }

    func bookmarkTags(limit: Int = 100, startingAfter cursor: String? = nil) async throws -> BookmarkTagList {
        let page: RecordList<CommunityBookmark> = try await repository.listRecords(
            in: repositoryDID,
            collection: .bookmark,
            limit: min(max(limit, 1), 100),
            startingAfter: cursor
        )
        var counts: [String: Int] = [:]
        for record in page.records {
            for tag in Set(record.value.tags ?? []) {
                counts[tag, default: 0] += 1
            }
        }
        let tagCounts = counts.keys.sorted().map { BookmarkTagCount(tag: $0, count: counts[$0] ?? 0) }
        return BookmarkTagList(tagCounts: tagCounts, scanned: page.records.count, cursor: page.cursor)
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
        return BookmarkView(
            record: selected,
            metadataRecord: metadata.flatMap { bookmarkMetadata($0, matches: selected) ? $0 : nil }
        )
    }

    func syncBookmarkMetadata(
        limit rawLimit: Int = 50,
        startingAfter cursor: String? = nil
    ) async throws -> BookmarkMetadataSyncSummary {
        let page: RecordList<CommunityBookmark> = try await repository.listRecords(
            in: repositoryDID,
            collection: .bookmark,
            limit: min(max(rawLimit, 1), 100),
            startingAfter: cursor
        )
        let metadataByKey = try await bookmarkMetadataByKey()
        var summary = BookmarkMetadataSyncSummary(scanned: page.records.count, cursor: page.cursor)
        var writes: [RepositoryWrite] = []

        for bookmark in page.records {
            guard let key = LexiconURI.recordKey(from: bookmark.uri) else {
                throw SavedLibraryError.invalidStoredRecord(uri: bookmark.uri)
            }
            if let metadata = metadataByKey[key] {
                if bookmarkMetadata(metadata, matches: bookmark) {
                    summary.reused += 1
                } else {
                    summary.skippedConflict += 1
                }
                continue
            }

            let metadata = BookmarkMetadata(
                bookmarkUri: bookmark.uri,
                subject: bookmark.value.subject,
                state: .unread
            )
            writes.append(try .creating(collection: .bookmarkMetadata, key: key, value: metadata))
        }

        if !writes.isEmpty {
            try await repository.applyWrites(in: repositoryDID, writes: writes)
            summary.created = writes.count
        }
        return summary
    }

    @discardableResult
    func saveBookmark(subject rawSubject: String, tags: [String]? = nil) async throws -> BookmarkView {
        let subject = try validatedBookmarkSubject(rawSubject)
        let stableTags = try tags.map(BookmarkTags.normalized)
        if let existing = try await bookmark(subject: subject) {
            guard let key = LexiconURI.recordKey(from: existing.uri) else {
                throw SavedLibraryError.invalidStoredRecord(uri: existing.uri)
            }
            var writes: [RepositoryWrite] = []
            var nextBookmark = existing.value
            if let stableTags {
                let mergedTags = try BookmarkTags.merging(nextBookmark.tags ?? [], with: stableTags)
                nextBookmark.tags = mergedTags.isEmpty ? nil : mergedTags
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
        let bookmark = CommunityBookmark(
            subject: subject,
            createdAt: Timestamp.iso8601Now(),
            tags: stableTags?.isEmpty == false ? stableTags : nil
        )
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

    @discardableResult
    func setTags(ofBookmarkURI uri: String, to rawTags: [String]) async throws -> BookmarkView {
        let tags = try BookmarkTags.normalized(rawTags)
        guard let key = LexiconURI.recordKey(from: uri),
              let current: RepositoryRecord<CommunityBookmark> = try await repository.record(
                  in: repositoryDID,
                  collection: .bookmark,
                  withKey: key
              ),
              current.uri == uri
        else {
            throw SavedLibraryError.bookmarkNotFound
        }

        var next = current.value
        next.tags = tags.isEmpty ? nil : tags
        if next.tags != current.value.tags {
            do {
                try await repository.applyWrites(in: repositoryDID, writes: [
                    try .updating(collection: .bookmark, key: key, value: next, swapRecord: current.cid),
                ])
            } catch RepositoryClientError.conflict {
                throw SavedLibraryError.conflict
            }
        }

        guard let updated: RepositoryRecord<CommunityBookmark> = try await repository.record(
            in: repositoryDID,
            collection: .bookmark,
            withKey: key
        ) else {
            throw SavedLibraryError.bookmarkNotFound
        }
        return try await bookmarkView(for: updated)
    }

    func renameTag(
        _ rawSource: String,
        to rawTarget: String,
        limit: Int = 25,
        continuingFrom cursor: String? = nil
    ) async throws -> BookmarkTagMutationSummary {
        let rename = try BookmarkTags.normalizedRename(source: rawSource, target: rawTarget)
        return try await mutateTag(
            rename.source,
            limit: limit,
            continuingFrom: cursor,
            transform: { tags in
                deduplicatedTags(tags.map { $0 == rename.source ? rename.target : $0 })
            }
        )
    }

    func deleteTag(
        _ rawTag: String,
        limit: Int = 25,
        continuingFrom cursor: String? = nil
    ) async throws -> BookmarkTagMutationSummary {
        let tag = try BookmarkTags.normalized(rawTag)
        return try await mutateTag(
            tag,
            limit: limit,
            continuingFrom: cursor,
            transform: { tags in deduplicatedTags(tags.filter { $0 != tag }) }
        )
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
            guard bookmarkMetadata(current, matches: bookmark) else {
                throw SavedLibraryError.invalidStoredRecord(uri: current.uri)
            }
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
        if let metadata, bookmarkMetadata(metadata, matches: bookmark) {
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

    private func bookmarkView(for bookmark: RepositoryRecord<CommunityBookmark>) async throws -> BookmarkView {
        guard let key = LexiconURI.recordKey(from: bookmark.uri) else {
            throw SavedLibraryError.invalidStoredRecord(uri: bookmark.uri)
        }
        let metadata: RepositoryRecord<BookmarkMetadata>? = try await repository.record(
            in: repositoryDID,
            collection: .bookmarkMetadata,
            withKey: key
        )
        return BookmarkView(
            record: bookmark,
            metadataRecord: metadata.flatMap { bookmarkMetadata($0, matches: bookmark) ? $0 : nil }
        )
    }

    private func mutateTag(
        _ source: String,
        limit: Int,
        continuingFrom rawCursor: String?,
        transform: ([String]) -> [String]
    ) async throws -> BookmarkTagMutationSummary {
        let cursor = try BookmarkTagMutationCursor(rawValue: rawCursor)
        let page: RecordList<CommunityBookmark> = try await repository.listRecords(
            in: repositoryDID,
            collection: .bookmark,
            limit: min(max(limit, 1), 25),
            startingAfter: cursor.repositoryCursor
        )
        let matches = page.records.filter { $0.value.tags?.contains(source) == true }
        var writes: [RepositoryWrite] = []
        writes.reserveCapacity(matches.count)

        for record in matches {
            guard let key = LexiconURI.recordKey(from: record.uri) else {
                throw SavedLibraryError.invalidStoredRecord(uri: record.uri)
            }
            var next = record.value
            let tags = transform(record.value.tags ?? [])
            next.tags = tags.isEmpty ? nil : tags
            writes.append(try .updating(
                collection: .bookmark,
                key: key,
                value: next,
                swapRecord: record.cid
            ))
        }

        if !writes.isEmpty {
            do {
                try await repository.applyWrites(in: repositoryDID, writes: writes)
            } catch RepositoryClientError.conflict {
                throw SavedLibraryError.conflict
            }
        }

        switch cursor {
        case .mutation:
            let nextCursor = page.cursor.map(BookmarkTagMutationCursor.mutation)
                ?? .verification(nil)
            return BookmarkTagMutationSummary(
                scanned: page.records.count,
                matched: matches.count,
                updated: writes.count,
                cursor: nextCursor.rawValue
            )
        case .verification:
            if !writes.isEmpty {
                return BookmarkTagMutationSummary(
                    scanned: page.records.count,
                    matched: matches.count,
                    updated: writes.count,
                    cursor: BookmarkTagMutationCursor.verification(nil).rawValue
                )
            }
            if let next = page.cursor {
                return BookmarkTagMutationSummary(
                    scanned: page.records.count,
                    matched: 0,
                    updated: 0,
                    cursor: BookmarkTagMutationCursor.verification(next).rawValue
                )
            }
            return BookmarkTagMutationSummary(
                scanned: page.records.count,
                matched: 0,
                updated: 0,
                cursor: nil
            )
        }
    }

    private func deduplicatedTags(_ tags: [String]) -> [String] {
        var seen: Set<String> = []
        return tags.filter { seen.insert($0).inserted }
    }

    private func canonicalBookmark(from records: [RepositoryRecord<CommunityBookmark>]) -> RepositoryRecord<CommunityBookmark>? {
        records.sorted {
            if $0.value.createdAt != $1.value.createdAt { return $0.value.createdAt < $1.value.createdAt }
            return $0.uri < $1.uri
        }.first
    }

    private func bookmarkMetadataByKey() async throws -> [String: RepositoryRecord<BookmarkMetadata>] {
        var metadataByKey: [String: RepositoryRecord<BookmarkMetadata>] = [:]
        var cursor: String?
        repeat {
            let page: RecordList<BookmarkMetadata> = try await repository.listRecords(
                in: repositoryDID,
                collection: .bookmarkMetadata,
                limit: 100,
                startingAfter: cursor
            )
            for metadata in page.records {
                if let key = LexiconURI.recordKey(from: metadata.uri) {
                    metadataByKey[key] = metadata
                }
            }
            cursor = page.cursor
        } while cursor != nil
        return metadataByKey
    }

    private func bookmarkMetadata(
        _ metadata: RepositoryRecord<BookmarkMetadata>,
        matches bookmark: RepositoryRecord<CommunityBookmark>
    ) -> Bool {
        metadata.value.bookmarkUri == bookmark.uri && metadata.value.subject == bookmark.value.subject
    }
}

private enum BookmarkTagMutationCursor {
    case mutation(String?)
    case verification(String?)

    init(rawValue: String?) throws {
        guard let rawValue else {
            self = .mutation(nil)
            return
        }
        if rawValue.hasPrefix("m:") {
            let value = String(rawValue.dropFirst(2))
            self = .mutation(value.isEmpty ? nil : value)
            return
        }
        if rawValue.hasPrefix("v:") {
            let value = String(rawValue.dropFirst(2))
            self = .verification(value.isEmpty ? nil : value)
            return
        }
        throw SavedLibraryError.invalidTagMutationCursor
    }

    var repositoryCursor: String? {
        switch self {
        case let .mutation(cursor), let .verification(cursor): cursor
        }
    }

    var rawValue: String {
        switch self {
        case let .mutation(cursor): "m:\(cursor ?? "")"
        case let .verification(cursor): "v:\(cursor ?? "")"
        }
    }
}
