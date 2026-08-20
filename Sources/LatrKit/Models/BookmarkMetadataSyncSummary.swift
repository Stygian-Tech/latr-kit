public struct BookmarkMetadataSyncSummary: Codable, Sendable, Equatable {
    public var ok = true
    public var scanned: Int
    public var created = 0
    public var reused = 0
    public var skippedConflict = 0
    public var cursor: String?

    public init(scanned: Int = 0, cursor: String? = nil) {
        self.scanned = scanned
        self.cursor = cursor
    }
}
