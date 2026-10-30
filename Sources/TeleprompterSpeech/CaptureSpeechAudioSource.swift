import AVFoundation
import CoreMedia
import Foundation
import Speech

/// One microphone owner (AVCaptureSession), with an independently detachable speech consumer.
/// All converter state and continuation access is serialized by this lock. Capture buffers are
/// copied before the delegate returns; no CMSampleBuffer crosses into the analyzer's task.
public final class CaptureSpeechAudioSource: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncThrowingStream<AnalyzerInput, Error>.Continuation?
    private var targetFormat: AVAudioFormat?
    private var converter: AVAudioConverter?
    private var sourceFormat: AVAudioFormat?
    private var timeline: AudioSampleTimeline?

    public init() {}

    package func start(format: AVAudioFormat, continuation: AsyncThrowingStream<AnalyzerInput, Error>.Continuation) {
        lock.lock()
        defer { lock.unlock() }
        self.continuation?.finish()
        self.continuation = continuation
        targetFormat = format
        timeline = AudioSampleTimeline(sampleRate: format.sampleRate)
        converter = nil
        sourceFormat = nil
    }

    public func stop(error: String? = nil) {
        lock.lock()
        defer { lock.unlock() }
        if let error { continuation?.finish(throwing: SpeechEngineError(error)) }
        else { continuation?.finish() }
        continuation = nil
        converter = nil
        sourceFormat = nil
        targetFormat = nil
        timeline = nil
    }

    public func consume(_ sample: CMSampleBuffer) {
        lock.lock()
        defer { lock.unlock() }
        guard let continuation, let targetFormat else { return }
        do {
            guard let description = CMSampleBufferGetFormatDescription(sample) else {
                throw SpeechEngineError("相机音频格式无法识别")
            }
            let format = AVAudioFormat(cmAudioFormatDescription: description)
            let count = CMSampleBufferGetNumSamples(sample)
            guard count > 0, count <= Int(Int32.max),
                  let input = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)) else {
                throw SpeechEngineError("相机音频缓冲区不可用")
            }
            input.frameLength = AVAudioFrameCount(count)
            guard CMSampleBufferCopyPCMDataIntoAudioBufferList(sample, at: 0, frameCount: Int32(count), into: input.mutableAudioBufferList) == noErr else {
                throw SpeechEngineError("无法读取相机麦克风声音")
            }
            if sourceFormat != format {
                converter = AVAudioConverter(from: format, to: targetFormat)
                sourceFormat = format
            }
            guard let converter, var timeline else { throw SpeechEngineError("无法转换相机音频格式") }
            let capacity = AVAudioFrameCount(Double(count) * targetFormat.sampleRate / format.sampleRate + 64)
            guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
                throw SpeechEngineError("无法分配语音识别缓冲区")
            }
            var supplied = false
            var error: NSError?
            let result = converter.convert(to: output, error: &error) { _, status in
                if supplied { status.pointee = .noDataNow; return nil }
                supplied = true
                status.pointee = .haveData
                return input
            }
            guard result != .error else { throw error ?? SpeechEngineError("相机音频转换失败") as NSError }
            if output.frameLength > 0 {
                let time = timeline.nextStartTime(frameCount: Int64(output.frameLength))
                self.timeline = timeline
                if case .dropped = continuation.yield(AnalyzerInput(buffer: output, bufferStartTime: time)) {
                    throw SpeechEngineError("识别处理暂时跟不上，录像继续，请重新开启跟随")
                }
            }
        } catch {
            continuation.finish(throwing: error)
            self.continuation = nil
        }
    }
}
