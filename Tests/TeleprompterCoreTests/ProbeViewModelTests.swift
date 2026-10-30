import Foundation
import TeleprompterCore
import TeleprompterPresentation
import TeleprompterSpeech

private let probeTestScript = "你有没有发现，越忙的时候，时间好像过得越快？早上刚坐下来，消息一条接一条，转眼就到了中午。我们以为自己做了很多事，回头一看，却很难说出完成了什么。"
private let probeFirstSegment = "你有没有发现，越忙的时候，时间好像过得越快？"
private let probeSecondSegment = "早上刚坐下来，消息一条接一条，转眼就到了中午。"

private func recognizedPrefix(_ text: String, coverage: Double = 0.7) -> String {
    let normalized = TextNormalizer.normalize(text, recognition: true)
    let length = Int((Double(normalized.count) * coverage).rounded(.up))
    return String(normalized.prefix(length))
}

@MainActor
func runSpeechAndViewModelTests() async throws {
    let engine = FakeSpeechRecognitionEngine()
    let viewModel = ProbeViewModel(engine: engine)
    try checkTrue(viewModel.setScriptText(probeTestScript), "script can be edited while stopped")
    try checkEqual(viewModel.segments.count, 3, "editing the script segments it automatically")
    try checkEqual(engine.prepareCount, 0, "model preparation waits until the user starts following")

    await viewModel.start()
    let firstSession = engine.startSessions.last
    try checkEqual(engine.prepareCount, 1, "start prepares a missing model automatically")
    try checkEqual(engine.status.modelState, .installed, "automatic model preparation succeeds")
    try checkEqual(engine.startCount, 1, "first start creates one session")
    try checkTrue(viewModel.isListening, "view model reports active listening")
    await viewModel.start()
    try checkEqual(engine.startCount, 1, "repeated start does not create another session")

    let staleEvent = RecognitionEvent(sessionID: UUID(), revision: 1, audioStart: 0, audioEnd: 2,
                                      text: "大脑要重新找回刚才的思路", stability: .final)
    engine.send(staleEvent, through: firstSession)
    try await waitUntil("stale event reached view model") { viewModel.receivedEventCount == 1 }
    try checkEqual(viewModel.currentSegmentID, 0, "stale session cannot move cursor")

    let rawPreviewEvent = RecognitionEvent(sessionID: firstSession!, revision: 2, audioStart: 1, audioEnd: 1,
                                          text: "识别器原始预览", stability: .volatile)
    engine.send(rawPreviewEvent, through: firstSession)
    try await waitUntil("raw recognition preview is surfaced") { viewModel.latestRecognitionEvent == rawPreviewEvent }
    try checkEqual(viewModel.recentRecognition, "", "raw recognition is visible even if matching rejects its audio range")
    try checkTrue(viewModel.latestRecognitionReceivedAt != nil, "raw recognition records when it reached the UI")

    let partialEvent = RecognitionEvent(sessionID: firstSession!, revision: 3, audioStart: 0, audioEnd: 3,
                                        text: recognizedPrefix(probeFirstSegment), stability: .volatile)
    engine.send(partialEvent, through: firstSession)
    try await waitUntil("partial current speech is received") { viewModel.latestRecognitionEvent == partialEvent }
    try checkEqual(viewModel.currentSegmentID, 0, "highlight stays on the sentence actually being spoken at 70 percent")
    try checkEqual(viewModel.latestRecognitionEvent, partialEvent, "live panel retains the newest raw volatile event")
    try checkEqual(viewModel.recentRecognition, recognizedPrefix(probeFirstSegment), "recognized text is normalized for matching")

    let firstFinalEvent = RecognitionEvent(sessionID: firstSession!, revision: 4, audioStart: 0, audioEnd: 3,
                                           text: probeFirstSegment, stability: .final)
    engine.send(firstFinalEvent, through: firstSession)
    try await waitUntil("first sentence finalizes after early advancement") { viewModel.latestRecognitionEvent == firstFinalEvent }
    try checkEqual(viewModel.currentSegmentID, 0, "sentence completion preserves recognition anchor")
    try checkEqual(viewModel.promptSegmentID, 1, "UI offers next sentence without waiting for next recognized words")

    let secondPartialEvent = RecognitionEvent(sessionID: firstSession!, revision: 5, audioStart: 3, audioEnd: 6,
                                              text: recognizedPrefix(probeSecondSegment), stability: .volatile)
    engine.send(secondPartialEvent, through: firstSession)
    try await waitUntil("second volatile event reaches the live panel") { viewModel.latestRecognitionEvent == secondPartialEvent }
    try checkEqual(viewModel.currentSegmentID, 1, "second sentence is highlighted only when its words arrive")
    try checkEqual(viewModel.latestRecognitionEvent, secondPartialEvent, "live panel retains the newest volatile event")

    let finalEvent = RecognitionEvent(sessionID: firstSession!, revision: 6, audioStart: 3, audioEnd: 6,
                                      text: probeSecondSegment, stability: .final)
    engine.send(finalEvent, through: firstSession)
    try await waitUntil("finalized event reaches the live panel") { viewModel.latestRecognitionEvent == finalEvent }
    try checkEqual(viewModel.currentSegmentID, 1, "second completion preserves recognition anchor")
    try checkEqual(viewModel.promptSegmentID, 2, "next prompt is exposed through view model on completion")
    try checkEqual(viewModel.latestRecognitionEvent, finalEvent, "live panel retains the newest raw final event")

    let rollingEngine = FakeSpeechRecognitionEngine()
    let rollingVM = ProbeViewModel(engine: rollingEngine)
    try checkTrue(rollingVM.setScriptText(probeTestScript), "rolling recognition test script is accepted")
    await rollingVM.start()
    let rollingSession = rollingEngine.startSessions.last!
    let normalizedFirst = TextNormalizer.normalize(probeFirstSegment, recognition: true)
    let firstAudioPiece = String(normalizedFirst.prefix(6))
    let secondAudioPiece = String(normalizedFirst.dropFirst(6).prefix(3))
    let thirdAudioPiece = String(normalizedFirst.dropFirst(9).prefix(3))
    rollingEngine.send(RecognitionEvent(sessionID: rollingSession, revision: 1, audioStart: 0, audioEnd: 1,
                                        text: firstAudioPiece, stability: .final))
    try await waitUntil("first finalized audio range is accumulated") { rollingVM.receivedEventCount == 1 }
    rollingEngine.send(RecognitionEvent(sessionID: rollingSession, revision: 2, audioStart: 1, audioEnd: 2,
                                        text: secondAudioPiece, stability: .final))
    try await waitUntil("second finalized audio range is accumulated") { rollingVM.receivedEventCount == 2 }
    let rollingVolatileEvent = RecognitionEvent(sessionID: rollingSession, revision: 3, audioStart: 2, audioEnd: 3,
                                                text: thirdAudioPiece, stability: .volatile)
    rollingEngine.send(rollingVolatileEvent)
    try await waitUntil("latest volatile range is accumulated") { rollingVM.latestRecognitionEvent == rollingVolatileEvent }
    try checkEqual(rollingVM.currentSegmentID, 0,
                   "fragmented current speech accumulates without highlighting unspoken text")
    await rollingVM.stop()

    await viewModel.selectSegment(2)
    let secondSession = engine.startSessions.last
    try checkEqual(engine.stopCount, 1, "manual selection stops the old session")
    try checkEqual(engine.startCount, 2, "manual selection starts a fresh session")
    try checkTrue(firstSession != secondSession, "manual selection uses a new session identifier")
    try checkEqual(viewModel.currentSegmentID, 2, "manual selection retains requested segment")

    await viewModel.stop()
    try checkTrue(!viewModel.isListening, "stop releases listening state")
    await viewModel.stop()
    try checkEqual(engine.stopCount, 3, "repeated stop is safe")
    try checkTrue(viewModel.setScriptText("停止后可以编辑这份口播稿"), "script can be edited after stop")

    let failingPrepareEngine = FakeSpeechRecognitionEngine()
    failingPrepareEngine.prepareFailureMessage = "中文模型不可用"
    let failingPrepareVM = ProbeViewModel(engine: failingPrepareEngine)
    await failingPrepareVM.prepareModel()
    try checkEqual(failingPrepareVM.errorMessage, "中文模型不可用", "prepare error is human readable")

    let failingStartEngine = FakeSpeechRecognitionEngine()
    let failingStartVM = ProbeViewModel(engine: failingStartEngine)
    try checkTrue(failingStartVM.setScriptText(probeTestScript), "failure test script is accepted")
    failingStartEngine.startFailureMessage = "麦克风忙碌"
    await failingStartVM.start()
    try checkEqual(failingStartEngine.prepareCount, 1, "start prepares the model before opening the microphone")
    try checkEqual(failingStartVM.errorMessage, "麦克风忙碌", "start error is human readable")
    try checkTrue(!failingStartVM.isListening, "failed start leaves engine stopped")

    let autoPrepareFailureEngine = FakeSpeechRecognitionEngine()
    autoPrepareFailureEngine.prepareFailureMessage = "中文模型不可用"
    let autoPrepareFailureVM = ProbeViewModel(engine: autoPrepareFailureEngine)
    try checkTrue(autoPrepareFailureVM.setScriptText(probeTestScript), "auto-prepare failure script is accepted")
    await autoPrepareFailureVM.start()
    try checkEqual(autoPrepareFailureVM.errorMessage, "中文模型不可用", "automatic preparation error is human readable")
    try checkEqual(autoPrepareFailureEngine.startCount, 0, "recognition does not start when model preparation fails")

    let emptyEngine = FakeSpeechRecognitionEngine()
    let emptyVM = ProbeViewModel(engine: emptyEngine)
    await emptyVM.prepareModel()
    await emptyVM.start()
    try checkEqual(emptyEngine.startCount, 0, "empty script cannot start engine")

    let preparingEngine = FakeSpeechRecognitionEngine()
    preparingEngine.preparationDelay = .milliseconds(100)
    let preparingVM = ProbeViewModel(engine: preparingEngine)
    let preparationTask = Task { await preparingVM.prepareModel() }
    try await waitUntil("model preparation begins") { preparingVM.isPreparing }
    await preparingVM.stop()
    try checkTrue(preparingVM.isPreparing, "stop does not pretend to cancel an uninterruptible asset install")
    try checkEqual(preparingEngine.stopCount, 0, "stop does not tear down the engine during model installation")
    await preparationTask.value
    try checkTrue(!preparingVM.isPreparing && preparingVM.engineStatus.modelState == .installed,
                  "view model receives final status after model preparation")
}

