import Foundation

public enum BookmarkTagValidationError: Error, Sendable, Equatable {
    case emptyTag
    case tooManyTags(maximum: Int)
    case exceedsGraphemeLimit(maximum: Int)
    case exceedsUTF8Limit(maximum: Int)
    case identicalRename
}

public enum BookmarkTags {
    public static let maximumCount = 100
    public static let maximumGraphemes = 64
    public static let maximumUTF8Bytes = 640

    public static func normalized(_ rawTag: String) throws -> String {
        let tag = rawTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tag.isEmpty else { throw BookmarkTagValidationError.emptyTag }
        guard tag.count <= maximumGraphemes else {
            throw BookmarkTagValidationError.exceedsGraphemeLimit(maximum: maximumGraphemes)
        }
        guard tag.utf8.count <= maximumUTF8Bytes else {
            throw BookmarkTagValidationError.exceedsUTF8Limit(maximum: maximumUTF8Bytes)
        }
        return tag
    }

    public static func normalized(_ rawTags: [String]) throws -> [String] {
        guard rawTags.count <= maximumCount else {
            throw BookmarkTagValidationError.tooManyTags(maximum: maximumCount)
        }
        var seen: Set<String> = []
        var tags: [String] = []
        tags.reserveCapacity(min(rawTags.count, maximumCount))

        for rawTag in rawTags {
            let tag = try normalized(rawTag)
            if seen.insert(tag).inserted {
                tags.append(tag)
            }
        }

        return tags
    }

    public static func merging(_ existingTags: [String], with addedTags: [String]) throws -> [String] {
        let existing = try normalized(existingTags)
        let added = try normalized(addedTags)
        var seen = Set(existing)
        var merged = existing
        for tag in added where seen.insert(tag).inserted {
            merged.append(tag)
        }
        guard merged.count <= maximumCount else {
            throw BookmarkTagValidationError.tooManyTags(maximum: maximumCount)
        }
        return merged
    }

    public static func normalizedRename(source rawSource: String, target rawTarget: String) throws -> (source: String, target: String) {
        let source = try normalized(rawSource)
        let target = try normalized(rawTarget)
        guard source != target else { throw BookmarkTagValidationError.identicalRename }
        return (source, target)
    }
}

public struct BookmarkTagCount: Codable, Sendable, Equatable {
    public let tag: String
    public let count: Int

    public init(tag: String, count: Int) {
        self.tag = tag
        self.count = count
    }
}

public struct BookmarkTagList: Codable, Sendable, Equatable {
    public let tagCounts: [BookmarkTagCount]
    public let scanned: Int
    public let cursor: String?

    public init(tagCounts: [BookmarkTagCount], scanned: Int, cursor: String?) {
        self.tagCounts = tagCounts
        self.scanned = scanned
        self.cursor = cursor
    }
}

public struct BookmarkTagMutationSummary: Codable, Sendable, Equatable {
    public let ok: Bool
    public let scanned: Int
    public let matched: Int
    public let updated: Int
    public let cursor: String?

    public init(
        ok: Bool = true,
        scanned: Int,
        matched: Int,
        updated: Int,
        cursor: String?
    ) {
        self.ok = ok
        self.scanned = scanned
        self.matched = matched
        self.updated = updated
        self.cursor = cursor
    }
}
