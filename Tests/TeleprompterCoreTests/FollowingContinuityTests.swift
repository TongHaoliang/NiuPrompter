import Foundation
import TeleprompterCore

func runFollowingContinuityTests() throws {
    let lines = [
        "清晨我们沿着河边散步看见远处山顶升起金色的太阳",
        "厨房里面刚刚烤好的面包散发着香味大家准备吃早餐",
        "城市图书馆收藏了许多关于天文学和历史研究的书籍",
        "周末孩子们喜欢在操场踢足球也喜欢去海边捡贝壳"
    ]
    let segments = lines.enumerated().map { ScriptSegment(id: $0.offset, originalText: $0.element) }
    func sample(_ text: String, _ revision: UInt64, _ time: Double) -> TranscriptSnapshot {
        TranscriptSnapshot(finalText: "", volatileText: text, recentText: text,
                           evidenceRevision: revision, latestText: text, latestAudioEnd: time)
    }
    var paused = ScriptMatcher(segments: segments)
    _ = paused.consume(sample(String(lines[3].prefix(12)), 1, 2))
    _ = paused.consume(sample(String(lines[3].prefix(17)), 2, 62))
    try checkEqual(paused.currentSegmentID, 0, "return confirmation cannot combine evidence across a minute of silence")
    _ = paused.consume(sample(String(lines[3].prefix(23)), 3, 63))
    try checkEqual(paused.currentSegmentID, 3, "fresh sustained speech still reacquires after long pause")

    var revised = ScriptMatcher(segments: segments)
    _ = revised.consume(sample(String(lines[3].prefix(12)), 1, 2))
    _ = revised.consume(sample(String(lines[3].prefix(17)), 2, 2))
    try checkEqual(revised.currentSegmentID, 0, "two hypotheses of the same audio cannot confirm distant jump")
    _ = revised.consume(sample(String(lines[3].prefix(23)), 3, 3))
    try checkEqual(revised.currentSegmentID, 3, "new audio can confirm revised hypothesis")

    var lead = ScriptMatcher(segments: segments)
    _ = lead.consume(sample(String(lines[0].dropLast(4)), 1, 3))
    try checkEqual(lead.promptSegmentID, 1, "lead remains four characters before end")
    _ = lead.consume(sample("我先喝口水然后我们继续刚才的内容", 2, 63))
    try checkEqual(lead.currentSegmentID, 0, "aside after pause retains spoken anchor")
    try checkEqual(lead.promptSegmentID, 1, "aside cannot pull anticipated display backwards")
    _ = lead.consume(sample(String(lines[0].prefix(11)), 3, 65))
    _ = lead.consume(sample(String(lines[0].prefix(15)), 4, 66))
    try checkEqual(lead.promptSegmentID, 0, "genuine reread brings display back after aside")
    _ = lead.consume(sample(String(lines[0].dropLast(4)), 5, 68))
    try checkEqual(lead.promptSegmentID, 1, "reread still leads at sentence end")
}
