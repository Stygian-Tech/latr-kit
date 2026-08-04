import LatrKit
import XCTest

final class SavedLibraryTests: XCTestCase {
    private let did = "did:plc:testviewer"

    private func library(using repository: InMemoryRepository = InMemoryRepository()) -> (SavedLibrary, InMemoryRepository) {
        (SavedLibrary(repository: repository, repositoryDID: did), repository)
    }

    func testEnsureExternalSaveCreatesDeterministicWrapperOnce() async throws {
        let (library, repository) = library()
        let first = try await library.ensureExternalSave(for: "https://Example.COM/article?utm_source=x")
        let second = try await library.ensureExternalSave(for: "https://example.com/article")

        XCTAssertEqual(first.normalizedURL, "https://example.com/article")
        XCTAssertEqual(second.wrapperURI, first.wrapperURI)
        XCTAssertEqual(
            repository.snapshotKeys().filter { $0.hasPrefix("\(LexiconCollection.external.identifier):") }.count,
            1
        )
    }

    func testSaveURLCreatesRecordsWithPreview() async throws {
        let (library, repository) = library()
        try await library.save(
            url: "https://news.example/story",
            preview: OpenGraphPreview(
                title: "Story",
                description: "Lead",
                image: "https://news.example/og.png",
                author: "Ada Lovelace"
            )
        )

        let externalKey = RecordKey.key(forNormalizedURL: "https://news.example/story")
        let external = try await library.externalSave(withKey: externalKey)
        let wrapperURI = ATURI.externalSave(repositoryDID: did, recordKey: externalKey)
        let itemKey = RecordKey.key(forSubjectURI: wrapperURI)
        let item = try await library.savedItem(withKey: itemKey)

        XCTAssertEqual(external?.value.title, "Story")
        XCTAssertEqual(external?.value.author, "Ada Lovelace")
        XCTAssertEqual(item?.value.previewTitle, "Story")
        XCTAssertEqual(item?.value.previewImage, "https://news.example/og.png")
        XCTAssertEqual(item?.value.previewAuthor, "Ada Lovelace")
        XCTAssertEqual(item?.value.linkedWebUrl, "https://news.example/story")
        XCTAssertEqual(item?.value.state, .unread)
        XCTAssertTrue(repository.hasRecord(collection: .savedItem, key: itemKey))
    }

    func testSetStateUpdatesExistingItem() async throws {
        let (library, _) = library()
        let subjectURI = "at://did:plc:author/app.bsky.feed.post/state"
        _ = try await library.upsertSavedItem(subjectURI: subjectURI, state: .unread)
        let key = RecordKey.key(forSubjectURI: subjectURI)
        try await library.setState(ofSavedItemWithKey: key, to: .archived)

        let record = try await library.savedItem(withKey: key)
        XCTAssertEqual(record?.value.state, .archived)
    }

    func testRemoveSavedItemRemovesOnlyEdge() async throws {
        let (library, repository) = library()
        try await library.save(url: "https://delete.example/x")
        let externalKey = RecordKey.key(forNormalizedURL: "https://delete.example/x")
        let wrapperURI = ATURI.externalSave(repositoryDID: did, recordKey: externalKey)
        let itemKey = RecordKey.key(forSubjectURI: wrapperURI)

        try await library.removeSavedItem(withKey: itemKey)

        XCTAssertFalse(repository.hasRecord(collection: .savedItem, key: itemKey))
        XCTAssertTrue(repository.hasRecord(collection: .external, key: externalKey))
    }

    func testSavedItemsPageReturnsBoundedPageWithCursor() async throws {
        let (library, _) = library()
        for index in 0..<5 {
            _ = try await library.upsertSavedItem(
                subjectURI: "at://did:plc:author/app.bsky.feed.post/page\(index)"
            )
        }

        let first = try await library.savedItems(limit: 2)
        XCTAssertEqual(first.records.count, 2)
        XCTAssertNotNil(first.cursor)
    }

    func testSavedItemsPageCursorYieldsDisjointPagesAndTerminates() async throws {
        let (library, _) = library()
        for index in 0..<5 {
            _ = try await library.upsertSavedItem(
                subjectURI: "at://did:plc:author/app.bsky.feed.post/page\(index)"
            )
        }

        var paged: [String] = []
        var cursor: String?
        var pages = 0
        repeat {
            let page = try await library.savedItems(limit: 2, startingAfter: cursor)
            let uris = page.records.map(\.uri)
            XCTAssertTrue(Set(paged).isDisjoint(with: uris))
            paged.append(contentsOf: uris)
            cursor = page.cursor
            pages += 1
        } while cursor != nil

        XCTAssertEqual(pages, 3)
        let all = try await library.savedItems()
        XCTAssertEqual(paged, all.map(\.uri))
    }

    func testSavedItemsPageClampsLimit() async throws {
        let (library, _) = library()
        for index in 0..<3 {
            _ = try await library.upsertSavedItem(
                subjectURI: "at://did:plc:author/app.bsky.feed.post/clamp\(index)"
            )
        }

        let zeroLimit = try await library.savedItems(limit: 0)
        XCTAssertEqual(zeroLimit.records.count, 1)

        let hugeLimit = try await library.savedItems(limit: 500)
        XCTAssertEqual(hugeLimit.records.count, 3)
        XCTAssertNil(hugeLimit.cursor)
    }

    func testExternalSaveDisplayTitlePrefersTitleThenSiteThenURL() {
        let bare = ExternalSave(
            url: "https://fallback.example",
            normalizedUrl: "https://fallback.example",
            fingerprint: "abc",
            createdAt: "2026-01-01T00:00:00Z"
        )
        XCTAssertEqual(bare.displayTitle, "https://fallback.example")

        let withSite = ExternalSave(
            url: "https://x.com",
            normalizedUrl: "https://x.com",
            fingerprint: "abc",
            createdAt: "2026-01-01T00:00:00Z",
            site: "Example Org"
        )
        XCTAssertEqual(withSite.displayTitle, "Example Org")

        let withTitle = ExternalSave(
            url: "https://x.com",
            normalizedUrl: "https://x.com",
            fingerprint: "abc",
            createdAt: "2026-01-01T00:00:00Z",
            title: "Headline",
            site: "Example Org"
        )
        XCTAssertEqual(withTitle.displayTitle, "Headline")
    }
}
