import Foundation

enum Timestamp {
    static func iso8601Now() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}
