public struct BookmarkView: Codable, Sendable {
    public let uri: String
    public let cid: String
    public let value: CommunityBookmark
    public let metadataRecord: RepositoryRecord<BookmarkMetadata>?

    public init(record: RepositoryRecord<CommunityBookmark>, metadataRecord: RepositoryRecord<BookmarkMetadata>? = nil) {
        uri = record.uri; cid = record.cid; value = record.value; self.metadataRecord = metadataRecord
    }
}

public struct BookmarkList: Codable, Sendable {
    public let records: [BookmarkView]
    public let cursor: String?

    public init(records: [BookmarkView], cursor: String?) {
        self.records = records; self.cursor = cursor
    }
}
