import AVFoundation
import CoreMedia
import Foundation
import Speech
import TeleprompterSpeech

@MainActor
func runCaptureSpeechAudioTests() async throws {
    let source = CaptureSpeechAudioSource()
    let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
    let analyzerFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: false)!
    let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 320)!
    pcm.frameLength = 320
    for i in 0..<320 { pcm.floatChannelData![0][i] = 0.25 }
    var sample: CMSampleBuffer?
    var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 16_000), presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
    let made = CMSampleBufferCreate(allocator: kCFAllocatorDefault, dataBuffer: nil, dataReady: false,
                                   makeDataReadyCallback: nil, refcon: nil, formatDescription: format.formatDescription,
                                   sampleCount: 320, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
                                   sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &sample)
    try checkEqual(made, noErr, "synthetic capture PCM sample is valid")
    guard let sample else { throw TestFailure(message: "missing capture sample") }
    try checkEqual(CMSampleBufferSetDataBufferFromAudioBufferList(sample, blockBufferAllocator: kCFAllocatorDefault,
                                                                 blockBufferMemoryAllocator: kCFAllocatorDefault, flags: 0,
                                                                 bufferList: pcm.audioBufferList), noErr, "capture PCM data attaches")
    CMSampleBufferSetDataReady(sample)
    let (stream, continuation) = AsyncThrowingStream<AnalyzerInput, Error>.makeStream(bufferingPolicy: .bufferingOldest(16))
    source.start(format: analyzerFormat, continuation: continuation)
    source.consume(sample)
    source.consume(sample)
    source.stop()
    var items: [AnalyzerInput] = []
    for try await item in stream { items.append(item) }
    try checkEqual(items.count, 2, "camera audio feeds speech while independent capture continues")
    try checkEqual(items.first?.buffer.frameLength, 320, "camera PCM frame count survives conversion")
    if let buffer = items.first?.buffer {
        try withExtendedLifetime(buffer) {
            try checkEqual(buffer.int16ChannelData?[0][10], 8192, "camera PCM values survive conversion")
        }
    }
    try checkEqual(items.first?.bufferStartTime, .zero, "speech attachment starts a fresh timeline")
    try checkEqual(items.last?.bufferStartTime, CMTime(value: 320, timescale: 16_000), "shared mic speech timeline advances by samples")

    // The capture delegate is allowed to continue delivering while speech is paused.
    source.consume(sample)
    let (resumed, resumedContinuation) = AsyncThrowingStream<AnalyzerInput, Error>.makeStream()
    source.start(format: analyzerFormat, continuation: resumedContinuation)
    source.consume(sample)
    source.stop()
    var resumedItems: [AnalyzerInput] = []
    for try await item in resumed { resumedItems.append(item) }
    try checkEqual(resumedItems.count, 1, "pause detaches speech without accumulating old camera audio")
    try checkEqual(resumedItems.first?.bufferStartTime, .zero, "resume creates new analyzer timeline")

    let (overloaded, limited) = AsyncThrowingStream<AnalyzerInput, Error>.makeStream(bufferingPolicy: .bufferingOldest(1))
    source.start(format: analyzerFormat, continuation: limited)
    source.consume(sample)
    source.consume(sample)
    var overflowWasReported = false
    do { for try await _ in overloaded {} } catch { overflowWasReported = true }
    try checkTrue(overflowWasReported, "speech overload surfaces instead of silently losing audio")
    source.stop()
}
