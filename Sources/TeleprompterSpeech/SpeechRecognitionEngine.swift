import Foundation
import TeleprompterCore

public struct EngineStatus: Sendable, Equatable {
    public enum Phase: String, Sendable { case idle, preparing, ready, listening, stopping, failed }
    public enum ModelState: String, Sendable { case notInstalled, downloading, installed, failed }
    public enum MicrophoneAuthorization: String, Sendable { case notDetermined, granted, denied, restricted }

    public var phase: Phase
    public var localeIdentifier: String?
    public var speechAvailable: Bool
    public var localeSupported: Bool
    public var modelState: ModelState
    public var downloadProgress: Double
    public var microphoneAuthorization: MicrophoneAuthorization
    public var message: String?

    public init(
        phase: Phase = .idle,
        localeIdentifier: String? = nil,
        speechAvailable: Bool = false,
        localeSupported: Bool = false,
        modelState: ModelState = .notInstalled,
        downloadProgress: Double = 0,
        microphoneAuthorization: MicrophoneAuthorization = .notDetermined,
        message: String? = nil
    ) {
        self.phase = phase
        self.localeIdentifier = localeIdentifier
        self.speechAvailable = speechAvailable
        self.localeSupported = localeSupported
        self.modelState = modelState
        self.downloadProgress = min(max(downloadProgress, 0), 1)
        self.microphoneAuthorization = microphoneAuthorization
        self.message = message
    }
}

@MainActor
public protocol SpeechRecognitionEngine: AnyObject {
    var status: EngineStatus { get }
    func prepare(locale: Locale) async throws
    func start(sessionID: UUID) async throws -> AsyncThrowingStream<RecognitionEvent, Error>
    func stop() async
    func setCaptureAudioSource(_ source: CaptureSpeechAudioSource?) throws
}

public extension SpeechRecognitionEngine {
    func setCaptureAudioSource(_ source: CaptureSpeechAudioSource?) throws {
        if source != nil { throw SpeechEngineError("当前识别引擎不支持拍摄跟随") }
    }
}

public struct SpeechEngineError: LocalizedError, Sendable {
    public let errorDescription: String?
    public init(_ message: String) { errorDescription = message }
}
