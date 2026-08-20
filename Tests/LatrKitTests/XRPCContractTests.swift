import Foundation
import Testing
@testable import LatrKit

@Test func xrpcDescriptorsHaveStableVerbsAndCredentialPolicy() {
    #expect(LatrXRPCMethod.all.count == 28)
    #expect(LatrXRPCMethod.listBookmarks.verb == "GET")
    #expect(LatrXRPCMethod.listTags.nsid == "link.latr.bookmarks.listTags")
    #expect(LatrXRPCMethod.listTags.verb == "GET")
    #expect(LatrXRPCMethod.saveBookmark.nsid == "link.latr.bookmarks.saveBookmark")
    #expect(LatrXRPCMethod.syncBookmarkMetadata.nsid == "link.latr.bookmarks.syncMetadata")
    #expect(LatrXRPCMethod.syncBookmarkMetadata.verb == "POST")
    #expect(LatrXRPCMethod.setBookmarkTags.nsid == "link.latr.bookmarks.setTags")
    #expect(LatrXRPCMethod.renameBookmarkTag.nsid == "link.latr.bookmarks.renameTag")
    #expect(LatrXRPCMethod.deleteBookmarkTag.nsid == "link.latr.bookmarks.deleteTag")
    #expect(LatrXRPCMethod.listItems.verb == "GET")
    #expect(LatrXRPCMethod.saveURL.verb == "POST")
    #expect(!LatrXRPCMethod.listClients.requiresApplicationCredential)
}

@Test func tagXRPCClientNormalizesAndEncodesPublicContracts() async throws {
    let bookmarkJSON = #"{"uri":"at://did:plc:test/community.lexicon.bookmarks.bookmark/3abc","cid":"bafybookmark","value":{"$type":"community.lexicon.bookmarks.bookmark","subject":"https://example.com/story","createdAt":"2026-08-13T00:00:00Z","tags":["Swift"]}}"#
    let mutationJSON = #"{"ok":true,"scanned":25,"matched":2,"updated":2,"cursor":"m:next"}"#
    let transport = RecordingXRPCTransport(responses: [
        LatrXRPCMethod.listBookmarks.nsid: Data(#"{"bookmarks":[],"cursor":"next"}"#.utf8),
        LatrXRPCMethod.listTags.nsid: Data(#"{"tagCounts":[{"tag":"Swift","count":2}],"scanned":2}"#.utf8),
        LatrXRPCMethod.setBookmarkTags.nsid: Data(bookmarkJSON.utf8),
        LatrXRPCMethod.renameBookmarkTag.nsid: Data(mutationJSON.utf8),
        LatrXRPCMethod.deleteBookmarkTag.nsid: Data(mutationJSON.utf8),
    ])
    let client = LatrXRPCClient(transport: transport)
    let bookmarkURI = "at://did:plc:test/community.lexicon.bookmarks.bookmark/3abc"

    _ = try await client.listBookmarks(.init(limit: 50, cursor: "page", tag: " Design Systems "))
    let tags = try await client.listTags(.init(limit: 25, cursor: "tags-page"))
    _ = try await client.setBookmarkTags(.init(bookmarkUri: bookmarkURI, tags: [" Swift ", "Swift", "swift"]))
    _ = try await client.renameBookmarkTag(.init(tag: " Swift ", replacement: "Language", limit: 25, cursor: "m:25"))
    _ = try await client.deleteBookmarkTag(.init(tag: " Language ", limit: 25, cursor: "v:"))

    let calls = await transport.recordedCalls()
    #expect(calls.count == 5)
    #expect(calls[0].method == .listBookmarks)
    #expect(calls[0].parameters == [
        URLQueryItem(name: "limit", value: "50"),
        URLQueryItem(name: "cursor", value: "page"),
        URLQueryItem(name: "tag", value: "Design Systems"),
    ])
    #expect(calls[1].method == .listTags)
    #expect(calls[1].parameters == [
        URLQueryItem(name: "limit", value: "25"),
        URLQueryItem(name: "cursor", value: "tags-page"),
    ])
    #expect(tags.tagCounts == [BookmarkTagCount(tag: "Swift", count: 2)])
    #expect(tags.scanned == 2)

    let setBody = try #require(calls[2].body)
    let setInput = try JSONDecoder().decode(LatrSetBookmarkTagsInput.self, from: setBody)
    #expect(setInput.tags == ["Swift", "swift"])
    let renameBody = try #require(calls[3].body)
    let renameInput = try JSONDecoder().decode(LatrRenameBookmarkTagInput.self, from: renameBody)
    #expect(renameInput == .init(tag: "Swift", replacement: "Language", limit: 25, cursor: "m:25"))
    let deleteBody = try #require(calls[4].body)
    let deleteInput = try JSONDecoder().decode(LatrDeleteBookmarkTagInput.self, from: deleteBody)
    #expect(deleteInput == .init(tag: "Language", limit: 25, cursor: "v:"))
}

