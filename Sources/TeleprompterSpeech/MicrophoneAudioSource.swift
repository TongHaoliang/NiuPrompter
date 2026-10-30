import AVFoundation
import Foundation
import Speech

package struct CapturedAudioChunk: Sendable {
    package let channelSamples: [[Float]]
    package let frameCount: Int
}

private enum AudioSourceFailure: LocalizedError {
    case permissionDenied
    case unavailableInput
    case unsupportedSampleFormat
    case queueOverflow
    case conversion(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied: "请在系统设置中允许本 App 使用麦克风"
        case .unavailableInput: "找不到可用的麦克风输入设备"
        case .unsupportedSampleFormat: "麦克风没有提供受支持的 Float32 音频格式"
        case .queueOverflow: "音频处理跟不上，请停止后重试"
        case let .conversion(message): "麦克风音频转换失败：\(message)"
        }
    }
}

package func makeAudioTapHandler(
    channelCount: Int,
    chunkContinuation: AsyncThrowingStream<CapturedAudioChunk, Error>.Continuation
) -> @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void {
    { buffer, _ in
        guard let channelData = buffer.floatChannelData else {
            chunkContinuation.finish(throwing: AudioSourceFailure.unsupportedSampleFormat)
            return
        }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }
        var planes: [[Float]] = []
        planes.reserveCapacity(channelCount)
        for channel in 0..<channelCount {
            planes.append(Array(UnsafeBufferPointer(start: channelData[channel], count: frameCount)))
        }
        if case .dropped = chunkContinuation.yield(CapturedAudioChunk(channelSamples: planes, frameCount: frameCount)) {
            chunkContinuation.finish(throwing: AudioSourceFailure.queueOverflow)
        }
    }
}

@available(macOS 26.0, iOS 26.0, *)
@MainActor
final class MicrophoneAudioSource {
    private var audioEngine: AVAudioEngine?
    private var chunkContinuation: AsyncThrowingStream<CapturedAudioChunk, Error>.Continuation?
    private var feederTask: Task<Void, Never>?
    private var tapInstalled = false
    private var sessionActivated = false
    private(set) var authorization: EngineStatus.MicrophoneAuthorization = .notDetermined

    func requestAuthorization() async throws -> EngineStatus.MicrophoneAuthorization {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            authorization = .granted
        case .denied:
            authorization = .denied
        case .restricted:
            authorization = .restricted
        case .notDetermined:
            authorization = await AVCaptureDevice.requestAccess(for: .audio) ? .granted : .denied
        @unknown default:
            authorization = .restricted
        }
        guard authorization == .granted else { throw AudioSourceFailure.permissionDenied }
        return authorization
    }

    func start(
        analyzerFormat: AVAudioFormat,
        inputContinuation: AsyncThrowingStream<AnalyzerInput, Error>.Continuation
    ) async throws {
        guard audioEngine == nil else { throw SpeechEngineError("麦克风已经启动") }
        _ = try await requestAuthorization()

        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement)
        try session.setActive(true)
        sessionActivated = true
        #endif

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let sourceFormat = inputNode.outputFormat(forBus: 0)
        guard sourceFormat.sampleRate > 0,
              sourceFormat.channelCount > 0,
              sourceFormat.commonFormat == .pcmFormatFloat32,
              !sourceFormat.isInterleaved
        else {
            await stop()
            throw AudioSourceFailure.unavailableInput
        }
        guard let converter = AVAudioConverter(from: sourceFormat, to: analyzerFormat) else {
            await stop()
            throw AudioSourceFailure.unsupportedSampleFormat
        }
        guard let initialTimeline = AudioSampleTimeline(sampleRate: analyzerFormat.sampleRate) else {
            await stop()
            throw AudioSourceFailure.unsupportedSampleFormat
        }

        let (chunks, chunkContinuation) = AsyncThrowingStream<CapturedAudioChunk, Error>.makeStream(
            bufferingPolicy: .bufferingOldest(16)
        )
        self.chunkContinuation = chunkContinuation
        audioEngine = engine
        let sampleRate = sourceFormat.sampleRate
        let channelCount = Int(sourceFormat.channelCount)

        let tapHandler = makeAudioTapHandler(
            channelCount: channelCount,
            chunkContinuation: chunkContinuation
        )
        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: sourceFormat, block: tapHandler)
        tapInstalled = true

        feederTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var timeline = initialTimeline
            do {
                for try await chunk in chunks {
                    try Task.checkCancellation()
                    let sourceBuffer = try self.makeBuffer(chunk, format: sourceFormat)
                    let ratio = analyzerFormat.sampleRate / sampleRate
                    let capacity = AVAudioFrameCount(max(1, Double(chunk.frameCount) * ratio + 64))
                    guard let converted = AVAudioPCMBuffer(pcmFormat: analyzerFormat, frameCapacity: capacity) else {
                        throw AudioSourceFailure.conversion("无法分配输出缓冲区")
                    }
                    var conversionError: NSError?
                    var suppliedInput = false
                    let conversionStatus = converter.convert(to: converted, error: &conversionError) { _, outputStatus in
                        guard !suppliedInput else {
                            outputStatus.pointee = .noDataNow
                            return nil
                        }
                        suppliedInput = true
                        outputStatus.pointee = .haveData
                        return sourceBuffer
                    }
                    if conversionStatus == .error {
                        throw AudioSourceFailure.conversion(conversionError?.localizedDescription ?? "未知格式错误")
                    }
                    if converted.frameLength > 0 {
                        let time = timeline.nextStartTime(frameCount: Int64(converted.frameLength))
                        switch inputContinuation.yield(AnalyzerInput(buffer: converted, bufferStartTime: time)) {
                        case .enqueued:
                            break
                        case .dropped:
                            throw AudioSourceFailure.queueOverflow
                        case .terminated:
                            return
                        @unknown default:
                            throw AudioSourceFailure.queueOverflow
                        }
                    }
                }
                inputContinuation.finish()
            } catch {
                inputContinuation.finish(throwing: error)
            }
        }

        do {
            try engine.start()
        } catch {
            await stop()
            throw SpeechEngineError("无法启动麦克风：\(error.localizedDescription)")
        }
    }

    func stop() async {
        if tapInstalled {
            audioEngine?.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        audioEngine?.stop()
        chunkContinuation?.finish()
        if let feederTask { await feederTask.value }
        feederTask = nil
        chunkContinuation = nil
        audioEngine = nil
        #if os(iOS)
        if sessionActivated {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            sessionActivated = false
        }
        #endif
    }

    private func makeBuffer(_ chunk: CapturedAudioChunk, format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(chunk.frameCount)),
              let channelData = buffer.floatChannelData,
              chunk.channelSamples.count == Int(format.channelCount)
        else { throw AudioSourceFailure.conversion("无法重建麦克风输入缓冲区") }
        buffer.frameLength = AVAudioFrameCount(chunk.frameCount)
        for channel in chunk.channelSamples.indices {
            chunk.channelSamples[channel].withUnsafeBufferPointer { samples in
                if let baseAddress = samples.baseAddress {
                    channelData[channel].update(from: baseAddress, count: chunk.frameCount)
                }
            }
        }
        return buffer
    }
}
