import TeleprompterCore

func runAdjacentHandoffTests() throws {
    let first = "今天先把准备工作讲清楚然后我们继续讨论具体的操作步骤"
    let next = "打开窗户让清晨的新鲜空气进来然后给桌上的绿植浇水再开始今天的工作"
    let texts = [first, next, "书架上放着几本关于历史和地理的书籍"]
    func matcher(_ lines: [String] = texts) -> ScriptMatcher {
        ScriptMatcher(segments: lines.enumerated().map { ScriptSegment(id: $0.offset, originalText: $0.element) })
    }
    func snap(_ recent: String, _ latest: String, _ revision: UInt64) -> TranscriptSnapshot {
        TranscriptSnapshot(finalText: "", volatileText: latest, recentText: recent,
                           evidenceRevision: revision, latestText: latest, latestAudioEnd: Double(revision))
    }
    var fast = matcher()
    _ = fast.consume(snap(first, first, 1))
    try checkEqual(fast.currentSegmentID, 0, "completed sentence does not predict next highlight")
    _ = fast.consume(snap(first + "打开窗户", "打开窗户", 2))
    try checkEqual(fast.currentSegmentID, 1, "four distinctive next-sentence words immediately switch a tracked boundary")

    var fragments = matcher()
    _ = fragments.consume(snap(first, first, 1))
    _ = fragments.consume(snap(first + "打开", "打开", 2))
    try checkEqual(fragments.currentSegmentID, 0, "two words are insufficient at a boundary")
    _ = fragments.consume(snap(first + "打开窗户", "窗户", 3))
    try checkEqual(fragments.currentSegmentID, 1, "short audio fragments combine for immediate boundary handoff")

    var isolated = matcher()
    _ = isolated.consume(snap("打开窗户", "打开窗户", 1))
    try checkEqual(isolated.currentSegmentID, 0, "short phrase without current tracking anchor cannot jump")

    var aside = matcher()
    _ = aside.consume(snap(first, first, 1))
    let unrelated = "顺便讲一下昨天我和朋友出去吃饭时候发生的趣事"
    _ = aside.consume(snap(first + unrelated, unrelated, 2))
    _ = aside.consume(snap(first + unrelated + "打开窗户", "打开窗户", 3))
    try checkEqual(aside.currentSegmentID, 0, "after a digression short common speech cannot use stale boundary anchor")

    var repeated = matcher([first + "打开窗户以后还有别的事情", next, texts[2]])
    _ = repeated.consume(snap(first + "打开窗户以后还有别的事情", first + "打开窗户以后还有别的事情", 1))
    _ = repeated.consume(snap("打开窗户", "打开窗户", 2))
    try checkEqual(repeated.currentSegmentID, 0, "prefix shared with current sentence waits for more evidence")

    var distant = matcher([first, next, "打开窗户之后需要检查纱窗是否关紧"])
    _ = distant.consume(snap(first, first, 1))
    _ = distant.consume(snap(first + "打开窗户", "打开窗户", 2))
    try checkEqual(distant.currentSegmentID, 0, "prefix shared elsewhere cannot fast jump")
}

func runPacePromptTests() throws {
    let first = "今天先把准备工作讲清楚然后我们继续讨论具体的操作步骤"
    let segments = [first, "打开窗户让清晨的新鲜空气进来然后开始工作", "最后我们收拾桌面准备休息"].enumerated().map {
        ScriptSegment(id: $0.offset, originalText: $0.element)
    }
    func snap(_ count: Int, _ time: Double, _ revision: UInt64) -> TranscriptSnapshot {
        let text = String(first.prefix(count))
        return TranscriptSnapshot(finalText: "", volatileText: text, recentText: text,
                                  evidenceRevision: revision, latestText: text, latestAudioEnd: time)
    }
    var fast = ScriptMatcher(segments: segments)
    _ = fast.consume(snap(18, 3, 1))
    try checkEqual(fast.promptSegmentID, 0, "single sample cannot invent a speaking pace")
    _ = fast.consume(snap(23, 4, 2))
    try checkEqual(fast.promptSegmentID, 1, "five characters per second offers next sentence before current ends")
    try checkEqual(fast.currentSegmentID, 0, "anticipation preserves actual recognized position")
    _ = fast.consume(snap(first.count, 5, 3))
    try checkEqual(fast.promptSegmentID, 1, "finishing current cannot cascade two sentences ahead")
    _ = fast.consume(snap(first.count, 6, 4))
    try checkEqual(fast.promptSegmentID, 1, "duplicate finalization does not cascade")
    fast.reset(to: 0)
    try checkEqual(fast.promptSegmentID, 0, "manual navigation clears anticipation")

    var slow = ScriptMatcher(segments: segments)
    _ = slow.consume(snap(21, 3, 1))
    _ = slow.consume(snap(23, 5, 2))
    try checkEqual(slow.promptSegmentID, 1, "slow delivery still gets the default final-four-character lead")
    _ = slow.consume(snap(25, 7, 3))
    try checkEqual(slow.promptSegmentID, 1, "slow delivery keeps next prompt ready through sentence end")
    _ = slow.consume(snap(first.count, 8, 4))
    try checkEqual(slow.promptSegmentID, 1, "completed slow sentence offers next prompt without waiting for its words")

    var paused = ScriptMatcher(segments: segments)
    _ = paused.consume(snap(18, 3, 1))
    _ = paused.consume(snap(23, 8, 2))
    try checkEqual(paused.promptSegmentID, 1, "new speech near sentence end leads even after a pause invalidates rhythm")
    var aside = ScriptMatcher(segments: segments)
    _ = aside.consume(snap(18, 3, 1))
    _ = aside.consume(snap(23, 4, 2))
    _ = aside.consume(TranscriptSnapshot(finalText: "", volatileText: "昨天朋友邀请我去海边吃饭", recentText: "昨天朋友邀请我去海边吃饭", evidenceRevision: 3, latestAudioEnd: 5))
    try checkEqual(aside.promptSegmentID, 1, "digression holds visible prompt without further prediction")
    _ = aside.consume(snap(24, 6, 4))
    try checkEqual(aside.promptSegmentID, 1, "return from aside retains visible prompt while reestablishing pace")
}

