import TeleprompterCore

func runScriptStatisticsTests() throws {
    try checkEqual(ScriptStatistics(text: "").characterCount, 0, "empty script count")
    try checkEqual(ScriptStatistics(text: " ，。！\n 👋").estimatedSeconds, 0, "nonspoken symbols have no duration")
    try checkEqual(ScriptStatistics(text: "你好，世界！\n").characterCount, 4, "punctuation and whitespace excluded")
    try checkEqual(ScriptStatistics(text: "嗯那个啊").characterCount, 4, "scripted fillers are counted")
    try checkEqual(ScriptStatistics(text: "AI 2026，你好").characterCount, 8, "letters and digits counted explicitly")
    try checkEqual(ScriptStatistics(text: String(repeating: "字", count: 250)).durationLabel, "1 分钟", "reference rate one minute")
    try checkEqual(ScriptStatistics(text: String(repeating: "字", count: 375)).durationLabel, "1 分 30 秒", "minute and second formatting")
    try checkEqual(ScriptStatistics(text: "你").durationLabel, "1 秒", "nonempty script rounds up")
    try checkEqual(ScriptStatistics(text: "").durationLabel, "0 秒", "empty duration formatting")
}
