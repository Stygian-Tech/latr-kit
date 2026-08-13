import Foundation

public struct LatrXRPCErrorBody: Codable, Sendable, Equatable { public let error: String; public let message: String }
public struct LatrListItemsParameters: Codable, Sendable, Equatable { public let limit: Int; public let cursor: String?; public init(limit: Int, cursor: String? = nil) { self.limit = limit; self.cursor = cursor } }
public struct LatrListItemsOutput: Codable, Sendable { public let records: [RepositoryRecord<SavedItem>]; public let cursor: String? }
public struct LatrSaveURLInput: Codable, Sendable, Equatable { public let url: String; public init(url: String) { self.url = url } }
public struct LatrSaveSubjectInput: Codable, Sendable, Equatable { public let subjectUri: String; public let linkedWebUrl: String?; public init(subjectUri: String, linkedWebUrl: String? = nil) { self.subjectUri = subjectUri; self.linkedWebUrl = linkedWebUrl } }
public struct LatrSetStateInput: Codable, Sendable, Equatable { public let itemRkey: String; public let state: SavedItemState; public init(itemRkey: String, state: SavedItemState) { self.itemRkey = itemRkey; self.state = state } }
public struct LatrDeleteItemInput: Codable, Sendable, Equatable { public let itemRkey: String; public init(itemRkey: String) { self.itemRkey = itemRkey } }
public struct LatrSimpleOK: Codable, Sendable, Equatable { public let ok: Bool }
public struct LatrSaveResult: Codable, Sendable, Equatable { public let ok: Bool; public let kind: String; public let subjectUri: String?; public let linkedWebUrl: String?; public let storage: String? }

public enum LatrPayloadValidationError: Error, Sendable, Equatable { case invalidLimit; case invalidURL; case invalidATURI; case emptyRecordKey; case exceedsUTF8Limit(field: String, maximum: Int) }
public enum LatrPayloadValidator {
    public static func validate(_ value: LatrListItemsParameters) throws { guard (1 ... 100).contains(value.limit) else { throw LatrPayloadValidationError.invalidLimit } }
    public static func validateURL(_ value: String, field: String = "url") throws {
        guard value.utf8.count <= 8192 else { throw LatrPayloadValidationError.exceedsUTF8Limit(field: field, maximum: 8192) }
        guard let url = URL(string: value), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { throw LatrPayloadValidationError.invalidURL }
    }
    public static func validateATURI(_ value: String) throws { guard value.utf8.count <= 8192, value.hasPrefix("at://"), value.split(separator: "/").count >= 5 else { throw LatrPayloadValidationError.invalidATURI } }
    public static func validateRecordKey(_ value: String) throws { guard !value.isEmpty else { throw LatrPayloadValidationError.emptyRecordKey } }
}

public struct LatrXRPCClient: Sendable {
    public let transport: any LatrXRPCTransport
    public init(transport: any LatrXRPCTransport) { self.transport = transport }
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
