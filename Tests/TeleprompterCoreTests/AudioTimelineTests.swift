import CoreMedia
import Foundation
import Speech
import TeleprompterSpeech

func runAudioTimelineTests() throws {
    guard var timeline = AudioSampleTimeline(sampleRate: 44_100) else {
        throw TestFailure(message: "integer analyzer sample rates should create an audio timeline")
    }

    var previousEnd: CMTime?
    var neverOverlapped = true
    let frameCounts: [Int64] = [1_024, 960, 512, 997]
    for index in 0..<5_000 {
        let frameCount = frameCounts[index % frameCounts.count]
        let start = timeline.nextStartTime(frameCount: frameCount)
        if let previousEnd, CMTimeCompare(start, previousEnd) < 0 {
            neverOverlapped = false
            break
        }
        let duration = CMTime(value: frameCount, timescale: 44_100)
        previousEnd = CMTimeAdd(start, duration)
    }
    try checkTrue(neverOverlapped, "sample-count timestamps must stay non-overlapping over a long audio session")
    try checkTrue(AudioSampleTimeline(sampleRate: 44_100.5) == nil, "audio timeline rejects non-integral sample rates")
}

func runFreshTranscriberTests() throws {
    let locale = Locale(identifier: "zh-CN")
    let first = makeSpeechTranscriber(locale: locale)
    let second = makeSpeechTranscriber(locale: locale)
    try checkTrue(first !== second, "each SpeechAnalyzer session receives its own transcriber module")
}