@MainActor
func runFakeDemoTests() async throws {
    let engine = FakeSpeechRecognitionEngine()
    engine.configureDemo(texts: ["这是纯合成的演示稿件段落。"])
    try await engine.prepare(locale: Locale(identifier: "zh-CN"))
    let sessionID = UUID()
    let stream = try await engine.start(sessionID: sessionID)
    var events: [RecognitionEvent] = []
    for try await event in stream {
        events.append(event)
        if events.count == 3 { break }
    }
    await engine.stop()

    try checkEqual(events.count, 3, "demo emits volatile revisions and one final")
    try checkEqual(events.map(\.stability), [.volatile, .volatile, .final], "demo shows volatile-to-final updates")
    try checkEqual(Set(events.map(\.sessionID)), Set([sessionID]), "demo events belong to the active session")
    try checkTrue(events.allSatisfy { $0.audioStart == events[0].audioStart && $0.audioEnd == events[0].audioEnd }, "demo revisions replace one audio range")
    try checkTrue(engine.status.microphoneAuthorization == .notDetermined, "demo does not request or claim microphone permission")
    try checkEqual(engine.stopCount, 1, "demo stop releases its synthetic session")
    try checkEqual(events.map(\.text).last, "这是纯合成的演示稿件段落。", "demo ends with the complete scripted line")
}

