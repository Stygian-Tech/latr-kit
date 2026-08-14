import Foundation

public enum TID {
    private static let alphabet = Array("234567abcdefghijklmnopqrstuvwxyz")

    public static func now(clockID: UInt16 = UInt16.random(in: 0 ..< 1024)) -> String {
        let micros = UInt64(Date().timeIntervalSince1970 * 1_000_000)
        var value = (micros << 10) | UInt64(clockID & 0x03ff)
        var result = Array(repeating: Character("2"), count: 13)
        for index in stride(from: 12, through: 0, by: -1) {
            result[index] = alphabet[Int(value & 31)]
            value >>= 5
        }
        return String(result)
    }
}
