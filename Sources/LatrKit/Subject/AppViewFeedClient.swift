import Foundation

/// Gateway-injected client for enriched feed post previews (optional AppView + PDS fallback).
public protocol AppViewFeedClient: Sendable {
    func postPreview(for subjectURI: String) async -> AppViewPostPreview?
}
