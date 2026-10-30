import Foundation

public struct MatchResult: Sendable, Equatable {
    public let segmentID: Int
    public let confidence: Double
    public let reason: String

    public init(segmentID: Int, confidence: Double, reason: String) {
        self.segmentID = segmentID
        self.confidence = confidence
        self.reason = reason
    }
}

/// Tracks spoken evidence separately from the pace-aware reading prompt. Local matching is responsive;
/// backward/distant reacquisition requires distinct, sustained textual evidence.
public struct ScriptMatcher {
    private struct Candidate {
        let index: Int
        let score: Double
        let support: Int
        let precision: Double
        let coverage: Double
        let endOffset: Int
    }

    private let segments: [ScriptSegment]
    private let configuration: MatchConfiguration
    public private(set) var currentSegmentID: Int?
    public private(set) var lastCandidate: MatchResult?
    private var lastEvidenceRevision: UInt64 = 0
    private var lastQuery = ""
    private var lastLatestText = ""
    private var lastAudioEnd: TimeInterval = 0
    private var pendingTargetID: Int?
    private var pendingHitCount = 0
    private var pendingEvidence = ""
    private var boundaryReady = false
    private var anticipatedSegmentID: Int?
    private var paceSample: (id: Int, offset: Int, time: TimeInterval)?
    private var charactersPerSecond: Double?
    private var rereadSample: (offset: Int, time: TimeInterval)?
    /// UI may lead by one sentence; recognition always retains the actual spoken position.
    public var promptSegmentID: Int? { anticipatedSegmentID ?? currentSegmentID }


    public init(segments: [ScriptSegment], configuration: MatchConfiguration = MatchConfiguration()) {
        self.segments = segments
        self.configuration = configuration
        self.currentSegmentID = segments.first?.id
    }

