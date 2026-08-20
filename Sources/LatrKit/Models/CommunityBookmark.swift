import Foundation

public struct CommunityBookmark: Codable, Sendable, Equatable {
    public var type: String
    public var subject: String
    public var createdAt: String
    public var tags: [String]?
    public var unknownFields: [String: JSONValue]

    enum CodingKeys: String, CodingKey, CaseIterable { case type = "$type", subject, createdAt, tags }

    public init(subject: String, createdAt: String, tags: [String]? = nil, unknownFields: [String: JSONValue] = [:]) {
        self.type = LexiconCollection.bookmark.identifier
        self.subject = subject
        self.createdAt = createdAt
        self.tags = tags
        self.unknownFields = unknownFields
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decode(String.self, forKey: .type)
        subject = try c.decode(String.self, forKey: .subject)
        createdAt = try c.decode(String.self, forKey: .createdAt)
        tags = try c.decodeIfPresent([String].self, forKey: .tags)
        let dynamic = try decoder.container(keyedBy: AnyCodingKey.self)
        let known = Set(CodingKeys.allCases.map(\.rawValue))
        unknownFields = try dynamic.allKeys.reduce(into: [:]) { result, key in
            if !known.contains(key.stringValue) { result[key.stringValue] = try dynamic.decode(JSONValue.self, forKey: key) }
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(type, forKey: .type)
        try c.encode(subject, forKey: .subject)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(tags, forKey: .tags)
        var dynamic = encoder.container(keyedBy: AnyCodingKey.self)
        for (key, value) in unknownFields { try dynamic.encode(value, forKey: AnyCodingKey(stringValue: key)!) }
    }
}
