import Foundation
import TeleprompterPresentation
import TeleprompterSpeech

@MainActor
func runScriptLibraryTests() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appendingPathComponent("session.json")
    let store = FileReadingSessionStore(url: url)
    let text = "第一句话介绍今天的主题。第二句话说明具体方法。第三句话总结操作过程。"
    try store.save(ReadingSession(text: text, currentSegmentID: 1, promptSegmentID: 2))
    let vm = ProbeViewModel(engine: FakeSpeechRecognitionEngine(), sessionStore: store)
    let first = vm.activeDocumentID!
    try checkEqual(vm.documents.count, 1, "legacy draft migrates exactly once")
    try checkEqual(vm.scriptText, text, "legacy text survives library migration")
    try checkEqual(vm.promptSegmentID, 2, "migration preserves anticipated prompt")
    try checkEqual(await vm.createDocument(), true, "new document commits successfully")
    let second = vm.activeDocumentID!
    _ = vm.setScriptText("另外一篇稿件讲不同的事情。后面还有新的内容。")
    _ = vm.renameDocument(second, title: "第二篇")
    await vm.selectSegment(1)
    try checkEqual(await vm.selectDocument(first), true, "switch back to original document")
    try checkEqual(vm.currentSegmentID, 1, "each document keeps actual cursor")
    try checkEqual(vm.promptSegmentID, 2, "each document keeps anticipated cursor")
    let reopened = ProbeViewModel(engine: FakeSpeechRecognitionEngine(), sessionStore: store)
    try checkEqual(reopened.documents.count, 2, "library survives reopening without duplicate migration")
    try checkEqual(reopened.activeDocumentID, first, "active document survives reopening")
    _ = await reopened.selectDocument(second)
    try checkEqual(reopened.activeDocumentTitle, "第二篇", "renamed title persists")
    try checkEqual(reopened.currentSegmentID, 1, "other document cursor survives reopening")
    try checkEqual(await reopened.deleteDocument(first), true, "inactive document can be deleted")
    try checkEqual(reopened.activeDocumentID, second, "deleting inactive draft preserves current draft")
    try checkEqual(await reopened.deleteDocument(second), true, "last document can be deleted")
    let empty = ProbeViewModel(engine: FakeSpeechRecognitionEngine(), sessionStore: store)
    try checkEqual(empty.documents.count, 1, "deleting last document leaves one usable blank draft")
    try checkEqual(empty.scriptText, "", "deleted last draft cannot return after restart")
    try checkTrue(!empty.renameDocument(empty.activeDocumentID!, title: "  "), "blank titles rejected")

    // Make the save path unwritable after loading. Destructive changes must not commit.
    let protected = ProbeViewModel(engine: FakeSpeechRecognitionEngine(), sessionStore: store)
    let protectedID = protected.activeDocumentID!
    try FileManager.default.removeItem(at: url)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    try checkEqual(await protected.deleteDocument(protectedID), false, "failed save blocks deletion")
    try checkEqual(protected.activeDocumentID, protectedID, "failed deletion retains active draft")
    try checkEqual(await protected.createDocument(), false, "failed save blocks changing to a new draft")
    try checkTrue(protected.storageWarning != nil, "storage failure visible in library")
}
