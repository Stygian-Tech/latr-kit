import LatrKit
import XCTest

final class BookmarkLibraryTests: XCTestCase {
    private let did = "did:plc:testviewer"

    func testTIDUsesCanonicalLengthAndAlphabet() {
        let tid = TID.now(clockID: 1)
        XCTAssertEqual(tid.count, 13)
        XCTAssertTrue(tid.allSatisfy { "234567abcdefghijklmnopqrstuvwxyz".contains($0) })
    }

    func testSavePreservesExactHTTPSubjectAndIsIdempotent() async throws {
        let repository = InMemoryRepository()
        let library = SavedLibrary(repository: repository, repositoryDID: did)
        let subject = "https://Example.com/article?utm_source=encountered#section"
        let first = try await library.saveBookmark(subject: subject, tags: ["news", "news"])
        let second = try await library.saveBookmark(subject: subject, tags: ["later"])

        XCTAssertEqual(first.uri, second.uri)
        XCTAssertEqual(second.value.subject, subject)
        XCTAssertEqual(second.value.tags, ["later", "news"])
        XCTAssertEqual(second.metadataRecord?.value.state, .unread)
        XCTAssertEqual(repository.snapshotKeys().filter { $0.hasPrefix("\(LexiconCollection.bookmark.identifier):") }.count, 1)
    }

    func testDirectATURISubjectAndStateSidecar() async throws {
        let repository = InMemoryRepository()
        let library = SavedLibrary(repository: repository, repositoryDID: did)
        let subject = "at://did:plc:author/app.bsky.feed.post/3abc"
        let saved = try await library.saveBookmark(subject: subject)
        try await library.setState(ofBookmarkURI: saved.uri, to: .archived)
        let updated = try await library.bookmark(subject: subject)
        XCTAssertEqual(updated?.value.subject, subject)
        XCTAssertEqual(updated?.metadataRecord?.value.state, .archived)
    }

    func testSyncCreatesUnreadMetadataForExternalHTTPAndATBookmarks() async throws {
        let repository = InMemoryRepository()
        let library = SavedLibrary(repository: repository, repositoryDID: did)
        let subjects = [
            "https://Example.com/article?utm_source=encountered#section",
            "at://did:plc:author/app.bsky.feed.post/3abc",
        ]
        for (index, subject) in subjects.enumerated() {
            _ = try await repository.createRecord(
                in: did,
                collection: .bookmark,
                withKey: "external-\(index)",
                value: CommunityBookmark(subject: subject, createdAt: "2026-01-0\(index + 1)T00:00:00Z")
            )
        }

        let summary = try await library.syncBookmarkMetadata()

        XCTAssertEqual(summary.scanned, 2)
        XCTAssertEqual(summary.created, 2)
        for (index, subject) in subjects.enumerated() {
            let metadata: RepositoryRecord<BookmarkMetadata>? = try await repository.record(
                in: did,
                collection: .bookmarkMetadata,
                withKey: "external-\(index)"
            )
            XCTAssertEqual(metadata?.value.bookmarkUri, "at://\(did)/\(LexiconCollection.bookmark.identifier)/external-\(index)")
            XCTAssertEqual(metadata?.value.subject, subject)
            XCTAssertEqual(metadata?.value.state, .unread)
        }
    }

    func testSyncPreservesValidMetadataAndSkipsMismatchedSidecar() async throws {
        let repository = InMemoryRepository()
        let library = SavedLibrary(repository: repository, repositoryDID: did)
        let validURI = "at://\(did)/\(LexiconCollection.bookmark.identifier)/valid"
        let conflictURI = "at://\(did)/\(LexiconCollection.bookmark.identifier)/conflict"
        _ = try await repository.createRecord(in: did, collection: .bookmark, withKey: "valid", value: CommunityBookmark(
            subject: "https://example.com/valid", createdAt: "2026-01-01T00:00:00Z"
        ))
        _ = try await repository.createRecord(in: did, collection: .bookmarkMetadata, withKey: "valid", value: BookmarkMetadata(
            bookmarkUri: validURI,
            subject: "https://example.com/valid",
            state: .archived,
            unknownFields: ["future": .string("preserve")]
        ))
        _ = try await repository.createRecord(in: did, collection: .bookmark, withKey: "conflict", value: CommunityBookmark(
            subject: "https://example.com/current", createdAt: "2026-01-02T00:00:00Z"
        ))
        _ = try await repository.createRecord(in: did, collection: .bookmarkMetadata, withKey: "conflict", value: BookmarkMetadata(
            bookmarkUri: conflictURI,
            subject: "https://example.com/stale",
            state: .archived
        ))

        let summary = try await library.syncBookmarkMetadata()
        let list = try await library.bookmarks()

        XCTAssertEqual(summary.created, 0)
        XCTAssertEqual(summary.reused, 1)
        XCTAssertEqual(summary.skippedConflict, 1)
        XCTAssertEqual(list.records.first { $0.uri == validURI }?.metadataRecord?.value.unknownFields["future"], .string("preserve"))
        XCTAssertNil(list.records.first { $0.uri == conflictURI }?.metadataRecord)
    }

