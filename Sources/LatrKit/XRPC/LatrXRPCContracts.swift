import Foundation

public struct LatrXRPCErrorBody: Codable, Sendable, Equatable { public let error: String; public let message: String }
public struct LatrListItemsParameters: Codable, Sendable, Equatable { public let limit: Int; public let cursor: String?; public init(limit: Int, cursor: String? = nil) { self.limit = limit; self.cursor = cursor } }
public struct LatrListItemsOutput: Codable, Sendable { public let records: [RepositoryRecord<SavedItem>]; public let cursor: String? }
public struct LatrSaveURLInput: Codable, Sendable, Equatable { public let url: String; public init(url: String) { self.url = url } }
public struct LatrSaveSubjectInput: Codable, Sendable, Equatable { public let subjectUri: String; public let linkedWebUrl: String?; public init(subjectUri: String, linkedWebUrl: String? = nil) { self.subjectUri = subjectUri; self.linkedWebUrl = linkedWebUrl } }
public struct LatrSetStateInput: Codable, Sendable, Equatable { public let itemRkey: String; public let state: SavedItemState; public init(itemRkey: String, state: SavedItemState) { self.itemRkey = itemRkey; self.state = state } }
public struct LatrDeleteItemInput: Codable, Sendable, Equatable { public let itemRkey: String; public init(itemRkey: String) { self.itemRkey = itemRkey } }
public struct LatrSimpleOK: Codable, Sendable, Equatable { public let ok: Bool; public init(ok: Bool) { self.ok = ok } }
public struct LatrSaveResult: Codable, Sendable, Equatable { public let ok: Bool; public let kind: String; public let subjectUri: String?; public let linkedWebUrl: String?; public let storage: String? }
public struct LatrListBookmarksParameters: Codable, Sendable, Equatable { public let limit: Int?; public let cursor: String?; public init(limit: Int? = nil, cursor: String? = nil) { self.limit = limit; self.cursor = cursor } }
public struct LatrListBookmarksOutput: Codable, Sendable { public let bookmarks: [BookmarkView]; public let cursor: String?; public init(bookmarks: [BookmarkView], cursor: String?) { self.bookmarks = bookmarks; self.cursor = cursor } }
public struct LatrGetBookmarkOutput: Codable, Sendable { public let bookmark: BookmarkView?; public init(bookmark: BookmarkView?) { self.bookmark = bookmark } }
public struct LatrSaveBookmarkInput: Codable, Sendable, Equatable { public let subject: String; public let tags: [String]?; public init(subject: String, tags: [String]? = nil) { self.subject = subject; self.tags = tags } }
public struct LatrSyncBookmarkMetadataInput: Codable, Sendable, Equatable { public let limit: Int?; public let cursor: String?; public init(limit: Int? = nil, cursor: String? = nil) { self.limit = limit; self.cursor = cursor } }
public struct LatrSetBookmarkStateInput: Codable, Sendable, Equatable { public let bookmarkUri: String; public let state: SavedItemState; public init(bookmarkUri: String, state: SavedItemState) { self.bookmarkUri = bookmarkUri; self.state = state } }
public struct LatrDeleteBookmarkInput: Codable, Sendable, Equatable { public let bookmarkUri: String; public init(bookmarkUri: String) { self.bookmarkUri = bookmarkUri } }
public struct LatrMigrateBookmarksInput: Codable, Sendable, Equatable { public let limit: Int?; public let cursor: String?; public init(limit: Int? = nil, cursor: String? = nil) { self.limit = limit; self.cursor = cursor } }
public struct LatrBookmarkMigrationResult: Codable, Sendable, Equatable {
    public let ok: Bool; public let scanned: Int; public let created: Int; public let reused: Int; public let duplicates: Int
    public let skippedConflict: Int; public let cached: Int; public let retired: Int; public let cursor: String?
}

public enum LatrPayloadValidationError: Error, Sendable, Equatable { case invalidLimit; case invalidURL; case invalidATURI; case emptyRecordKey; case exceedsUTF8Limit(field: String, maximum: Int) }
public enum LatrPayloadValidator {
    public static func validate(_ value: LatrListItemsParameters) throws { guard (1 ... 100).contains(value.limit) else { throw LatrPayloadValidationError.invalidLimit } }
    public static func validateURL(_ value: String, field: String = "url") throws {
        guard value.utf8.count <= 8192 else { throw LatrPayloadValidationError.exceedsUTF8Limit(field: field, maximum: 8192) }
        guard let url = URL(string: value), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { throw LatrPayloadValidationError.invalidURL }
    }
    public static func validateATURI(_ value: String) throws { guard value.utf8.count <= 8192, value.hasPrefix("at://"), value.split(separator: "/").count >= 4 else { throw LatrPayloadValidationError.invalidATURI } }
    public static func validateRecordKey(_ value: String) throws { guard !value.isEmpty else { throw LatrPayloadValidationError.emptyRecordKey } }
    public static func validateSubject(_ value: String) throws {
        guard value.utf8.count <= 8192 else { throw LatrPayloadValidationError.invalidURL }
        if value.hasPrefix("at://") { try validateATURI(value); return }
        guard let scheme = URLComponents(string: value)?.scheme?.lowercased(), ["http", "https"].contains(scheme) else { throw LatrPayloadValidationError.invalidURL }
    }
}

