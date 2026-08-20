import Foundation

public enum SavedLibraryError: Error, Sendable {
    case invalidURL
    case itemNotFound
    case conflict
    case invalidStoredRecord(uri: String)
    case bookmarkNotFound
    case invalidTagMutationCursor
}
