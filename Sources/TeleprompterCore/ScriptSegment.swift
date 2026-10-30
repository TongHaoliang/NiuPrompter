import Foundation

public struct ScriptSegment: Identifiable, Sendable, Equatable {
    public let id: Int
    public let originalText: String
    public let normalizedText: String
    public let phoneticText: String

    public init(id: Int, originalText: String) {
        self.id = id
        self.originalText = originalText
        self.normalizedText = TextNormalizer.normalize(originalText, recognition: false)
        self.phoneticText = TextNormalizer.phonetic(originalText)
    }
}