@Test func tagMutationResultEncodesOnlyCanonicalProgressFields() throws {
    let result = BookmarkTagMutationSummary(
        scanned: 25,
        matched: 2,
        updated: 2,
        cursor: "v:next"
    )

    let object = try #require(
        JSONSerialization.jsonObject(with: JSONEncoder().encode(result)) as? [String: Any]
    )
    #expect(Set(object.keys) == ["ok", "scanned", "matched", "updated", "cursor"])
}

@Test func tagXRPCClientEnforcesCanonicalOperationLimits() async throws {
    let transport = RecordingXRPCTransport(responses: [:])
    let client = LatrXRPCClient(transport: transport)

    await #expect(throws: LatrPayloadValidationError.invalidLimit) {
        _ = try await client.listTags(.init(limit: 101))
    }
    await #expect(throws: LatrPayloadValidationError.invalidLimit) {
        _ = try await client.renameBookmarkTag(.init(tag: "source", replacement: "target", limit: 26))
    }
    await #expect(throws: LatrPayloadValidationError.invalidLimit) {
        _ = try await client.deleteBookmarkTag(.init(tag: "source", limit: 0))
    }
}

@Test func communityBookmarkAndMetadataPreserveUnknownFields() throws {
    let bookmarkData = Data(#"{"$type":"community.lexicon.bookmarks.bookmark","subject":"https://example.com","createdAt":"2026-08-13T00:00:00Z","future":true}"#.utf8)
    let metadataData = Data(#"{"$type":"link.latr.bookmarks.metadata","bookmarkUri":"at://did:plc:test/community.lexicon.bookmarks.bookmark/3abc","subject":"https://example.com","state":"unread","future":{"version":2}}"#.utf8)
    let bookmark = try JSONDecoder().decode(CommunityBookmark.self, from: bookmarkData)
    var metadata = try JSONDecoder().decode(BookmarkMetadata.self, from: metadataData)
    metadata.state = .archived
    let bookmarkObject = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(bookmark)) as? [String: Any])
    let metadataObject = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(metadata)) as? [String: Any])
    #expect(bookmarkObject["future"] as? Bool == true)
    #expect((metadataObject["future"] as? [String: Int])?["version"] == 2)
}

@Test func recordsPreserveUnknownFieldsAcrossMutationRoundTrip() throws {
    let data = Data(#"{"$type":"link.latr.saved.item","subjectUri":"at://did:plc:test/app.bsky.feed.post/abc","savedAt":"2026-08-13T00:00:00Z","future":{"enabled":true}}"#.utf8)
    var item = try JSONDecoder().decode(SavedItem.self, from: data)
    item.state = .archived
    let encoded = try JSONEncoder().encode(item)
    let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    #expect((object["future"] as? [String: Bool])?["enabled"] == true)
}

@Test func bookmarkViewDecodesServiceDerivedPreview() throws {
    let data = Data(#"{"uri":"at://did:plc:test/community.lexicon.bookmarks.bookmark/3abc","cid":"bafybookmark","value":{"$type":"community.lexicon.bookmarks.bookmark","subject":"https://example.com/story","createdAt":"2026-08-13T00:00:00Z"},"preview":{"title":"A story","description":"Summary","image":"https://example.com/og.png","siteName":"Example","author":"Ada"}}"#.utf8)

    let view = try JSONDecoder().decode(BookmarkView.self, from: data)

    #expect(view.preview?.title == "A story")
    #expect(view.preview?.description == "Summary")
    #expect(view.preview?.image == "https://example.com/og.png")
    #expect(view.preview?.siteName == "Example")
    #expect(view.preview?.author == "Ada")
}

@Test func validationCountsUTF8Bytes() {
    let oversized = String(repeating: "😀", count: 2_049)
    #expect(throws: LatrPayloadValidationError.exceedsUTF8Limit(field: "url", maximum: 8192)) {
        try LatrPayloadValidator.validateURL(oversized)
    }
}

private actor RecordingXRPCTransport: LatrXRPCTransport {
    struct Call: Sendable {
        let method: LatrXRPCMethod
        let parameters: [URLQueryItem]
        let body: Data?
    }

    private let responses: [String: Data]
    private var calls: [Call] = []

    init(responses: [String: Data]) {
        self.responses = responses
    }

    func send(method: LatrXRPCMethod, parameters: [URLQueryItem], body: Data?) async throws -> Data {
        calls.append(Call(method: method, parameters: parameters, body: body))
        return responses[method.nsid] ?? Data()
    }

    func recordedCalls() -> [Call] {
        calls
    }
}
