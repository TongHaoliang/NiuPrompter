import TeleprompterCore

func runSimilarityTests() throws {
    try checkEqual(Similarity.characterBigramDice("电话客服", "电话客服"), 1, "equal bigram dice")
    try checkEqual(Similarity.characterBigramDice("电话", "客服"), 0, "disjoint bigram dice")
    try checkEqual(Similarity.characterBigramDice("", "客服"), 0, "empty bigram dice")
    try checkEqual(Similarity.characterBigramDice("啊", "啊"), 1, "single character equality")
    try checkEqual(Similarity.characterBigramDice("啊", "嗯"), 0, "different single characters")
    try checkEqual(Similarity.characterBigramDice("aaaa", "aaab"), 2.0 / 3.0, "duplicate bigram counts")
    try checkEqual(Similarity.lcsRatio("电话客服", "电话客服"), 1, "equal lcs ratio")
    try checkEqual(Similarity.lcsRatio("电话", "客服"), 0, "disjoint lcs ratio")
    try checkEqual(Similarity.lcsRatio("", "客服"), 0, "empty lcs ratio")
    try checkEqual(Similarity.lcsRatio("abcde", "abde"), 8.0 / 9.0, "lcs ratio for missing character")
    try checkTrue(Similarity.characterBigramDice("abcde", "abde") == Similarity.characterBigramDice("abde", "abcde"), "dice symmetry")
}