    func testSyncIsIdempotentAndCursorPaged() async throws {
        let repository = InMemoryRepository()
        let library = SavedLibrary(repository: repository, repositoryDID: did)
        for index in 0 ..< 3 {
            _ = try await repository.createRecord(in: did, collection: .bookmark, withKey: "page-\(index)", value: CommunityBookmark(
                subject: "https://example.com/\(index)", createdAt: "2026-01-0\(index + 1)T00:00:00Z"
            ))
        }

        let first = try await library.syncBookmarkMetadata(limit: 2)
        let second = try await library.syncBookmarkMetadata(limit: 2, startingAfter: first.cursor)
        let retry = try await library.syncBookmarkMetadata(limit: 2)

        XCTAssertEqual(first.scanned, 2)
        XCTAssertEqual(first.created, 2)
        XCTAssertNotNil(first.cursor)
        XCTAssertEqual(second.scanned, 1)
        XCTAssertEqual(second.created, 1)
        XCTAssertNil(second.cursor)
        XCTAssertEqual(retry.created, 0)
        XCTAssertEqual(retry.reused, 2)
    }

    func testSyncAtomicCreateConflictSucceedsOnRetry() async throws {
        let repository = InMemoryRepository()
        let library = SavedLibrary(repository: repository, repositoryDID: did)
        let key = "racing"
        let subject = "https://example.com/racing"
        let uri = "at://\(did)/\(LexiconCollection.bookmark.identifier)/\(key)"
        let repositoryDID = did
        _ = try await repository.createRecord(in: did, collection: .bookmark, withKey: key, value: CommunityBookmark(
            subject: subject, createdAt: "2026-01-01T00:00:00Z"
        ))
        repository.beforeNextApplyWrites { _ in
            _ = try await repository.createRecord(
                in: repositoryDID,
                collection: .bookmarkMetadata,
                withKey: key,
                value: BookmarkMetadata(bookmarkUri: uri, subject: subject, state: .unread)
            )
        }

        do {
            _ = try await library.syncBookmarkMetadata()
            XCTFail("Expected an atomic create conflict")
        } catch RepositoryClientError.conflict {}

        let retry = try await library.syncBookmarkMetadata()
        XCTAssertEqual(retry.created, 0)
        XCTAssertEqual(retry.reused, 1)
    }

    func testMigrationFlattensWrapperPreservesStateAndIsRetrySafe() async throws {
        let repository = InMemoryRepository()
        let library = SavedLibrary(repository: repository, repositoryDID: did)
        let externalKey = "external"
        let wrapperURI = "at://\(did)/\(LexiconCollection.external.identifier)/\(externalKey)"
        _ = try await repository.createRecord(in: did, collection: .external, withKey: externalKey, value: ExternalSave(
            url: "https://example.com/original?ref=encountered",
            normalizedUrl: "https://example.com/original",
            fingerprint: "abc",
            createdAt: "2026-01-01T00:00:00Z",
            title: "Derived title"
        ))
        _ = try await repository.createRecord(in: did, collection: .savedItem, withKey: "item", value: SavedItem(
            subjectUri: wrapperURI,
            savedAt: "2026-01-02T00:00:00Z",
            state: .archived,
            tags: ["news"],
            note: "Keep me"
        ))

        let first = try await library.migrateBookmarks()
        let migrated = try await library.bookmark(subject: "https://example.com/original?ref=encountered")
        let second = try await library.migrateBookmarks()

        XCTAssertEqual(first.created, 1)
        XCTAssertEqual(first.retired, 2)
        XCTAssertEqual(migrated?.value.createdAt, "2026-01-02T00:00:00Z")
        XCTAssertEqual(migrated?.value.tags, ["news"])
        XCTAssertEqual(migrated?.metadataRecord?.value.state, .archived)
        XCTAssertEqual(migrated?.metadataRecord?.value.note, "Keep me")
        XCTAssertEqual(second.scanned, 0)
    }

    func testMigrationLeavesConflictingDuplicateNotesUntouched() async throws {
        let repository = InMemoryRepository()
        let library = SavedLibrary(repository: repository, repositoryDID: did)
        let subject = "https://example.com/conflict"
        _ = try await repository.createRecord(in: did, collection: .savedItem, withKey: "a", value: SavedItem(
            subjectUri: "at://did:plc:author/site.standard.document/a",
            savedAt: "2026-01-01T00:00:00Z",
            note: "first",
            linkedWebUrl: subject
        ))
        _ = try await repository.createRecord(in: did, collection: .legacySavedItem, withKey: "b", value: SavedItem(
            subjectUri: "at://did:plc:author/site.standard.document/a",
            savedAt: "2026-01-02T00:00:00Z",
            note: "second",
            linkedWebUrl: subject
        ))

        let summary = try await library.migrateBookmarks()

        XCTAssertEqual(summary.skippedConflict, 2)
        let migrated = try await library.bookmark(subject: subject)
        XCTAssertNil(migrated)
        XCTAssertTrue(repository.hasRecord(collection: .savedItem, key: "a"))
        XCTAssertTrue(repository.hasRecord(collection: .legacySavedItem, key: "b"))
    }

    func testMigrationLeavesUnknownLegacyFieldsUntouched() async throws {
        let repository = InMemoryRepository()
        let library = SavedLibrary(repository: repository, repositoryDID: did)
        _ = try await repository.createRecord(in: did, collection: .savedItem, withKey: "unknown", value: SavedItem(
            subjectUri: "https://example.com/unknown",
            savedAt: "2026-01-01T00:00:00Z",
            unknownFields: ["future": .string("preserve")]
        ))

        let summary = try await library.migrateBookmarks()

        XCTAssertEqual(summary.skippedConflict, 1)
        XCTAssertTrue(repository.hasRecord(collection: .savedItem, key: "unknown"))
        let migrated = try await library.bookmark(subject: "https://example.com/unknown")
        XCTAssertNil(migrated)
    }
}
