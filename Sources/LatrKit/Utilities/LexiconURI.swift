import Foundation

public enum LexiconURI {
    public static func isExternalWrapper(_ uri: String) -> Bool {
        uri.contains("/\(LexiconCollection.external.rawValue)/")
            || uri.contains("/\(LexiconCollection.legacyExternal.rawValue)/")
    }

    public static func remapLegacySubject(_ uri: String, repositoryDID: String) -> String {
        let legacyPrefix = "at://\(repositoryDID)/\(LexiconCollection.legacyExternal.rawValue)/"
        guard uri.hasPrefix(legacyPrefix) else { return uri }
        let recordKey = String(uri.dropFirst(legacyPrefix.count))
        return ATURI.externalSave(repositoryDID: repositoryDID, recordKey: recordKey)
    }

    public static func recordKey(from uri: String) -> String? {
        guard uri.hasPrefix("at://") else { return nil }
        guard let last = uri.split(separator: "/").last else { return nil }
        let key = String(last)
        return key.isEmpty ? nil : key
    }
}
