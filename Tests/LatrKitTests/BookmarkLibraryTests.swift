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
        XCTAssertEqual(second.value.tags, ["news", "later"])
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

    func testTagNormalizationPreservesCaseAndInternalSpaces() throws {
        XCTAssertEqual(
            try BookmarkTags.normalized(["  Swift  ", "Swift", "swift", "Design Systems"]),
            ["Swift", "swift", "Design Systems"]
        )
        XCTAssertThrowsError(try BookmarkTags.normalized([" \n "])) { error in
            XCTAssertEqual(error as? BookmarkTagValidationError, .emptyTag)
        }
        XCTAssertThrowsError(try BookmarkTags.normalized(Array(repeating: "same", count: 101))) { error in
            XCTAssertEqual(error as? BookmarkTagValidationError, .tooManyTags(maximum: 100))
        }
        XCTAssertThrowsError(try BookmarkTags.normalized(String(repeating: "a", count: 65))) { error in
            XCTAssertEqual(error as? BookmarkTagValidationError, .exceedsGraphemeLimit(maximum: 64))
        }
        let byteHeavy = String(repeating: "👨‍👩‍👧‍👦", count: 26)
        XCTAssertLessThanOrEqual(byteHeavy.count, 64)
        XCTAssertGreaterThan(byteHeavy.utf8.count, 640)
        XCTAssertThrowsError(try BookmarkTags.normalized(byteHeavy)) { error in
            XCTAssertEqual(error as? BookmarkTagValidationError, .exceedsUTF8Limit(maximum: 640))
        }
        XCTAssertThrowsError(try BookmarkTags.normalizedRename(source: "News", target: " News ")) { error in
            XCTAssertEqual(error as? BookmarkTagValidationError, .identicalRename)
        }

        let full = (0 ..< 100).map { "tag-\($0)" }
        XCTAssertEqual(try BookmarkTags.merging(full, with: ["tag-99"]), full)
        XCTAssertThrowsError(try BookmarkTags.merging(full, with: ["tag-100"])) { error in
            XCTAssertEqual(error as? BookmarkTagValidationError, .tooManyTags(maximum: 100))
        }
    }

    func testFilteredBookmarkPageKeepsSourceCursorWhenNoRowsMatch() async throws {
        let repository = InMemoryRepository()
        let library = SavedLibrary(repository: repository, repositoryDID: did)
        for (key, tags) in [("a", ["News"]), ("b", ["news"]), ("c", ["News"])] {
            _ = try await repository.createRecord(
                in: did,
                collection: .bookmark,
                withKey: key,
                value: CommunityBookmark(
                    subject: "https://example.com/\(key)",
                    createdAt: "2026-01-01T00:00:00Z",
                    tags: tags
                )
            )
        }

        let empty = try await library.bookmarks(limit: 1, startingAfter: "1", taggedWith: "News")
        XCTAssertTrue(empty.records.isEmpty)
        XCTAssertEqual(empty.cursor, "2")

        let next = try await library.bookmarks(limit: 1, startingAfter: empty.cursor, taggedWith: " News ")
        XCTAssertEqual(next.records.map(\.value.subject), ["https://example.com/c"])
        XCTAssertNil(next.cursor)
    }

    func testBookmarkTagsReturnsExactPerPageBookmarkCounts() async throws {
        let repository = InMemoryRepository()
        let library = SavedLibrary(repository: repository, repositoryDID: did)
        let fixtures: [(String, [String]?)] = [
            ("a", ["News", "News", "Swift"]),
            ("b", ["News", "news"]),
            ("c", nil),
        ]
        for (key, tags) in fixtures {
            _ = try await repository.createRecord(
                in: did,
                collection: .bookmark,
                withKey: key,
                value: CommunityBookmark(
                    subject: "https://example.com/\(key)",
                    createdAt: "2026-01-01T00:00:00Z",
                    tags: tags
                )
            )
        }

        let first = try await library.bookmarkTags(limit: 2)
        XCTAssertEqual(first.scanned, 2)
        XCTAssertEqual(first.tagCounts, [
            BookmarkTagCount(tag: "News", count: 2),
            BookmarkTagCount(tag: "Swift", count: 1),
            BookmarkTagCount(tag: "news", count: 1),
        ])
        XCTAssertEqual(first.cursor, "2")

        let second = try await library.bookmarkTags(limit: 2, startingAfter: first.cursor)
        XCTAssertEqual(second.scanned, 1)
        XCTAssertTrue(second.tagCounts.isEmpty)
        XCTAssertNil(second.cursor)
    }

    func testBookmarkTagsClampsAndPaginatesBeyondFiftyRecords() async throws {
        let repository = InMemoryRepository()
        let library = SavedLibrary(repository: repository, repositoryDID: did)
        for index in 0 ..< 55 {
            _ = try await repository.createRecord(
                in: did,
                collection: .bookmark,
                withKey: String(format: "page-%02d", index),
                value: CommunityBookmark(
                    subject: "https://example.com/\(index)",
                    createdAt: "2026-01-01T00:00:00Z",
                    tags: ["all", index.isMultiple(of: 2) ? "even" : "odd"]
                )
            )
        }

        var cursor: String?
        var scannedPages: [Int] = []
        var totalCounts: [String: Int] = [:]
        repeat {
            let page = try await library.bookmarkTags(limit: 40, startingAfter: cursor)
            scannedPages.append(page.scanned)
            for tag in page.tagCounts { totalCounts[tag.tag, default: 0] += tag.count }
            cursor = page.cursor
        } while cursor != nil

        XCTAssertEqual(scannedPages, [40, 15])
        XCTAssertEqual(totalCounts, ["all": 55, "even": 28, "odd": 27])
    }

    func testSetTagsReplacesClearsAndPreservesUnknownFields() async throws {
        let repository = InMemoryRepository()
        let library = SavedLibrary(repository: repository, repositoryDID: did)
        let key = "tagged"
        let uri = "at://\(did)/\(LexiconCollection.bookmark.identifier)/\(key)"
        _ = try await repository.createRecord(
            in: did,
            collection: .bookmark,
            withKey: key,
            value: CommunityBookmark(
                subject: "https://example.com/tagged",
                createdAt: "2026-01-01T00:00:00Z",
                tags: ["old"],
                unknownFields: ["future": .string("preserve")]
            )
        )
        _ = try await repository.createRecord(
            in: did,
            collection: .bookmarkMetadata,
            withKey: key,
            value: BookmarkMetadata(bookmarkUri: uri, subject: "https://example.com/tagged", state: .archived)
        )

        let replaced = try await library.setTags(ofBookmarkURI: uri, to: [" Swift ", "swift", "Swift"])
        XCTAssertEqual(replaced.value.tags, ["Swift", "swift"])
        XCTAssertEqual(replaced.value.unknownFields["future"], .string("preserve"))
        XCTAssertEqual(replaced.metadataRecord?.value.state, .archived)

        let cleared = try await library.setTags(ofBookmarkURI: uri, to: [])
        XCTAssertNil(cleared.value.tags)
        XCTAssertEqual(cleared.value.unknownFields["future"], .string("preserve"))
    }

    func testSetTagsConflictIsRetryableWithoutLosingConcurrentFields() async throws {
        let repository = InMemoryRepository()
        let library = SavedLibrary(repository: repository, repositoryDID: did)
        let saved = try await library.saveBookmark(subject: "https://example.com/conflict", tags: ["old"])
        let key = try XCTUnwrap(LexiconURI.recordKey(from: saved.uri))
        let repositoryDID = did
        repository.beforeNextApplyWrites { _ in
            var concurrent = saved.value
            concurrent.unknownFields["concurrent"] = .boolean(true)
            _ = try await repository.updateRecord(
                in: repositoryDID,
                collection: .bookmark,
                withKey: key,
                value: concurrent,
                swapRecord: saved.cid
            )
        }

        do {
            _ = try await library.setTags(ofBookmarkURI: saved.uri, to: ["new"])
            XCTFail("Expected CID conflict")
        } catch SavedLibraryError.conflict {}

        let retried = try await library.setTags(ofBookmarkURI: saved.uri, to: ["new"])
        XCTAssertEqual(retried.value.tags, ["new"])
        XCTAssertEqual(retried.value.unknownFields["concurrent"], .boolean(true))
    }

    func testRenameTagUsesBoundedCIDGuardedBatchesAndVerification() async throws {
        let repository = InMemoryRepository()
        let library = SavedLibrary(repository: repository, repositoryDID: did)
        for index in 0 ..< 30 {
            _ = try await repository.createRecord(
                in: did,
                collection: .bookmark,
                withKey: String(format: "tag-%02d", index),
                value: CommunityBookmark(
                    subject: "https://example.com/\(index)",
                    createdAt: "2026-01-01T00:00:00Z",
                    tags: ["source", "target", "other"],
                    unknownFields: index == 0 ? ["future": .string("preserve")] : [:]
                )
            )
        }
        repository.resetAppliedWriteBatches()

        let first = try await library.renameTag(" source ", to: "target")
        XCTAssertEqual(first.scanned, 25)
        XCTAssertEqual(first.updated, 25)
        XCTAssertEqual(first.cursor, "m:25")

        let second = try await library.renameTag("source", to: "target", continuingFrom: first.cursor)
        XCTAssertEqual(second.scanned, 5)
        XCTAssertEqual(second.updated, 5)
        XCTAssertEqual(second.cursor, "v:")

        let verifyFirst = try await library.renameTag("source", to: "target", continuingFrom: second.cursor)
        XCTAssertEqual(verifyFirst.scanned, 25)
        XCTAssertEqual(verifyFirst.cursor, "v:25")

        let done = try await library.renameTag("source", to: "target", continuingFrom: verifyFirst.cursor)
        XCTAssertNil(done.cursor)
        XCTAssertEqual(repository.appliedWriteBatches.map(\.count), [25, 5])

        for index in 0 ..< 30 {
            let record: RepositoryRecord<CommunityBookmark>? = try await repository.record(
                in: did,
                collection: .bookmark,
                withKey: String(format: "tag-%02d", index)
            )
            XCTAssertEqual(record?.value.tags, ["target", "other"])
            if index == 0 {
                XCTAssertEqual(record?.value.unknownFields["future"], .string("preserve"))
            }
        }
    }

    func testDeleteTagVerificationRestartsWhenSourceReappears() async throws {
        let repository = InMemoryRepository()
        let library = SavedLibrary(repository: repository, repositoryDID: did)
        _ = try await repository.createRecord(
            in: did,
            collection: .bookmark,
            withKey: "a",
            value: CommunityBookmark(subject: "https://example.com/a", createdAt: "2026-01-01T00:00:00Z", tags: ["source"])
        )

        let mutation = try await library.deleteTag("source")
        XCTAssertEqual(mutation.cursor, "v:")
        let currentRecord: RepositoryRecord<CommunityBookmark>? = try await repository.record(
            in: did,
            collection: .bookmark,
            withKey: "a"
        )
        let current = try XCTUnwrap(currentRecord)
        var reintroduced = current.value
        reintroduced.tags = ["source", "other"]
        _ = try await repository.updateRecord(
            in: did,
            collection: .bookmark,
            withKey: "a",
            value: reintroduced,
            swapRecord: current.cid
        )

        let verification = try await library.deleteTag("source", continuingFrom: mutation.cursor)
        XCTAssertEqual(verification.updated, 1)
        XCTAssertEqual(verification.cursor, "v:")

        let done = try await library.deleteTag("source", continuingFrom: verification.cursor)
        XCTAssertNil(done.cursor)
        let finalRecord: RepositoryRecord<CommunityBookmark>? = try await repository.record(
            in: did,
            collection: .bookmark,
            withKey: "a"
        )
        let final = try XCTUnwrap(finalRecord)
        XCTAssertEqual(final.value.tags, ["other"])
    }

    func testTagMutationHonorsRequestedBatchLimit() async throws {
        let repository = InMemoryRepository()
        let library = SavedLibrary(repository: repository, repositoryDID: did)
        for key in ["a", "b", "c"] {
            _ = try await repository.createRecord(
                in: did,
                collection: .bookmark,
                withKey: key,
                value: CommunityBookmark(
                    subject: "https://example.com/\(key)",
                    createdAt: "2026-01-01T00:00:00Z",
                    tags: ["source"]
                )
            )
        }

        let first = try await library.deleteTag("source", limit: 2)

        XCTAssertEqual(first.scanned, 2)
        XCTAssertEqual(first.matched, 2)
        XCTAssertEqual(first.updated, 2)
        XCTAssertEqual(first.cursor, "m:2")
        XCTAssertEqual(repository.appliedWriteBatches.map(\.count), [2])
    }

    func testTagBatchConflictCommitsNoLibraryWritesAndSameCursorRetries() async throws {
        let repository = InMemoryRepository()
        let library = SavedLibrary(repository: repository, repositoryDID: did)
        for key in ["a", "b"] {
            _ = try await repository.createRecord(
                in: did,
                collection: .bookmark,
                withKey: key,
                value: CommunityBookmark(
                    subject: "https://example.com/\(key)",
                    createdAt: "2026-01-01T00:00:00Z",
                    tags: ["source"]
                )
            )
        }
        let concurrentRecord: RepositoryRecord<CommunityBookmark>? = try await repository.record(
            in: did,
            collection: .bookmark,
            withKey: "b"
        )
        let concurrent = try XCTUnwrap(concurrentRecord)
        let repositoryDID = did
        repository.resetAppliedWriteBatches()
        repository.beforeNextApplyWrites { _ in
            var value = concurrent.value
            value.unknownFields["concurrent"] = .boolean(true)
            _ = try await repository.updateRecord(
                in: repositoryDID,
                collection: .bookmark,
                withKey: "b",
                value: value,
                swapRecord: concurrent.cid
            )
        }

        do {
            _ = try await library.renameTag("source", to: "target")
            XCTFail("Expected CID conflict")
        } catch SavedLibraryError.conflict {}
        XCTAssertTrue(repository.appliedWriteBatches.isEmpty)

        let unchangedRecord: RepositoryRecord<CommunityBookmark>? = try await repository.record(
            in: did,
            collection: .bookmark,
            withKey: "a"
        )
        let unchanged = try XCTUnwrap(unchangedRecord)
        XCTAssertEqual(unchanged.value.tags, ["source"])

        let retry = try await library.renameTag("source", to: "target")
        XCTAssertEqual(retry.updated, 2)
    }

    func testTagMutationRejectsUnknownCursor() async throws {
        let repository = InMemoryRepository()
        let library = SavedLibrary(repository: repository, repositoryDID: did)

        do {
            _ = try await library.deleteTag("source", continuingFrom: "not-a-tag-cursor")
            XCTFail("Expected invalid cursor")
        } catch SavedLibraryError.invalidTagMutationCursor {}
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
