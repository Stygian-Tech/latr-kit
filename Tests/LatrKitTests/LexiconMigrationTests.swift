import LatrKit
import XCTest

final class LexiconMigrationTests: XCTestCase {
    private let did = "did:plc:testviewer"

    func testMigrateLegacyExternalAndItemRecords() async throws {
        let repository = InMemoryRepository()
        let library = SavedLibrary(repository: repository, repositoryDID: did)
        let externalKey = RecordKey.key(forNormalizedURL: "https://example.com/article")
        let legacyWrapperURI = "at://\(did)/\(LexiconCollection.legacyExternal.rawValue)/\(externalKey)"
        let itemKey = RecordKey.key(forSubjectURI: legacyWrapperURI)

        _ = try await repository.createRecord(
            in: did,
            collection: .legacyExternal,
            withKey: externalKey,
            value: ExternalSave(
                url: "https://example.com/article",
                normalizedUrl: "https://example.com/article",
                fingerprint: RecordKey.fingerprint(forNormalizedURL: "https://example.com/article"),
                createdAt: "2026-01-01T00:00:00Z",
                title: "Article"
            )
        )
        _ = try await repository.createRecord(
            in: did,
            collection: .legacySavedItem,
            withKey: itemKey,
            value: SavedItem(
                subjectUri: legacyWrapperURI,
                savedAt: "2026-01-01T00:00:00Z",
                state: .unread,
                linkedWebUrl: "https://example.com/article"
            )
        )

        let summary = try await library.migrateLegacyLexiconsIfNeeded()

        XCTAssertEqual(summary.externalCopied, 1)
        XCTAssertEqual(summary.itemsCopied, 1)
        XCTAssertEqual(summary.externalDeleted, 1)
        XCTAssertEqual(summary.itemsDeleted, 1)
        XCTAssertTrue(repository.hasRecord(collection: .external, key: externalKey))
        XCTAssertTrue(repository.hasRecord(collection: .savedItem, key: itemKey))
        XCTAssertFalse(repository.hasRecord(collection: .legacyExternal, key: externalKey))
        XCTAssertFalse(repository.hasRecord(collection: .legacySavedItem, key: itemKey))

        let item = try await library.savedItem(withKey: itemKey)
        XCTAssertEqual(
            item?.value.subjectUri,
            ATURI.externalSave(repositoryDID: did, recordKey: externalKey)
        )
    }

    func testMigrateIsNoOpWhenLegacyCollectionsEmpty() async throws {
        let repository = InMemoryRepository()
        let library = SavedLibrary(repository: repository, repositoryDID: did)
        let summary = try await library.migrateLegacyLexiconsIfNeeded()
        XCTAssertFalse(summary.changed)
    }
}