func runPromptStabilityTests() throws {
    let first = "今天先把准备工作讲清楚然后我们继续讨论具体的操作步骤"
    let next = "打开窗户让清晨的新鲜空气进来然后给桌上的绿植浇水"
    let segments = [first, next].enumerated().map { ScriptSegment(id: $0.offset, originalText: $0.element) }
    func snapshot(_ text: String, _ time: Double, _ revision: UInt64) -> TranscriptSnapshot {
        TranscriptSnapshot(finalText: "", volatileText: text, recentText: text,
                           evidenceRevision: revision, latestText: text, latestAudioEnd: time)
    }
    func leading() -> ScriptMatcher {
        var matcher = ScriptMatcher(segments: segments)
        _ = matcher.consume(snapshot(String(first.prefix(18)), 3, 1))
        _ = matcher.consume(snapshot(String(first.prefix(23)), 4, 2))
        return matcher
    }
    var uncertain = leading()
    try checkEqual(uncertain.promptSegmentID, 1, "regression starts with next prompt already visible")
    _ = uncertain.consume(snapshot("嗯刚才这个事情呢", 5, 3))
    try checkEqual(uncertain.promptSegmentID, 1, "uncertain recognition must not pull visible prompt backward")
    try checkEqual(uncertain.currentSegmentID, 0, "holding prompt does not invent spoken progress")
    _ = uncertain.consume(snapshot(String(first.prefix(24)), 6, 4))
    try checkEqual(uncertain.promptSegmentID, 1, "returning evidence does not flicker back to previous sentence")

    var revision = leading()
    _ = revision.consume(snapshot(String(first.prefix(21)), 4, 3))
    try checkEqual(revision.promptSegmentID, 1, "shorter ASR revision cannot undo anticipatory handoff")
    _ = revision.consume(snapshot(String(first.prefix(24)), 8, 4))
    try checkEqual(revision.promptSegmentID, 1, "pause invalidates pace without moving prompt backward")
    _ = revision.consume(snapshot(first, 9, 5))
    _ = revision.consume(snapshot(first + "打开窗户", 10, 6))
    try checkEqual(revision.currentSegmentID, 1, "recognition catches up to the visible next sentence")
    try checkEqual(revision.promptSegmentID, 1, "handoff to actual next speech is visually stable")

    var reread = leading()
    _ = reread.consume(snapshot(String(first.prefix(10)), 5, 3))
    try checkEqual(reread.promptSegmentID, 1, "one early-sentence hypothesis cannot rewind prompt")
    _ = reread.consume(snapshot(String(first.prefix(12)), 5, 4))
    try checkEqual(reread.promptSegmentID, 1, "same audio interval correction is not a second reread")
    _ = reread.consume(snapshot(String(first.prefix(16)), 6, 5))
    try checkEqual(reread.promptSegmentID, 0, "fresh advancing speech near beginning confirms intentional reread")
    reread.reset(to: 1)
    reread.reset(to: 0)
    try checkEqual(reread.promptSegmentID, 0, "manual previous remains available")
}

func runSentenceEndLeadTests() throws {
    let text = "今天先把准备工作讲清楚然后我们继续讨论具体的操作步骤"
    let segments = [text, "打开窗户让清晨的新鲜空气进来然后开始工作"].enumerated().map { ScriptSegment(id: $0.offset, originalText: $0.element) }
    func snapshot(_ count: Int, _ revision: UInt64, _ time: Double? = nil) -> TranscriptSnapshot {
        let spoken = String(text.prefix(count))
        return TranscriptSnapshot(finalText: "", volatileText: spoken, recentText: spoken,
                                  evidenceRevision: revision, latestText: spoken, latestAudioEnd: time)
    }
    var fresh = ScriptMatcher(segments: segments)
    _ = fresh.consume(snapshot(text.count - 4, 1))
    try checkEqual(fresh.promptSegmentID, 1, "last four characters offer next prompt even without a pace sample or timestamp")
    try checkEqual(fresh.currentSegmentID, 0, "default lead does not invent spoken progress")
    var middle = ScriptMatcher(segments: segments)
    _ = middle.consume(snapshot(text.count - 8, 1, 3))
    try checkEqual(middle.promptSegmentID, 0, "middle of sentence cannot trigger default lead")
    _ = middle.consume(TranscriptSnapshot(finalText: "", volatileText: "昨天朋友请我吃饭", recentText: "昨天朋友请我吃饭", evidenceRevision: 2, latestAudioEnd: 4))
    _ = middle.consume(snapshot(text.count - 3, 3, 8))
    try checkEqual(middle.promptSegmentID, 1, "return near sentence end leads despite discarded pace")
    var last = ScriptMatcher(segments: [segments[0]])
    _ = last.consume(snapshot(text.count - 3, 1, 2))
    try checkEqual(last.promptSegmentID, 0, "last sentence cannot lead beyond script")
}
