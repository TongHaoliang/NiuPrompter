import Foundation

public struct RecognitionEvent: Sendable, Equatable {
    public enum Stability: Sendable, Equatable {
        case volatile
        case final
    }

    public let sessionID: UUID
    public let revision: UInt64
    public let audioStart: TimeInterval
    public let audioEnd: TimeInterval
    public let text: String
    public let stability: Stability

    public init(
        sessionID: UUID,
        revision: UInt64,
        audioStart: TimeInterval,
        audioEnd: TimeInterval,
        text: String,
        stability: Stability
    ) {
        self.sessionID = sessionID
        self.revision = revision
        self.audioStart = audioStart
        self.audioEnd = audioEnd
        self.text = text
        self.stability = stability
    }
}

public struct TranscriptSnapshot: Sendable, Equatable {
    public let finalText: String
    public let volatileText: String
    public let recentText: String
    public let evidenceRevision: UInt64
    public let latestText: String?
    public let latestAudioEnd: TimeInterval?

    public init(finalText: String, volatileText: String, recentText: String, evidenceRevision: UInt64,
                latestText: String? = nil, latestAudioEnd: TimeInterval? = nil) {
        self.finalText = finalText
        self.volatileText = volatileText
        self.recentText = recentText
        self.evidenceRevision = evidenceRevision
        self.latestText = latestText
        self.latestAudioEnd = latestAudioEnd
    }
}
