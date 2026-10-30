import AVFoundation
import CoreMedia
import Foundation
import Speech
import TeleprompterCore

@available(macOS 26.0, iOS 26.0, *)
@MainActor
public final class AppleSpeechAnalyzerEngine: SpeechRecognitionEngine {
    public private(set) var status = EngineStatus()
    private let assetManager = SpeechAssetManager()
    private let microphone = MicrophoneAudioSource()

    private var preparedLocale: Locale?
    private var analyzer: SpeechAnalyzer?
    private var inputContinuation: AsyncThrowingStream<AnalyzerInput, Error>.Continuation?
    private var resultContinuation: AsyncThrowingStream<RecognitionEvent, Error>.Continuation?
    private var resultTask: Task<Void, Never>?
    private var stopTask: Task<Void, Never>?
    private var activeSessionID: UUID?
    private var startingSessionID: UUID?
    private var resultRevision: UInt64 = 0
    private var analyzerStarted = false

    public init() {}

    public func prepare(locale: Locale) async throws {
        guard status.phase != .listening else { throw SpeechEngineError("请先停止识别，再准备模型") }
        status = EngineStatus(
            phase: .preparing,
            localeIdentifier: locale.identifier,
            speechAvailable: SpeechTranscriber.isAvailable,
            microphoneAuthorization: currentMicrophoneAuthorization
        )
        do {
            let preparedLocale = try await assetManager.prepare(requestedLocale: locale) { [weak self] update in
                self?.status = update
            }
            self.preparedLocale = preparedLocale
            status = EngineStatus(
                phase: .ready,
                localeIdentifier: preparedLocale.identifier,
                speechAvailable: true,
                localeSupported: true,
                modelState: .installed,
                downloadProgress: 1,
                microphoneAuthorization: currentMicrophoneAuthorization
            )
        } catch {
            status.phase = .failed
            status.modelState = .failed
            status.message = readableMessage(error)
            throw error
        }
    }

