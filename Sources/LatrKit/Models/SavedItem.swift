import Foundation

/// A saved-item edge record (`com.latr.saved.item`).
public struct SavedItem: Codable, Sendable, Equatable {
    public var type: String
    public var subjectUri: String
    public var savedAt: String
    public var state: SavedItemState?
    public var tags: [String]?
    public var note: String?
    public var lastOpenedAt: String?
    public var linkedWebUrl: String?
    public var previewTitle: String?
    public var previewExcerpt: String?
    public var previewSite: String?
    public var previewImage: String?
    public var previewAuthor: String?
    public var unknownFields: [String: JSONValue]

    enum CodingKeys: String, CodingKey {
        case type = "$type"
        case subjectUri
        case savedAt
        case state
        case tags
        case note
        case lastOpenedAt
        case linkedWebUrl
        case previewTitle
        case previewExcerpt
        case previewSite
        case previewImage
        case previewAuthor
    }

    public init(
        subjectUri: String,
        savedAt: String,
        state: SavedItemState? = nil,
        tags: [String]? = nil,
        note: String? = nil,
        lastOpenedAt: String? = nil,
        linkedWebUrl: String? = nil,
        previewTitle: String? = nil,
        previewExcerpt: String? = nil,
        previewSite: String? = nil,
        previewImage: String? = nil,
        previewAuthor: String? = nil,
        unknownFields: [String: JSONValue] = [:]
    ) {
        self.type = LexiconCollection.savedItem.identifier
        self.subjectUri = subjectUri
        self.savedAt = savedAt
        self.state = state
        self.tags = tags
        self.note = note
        self.lastOpenedAt = lastOpenedAt
        self.linkedWebUrl = linkedWebUrl
        self.previewTitle = previewTitle
        self.previewExcerpt = previewExcerpt
        self.previewSite = previewSite
        self.previewImage = previewImage
        self.previewAuthor = previewAuthor
        self.unknownFields = unknownFields
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decode(String.self, forKey: .type)
        subjectUri = try c.decode(String.self, forKey: .subjectUri)
        savedAt = try c.decode(String.self, forKey: .savedAt)
        state = try c.decodeIfPresent(SavedItemState.self, forKey: .state)
        tags = try c.decodeIfPresent([String].self, forKey: .tags)
        note = try c.decodeIfPresent(String.self, forKey: .note)
        lastOpenedAt = try c.decodeIfPresent(String.self, forKey: .lastOpenedAt)
        linkedWebUrl = try c.decodeIfPresent(String.self, forKey: .linkedWebUrl)
        previewTitle = try c.decodeIfPresent(String.self, forKey: .previewTitle)
        previewExcerpt = try c.decodeIfPresent(String.self, forKey: .previewExcerpt)
        previewSite = try c.decodeIfPresent(String.self, forKey: .previewSite)
        previewImage = try c.decodeIfPresent(String.self, forKey: .previewImage)
        previewAuthor = try c.decodeIfPresent(String.self, forKey: .previewAuthor)
        let dynamic = try decoder.container(keyedBy: AnyCodingKey.self)
        let known = Set(CodingKeys.allCases.map(\.rawValue))
        unknownFields = try dynamic.allKeys.reduce(into: [:]) { result, key in
            if !known.contains(key.stringValue) { result[key.stringValue] = try dynamic.decode(JSONValue.self, forKey: key) }
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(type, forKey: .type); try c.encode(subjectUri, forKey: .subjectUri); try c.encode(savedAt, forKey: .savedAt)
        try c.encodeIfPresent(state, forKey: .state); try c.encodeIfPresent(tags, forKey: .tags); try c.encodeIfPresent(note, forKey: .note)
        try c.encodeIfPresent(lastOpenedAt, forKey: .lastOpenedAt); try c.encodeIfPresent(linkedWebUrl, forKey: .linkedWebUrl)
        try c.encodeIfPresent(previewTitle, forKey: .previewTitle); try c.encodeIfPresent(previewExcerpt, forKey: .previewExcerpt)
        try c.encodeIfPresent(previewSite, forKey: .previewSite); try c.encodeIfPresent(previewImage, forKey: .previewImage); try c.encodeIfPresent(previewAuthor, forKey: .previewAuthor)
        var dynamic = encoder.container(keyedBy: AnyCodingKey.self)
        for (key, value) in unknownFields { try dynamic.encode(value, forKey: AnyCodingKey(stringValue: key)!) }
    }
}

extension SavedItem.CodingKeys: CaseIterable {}
