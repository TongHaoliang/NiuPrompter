import Foundation
import Combine
import TeleprompterCore
import TeleprompterSpeech

public struct CursorChange: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let segmentID: Int
    public let reason: String
    public let changedAt: Date

    public init(segmentID: Int, reason: String, changedAt: Date = Date()) {
        self.id = UUID()
        self.segmentID = segmentID
        self.reason = reason
        self.changedAt = changedAt
    }
}

@MainActor
public final class ProbeViewModel: ObservableObject {
    @Published public private(set) var engineStatus: EngineStatus
    @Published public private(set) var scriptText = ""
    @Published public private(set) var segments: [ScriptSegment] = []
    @Published public private(set) var finalTranscript = ""
    @Published public private(set) var volatileTranscript = ""
    @Published public private(set) var recentRecognition = ""
    @Published public private(set) var latestRecognitionEvent: RecognitionEvent?
    @Published public private(set) var latestRecognitionReceivedAt: Date?
    @Published public private(set) var currentCandidate: MatchResult?
    @Published public private(set) var cursorHistory: [CursorChange] = []
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var receivedEventCount = 0
    @Published public private(set) var isPreparing = false
    @Published public private(set) var isStarting = false
    @Published public private(set) var storageWarning: String?
    @Published public private(set) var hasSavedDraft = false
    @Published public private(set) var usesCaptureAudio = false

    @Published public private(set) var documents: [ScriptDocument] = []
    @Published public private(set) var activeDocumentID: UUID?
    public var activeDocumentTitle: String { documents.first(where: { $0.id == activeDocumentID })?.title ?? "未命名稿件" }

    public var isListening: Bool { engineStatus.phase == .listening }
    public var promptSegmentID: Int? { matcher?.promptSegmentID }
    public var currentSegmentID: Int? { matcher?.currentSegmentID }
    public var currentSegment: ScriptSegment? {
        guard let currentSegmentID else { return nil }
        return segments.first { $0.id == currentSegmentID }
    }

    private let engine: any SpeechRecognitionEngine
    private let sessionStore: (any ReadingSessionStore)?
    private var storageLoadFailed = false
    private var lastSavedSession: ReadingSession?
    private var matcher: ScriptMatcher?
    private var accumulator = TranscriptAccumulator()
    private var streamTask: Task<Void, Never>?
    private var activeSessionID: UUID?
    private var operationGeneration: UInt64 = 0

    public init(engine: any SpeechRecognitionEngine, sessionStore: (any ReadingSessionStore)? = nil) {
        self.engine = engine
        self.engineStatus = engine.status
        self.sessionStore = sessionStore
        restoreSession()
        if documents.isEmpty {
            let document = ScriptDocument(title: "未命名稿件", text: scriptText, currentSegmentID: currentSegmentID, promptSegmentID: promptSegmentID)
            documents = [document]
            activeDocumentID = document.id
        }
    }

    @discardableResult
    public func setScriptText(_ text: String) -> Bool {
        guard !isListening, !isStarting else { return false }
        if text == scriptText { return true }
        let anchor = currentSegment?.normalizedText
        scriptText = text
        previewSegments()
        if let anchor {
            let matches = segments.filter { $0.normalizedText == anchor }
            if matches.count == 1 { matcher?.reset(to: matches[0].id) }
        }
        persistSession()
        return true
    }

    public func previewSegments() {
        guard !isListening, !isStarting else { return }
        segments = ScriptSegmenter.segment(scriptText)
        matcher = ScriptMatcher(segments: segments, configuration: MatchConfiguration())
        clearTranscriptDisplay()
        cursorHistory.removeAll(keepingCapacity: false)
    }

    private func restoreSession() {
        guard let sessionStore else { return }
        do {
            guard let saved = try sessionStore.load() else { return }
            if let stored = saved.documents {
                documents = stored
                activeDocumentID = saved.activeDocumentID
            } else {
                let migrated = ScriptDocument(title: "原来的稿件", text: saved.text, currentSegmentID: saved.currentSegmentID, promptSegmentID: saved.promptSegmentID)
                documents = [migrated]
                activeDocumentID = migrated.id
            }
            scriptText = saved.text
            previewSegments()
            matcher?.restorePosition(currentSegmentID: saved.currentSegmentID, promptSegmentID: saved.promptSegmentID)
            lastSavedSession = saved
            hasSavedDraft = true
        } catch {
            storageLoadFailed = true
            storageWarning = "无法读取上次稿件，原文件已保留。当前内容暂不自动保存，请保留原稿。"
        }
    }