    @discardableResult
    public mutating func consume(_ snapshot: TranscriptSnapshot) -> MatchResult? {
        guard let currentSegmentID,
              let currentIndex = segments.firstIndex(where: { $0.id == currentSegmentID }),
              snapshot.evidenceRevision > lastEvidenceRevision else { return nil }
        lastEvidenceRevision = snapshot.evidenceRevision
        // Late finalization of an earlier audio interval must not rewind the reader.
        if let end = snapshot.latestAudioEnd {
            guard end >= lastAudioEnd else { return nil }
            lastAudioEnd = end
        }
        let query = TextNormalizer.normalize(snapshot.recentText, recognition: true)
        let latest = TextNormalizer.normalize(snapshot.latestText ?? snapshot.recentText, recognition: true)
        guard query != lastQuery || latest != lastLatestText else { return nil }
        lastQuery = query
        lastLatestText = latest
        if boundaryReady, !latest.isEmpty, currentIndex + 1 < segments.count {
            let next = segments[currentIndex + 1].normalizedText
            // Only use observed words. Never predict a handoff from sentence completion.
            if next.count >= 4 {
                for length in stride(from: min(12, next.count, query.count), through: 4, by: -1) {
                    let opening = String(next.prefix(length))
                    guard query.hasSuffix(opening) else { continue }
                    let ambiguous = segments.enumerated().contains {
                        $0.offset != currentIndex + 1 && $0.element.normalizedText.contains(opening)
                    }
                    guard !ambiguous else { continue }
                    let result = MatchResult(segmentID: segments[currentIndex + 1].id, confidence: 0.95,
                                             reason: "已识别到下一句独有开头，快速跟随")
                    clearPace()
                    self.currentSegmentID = result.segmentID
                    lastCandidate = result
                    boundaryReady = false
                    resetPendingCandidate()
                    return result
                }
                // Keep the current-sentence anchor across tiny streaming audio fragments.
                if (1...3).contains(where: { query.hasSuffix(String(next.prefix($0))) }) {
                    return nil
                }
            }
        }
        guard query.count >= configuration.minimumQueryCharacters, !latest.isEmpty else {
            hold("等待更多朗读内容")
            return nil
        }

        // Use several recent suffixes: a digression must not dilute a return to the script.
        // Short ASR fragments still use accumulated final + volatile context.
        let sizes = Set([8, 12, 20, 32, 48, 80, min(latest.count, 80)])
        let tails = Set(sizes.filter { $0 >= configuration.minimumQueryCharacters }
            .map { String(query.suffix($0)) }).sorted { $0.count > $1.count }
        let anchor = String(query.suffix(6))
        var candidates: [Candidate] = []
        for (index, segment) in segments.enumerated() {
            let reference = segment.normalizedText
            guard !reference.isEmpty else { continue }
            // Recent words must actually be present here, not just earlier accumulated words.
            let anchorMatches = Similarity.lcsMatchIndices(reference: reference, comparison: anchor).count
            guard Double(anchorMatches) / Double(max(1, anchor.count)) >= 0.66 else { continue }
            let isRemote = index < currentIndex || index > currentIndex + 2
            var best: Candidate?
            for tail in tails {
                let matching = Similarity.lcsMatchIndices(reference: reference, comparison: tail)
                let support = matching.count
                let minimumSupport = isRemote ? 10 : configuration.minimumQueryCharacters
                guard support >= minimumSupport, let first = matching.first, let last = matching.last else { continue }
                let precision = Double(support) / Double(tail.count)
                guard precision >= (isRemote ? 0.8 : 0.6) else { continue }
                let span = String(Array(reference)[first...last])
                let coverage = Double(support) / Double(reference.count)
                guard coverage >= (isRemote ? 0.35 : 0.2) else { continue }
                // Align to the spoken portion of a sentence, so partial speech can highlight it.
                let lexical = Similarity.characterBigramDice(span, tail)
                let lcs = Similarity.lcsRatio(span, tail)
                let proximity = max(0, 1 - Double(abs(index - currentIndex)) / 9)
                // Avoid expensive phonetic transforms for obviously unrelated candidates.
                guard lexical >= 0.25 else { continue }
                let phonetic = Similarity.phoneticBigramDice(TextNormalizer.phonetic(span), TextNormalizer.phonetic(tail))
                let score = min(1, configuration.characterWeight * lexical
                    + configuration.lcsWeight * lcs
                    + configuration.phoneticWeight * phonetic
                    + configuration.proximityWeight * proximity)
                let candidate = Candidate(index: index, score: score, support: support,
                                          precision: precision, coverage: coverage, endOffset: last)
                if best == nil || score > best!.score + 0.001
                    || (abs(score - best!.score) <= 0.001 && support > best!.support) {
                    best = candidate
                }
            }
            if let best { candidates.append(best) }
        }
        candidates.sort {
            if abs($0.score - $1.score) > 0.001 { return $0.score > $1.score }
            return abs($0.index - currentIndex) < abs($1.index - currentIndex)
        }
        guard let best = candidates.first else {
            hold("暂未匹配到稿件，保持位置等待回稿")
            return nil
        }
        let remote = best.index < currentIndex || best.index > currentIndex + 2
        let threshold = remote ? max(configuration.mediumFloor, 0.78) : configuration.mediumFloor
        guard best.score >= threshold else {
            hold("朗读证据不足，保持当前位置")
            return nil
        }
        let ambiguityGap = remote ? max(configuration.ambiguityGap, 0.08) : configuration.ambiguityGap
        if let second = candidates.dropFirst().first, best.score - second.score < ambiguityGap {
            hold("多个位置相似，等待更多上下文")
            return nil
        }
        let targetID = segments[best.index].id
        lastCandidate = MatchResult(segmentID: targetID, confidence: best.score,
                                    reason: remote ? "正在确认回稿位置" : "正在跟随朗读")
        guard targetID != currentSegmentID else {
            boundaryReady = best.support >= 8 && best.endOffset >= segments[currentIndex].normalizedText.count - 3
            confirmReread(best, audioEnd: snapshot.latestAudioEnd)
            updatePrompt(best, audioEnd: snapshot.latestAudioEnd)
            resetPendingCandidate()
            return nil
        }
        let requiresConfirmation = remote || best.score < configuration.highConfidence
        if requiresConfirmation {
            if pendingTargetID != targetID {
                pendingTargetID = targetID
                pendingHitCount = 1
                pendingEvidence = latest
            } else if pendingEvidence != latest {
                pendingHitCount += 1
                pendingEvidence = latest
            }
            guard pendingHitCount >= configuration.confirmationCount else { return nil }
        }
        clearPace()
        self.currentSegmentID = targetID
        boundaryReady = best.support >= 8 && best.endOffset >= segments[best.index].normalizedText.count - 3
        updatePrompt(best, audioEnd: snapshot.latestAudioEnd)
        let result = MatchResult(segmentID: targetID, confidence: best.score,
                                 reason: remote ? "连续朗读证据确认，重新定位" : "跟随当前朗读")
        lastCandidate = result
        resetPendingCandidate()
        return result
    }