@MainActor
private func waitUntil(_ description: String, condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(2)
    while !condition(), ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(1))
    }
    try checkTrue(condition(), "timed out waiting for \(description)")
}

@MainActor
func runSentenceLeadViewModelTests() async throws {
    let engine = FakeSpeechRecognitionEngine()
    let vm = ProbeViewModel(engine: engine)
    _ = vm.setScriptText(probeTestScript)
    await vm.start()
    let session = engine.startSessions.last!
    let first = vm.segments[0].normalizedText
    let nearEnd = String(first.dropLast(4))
    engine.send(RecognitionEvent(sessionID: session, revision: 1, audioStart: 0, audioEnd: 3,
                                 text: nearEnd, stability: .volatile))
    try await waitUntil("first partial speech reaches reading UI") { vm.receivedEventCount == 1 }
    try checkEqual(vm.promptSegmentID, 1, "reading UI offers next sentence before first sentence completes")
    try checkEqual(vm.currentSegmentID, 0, "recognizer still anchors current sentence during lead")
    engine.send(RecognitionEvent(sessionID: session, revision: 2, audioStart: 0, audioEnd: 4,
                                 text: first, stability: .final))
    try await waitUntil("sentence finalization reaches reading UI") { vm.receivedEventCount == 2 }
    try checkEqual(vm.promptSegmentID, 1, "sentence finalization cannot undo lead or skip again")
    let second = vm.segments[1].normalizedText
    engine.send(RecognitionEvent(sessionID: session, revision: 3, audioStart: 4, audioEnd: 7,
                                 text: String(second.dropLast(4)), stability: .volatile))
    try await waitUntil("next sentence reaches its final four characters") { vm.receivedEventCount == 3 }
    try checkEqual(vm.currentSegmentID, 1, "recognition moves to actually spoken second sentence")
    try checkEqual(vm.promptSegmentID, 2, "continuous reading offers third sentence without waiting for second completion")
    await vm.stop()
}