    @discardableResult
    private func persistSession() -> Bool {
        guard !storageLoadFailed else { return false }
        if let index = documents.firstIndex(where: { $0.id == activeDocumentID }) {
            documents[index].text = scriptText
            documents[index].currentSegmentID = currentSegmentID
            documents[index].promptSegmentID = promptSegmentID
        }
        let saved = ReadingSession(text: scriptText, currentSegmentID: currentSegmentID, promptSegmentID: promptSegmentID,
                                   documents: documents, activeDocumentID: activeDocumentID)
        guard let sessionStore, saved != lastSavedSession else { return true }
        do {
            try sessionStore.save(saved)
            lastSavedSession = saved
            hasSavedDraft = true
            storageWarning = nil
            return true
        } catch {
            storageWarning = "稿件或阅读位置尚未保存成功，请保留原稿。稍后编辑或暂停时会重试。"
            return false
        }
    }

    // Save the whole library before changing selection or removing a document.
    @discardableResult
    private func commitLibrary(_ updated: [ScriptDocument], activeID: UUID) -> Bool {
        guard let active = updated.first(where: { $0.id == activeID }) else { return false }
        let saved = ReadingSession(text: active.text, currentSegmentID: active.currentSegmentID,
                                   promptSegmentID: active.promptSegmentID, documents: updated, activeDocumentID: activeID)
        do {
            try sessionStore?.save(saved)
            documents = updated
            activeDocumentID = activeID
            scriptText = active.text
            previewSegments()
            matcher?.restorePosition(currentSegmentID: active.currentSegmentID, promptSegmentID: active.promptSegmentID)
            lastSavedSession = saved
            hasSavedDraft = sessionStore != nil
            storageWarning = nil
            return true
        } catch {
            storageWarning = "稿件库未保存成功，本次操作未生效，请稍后重试。"
            return false
        }
    }

    @discardableResult
    public func createDocument() async -> Bool {
        await stop()
        guard persistSession() else { return false }
        let document = ScriptDocument(title: "新稿件")
        return commitLibrary([document] + documents, activeID: document.id)
    }

    @discardableResult
    public func selectDocument(_ id: UUID) async -> Bool {
        await stop()
        guard persistSession() else { return false }
        return commitLibrary(documents, activeID: id)
    }

    @discardableResult
    public func renameDocument(_ id: UUID, title: String) -> Bool {
        guard !isListening, !isStarting, persistSession(), let activeDocumentID else { return false }
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let index = documents.firstIndex(where: { $0.id == id }) else { return false }
        var updated = documents
        updated[index].title = name
        return commitLibrary(updated, activeID: activeDocumentID)
    }

    @discardableResult
    public func deleteDocument(_ id: UUID) async -> Bool {
        await stop()
        guard persistSession(), documents.contains(where: { $0.id == id }) else { return false }
        var updated = documents.filter { $0.id != id }
        if updated.isEmpty { updated = [ScriptDocument(title: "未命名稿件")] }
        let active = activeDocumentID == id ? updated[0].id : (activeDocumentID ?? updated[0].id)
        return commitLibrary(updated, activeID: active)
    }

    public func setCaptureAudioSource(_ source: CaptureSpeechAudioSource?) async throws {
        await stop()
        try engine.setCaptureAudioSource(source)
        usesCaptureAudio = source != nil
    }

    public func prepareModel(locale: Locale = Locale(identifier: "zh-CN")) async {
        guard !isListening, !isPreparing else { return }
        operationGeneration &+= 1
        let generation = operationGeneration
        isPreparing = true
        errorMessage = nil
        do {
            try await engine.prepare(locale: locale)
            guard generation == operationGeneration else { return }
            engineStatus = engine.status
            isPreparing = false
        } catch {
            guard generation == operationGeneration else { return }
            engineStatus = engine.status
            isPreparing = false
            errorMessage = readableMessage(error)
        }
    }

