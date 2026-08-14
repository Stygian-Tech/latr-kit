import Foundation
import Testing
@testable import LatrKit

@Test func xrpcDescriptorsHaveStableVerbsAndCredentialPolicy() {
    #expect(LatrXRPCMethod.all.count == 23)
    #expect(LatrXRPCMethod.listBookmarks.verb == "GET")
    #expect(LatrXRPCMethod.saveBookmark.nsid == "link.latr.bookmarks.saveBookmark")
    #expect(LatrXRPCMethod.listItems.verb == "GET")
    #expect(LatrXRPCMethod.saveURL.verb == "POST")
    #expect(!LatrXRPCMethod.listClients.requiresApplicationCredential)
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

@Test func validationCountsUTF8Bytes() {
    let oversized = String(repeating: "😀", count: 2_049)
    #expect(throws: LatrPayloadValidationError.exceedsUTF8Limit(field: "url", maximum: 8192)) {
        try LatrPayloadValidator.validateURL(oversized)
    }
}
