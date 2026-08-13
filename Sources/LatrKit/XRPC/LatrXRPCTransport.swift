import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public typealias LatrXRPCHeaderProvider = @Sendable (LatrXRPCMethod, String, URL) async throws -> [String: String]

public protocol LatrXRPCTransport: Sendable {
    func send(method: LatrXRPCMethod, parameters: [URLQueryItem], body: Data?) async throws -> Data
}

public enum LatrXRPCTransportError: Error, Sendable, Equatable {
    case invalidURL, invalidResponse, http(status: Int, error: String?, message: String?)
}

public struct URLSessionLatrXRPCTransport: LatrXRPCTransport, Sendable {
    public let baseURL: URL
    public let session: URLSession
    public let headerProvider: LatrXRPCHeaderProvider

    public init(baseURL: URL, session: URLSession = .shared, headerProvider: @escaping LatrXRPCHeaderProvider) {
        self.baseURL = baseURL; self.session = session; self.headerProvider = headerProvider
    }

    public func send(method: LatrXRPCMethod, parameters: [URLQueryItem] = [], body: Data? = nil) async throws -> Data {
        var components = URLComponents(url: baseURL.appending(path: "xrpc/\(method.nsid)"), resolvingAgainstBaseURL: false)
        components?.queryItems = parameters.isEmpty ? nil : parameters
        guard let url = components?.url else { throw LatrXRPCTransportError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = method.verb
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body { request.httpBody = body; request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        for (name, value) in try await headerProvider(method, method.verb, url) { request.setValue(value, forHTTPHeaderField: name) }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw LatrXRPCTransportError.invalidResponse }
        guard (200 ... 299).contains(http.statusCode) else {
            let decoded = try? JSONDecoder().decode(LatrXRPCErrorBody.self, from: data)
            throw LatrXRPCTransportError.http(status: http.statusCode, error: decoded?.error, message: decoded?.message)
        }
        return data
    }
}
