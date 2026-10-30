import Foundation

public struct MatchConfiguration: Sendable, Equatable {
    public var highConfidence: Double
    public var mediumFloor: Double
    public var confirmationCount: Int
    public var lookBehind: Int
    public var lookAhead: Int
    public var maxGroupSegments: Int
    public var maxQueryOverhang: Int
    public var minimumQueryCharacters: Int
    public var minimumCandidateCoverage: Double
    public var ambiguityGap: Double
    public var characterWeight: Double
    public var lcsWeight: Double
    public var phoneticWeight: Double
    public var proximityWeight: Double

    public init(
        highConfidence: Double = 0.72,
        mediumFloor: Double = 0.52,
        confirmationCount: Int = 2,
        lookBehind: Int = 1,
        lookAhead: Int = 8,
        maxGroupSegments: Int = 3,
        maxQueryOverhang: Int = 8,
        minimumQueryCharacters: Int = 6,
        minimumCandidateCoverage: Double = 0.35,
        ambiguityGap: Double = 0.05,
        characterWeight: Double = 0.50,
        lcsWeight: Double = 0.30,
        phoneticWeight: Double = 0.15,
        proximityWeight: Double = 0.05
    ) {
        self.highConfidence = highConfidence
        self.mediumFloor = mediumFloor
        self.confirmationCount = max(1, confirmationCount)
        self.lookBehind = max(0, lookBehind)
        self.lookAhead = max(0, lookAhead)
        self.maxGroupSegments = max(1, maxGroupSegments)
        self.maxQueryOverhang = max(0, maxQueryOverhang)
        self.minimumQueryCharacters = max(1, minimumQueryCharacters)
        self.minimumCandidateCoverage = min(max(0, minimumCandidateCoverage), 1)
        self.ambiguityGap = max(0, ambiguityGap)
        self.characterWeight = max(0, characterWeight)
        self.lcsWeight = max(0, lcsWeight)
        self.phoneticWeight = max(0, phoneticWeight)
        self.proximityWeight = max(0, proximityWeight)
    }
}
