import Foundation
import TeleprompterCore

func runRecoveryTests() throws {
    let lines = [
        "我们每天接收很多信息却很少认真思考自己的生活",
        "早晨打开窗户能看到院子里面刚刚盛开的鲜花",
        "厨房里的面包已经烤好现在可以准备早餐",
        "把手机放进抽屉然后专心整理今天需要完成的工作",
        "城市里的公交车沿着河岸缓缓驶向火车站",
        "孩子们放学以后喜欢在操场踢球和跑步",
        "山顶的积雪在春天慢慢融化汇成清澈的小溪",
        "音乐会将在周六晚上开始请提前购买门票",
        "图书馆二楼收藏了很多关于天文学的书籍",
        "海边的渔民每天清晨出海傍晚带着收获回来",
        "真正重要的不是看过多少内容而是你从中带走了什么",
        "试着把注意力放回眼前一次只做好一件小事",
        "当你愿意慢下来表达反而会变得更加清楚"
    ]
    let segments = lines.enumerated().map { ScriptSegment(id: $0.offset, originalText: $0.element) }
    func sample(_ text: String, _ revision: UInt64) -> TranscriptSnapshot {
        TranscriptSnapshot(finalText: "", volatileText: text, recentText: text, evidenceRevision: revision)
    }
    var matcher = ScriptMatcher(segments: segments)
    _ = matcher.consume(sample("今天临时插一句我刚刚想起了朋友昨天讲的趣事", 1))
    try checkEqual(matcher.currentSegmentID, 0, "digression keeps position stable")
    _ = matcher.consume(sample(String(lines[10].prefix(16)), 2))
    try checkEqual(matcher.currentSegmentID, 0, "one distant candidate cannot jump")
    _ = matcher.consume(sample(String(lines[10].prefix(24)), 3))
    try checkEqual(matcher.currentSegmentID, 10, "return to script reacquires beyond eight segments")
    _ = matcher.consume(sample(String(lines[1].prefix(16)), 4))
    try checkEqual(matcher.currentSegmentID, 10, "first backward candidate waits")
    _ = matcher.consume(sample(lines[1], 5))
    try checkEqual(matcher.currentSegmentID, 1, "sustained rereading reacquires far earlier paragraph")

    var rolling = ScriptMatcher(segments: segments)
    let aside = "这里顺便说个题外话昨天朋友给我打电话聊到周末旅行计划"
    _ = rolling.consume(sample(aside + String(lines[11].prefix(16)), 1))
    _ = rolling.consume(sample(aside + lines[11], 2))
    try checkEqual(rolling.currentSegmentID, 11, "recent suffix returns to script despite unrelated accumulated context")

    var duplicates = ScriptMatcher(segments: segments + [ScriptSegment(id: 13, originalText: lines[10])])
    _ = duplicates.consume(sample(String(lines[10].prefix(16)), 1))
    _ = duplicates.consume(sample(lines[10], 2))
    try checkEqual(duplicates.currentSegmentID, 0, "identical distant passages remain ambiguous")

    // Identical finalization must not be counted as a second independent return cue.
    var same = ScriptMatcher(segments: segments)
    _ = same.consume(sample(String(lines[10].prefix(16)), 1))
    _ = same.consume(sample(String(lines[10].prefix(16)), 2))
    try checkEqual(same.currentSegmentID, 0, "duplicate text does not confirm a remote jump")
    _ = same.consume(sample("完全离开稿子聊一聊午餐准备吃什么菜", 3))
    _ = same.consume(sample(lines[10], 4))
    try checkEqual(same.currentSegmentID, 0, "digression clears pending remote evidence")

    var ordered = ScriptMatcher(segments: segments)
    _ = ordered.consume(TranscriptSnapshot(finalText: "", volatileText: lines[1], recentText: lines[1],
                                           evidenceRevision: 1, latestText: lines[1], latestAudioEnd: 10))
    try checkEqual(ordered.currentSegmentID, 1, "fresh audio selects its actual sentence")
    _ = ordered.consume(TranscriptSnapshot(finalText: lines[0], volatileText: "", recentText: lines[0],
                                           evidenceRevision: 2, latestText: lines[0], latestAudioEnd: 5))
    _ = ordered.consume(TranscriptSnapshot(finalText: lines[0], volatileText: "", recentText: lines[0],
                                           evidenceRevision: 3, latestText: lines[0], latestAudioEnd: 6))
    try checkEqual(ordered.currentSegmentID, 1, "late final blocks never rewind newer speech")

    // Realistic growing ASR stream, including accumulated old script + an aside.
    var mixed = ScriptMatcher(segments: segments)
    _ = mixed.consume(sample(lines[0], 1))
    _ = mixed.consume(sample(lines[0] + aside, 2))
    try checkEqual(mixed.currentSegmentID, 0, "old script mixed with aside stays stable")
    _ = mixed.consume(sample(lines[0] + aside + String(lines[10].prefix(16)), 3))
    _ = mixed.consume(sample(lines[0] + aside + lines[10], 4))
    try checkEqual(mixed.currentSegmentID, 10, "mixed rolling transcript reacquires after aside")

    // Long-script timing is reported separately; it is not an ASR accuracy claim.
    let longSegments = (0..<300).map { index in
        ScriptSegment(id: index, originalText: lines[index % lines.count] + "第\(index)次练习")
    }
    var large = ScriptMatcher(segments: longSegments)
    let clock = ContinuousClock()
    let began = clock.now
    for revision in 1...10 { _ = large.consume(sample(aside + String(repeating: "啊", count: revision), UInt64(revision))) }
    let elapsed = began.duration(to: clock.now)
    print("BENCH 300 segments / 10 off-script updates: \(elapsed)")
    try checkEqual(large.currentSegmentID, 0, "long script remains stable during unrelated speech")
    let matchingBegan = clock.now
    for revision in 11...20 { _ = large.consume(sample(String(lines[10].prefix(revision)), UInt64(revision))) }
    print("BENCH 300 segments / 10 matching updates: \(matchingBegan.duration(to: clock.now))")
}
