import Foundation

public enum ScriptSegmenter {
    private static let sentenceEndings: Set<Character> = ["。", "！", "？", "；"]
    private static let commaEndings: Set<Character> = ["，", "、", "："]
    private static let maxVisibleCharacters = 42
    private static let minNormalizedCharacters = 5

    public static func segment(_ text: String) -> [ScriptSegment] {
        let sentenceChunks = splitSentences(text)
        let pieces = sentenceChunks.flatMap(splitLongSentence)
            .map(trimmed)
            .filter { !TextNormalizer.normalize($0, recognition: false).isEmpty }

        let merged = mergeShortChunks(pieces)
        return merged.enumerated().map { ScriptSegment(id: $0.offset, originalText: $0.element) }
    }

    private static func splitSentences(_ text: String) -> [String] {
        var chunks: [String] = []
        var current = ""
        let characters = Array(text)

        for (index, character) in characters.enumerated() {
            if character.isNewline {
                appendIfUseful(current, to: &chunks)
                current = ""
                continue
            }

            current.append(character)
            if sentenceEndings.contains(character) {
                let next = characters.dropFirst(index + 1).first
                if next.map({ !sentenceEndings.contains($0) }) ?? true {
                    appendIfUseful(current, to: &chunks)
                    current = ""
                }
            }
        }
        appendIfUseful(current, to: &chunks)
        return chunks
    }

    private static func splitLongSentence(_ sentence: String) -> [String] {
        guard visibleCount(sentence) > maxVisibleCharacters else { return [sentence] }

        var pieces: [String] = []
        var current = ""
        let characters = Array(sentence)
        for (index, character) in characters.enumerated() {
            current.append(character)
            if commaEndings.contains(character) {
                let next = characters.dropFirst(index + 1).first
                if next.map({ !commaEndings.contains($0) }) ?? true,
                   visibleCount(sentence) > maxVisibleCharacters {
                    pieces.append(current)
                    current = ""
                }
            }
        }
        appendIfUseful(current, to: &pieces)
        return pieces.isEmpty ? [sentence] : pieces
    }

    private static func mergeShortChunks(_ chunks: [String]) -> [String] {
        var merged: [String] = []
        for chunk in chunks {
            if TextNormalizer.normalize(chunk, recognition: false).count >= minNormalizedCharacters {
                merged.append(chunk)
            } else if !merged.isEmpty {
                merged[merged.count - 1] += chunk
            } else {
                merged.append(chunk)
            }
        }

        guard merged.count > 1,
              TextNormalizer.normalize(merged[0], recognition: false).count < minNormalizedCharacters
        else { return merged }

        merged[1] = merged[0] + merged[1]
        merged.removeFirst()
        return merged
    }

    private static func visibleCount(_ text: String) -> Int {
        text.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) }.count
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func appendIfUseful(_ chunk: String, to chunks: inout [String]) {
        let candidate = trimmed(chunk)
        guard !candidate.isEmpty else { return }
        chunks.append(candidate)
    }
}

private extension Character {
    var isNewline: Bool {
        unicodeScalars.contains { CharacterSet.newlines.contains($0) }
    }
}
