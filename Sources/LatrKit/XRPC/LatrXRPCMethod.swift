import Foundation

public struct LatrXRPCMethod: Hashable, Sendable {
    public enum Kind: String, Sendable { case query, procedure }
    public let nsid: String
    public let kind: Kind
    public let requiresApplicationCredential: Bool
    public var verb: String { kind == .query ? "GET" : "POST" }

    public static let listBookmarks = Self("link.latr.bookmarks.listBookmarks", .query)
    public static let getBookmark = Self("link.latr.bookmarks.getBookmark", .query)
    public static let saveBookmark = Self("link.latr.bookmarks.saveBookmark", .procedure)
    public static let setBookmarkState = Self("link.latr.bookmarks.setState", .procedure)
    public static let deleteBookmark = Self("link.latr.bookmarks.deleteBookmark", .procedure)
    public static let migrateBookmarks = Self("link.latr.bookmarks.migrateLegacy", .procedure)

    public static let listItems = Self("link.latr.saved.listItems", .query)
    public static let getItem = Self("link.latr.saved.getItem", .query)
    public static let saveURL = Self("link.latr.saved.saveUrl", .procedure)
    public static let saveSubject = Self("link.latr.saved.saveSubject", .procedure)
    public static let setState = Self("link.latr.saved.setState", .procedure)
    public static let deleteItem = Self("link.latr.saved.deleteItem", .procedure)
    public static let migrateLegacy = Self("link.latr.saved.migrateLegacy", .procedure)
    public static let getOpenGraph = Self("link.latr.preview.getOpenGraph", .query)
    public static let resolveURL = Self("link.latr.discovery.resolveUrl", .query)
    public static let authProbe = Self("link.latr.auth.probe", .query)
    public static let listClients = Self("link.latr.developer.listClients", .query, false)
    public static let createClient = Self("link.latr.developer.createClient", .procedure, false)
    public static let deleteClient = Self("link.latr.developer.deleteClient", .procedure, false)
    public static let listKeys = Self("link.latr.developer.listKeys", .query, false)
    public static let createKey = Self("link.latr.developer.createKey", .procedure, false)
    public static let revokeKey = Self("link.latr.developer.revokeKey", .procedure, false)
    public static let getUsage = Self("link.latr.developer.getUsage", .query, false)
    public static let all: [Self] = [.listBookmarks, .getBookmark, .saveBookmark, .setBookmarkState, .deleteBookmark, .migrateBookmarks, .listItems, .getItem, .saveURL, .saveSubject, .setState, .deleteItem, .migrateLegacy, .getOpenGraph, .resolveURL, .authProbe, .listClients, .createClient, .deleteClient, .listKeys, .createKey, .revokeKey, .getUsage]

    private init(_ nsid: String, _ kind: Kind, _ requiresApplicationCredential: Bool = true) {
        self.nsid = nsid; self.kind = kind; self.requiresApplicationCredential = requiresApplicationCredential
    }
}
