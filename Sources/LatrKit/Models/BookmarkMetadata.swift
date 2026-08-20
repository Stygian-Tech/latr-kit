import Foundation

public struct BookmarkMetadata: Codable, Sendable, Equatable {
    public var type: String
    public var bookmarkUri: String
    public var subject: String
    public var state: SavedItemState?
    public var note: String?
    public var lastOpenedAt: String?
    public var legacyItemUris: [String]?
    public var unknownFields: [String: JSONValue]

    enum CodingKeys: String, CodingKey, CaseIterable {
        case type = "$type", bookmarkUri, subject, state, note, lastOpenedAt, legacyItemUris
    }

    public init(bookmarkUri: String, subject: String, state: SavedItemState? = nil, note: String? = nil, lastOpenedAt: String? = nil, legacyItemUris: [String]? = nil, unknownFields: [String: JSONValue] = [:]) {
        self.type = LexiconCollection.bookmarkMetadata.identifier
        self.bookmarkUri = bookmarkUri
        self.subject = subject
        self.state = state
        self.note = note
        self.lastOpenedAt = lastOpenedAt
        self.legacyItemUris = legacyItemUris
        self.unknownFields = unknownFields
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decode(String.self, forKey: .type)
        bookmarkUri = try c.decode(String.self, forKey: .bookmarkUri)
        subject = try c.decode(String.self, forKey: .subject)
        state = try c.decodeIfPresent(SavedItemState.self, forKey: .state)
        note = try c.decodeIfPresent(String.self, forKey: .note)
        lastOpenedAt = try c.decodeIfPresent(String.self, forKey: .lastOpenedAt)
        legacyItemUris = try c.decodeIfPresent([String].self, forKey: .legacyItemUris)
        let dynamic = try decoder.container(keyedBy: AnyCodingKey.self)
        let known = Set(CodingKeys.allCases.map(\.rawValue))
        unknownFields = try dynamic.allKeys.reduce(into: [:]) { result, key in
            if !known.contains(key.stringValue) { result[key.stringValue] = try dynamic.decode(JSONValue.self, forKey: key) }
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(type, forKey: .type); try c.encode(bookmarkUri, forKey: .bookmarkUri); try c.encode(subject, forKey: .subject)
        try c.encodeIfPresent(state, forKey: .state); try c.encodeIfPresent(note, forKey: .note); try c.encodeIfPresent(lastOpenedAt, forKey: .lastOpenedAt)
        try c.encodeIfPresent(legacyItemUris, forKey: .legacyItemUris)
        var dynamic = encoder.container(keyedBy: AnyCodingKey.self)
        for (key, value) in unknownFields { try dynamic.encode(value, forKey: AnyCodingKey(stringValue: key)!) }
    }
}
