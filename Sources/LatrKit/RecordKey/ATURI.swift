import Foundation

public enum ATURI {
    public static func externalSave(repositoryDID: String, recordKey: String) -> String {
        "at://\(repositoryDID)/\(LexiconCollection.external.identifier)/\(recordKey)"
    }
}