    public func start() async {
        guard !segments.isEmpty else {
            errorMessage = "请先载入或输入稿件"
            return
        }
        guard !isListening, !isStarting, !isPreparing else { return }

        operationGeneration &+= 1
        let generation = operationGeneration
        isStarting = true
        errorMessage = nil

        do {
            if engineStatus.modelState != .installed {
                isPreparing = true
                try await engine.prepare(locale: Locale(identifier: "zh-CN"))
                guard generation == operationGeneration else { return }
                engineStatus = engine.status
                isPreparing = false
                guard engineStatus.modelState == .installed else {
                    throw StartError.modelNotReady
                }
            }

            let sessionID = UUID()
            activeSessionID = sessionID
            receivedEventCount = 0
            clearTranscriptDisplay()
            accumulator.reset(sessionID: sessionID)
            matcher?.clearEvidenceAndCandidate(preservingPrompt: true)

            let stream = try await engine.start(sessionID: sessionID)
            guard generation == operationGeneration, activeSessionID == sessionID else {
                await engine.stop()
                return
            }
            engineStatus = engine.status
            isStarting = false
            streamTask = Task { @MainActor [weak self] in
                do {
                    for try await event in stream {
                        guard let self, self.activeSessionID == sessionID, !Task.isCancelled else { return }
                        self.latestRecognitionEvent = event
                        self.latestRecognitionReceivedAt = Date()
                        self.receivedEventCount += 1
                        guard let snapshot = self.accumulator.ingest(event) else { continue }
                        self.apply(snapshot)
                    }
                    await self?.streamFinished(sessionID: sessionID)
                } catch {
                    await self?.streamFailed(error, sessionID: sessionID)
                }
            }
        } catch {
            guard generation == operationGeneration else { return }
            isStarting = false
            isPreparing = false
            engineStatus = engine.status
            errorMessage = readableMessage(error)
            activeSessionID = nil
            await engine.stop()
            engineStatus = engine.status
        }
    }

    private enum StartError: LocalizedError {
        case modelNotReady

        var errorDescription: String? {
            switch self {
            case .modelNotReady: "中文模型尚未准备完成，请稍后再试"
            }
        }
    }

    public func stop() async {
        persistSession()
        if isPreparing && !isStarting && !isListening && activeSessionID == nil {
            engineStatus = engine.status
            return
        }
        operationGeneration &+= 1
        isPreparing = false
        isStarting = false
        activeSessionID = nil
        let task = streamTask
        streamTask = nil
        task?.cancel()
        await engine.stop()
        engineStatus = engine.status
    }

    public func selectSegment(_ segmentID: Int) async {
        guard !segments.isEmpty, let oldID = currentSegmentID else { return }
        let shouldRestart = isListening || isStarting
        let wasChanged = oldID != segmentID
        if shouldRestart { await stop() }
        matcher?.reset(to: segmentID)
        clearTranscriptDisplay()
        recordCursorChange(reason: "手动选择")
        persistSession()
        if shouldRestart { await start() }
        if !wasChanged, !shouldRestart { currentCandidate = nil }
    }

    public func previousSegment() async {
        guard let currentSegmentID else { return }
        await selectSegment(currentSegmentID - 1)
    }

    public func nextSegment() async {
        guard let currentSegmentID else { return }
        await selectSegment(currentSegmentID + 1)
    }

    public func clearRecognitionCache() async {
        let shouldRestart = isListening || isStarting
        if shouldRestart { await stop() }
        accumulator = TranscriptAccumulator()
        matcher?.clearEvidenceAndCandidate(preservingPrompt: true)
        currentCandidate = nil
        clearTranscriptDisplay()
        if shouldRestart { await start() }
    }

    private func apply(_ snapshot: TranscriptSnapshot) {
        finalTranscript = snapshot.finalText
        volatileTranscript = snapshot.volatileText
        recentRecognition = snapshot.recentText
        let previousID = currentSegmentID
        let previousPromptID = promptSegmentID
        _ = matcher?.consume(snapshot)
        currentCandidate = matcher?.lastCandidate
        if let currentSegmentID, currentSegmentID != previousID {
            recordCursorChange(reason: currentCandidate?.reason ?? "自动定位")
        }
        if previousID != currentSegmentID || previousPromptID != promptSegmentID { persistSession() }
    }

    private func recordCursorChange(reason: String) {
        guard let currentSegmentID else { return }
        cursorHistory.append(CursorChange(segmentID: currentSegmentID, reason: reason))
        if cursorHistory.count > 5 { cursorHistory.removeFirst(cursorHistory.count - 5) }
    }

    private func clearTranscriptDisplay() {
        finalTranscript = ""
        volatileTranscript = ""
        recentRecognition = ""
        latestRecognitionEvent = nil
        latestRecognitionReceivedAt = nil
        currentCandidate = nil
    }

    private func readableMessage(_ error: Error) -> String {
        if let error = error as? LocalizedError, let description = error.errorDescription { return description }
        return error.localizedDescription
    }

    private func streamFinished(sessionID: UUID) async {
        guard activeSessionID == sessionID else { return }
        streamTask = nil
        activeSessionID = nil
        if engine.status.phase == .listening { await engine.stop() }
        engineStatus = engine.status
    }

    private func streamFailed(_ error: Error, sessionID: UUID) async {
        guard activeSessionID == sessionID else { return }
        errorMessage = readableMessage(error)
        streamTask = nil
        activeSessionID = nil
        await engine.stop()
        engineStatus = engine.status
    }
}
