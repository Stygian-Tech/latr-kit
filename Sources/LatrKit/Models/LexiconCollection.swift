import Foundation

/// ATProto collection identifiers for L@tr lexicons.
public enum LexiconCollection: String, Sendable {
    case bookmark = "community.lexicon.bookmarks.bookmark"
    case bookmarkMetadata = "link.latr.bookmarks.metadata"
    case external = "link.latr.saved.external"
    case savedItem = "link.latr.saved.item"
    case legacyExternal = "com.latr.saved.external"
    case legacySavedItem = "com.latr.saved.item"

    public var identifier: String { rawValue }

    public var isCurrent: Bool {
        switch self {
        case .bookmark, .bookmarkMetadata: true
        case .external, .savedItem: false
        case .legacyExternal, .legacySavedItem: false
        }
    }
}
