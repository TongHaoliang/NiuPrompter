import TeleprompterCore

func runTextNormalizerTests() throws {
    try checkEqual(TextNormalizer.normalize(
        "Meta 这两天，新出了一个叫 Muse 的 Agent。", recognition: false
    ), "meta这两天新出了一个叫muse的agent", "mixed script normalization")
    try checkEqual(TextNormalizer.normalize("ＡＢＣ１２３ XYZ", recognition: false), "abc123xyz", "full width and case")
    try checkEqual(TextNormalizer.normalize("你好， 世界！\n今天；很好。", recognition: false), "你好世界今天很好", "punctuation and whitespace")

    let text = "啊，那个就是说我们开始。"
    try checkEqual(TextNormalizer.normalize(text, recognition: true), "我们开始", "recognition fillers removed")
    try checkEqual(TextNormalizer.normalize(text, recognition: false), "啊那个就是说我们开始", "script fillers preserved")
    try checkEqual(TextNormalizer.phonetic("你好世界"), "nihaoshijie", "tone free pinyin")
    try checkEqual(TextNormalizer.phonetic("Muse Agent"), "museagent", "Latin phonetic text")
    try checkEqual(TextNormalizer.normalize("  ，。\n", recognition: true), "", "empty normalization")
    try checkEqual(TextNormalizer.phonetic(""), "", "empty phonetic text")
}
