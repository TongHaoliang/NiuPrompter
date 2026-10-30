import Foundation

public struct TranscriptAccumulator {
    private struct Block: Equatable {
        var start: TimeInterval
        var end: TimeInterval
        var text: String
    }

    private let maxDisplayCharacters = 2_000
    private let maxMatchingCharacters = 80
    private var activeSessionID: UUID?
    private var latestRevision: UInt64 = 0
    private var finalBlocks: [Block] = []
    private var volatileBlocks: [Block] = []

    public init() {}

    public mutating func reset(sessionID: UUID) {
        activeSessionID = sessionID
        latestRevision = 0
        finalBlocks.removeAll(keepingCapacity: false)
        volatileBlocks.removeAll(keepingCapacity: false)
    }

    public mutating func ingest(_ event: RecognitionEvent) -> TranscriptSnapshot? {
        guard event.sessionID == activeSessionID,
              event.revision > latestRevision,
              event.audioStart.isFinite,
              event.audioEnd.isFinite,
              event.audioStart >= 0,
              event.audioEnd > event.audioStart
        else { return nil }

        latestRevision = event.revision
        let normalized = TextNormalizer.normalize(event.text, recognition: true)
        let text = String(event.text.suffix(maxDisplayCharacters))
        let incoming = Block(start: event.audioStart, end: event.audioEnd, text: text)

        switch event.stability {
        case .final:
            if finalBlocks.contains(where: { Self.sameRange($0, incoming) && $0.text == incoming.text }) {
                return nil
            }
            finalBlocks.removeAll { Self.overlaps($0, incoming) }
            volatileBlocks.removeAll { Self.overlaps($0, incoming) }
            if !normalized.isEmpty { finalBlocks.append(incoming) }

        case .volatile:
            guard !finalBlocks.contains(where: { Self.overlaps($0, incoming) }) else { return nil }
            let isDuplicate = volatileBlocks.contains { Self.sameRange($0, incoming) && $0.text == incoming.text }
            if isDuplicate { return nil }
            volatileBlocks.removeAll { Self.overlaps($0, incoming) }
            if !normalized.isEmpty { volatileBlocks.append(incoming) }
        }

        sortBlocks()
        pruneDisplayHistory()
        return makeSnapshot(event: event)
    }

    private mutating func sortBlocks() {
        finalBlocks.sort(by: Self.blockOrder)
        volatileBlocks.sort(by: Self.blockOrder)
    }

    private func makeSnapshot(event: RecognitionEvent) -> TranscriptSnapshot {
        let final = capped(join(finalBlocks.map(\.text)))
        let volatile = capped(join(volatileBlocks.map(\.text)))
        let all = (finalBlocks + volatileBlocks).sorted(by: Self.blockOrder)
        let normalized = TextNormalizer.normalize(join(all.map(\.text)), recognition: true)
        let recent = String(normalized.suffix(maxMatchingCharacters))
        return TranscriptSnapshot(
            finalText: final,
            volatileText: volatile,
            recentText: recent,
            evidenceRevision: event.revision,
            latestText: event.text,
            latestAudioEnd: event.audioEnd
        )
    }

    private mutating func pruneDisplayHistory() {
        while finalBlocks.reduce(0, { $0 + $1.text.count }) > maxDisplayCharacters,
              finalBlocks.count > 1 {
            finalBlocks.removeFirst()
        }
        while finalBlocks.reduce(0, { $0 + $1.text.count }) + volatileBlocks.reduce(0, { $0 + $1.text.count }) > maxDisplayCharacters,
              finalBlocks.count + volatileBlocks.count > 1 {
            if let oldestFinal = finalBlocks.first, let oldestVolatile = volatileBlocks.first {
                if oldestFinal.start <= oldestVolatile.start { finalBlocks.removeFirst() }
                else { volatileBlocks.removeFirst() }
            } else if !finalBlocks.isEmpty {
                finalBlocks.removeFirst()
            } else {
                volatileBlocks.removeFirst()
            }
        }
    }

    private func capped(_ text: String) -> String {
        String(text.suffix(maxDisplayCharacters))
    }

    private func join(_ texts: [String]) -> String {
        texts.filter { !$0.isEmpty }.joined(separator: " ")
    }

    private static func blockOrder(_ lhs: Block, _ rhs: Block) -> Bool {
        lhs.start == rhs.start ? lhs.end < rhs.end : lhs.start < rhs.start
    }

    private static func sameRange(_ lhs: Block, _ rhs: Block) -> Bool {
        lhs.start == rhs.start && lhs.end == rhs.end
    }

    private static func overlaps(_ lhs: Block, _ rhs: Block) -> Bool {
        if sameRange(lhs, rhs) { return true }
        return lhs.start < rhs.end && rhs.start < lhs.end
    }
}
