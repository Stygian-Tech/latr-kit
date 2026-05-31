import Foundation

public enum SavedLibraryError: Error, Sendable {
    case invalidURL
    case itemNotFound
}