public struct LatrXRPCClient: Sendable {
    public let transport: any LatrXRPCTransport
    public init(transport: any LatrXRPCTransport) { self.transport = transport }
    public func listBookmarks(_ parameters: LatrListBookmarksParameters = .init()) async throws -> LatrListBookmarksOutput {
        if let limit = parameters.limit, !(1 ... 100).contains(limit) { throw LatrPayloadValidationError.invalidLimit }
        var query: [URLQueryItem] = []
        if let limit = parameters.limit { query.append(URLQueryItem(name: "limit", value: String(limit))) }
        if let cursor = parameters.cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
        return try JSONDecoder().decode(LatrListBookmarksOutput.self, from: try await transport.send(method: .listBookmarks, parameters: query, body: nil))
    }
    public func getBookmark(subject: String) async throws -> LatrGetBookmarkOutput {
        try LatrPayloadValidator.validateSubject(subject)
        return try JSONDecoder().decode(LatrGetBookmarkOutput.self, from: try await transport.send(method: .getBookmark, parameters: [URLQueryItem(name: "subject", value: subject)], body: nil))
    }
    public func saveBookmark(_ input: LatrSaveBookmarkInput) async throws -> BookmarkView {
        try LatrPayloadValidator.validateSubject(input.subject)
        return try await procedure(.saveBookmark, input, as: BookmarkView.self)
    }
    public func syncBookmarkMetadata(_ input: LatrSyncBookmarkMetadataInput = .init()) async throws -> BookmarkMetadataSyncSummary {
        if let limit = input.limit, !(1 ... 100).contains(limit) { throw LatrPayloadValidationError.invalidLimit }
        return try await procedure(.syncBookmarkMetadata, input, as: BookmarkMetadataSyncSummary.self)
    }
    public func setBookmarkState(_ input: LatrSetBookmarkStateInput) async throws -> LatrSimpleOK {
        try LatrPayloadValidator.validateATURI(input.bookmarkUri)
        return try await procedure(.setBookmarkState, input, as: LatrSimpleOK.self)
    }
    public func deleteBookmark(_ input: LatrDeleteBookmarkInput) async throws -> LatrSimpleOK {
        try LatrPayloadValidator.validateATURI(input.bookmarkUri)
        return try await procedure(.deleteBookmark, input, as: LatrSimpleOK.self)
    }
    public func migrateBookmarks(_ input: LatrMigrateBookmarksInput = .init()) async throws -> LatrBookmarkMigrationResult {
        if let limit = input.limit, !(1 ... 100).contains(limit) { throw LatrPayloadValidationError.invalidLimit }
        return try await procedure(.migrateBookmarks, input, as: LatrBookmarkMigrationResult.self)
    }
    public func listItems(_ parameters: LatrListItemsParameters) async throws -> LatrListItemsOutput {
        try LatrPayloadValidator.validate(parameters)
        var query = [URLQueryItem(name: "limit", value: String(parameters.limit))]
        if let cursor = parameters.cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
        return try JSONDecoder().decode(LatrListItemsOutput.self, from: try await transport.send(method: .listItems, parameters: query, body: nil))
    }
    public func saveURL(_ input: LatrSaveURLInput) async throws -> LatrSaveResult {
        try LatrPayloadValidator.validateURL(input.url)
        return try await procedure(.saveURL, input, as: LatrSaveResult.self)
    }
    public func setState(_ input: LatrSetStateInput) async throws -> LatrSimpleOK {
        try LatrPayloadValidator.validateRecordKey(input.itemRkey)
        return try await procedure(.setState, input, as: LatrSimpleOK.self)
    }
    private func procedure<Input: Encodable & Sendable, Output: Decodable>(_ method: LatrXRPCMethod, _ input: Input, as: Output.Type) async throws -> Output {
        let data = try JSONEncoder().encode(input)
        return try JSONDecoder().decode(Output.self, from: try await transport.send(method: method, parameters: [], body: data))
    }
}
