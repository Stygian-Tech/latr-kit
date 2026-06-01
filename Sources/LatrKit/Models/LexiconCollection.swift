import Foundation

/// ATProto collection identifiers for L@tr lexicons.
public enum LexiconCollection: String, Sendable {
    case external = "link.latr.saved.external"
    case savedItem = "link.latr.saved.item"
    case legacyExternal = "com.latr.saved.external"
    case legacySavedItem = "com.latr.saved.item"

    public var identifier: String { rawValue }

    public var isCurrent: Bool {
        switch self {
        case .external, .savedItem: true
        case .legacyExternal, .legacySavedItem: false
        }
    }
}