    public func start(sessionID: UUID) async throws -> AsyncThrowingStream<RecognitionEvent, Error> {
        guard status.phase != .listening, status.phase != .preparing, startingSessionID == nil else {
            throw SpeechEngineError("识别引擎当前正在工作")
        }
        guard status.modelState == .installed, let preparedLocale else {
            throw SpeechEngineError("请先准备 zh-CN 中文模型")
        }
        // Apple Speech modules belong to one analyzer session; make a fresh module for every start.
        let transcriber = makeSpeechTranscriber(locale: preparedLocale)

        let (events, eventContinuation) = AsyncThrowingStream<RecognitionEvent, Error>.makeStream(
            bufferingPolicy: .bufferingNewest(32)
        )
        eventContinuation.onTermination = { [weak self] _ in
            Task { @MainActor in
                guard let self, self.activeSessionID == sessionID else { return }
                await self.stop()
            }
        }

        activeSessionID = sessionID
        startingSessionID = sessionID
        resultRevision = 0
        resultContinuation = eventContinuation
        status.message = nil
        do {
            guard let audioFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
                throw SpeechEngineError("Apple SpeechTranscriber 没有可用的音频格式")
            }
            try ensureActiveSession(sessionID)

            switch try await microphone.requestAuthorization() {
            case .granted: status.microphoneAuthorization = .granted
            case .denied: status.microphoneAuthorization = .denied
            case .restricted: status.microphoneAuthorization = .restricted
            case .notDetermined: status.microphoneAuthorization = .notDetermined
            }
            try ensureActiveSession(sessionID)

            let (inputs, inputContinuation) = AsyncThrowingStream<AnalyzerInput, Error>.makeStream(
                bufferingPolicy: .bufferingOldest(16)
            )
            self.inputContinuation = inputContinuation
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            self.analyzer = analyzer
            try await analyzer.prepareToAnalyze(in: audioFormat)
            guard activeSessionID == sessionID else {
                await analyzer.cancelAndFinishNow()
                throw CancellationError()
            }
            resultTask = Task { @MainActor [weak self, transcriber] in
                do {
                    for try await result in transcriber.results {
                        guard let self, self.activeSessionID == sessionID, !Task.isCancelled else { return }
                        let start = result.range.start.seconds
                        let end = CMTimeRangeGetEnd(result.range).seconds
                        guard start.isFinite, end.isFinite, end > start else { continue }
                        self.resultRevision &+= 1
                        let event = RecognitionEvent(
                            sessionID: sessionID,
                            revision: self.resultRevision,
                            audioStart: start,
                            audioEnd: end,
                            text: String(result.text.characters),
                            stability: result.isFinal ? .final : .volatile
                        )
                        if case .dropped = eventContinuation.yield(event) {
                            throw SpeechEngineError("识别结果处理跟不上，请停止后重试")
                        }
                    }
                    eventContinuation.finish()
                } catch {
                    eventContinuation.finish(throwing: error)
                    guard let self, self.activeSessionID == sessionID else { return }
                    self.status.phase = .failed
                    self.status.message = self.readableMessage(error)
                    Task { @MainActor [weak self] in
                        await Task.yield()
                        await self?.stop()
                    }
                }
            }

            try await analyzer.start(inputSequence: inputs)
            try ensureActiveSession(sessionID)
            analyzerStarted = true
            try await microphone.start(analyzerFormat: audioFormat, inputContinuation: inputContinuation)
            try ensureActiveSession(sessionID)
            status.phase = .listening
            status.microphoneAuthorization = microphone.authorization
            status.localeSupported = true
            status.speechAvailable = true
            startingSessionID = nil
            return events
        } catch {
            let shouldReportFailure = activeSessionID == sessionID && !(error is CancellationError)
            eventContinuation.finish(throwing: error)
            await stop()
            if startingSessionID == sessionID { startingSessionID = nil }
            if shouldReportFailure {
                status.phase = .failed
                status.message = readableMessage(error)
            }
            throw error
        }
    }

    public func stop() async {
        if let stopTask {
            await stopTask.value
            return
        }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performStop()
        }
        stopTask = task
        await task.value
        stopTask = nil
    }

    private func performStop() async {
        guard analyzer != nil || activeSessionID != nil || status.phase == .listening || microphoneIsActive else {
            if status.modelState == .installed { status.phase = .ready }
            return
        }
        status.phase = .stopping
        await microphone.stop()
        inputContinuation?.finish()

        if analyzerStarted, let analyzer {
            do {
                try await withThrowingTaskGroup(of: Bool.self) { group in
                    group.addTask {
                        try await analyzer.finalizeAndFinishThroughEndOfInput()
                        return true
                    }
                    group.addTask {
                        try await Task.sleep(for: .seconds(3))
                        return false
                    }
                    let finished = try await group.next() ?? false
                    group.cancelAll()
                    if !finished { throw SpeechEngineError("识别结束超时") }
                }
            } catch {
                await analyzer.cancelAndFinishNow()
            }
        } else if let analyzer {
            await analyzer.cancelAndFinishNow()
        }

        if let resultTask { await resultTask.value }
        resultContinuation?.finish()
        resultTask = nil
        resultContinuation = nil
        inputContinuation = nil
        analyzer = nil
        activeSessionID = nil
        analyzerStarted = false
        resultRevision = 0
        status.phase = status.modelState == .installed ? .ready : .idle
        status.microphoneAuthorization = microphone.authorization
        status.message = nil
    }

    private var microphoneIsActive: Bool { status.phase == .listening }

    private func ensureActiveSession(_ sessionID: UUID) throws {
        guard activeSessionID == sessionID else { throw CancellationError() }
    }

    private var currentMicrophoneAuthorization: EngineStatus.MicrophoneAuthorization {
        AVCaptureDevice.authorizationStatus(for: .audio).engineAuthorization
    }

    private func readableMessage(_ error: Error) -> String {
        if let error = error as? LocalizedError, let description = error.errorDescription { return description }
        return error.localizedDescription
    }
}

private extension AVAuthorizationStatus {
    var engineAuthorization: EngineStatus.MicrophoneAuthorization {
        switch self {
        case .authorized: .granted
        case .denied: .denied
        case .restricted: .restricted
        case .notDetermined: .notDetermined
        @unknown default: .restricted
        }
    }
}
