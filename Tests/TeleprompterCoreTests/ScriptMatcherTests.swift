import TeleprompterCore

private let sampleSegments = [
    "你有没有发现，越忙的时候，时间好像过得越快？",
    "早上刚坐下来，消息一条接一条，转眼就到了中午。",
    "我们以为自己做了很多事，回头一看，却很难说出完成了什么。",
]

private func segments(_ texts: [String]) -> [ScriptSegment] {
    texts.enumerated().map { ScriptSegment(id: $0.offset, originalText: $0.element) }
}

private func snapshot(_ text: String, revision: UInt64, final: Bool = true) -> TranscriptSnapshot {
    let normalized = TextNormalizer.normalize(text, recognition: true)
    return TranscriptSnapshot(
        finalText: final ? text : "",
        volatileText: final ? "" : text,
        recentText: normalized,
        evidenceRevision: revision
    )
}

func runScriptMatcherTests() throws {
    let second = segments(sampleSegments)[1]
    var exactMatcher = ScriptMatcher(segments: segments(sampleSegments), configuration: MatchConfiguration())
    try checkEqual(exactMatcher.consume(snapshot(second.originalText, revision: 1))?.segmentID, 1, "exact transcript selects second segment")

    var liveMatcher = ScriptMatcher(segments: segments(sampleSegments), configuration: MatchConfiguration())
    try checkEqual(liveMatcher.consume(snapshot(second.originalText, revision: 1, final: false))?.segmentID, 1,
                   "high-confidence volatile transcript advances before finalization")

    var currentMatcher = ScriptMatcher(segments: segments(sampleSegments))
    let first = TextNormalizer.normalize(sampleSegments[0], recognition: true)
    for (revision, fraction) in [0.55, 0.7, 1.0].enumerated() {
        _ = currentMatcher.consume(snapshot(String(first.prefix(Int(Double(first.count) * fraction))),
                                            revision: UInt64(revision + 1), final: false))
        try checkEqual(currentMatcher.currentSegmentID, 0, "spoken current sentence never advances to unspoken text")
    }

    var phoneticMatcher = ScriptMatcher(segments: segments(sampleSegments), configuration: MatchConfiguration())
    let phonetic = "早上刚坐下来消息一条接一条转眼就道了中午"
    let phoneticResult = phoneticMatcher.consume(snapshot(phonetic, revision: 1))
    try checkEqual(phoneticResult?.segmentID, 1, "Chinese homophone transcript selects second segment")

    var fillerMatcher = ScriptMatcher(segments: segments(sampleSegments), configuration: MatchConfiguration())
    let withFillers = "早上啊 那个 刚坐下来消息一条接一条转眼就到了中午"
    try checkEqual(fillerMatcher.consume(snapshot(withFillers, revision: 1))?.segmentID, 1, "recognized filler words are ignored")

    var omissionMatcher = ScriptMatcher(segments: segments(sampleSegments), configuration: MatchConfiguration())
    let omitted = "我们做了很多事回头一看很难说出完成了什么"
    try checkEqual(omissionMatcher.consume(snapshot(omitted, revision: 1))?.segmentID, 2, "missing words still match")

    let duplicateText = "我们继续前进"
    let repeatedSegments = segments(["我们继续前进，今天从这里开始", "内容继续展开说明", "接下来举一个例子", "再补充一点背景", "最后做个总结", "我们继续前进，继续把内容讲完"])
    var repeatedMatcher = ScriptMatcher(segments: repeatedSegments, configuration: MatchConfiguration())
    _ = repeatedMatcher.consume(snapshot(duplicateText, revision: 1))
    try checkEqual(repeatedMatcher.currentSegmentID, 0, "common repeated phrase cannot jump to a distant duplicate")
    try checkTrue(repeatedMatcher.consume(snapshot("我们继续", revision: 2)) == nil, "short common phrase creates no match")
    try checkEqual(repeatedMatcher.currentSegmentID, 0, "short phrase leaves cursor frozen")

    var offScriptMatcher = ScriptMatcher(segments: segments(sampleSegments), configuration: MatchConfiguration())
    _ = offScriptMatcher.consume(snapshot("今天阳光很好，我要去公园散步然后喝咖啡", revision: 1))
    _ = offScriptMatcher.consume(snapshot("我正在分享另一个完全无关的话题", revision: 2))
    _ = offScriptMatcher.consume(snapshot("这是没有出现在稿子里的即兴内容", revision: 3))
    try checkEqual(offScriptMatcher.currentSegmentID, 0, "off-script speech keeps the current segment")

    var skipMatcher = ScriptMatcher(segments: segments(sampleSegments), configuration: MatchConfiguration())
    try checkEqual(skipMatcher.consume(snapshot(sampleSegments[2], revision: 1))?.segmentID, 2, "forward jump to third segment is accepted")

    var rewriteMatcher = ScriptMatcher(segments: segments(sampleSegments), configuration: MatchConfiguration())
    _ = rewriteMatcher.consume(snapshot(sampleSegments[2], revision: 1))
    _ = rewriteMatcher.consume(snapshot(sampleSegments[1], revision: 2, final: false))
    try checkEqual(rewriteMatcher.currentSegmentID, 2, "volatile rewrite cannot move cursor backward")

    var lowScoreMatcher = ScriptMatcher(segments: segments(sampleSegments), configuration: MatchConfiguration())
    try checkTrue(lowScoreMatcher.consume(snapshot("不相关", revision: 1)) == nil, "low score match returns nil")
    try checkEqual(lowScoreMatcher.currentSegmentID, 0, "low score freezes cursor")

    var emptyMatcher = ScriptMatcher(segments: [], configuration: MatchConfiguration())
    try checkTrue(emptyMatcher.consume(snapshot("随便说点什么", revision: 1)) == nil, "empty script is safe")
    try checkEqual(emptyMatcher.currentSegmentID, nil, "empty script has no cursor")
    var emptyTranscriptMatcher = ScriptMatcher(segments: segments(sampleSegments), configuration: MatchConfiguration())
    try checkTrue(emptyTranscriptMatcher.consume(snapshot("", revision: 1)) == nil, "empty transcript is safe")

    let longScript = segments((0..<12).map { "第\($0)段拥有独特的口播内容与编号\($0)" })
    var boundedMatcher = ScriptMatcher(segments: longScript, configuration: MatchConfiguration())
    _ = boundedMatcher.consume(snapshot("第9段拥有独特的口播内容与编号9", revision: 1))
    try checkEqual(boundedMatcher.currentSegmentID, 0, "a single distant similar phrase waits for confirmation")

    var boundaryMatcher = ScriptMatcher(segments: segments(sampleSegments), configuration: MatchConfiguration())
    _ = boundaryMatcher.consume(snapshot(sampleSegments[0], revision: 1))
    try checkEqual(boundaryMatcher.currentSegmentID, 0, "matching first segment does not pre-advance across the combined candidate")
    let partialNext = sampleSegments[1] + " AI"
    _ = boundaryMatcher.consume(snapshot(partialNext, revision: 2))
    try checkEqual(boundaryMatcher.currentSegmentID, 1, "a combined candidate only advances through words supported by transcript")

    var hysteresisConfiguration = MatchConfiguration()
    hysteresisConfiguration.highConfidence = 1.01
    var hysteresisMatcher = ScriptMatcher(segments: segments(sampleSegments), configuration: hysteresisConfiguration)
    let medium = snapshot(String(TextNormalizer.normalize(sampleSegments[1], recognition: true).prefix(14)), revision: 1, final: false)
    try checkTrue(hysteresisMatcher.consume(medium) == nil, "medium score waits for confirmation")
    try checkEqual(hysteresisMatcher.currentSegmentID, 0, "one medium hit does not move cursor")
    let confirmed = snapshot(sampleSegments[1], revision: 2)
    try checkEqual(hysteresisMatcher.consume(confirmed)?.segmentID, 1, "additional words confirm medium score")
    try checkTrue(hysteresisMatcher.consume(confirmed) == nil, "duplicate evidence is ignored")
}
