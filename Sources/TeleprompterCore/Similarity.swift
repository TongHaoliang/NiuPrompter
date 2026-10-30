import Foundation

public enum Similarity {
    public static func characterBigramDice(_ lhs: String, _ rhs: String) -> Double {
        bigramDice(Array(lhs), Array(rhs))
    }

    public static func phoneticBigramDice(_ lhs: String, _ rhs: String) -> Double {
        bigramDice(Array(lhs), Array(rhs))
    }

    public static func lcsRatio(_ lhs: String, _ rhs: String) -> Double {
        let left = Array(lhs)
        let right = Array(rhs)
        guard !left.isEmpty, !right.isEmpty else { return 0 }
        let length = lcsMatches(reference: left, comparison: right).count
        return 2 * Double(length) / Double(left.count + right.count)
    }

    static func lcsMatchIndices(reference: String, comparison: String) -> [Int] {
        lcsMatches(reference: Array(reference), comparison: Array(comparison))
    }

    private static func bigramDice(_ lhs: [Character], _ rhs: [Character]) -> Double {
        guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }
        if lhs.count < 2 || rhs.count < 2 { return lhs == rhs ? 1 : 0 }

        let left = bigramCounts(lhs)
        let right = bigramCounts(rhs)
        let intersection = left.reduce(into: 0) { total, pair in
            total += min(pair.value, right[pair.key, default: 0])
        }
        let denominator = left.values.reduce(0, +) + right.values.reduce(0, +)
        return denominator == 0 ? 0 : 2 * Double(intersection) / Double(denominator)
    }

    private static func bigramCounts(_ text: [Character]) -> [String: Int] {
        guard text.count > 1 else { return [:] }
        var counts: [String: Int] = [:]
        for index in 0..<(text.count - 1) {
            counts[String(text[index...index + 1]), default: 0] += 1
        }
        return counts
    }

    private static func lcsMatches(reference: [Character], comparison: [Character]) -> [Int] {
        guard !reference.isEmpty, !comparison.isEmpty else { return [] }
        var table = Array(repeating: Array(repeating: 0, count: comparison.count + 1),
                          count: reference.count + 1)

        for left in 1...reference.count {
            for right in 1...comparison.count {
                if reference[left - 1] == comparison[right - 1] {
                    table[left][right] = table[left - 1][right - 1] + 1
                } else {
                    table[left][right] = max(table[left - 1][right], table[left][right - 1])
                }
            }
        }

        var matches: [Int] = []
        var left = reference.count
        var right = comparison.count
        while left > 0 && right > 0 {
            if reference[left - 1] == comparison[right - 1] {
                matches.append(left - 1)
                left -= 1
                right -= 1
            } else if table[left - 1][right] >= table[left][right - 1] {
                left -= 1
            } else {
                right -= 1
            }
        }
        return matches.reversed()
    }
}
