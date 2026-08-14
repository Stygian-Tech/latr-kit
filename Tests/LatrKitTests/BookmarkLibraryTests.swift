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
