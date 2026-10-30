import Foundation

public enum TextNormalizer {
    private static let fillerWords = ["就是说", "那个", "啊", "呃", "嗯"]
    private static let tradToSimp = StringTransform("Traditional-Simplified")

    public static func normalize(_ text: String, recognition: Bool) -> String {
        var value = text.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? text
        value = value.applyingTransform(tradToSimp, reverse: false) ?? value
        value = value.lowercased(with: Locale(identifier: "en_US_POSIX"))

        let alphanumeric = value.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
        value = String(String.UnicodeScalarView(alphanumeric))

        if recognition {
            for filler in fillerWords {
                value = value.replacingOccurrences(of: filler, with: "")
            }
        }
        return value
    }

    public static func phonetic(_ text: String) -> String {
        var value = text.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? text
        value = value.lowercased(with: Locale(identifier: "en_US_POSIX"))
        value = value.applyingTransform(.toLatin, reverse: false) ?? value
        value = value.applyingTransform(.stripDiacritics, reverse: false) ?? value
        let alphanumeric = value.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
        return String(String.UnicodeScalarView(alphanumeric))
    }
}
