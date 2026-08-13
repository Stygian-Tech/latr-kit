import Foundation

/// A per-user URL wrapper record (`com.latr.saved.external`).
public struct ExternalSave: Codable, Sendable, Equatable {
    public var type: String
    public var url: String
    public var normalizedUrl: String
    public var fingerprint: String
    public var createdAt: String
    public var title: String?
    public var excerpt: String?
    public var site: String?
    public var image: String?
    public var language: String?
    public var publishedAt: String?
    public var author: String?
    public var unknownFields: [String: JSONValue]

    enum CodingKeys: String, CodingKey {
        case type = "$type"
        case url
        case normalizedUrl
        case fingerprint
        case createdAt
        case title
        case excerpt
        case site
        case image
        case language
        case publishedAt
        case author
    }

    public init(
        url: String,
        normalizedUrl: String,
        fingerprint: String,
        createdAt: String,
        title: String? = nil,
        excerpt: String? = nil,
        site: String? = nil,
        image: String? = nil,
        language: String? = nil,
        publishedAt: String? = nil,
        author: String? = nil,
        unknownFields: [String: JSONValue] = [:]
    ) {
        self.type = LexiconCollection.external.identifier
        self.url = url
        self.normalizedUrl = normalizedUrl
        self.fingerprint = fingerprint
        self.createdAt = createdAt
        self.title = title
        self.excerpt = excerpt
        self.site = site
        self.image = image
        self.language = language
        self.publishedAt = publishedAt
        self.author = author
        self.unknownFields = unknownFields
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decode(String.self, forKey: .type); url = try c.decode(String.self, forKey: .url)
        normalizedUrl = try c.decode(String.self, forKey: .normalizedUrl); fingerprint = try c.decode(String.self, forKey: .fingerprint)
        createdAt = try c.decode(String.self, forKey: .createdAt); title = try c.decodeIfPresent(String.self, forKey: .title)
        excerpt = try c.decodeIfPresent(String.self, forKey: .excerpt); site = try c.decodeIfPresent(String.self, forKey: .site)
        image = try c.decodeIfPresent(String.self, forKey: .image); language = try c.decodeIfPresent(String.self, forKey: .language)
        publishedAt = try c.decodeIfPresent(String.self, forKey: .publishedAt); author = try c.decodeIfPresent(String.self, forKey: .author)
        let dynamic = try decoder.container(keyedBy: AnyCodingKey.self)
        let known = Set(CodingKeys.allCases.map(\.rawValue))
        unknownFields = try dynamic.allKeys.reduce(into: [:]) { result, key in
            if !known.contains(key.stringValue) { result[key.stringValue] = try dynamic.decode(JSONValue.self, forKey: key) }
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(type, forKey: .type); try c.encode(url, forKey: .url); try c.encode(normalizedUrl, forKey: .normalizedUrl)
        try c.encode(fingerprint, forKey: .fingerprint); try c.encode(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(title, forKey: .title); try c.encodeIfPresent(excerpt, forKey: .excerpt); try c.encodeIfPresent(site, forKey: .site)
        try c.encodeIfPresent(image, forKey: .image); try c.encodeIfPresent(language, forKey: .language)
        try c.encodeIfPresent(publishedAt, forKey: .publishedAt); try c.encodeIfPresent(author, forKey: .author)
        var dynamic = encoder.container(keyedBy: AnyCodingKey.self)
        for (key, value) in unknownFields { try dynamic.encode(value, forKey: AnyCodingKey(stringValue: key)!) }
    }

    /// Best available human-readable title for display.
    public var displayTitle: String {
        if let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }
        if let site = site?.trimmingCharacters(in: .whitespacesAndNewlines), !site.isEmpty {
            return site
        }
        if !normalizedUrl.isEmpty {
            return normalizedUrl
        }
        if !url.isEmpty {
            return url
        }
        return "Saved link"
    }
}

extension ExternalSave.CodingKeys: CaseIterable {}
