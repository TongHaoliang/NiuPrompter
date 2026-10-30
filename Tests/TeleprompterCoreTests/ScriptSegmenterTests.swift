import TeleprompterCore

func runScriptSegmenterTests() throws {
    let result = ScriptSegmenter.segment("第一句内容足够长。第二句内容也足够长？\n第三句内容还是足够长！")
    try checkEqual(result.map(\.originalText), ["第一句内容足够长。", "第二句内容也足够长？", "第三句内容还是足够长！"], "sentence and newline splitting")

    let source = "第一段内容用于展示并且这句话已经超过了四十二个可见字符，所以应该从这里拆开，第二段内容也足够长用于后续显示。"
    let longResult = ScriptSegmenter.segment(source)
    try checkEqual(longResult.count, 3, "long sentence split at comma boundaries")
    try checkTrue(longResult[0].originalText.hasSuffix("，"), "original separator retained")
    try checkEqual(longResult.map(\.originalText).joined(), source, "long source text retained")

    let shortMerged = ScriptSegmenter.segment("好。这里是一段足够长的完整口播内容。对吧？接下来再说一段完整内容。")
    try checkEqual(shortMerged.map(\.originalText), ["好。这里是一段足够长的完整口播内容。对吧？", "接下来再说一段完整内容。"], "middle short chunks merge with previous neighbor")
    try checkTrue(ScriptSegmenter.segment(" \n  ").isEmpty, "empty script")
    try checkTrue(ScriptSegmenter.segment("。？！；\n。。").isEmpty, "punctuation only script")

    let repeatedPunctuation = ScriptSegmenter.segment("这是第一句内容够长！！！？？这是第二句内容也足够长。")
    try checkEqual(repeatedPunctuation.count, 2, "repeated punctuation creates no empty segments")
    try checkTrue(repeatedPunctuation.allSatisfy { !$0.normalizedText.isEmpty }, "all visible segments have content")
    try checkEqual(repeatedPunctuation[0].originalText, "这是第一句内容够长！！！？？", "consecutive punctuation stays together")
}
