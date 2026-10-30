import AVFoundation
import Dispatch
import TeleprompterSpeech

private final class AudioBufferBox: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer

    init(_ buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }
}

@MainActor
func runAudioTapIsolationTests() async throws {
    let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false
    )!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 64)!
    buffer.frameLength = 64
    let samples = buffer.floatChannelData![0]
    for index in 0..<64 {
        samples[index] = Float(index) / 64
    }

    let (chunks, continuation) = AsyncThrowingStream<CapturedAudioChunk, Error>.makeStream()
    let handler = makeAudioTapHandler(channelCount: 1, chunkContinuation: continuation)
    let bufferedAudio = AudioBufferBox(buffer)
    await withCheckedContinuation { (finished: CheckedContinuation<Void, Never>) in
        DispatchQueue.global().async {
            handler(bufferedAudio.buffer, AVAudioTime(hostTime: 0))
            continuation.finish()
            finished.resume()
        }
    }

    var iterator = chunks.makeAsyncIterator()
    let chunk = try await iterator.next()
    try checkEqual(chunk?.frameCount, 64, "audio tap copies a buffer from a non-main queue")
    try checkEqual(chunk?.channelSamples[0].count, 64, "audio tap preserves sample count")
    try checkEqual(chunk?.channelSamples[0][63], Float(63) / 64, "audio tap preserves samples")
}