    public mutating func reset(to segmentID: Int) {
        guard !segments.isEmpty else {
            currentSegmentID = nil
            clearEvidenceAndCandidate()
            return
        }
        let index = segments.firstIndex(where: { $0.id == segmentID })
            ?? min(max(segmentID, 0), segments.count - 1)
        currentSegmentID = segments[index].id
        clearEvidenceAndCandidate()
    }

    public mutating func clearEvidenceAndCandidate() {
        clearPace()
        lastEvidenceRevision = 0
        lastQuery = ""
        lastLatestText = ""
        lastAudioEnd = 0
        boundaryReady = false
        lastCandidate = nil
        resetPendingCandidate()
    }

    private mutating func hold(_ reason: String) {
        resetRhythm()
        rereadSample = nil
        boundaryReady = false
        lastCandidate = currentSegmentID.map { MatchResult(segmentID: $0, confidence: 0, reason: reason) }
        resetPendingCandidate()
    }

    private mutating func clearPace() {
        anticipatedSegmentID = nil
        rereadSample = nil
        resetRhythm()
    }

    private mutating func resetRhythm() {
        paceSample = nil
        charactersPerSecond = nil
    }

    private mutating func confirmReread(_ candidate: Candidate, audioEnd: TimeInterval?) {
        let length = segments[candidate.index].normalizedText.count
        // Revisions near the old sentence end are normal. Rewinding a displayed
        // prompt requires two advancing audio observations in the earlier part.
        guard anticipatedSegmentID != nil, candidate.support >= 10,
              candidate.score >= configuration.highConfidence,
              candidate.endOffset < Int(Double(length) * 0.67),
              let time = audioEnd, time.isFinite else {
            rereadSample = nil
            return
        }
        if let previous = rereadSample {
            if time > previous.time, time - previous.time <= 2.5,
               candidate.endOffset > previous.offset {
                clearPace()
                return
            }
            // Multiple hypotheses for the same audio do not confirm a reread.
            if time <= previous.time { return }
        }
        rereadSample = (candidate.endOffset, time)
    }

    private mutating func updatePrompt(_ candidate: Candidate, audioEnd: TimeInterval?) {
        guard candidate.score >= configuration.highConfidence,
              candidate.index + 1 < segments.count else { return }
        let id = segments[candidate.index].id
        let length = segments[candidate.index].normalizedText.count
        if let time = audioEnd, time.isFinite {
            if let previous = paceSample, previous.id == id {
                let elapsed = time - previous.time
                let advance = candidate.endOffset - previous.offset
                // Lose the tempo estimate after pauses/revisions, not the default lead.
                if elapsed > 2.5 || advance < 0 {
                    resetRhythm()
                } else if elapsed >= 0.15, advance > 0 {
                    let measured = min(10, max(1, Double(advance) / elapsed))
                    charactersPerSecond = charactersPerSecond.map { $0 * 0.4 + measured * 0.6 } ?? measured
                }
            }
            paceSample = (id, candidate.endOffset, time)
        }
        guard candidate.support >= min(8, length) else { return }
        let remaining = length - candidate.endOffset - 1
        // Near the sentence end, default to four characters of lead even when
        // ASR has not provided enough samples to estimate pace. Faster delivery
        // can extend this to six, but never beyond one sentence or its final third.
        let leadCharacters = max(4, min(6, (charactersPerSecond ?? 0) * 0.8))
        if Double(candidate.endOffset + 1) / Double(max(1, length)) >= 0.67,
           Double(remaining) <= leadCharacters {
            anticipatedSegmentID = segments[candidate.index + 1].id
        }
    }

    private mutating func resetPendingCandidate() {
        pendingTargetID = nil
        pendingHitCount = 0
        pendingEvidence = ""
    }
}
