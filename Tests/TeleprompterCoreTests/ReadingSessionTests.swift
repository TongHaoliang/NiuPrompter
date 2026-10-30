import Foundation
import TeleprompterCore
import TeleprompterPresentation
import TeleprompterSpeech

@MainActor
func runReadingSessionTests() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("session.json")
    let store = FileReadingSessionStore(url: url)
    let text = "清晨我们沿着河边散步看见远处山顶升起金色的太阳。厨房里面刚刚烤好的面包散发着香味大家准备吃早餐。城市图书馆收藏了许多关于天文学和历史研究的书籍。"
    let vm = ProbeViewModel(engine: FakeSpeechRecognitionEngine(), sessionStore: store)
    try checkEqual(vm.scriptText, "", "first install has no invented saved draft")
    _ = vm.setScriptText(text)
    await vm.selectSegment(1)
    let reopened = ProbeViewModel(engine: FakeSpeechRecognitionEngine(), sessionStore: FileReadingSessionStore(url: url))
    try checkEqual(reopened.scriptText, text, "draft automatically survives a new view model and file store")
    try checkEqual(reopened.currentSegmentID, 1, "manual reading position survives reopening")
    try checkTrue(!reopened.isListening, "restoring draft never starts microphone")
    _ = reopened.setScriptText(text)
    try checkEqual(reopened.currentSegmentID, 1, "same text cannot reset reading position")
    let edited = "这是新增的开场白用来介绍今天想分享的话题。" + text
    _ = reopened.setScriptText(edited)
    try checkEqual(reopened.currentSegmentID, 2, "inserted paragraph retains unique current sentence")
    let editedAgain = ProbeViewModel(engine: FakeSpeechRecognitionEngine(), sessionStore: store)
    try checkEqual(editedAgain.currentSegmentID, 2, "remapped position is saved with edited text")
    _ = editedAgain.setScriptText("")
    let empty = ProbeViewModel(engine: FakeSpeechRecognitionEngine(), sessionStore: store)
    try checkEqual(empty.scriptText, "", "intentional empty draft persists instead of resurrecting old content")
    try checkEqual(empty.currentSegmentID, nil, "empty draft cannot restore a stale cursor")

    let engine = FakeSpeechRecognitionEngine()
    let speaking = ProbeViewModel(engine: engine, sessionStore: store)
    _ = speaking.setScriptText(text)
    await speaking.start()
    let session = engine.startSessions.last!
    let first = speaking.segments[0].normalizedText
    engine.send(RecognitionEvent(sessionID: session, revision: 1, audioStart: 0, audioEnd: 3,
                                 text: String(first.dropLast(4)), stability: .volatile))
    let deadline = ContinuousClock.now + .seconds(2)
    while speaking.receivedEventCount == 0, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(1)) }
    try checkEqual(speaking.promptSegmentID, 1, "spoken sentence produces anticipated prompt before saving")
    let restoredLead = ProbeViewModel(engine: FakeSpeechRecognitionEngine(), sessionStore: store)
    try checkEqual(restoredLead.currentSegmentID, 0, "restore keeps actual anchor separate from prompt")
    try checkEqual(restoredLead.promptSegmentID, 1, "anticipated prompt survives reopening")
    await speaking.stop()
    await speaking.start()
    try checkEqual(speaking.promptSegmentID, 1, "pause and restart do not pull the prompt backwards")
    await speaking.stop()
    await restoredLead.start()
    try checkEqual(restoredLead.promptSegmentID, 1, "start after restoring does not pull prompt backwards")
    await restoredLead.stop()

    let data = try Data(contentsOf: url)
    let json = String(decoding: data, as: UTF8.self)
    try checkTrue(!json.contains("volatileTranscript") && !json.contains("sessionID"), "session file does not store recognized speech or audio sessions")
    try Data("broken".utf8).write(to: url)
    let damaged = ProbeViewModel(engine: FakeSpeechRecognitionEngine(), sessionStore: store)
    try checkTrue(damaged.storageWarning != nil, "damaged saved draft produces visible warning")
    _ = damaged.setScriptText("这份新稿不能自动覆盖原来的损坏文件")
    try checkEqual(try Data(contentsOf: url), Data("broken".utf8), "load failure preserves original file for recovery")

    let blocked = directory.appendingPathComponent("not-a-directory")
    try Data("block".utf8).write(to: blocked)
    let failed = ProbeViewModel(engine: FakeSpeechRecognitionEngine(), sessionStore: FileReadingSessionStore(url: blocked.appendingPathComponent("session.json")))
    _ = failed.setScriptText(text)
    try checkEqual(failed.scriptText, text, "storage failure keeps current draft usable in memory")
    try checkTrue(failed.storageWarning != nil, "storage failure is never reported as successful save")
}
