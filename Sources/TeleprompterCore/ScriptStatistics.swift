import Foundation

/// A transparent estimate for Chinese scripts, not a measurement of actual delivery.
public struct ScriptStatistics: Sendable, Equatable {
    public static let charactersPerMinute = 250
    public let characterCount: Int
    public let estimatedSeconds: Int

    public init(text: String) {
        // Count written letters/digits, excluding punctuation, whitespace and emoji.
        // Do not use recognition normalization: scripted fillers must still count.
        characterCount = text.filter { character in
            character.unicodeScalars.contains { CharacterSet.alphanumerics.contains($0) }
        }.count
        estimatedSeconds = Int(ceil(Double(characterCount) * 60 / Double(Self.charactersPerMinute)))
    }

    public var durationLabel: String {
        if estimatedSeconds == 0 { return "0 秒" }
        let minutes = estimatedSeconds / 60
        let seconds = estimatedSeconds % 60
        if minutes == 0 { return "\(seconds) 秒" }
        if seconds == 0 { return "\(minutes) 分钟" }
        return "\(minutes) 分 \(seconds) 秒"
    }
}
