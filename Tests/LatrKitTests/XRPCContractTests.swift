import Foundation
import Testing
@testable import LatrKit

@Test func xrpcDescriptorsHaveStableVerbsAndCredentialPolicy() {
    #expect(LatrXRPCMethod.all.count == 17)
    #expect(LatrXRPCMethod.listItems.verb == "GET")
    #expect(LatrXRPCMethod.saveURL.verb == "POST")
    #expect(!LatrXRPCMethod.listClients.requiresApplicationCredential)
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
