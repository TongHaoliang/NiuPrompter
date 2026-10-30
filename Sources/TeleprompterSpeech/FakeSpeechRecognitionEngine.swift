import Foundation
import TeleprompterCore

@MainActor
public final class FakeSpeechRecognitionEngine: SpeechRecognitionEngine {
    public private(set) var status = EngineStatus(
        speechAvailable: true,
        localeSupported: true
    )
    public private(set) var prepareCount = 0
    public private(set) var startCount = 0
    public private(set) var stopCount = 0
    public private(set) var startSessions: [UUID] = []
    public var prepareFailureMessage: String?
    public var startFailureMessage: String?
    public var preparationDelay: Duration?
    private var demoTexts: [String] = []
    private var demoTask: Task<Void, Never>?

    private var activeSessionID: UUID?
    private var continuations: [UUID: AsyncThrowingStream<RecognitionEvent, Error>.Continuation] = [:]

    public init() {}

    public func configureDemo(texts: [String]) {
        demoTexts = texts
    }

    public func prepare(locale: Locale) async throws {
        prepareCount += 1
        status.phase = .preparing
        status.localeIdentifier = locale.identifier
        status.modelState = .downloading
        status.downloadProgress = 0.5
        if let preparationDelay { try await Task.sleep(for: preparationDelay) }
        else { await Task.yield() }
        if let prepareFailureMessage {
            status.phase = .failed
            status.modelState = .failed
            status.message = prepareFailureMessage
            throw SpeechEngineError(prepareFailureMessage)
        }
        status.phase = .ready
        status.speechAvailable = true
        status.localeSupported = true
        status.modelState = .installed
        status.downloadProgress = 1
        status.message = nil
    }

    public func start(sessionID: UUID) async throws -> AsyncThrowingStream<RecognitionEvent, Error> {
        guard activeSessionID == nil else { throw SpeechEngineError("识别引擎已经在运行") }
        if let startFailureMessage {
            status.phase = .failed
            status.message = startFailureMessage
            throw SpeechEngineError(startFailureMessage)
        }

        startCount += 1
        startSessions.append(sessionID)
        activeSessionID = sessionID
        status.phase = .listening
        status.message = nil
        let stream = AsyncThrowingStream<RecognitionEvent, Error> { continuation in
            continuations[sessionID] = continuation
        }
        if !demoTexts.isEmpty {
            let texts = demoTexts
            demoTask = Task { @MainActor [weak self] in
                for (index, text) in texts.enumerated() {
                    let start = TimeInterval(index * 2)
                    let end = start + 1.5
                    let prefix = String(text.prefix(max(6, text.count / 2)))
                    let updates = [
                        (prefix, RecognitionEvent.Stability.volatile),
                        (text, .volatile),
                        (text, .final),
                    ]
                    for (offset, update) in updates.enumerated() {
                        do { try await Task.sleep(for: .milliseconds(350)) }
                        catch { return }
                        guard let self, !Task.isCancelled, self.activeSessionID == sessionID else { return }
                        self.send(RecognitionEvent(
                            sessionID: sessionID,
                            revision: UInt64(index * updates.count + offset + 1),
                            audioStart: start,
                            audioEnd: end,
                            text: update.0,
                            stability: update.1
                        ))
                    }
                }
            }
        }
        return stream
    }

    public func stop() async {
        stopCount += 1
        demoTask?.cancel()
        demoTask = nil
        if let activeSessionID {
            continuations[activeSessionID]?.finish()
            self.activeSessionID = nil
        }
        status.phase = status.modelState == .installed ? .ready : .idle
    }

    public func send(_ event: RecognitionEvent, through sessionID: UUID? = nil) {
        let destination = sessionID ?? event.sessionID
        continuations[destination]?.yield(event)
    }

    public func finish(sessionID: UUID, error: Error? = nil) {
        guard let continuation = continuations[sessionID] else { return }
        continuation.finish(throwing: error)
        if activeSessionID == sessionID {
            demoTask?.cancel()
            demoTask = nil
            activeSessionID = nil
            status.phase = status.modelState == .installed ? .ready : .idle
        }
    }
}
