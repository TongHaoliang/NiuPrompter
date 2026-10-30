import CoreMedia
import Foundation

package struct AudioSampleTimeline {
    private let sampleRate: CMTimeScale
    private var sampleOffset: Int64 = 0

    package init?(sampleRate: Double) {
        guard sampleRate.isFinite,
              sampleRate > 0,
              let exactSampleRate = CMTimeScale(exactly: sampleRate),
              exactSampleRate > 0
        else { return nil }
        self.sampleRate = exactSampleRate
    }

    package mutating func nextStartTime(frameCount: Int64) -> CMTime {
        precondition(frameCount > 0)
        defer { sampleOffset += frameCount }
        return CMTime(value: sampleOffset, timescale: sampleRate)
    }
}
