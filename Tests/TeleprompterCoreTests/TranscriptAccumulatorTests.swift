import Foundation
import TeleprompterCore

func runTranscriptAccumulatorTests() throws {
    let session = UUID()
    var accumulator = TranscriptAccumulator()
    accumulator.reset(sessionID: session)

    let first = RecognitionEvent(sessionID: session, revision: 1, audioStart: 0, audioEnd: 2,
                                text: "很多人", stability: .volatile)
    try checkEqual(accumulator.ingest(first)?.recentText, "很多人", "first volatile result")

    let correction = RecognitionEvent(sessionID: session, revision: 2, audioStart: 0, audioEnd: 3,
                                      text: "很多人都被电话客服折磨过", stability: .volatile)
    let correctionSnapshot = accumulator.ingest(correction)
    try checkEqual(correctionSnapshot?.recentText, "很多人都被电话客服折磨过", "volatile correction replaces prior text")
    try checkEqual(correctionSnapshot?.volatileText, correction.text, "current volatile text")

    let final = RecognitionEvent(sessionID: session, revision: 3, audioStart: 0, audioEnd: 3,
                                 text: correction.text, stability: .final)
    let finalSnapshot = accumulator.ingest(final)
    try checkEqual(finalSnapshot?.finalText, final.text, "final replaces volatile range")
    try checkEqual(finalSnapshot?.volatileText, "", "final clears volatile text")
    try checkEqual(finalSnapshot?.recentText, "很多人都被电话客服折磨过", "final text is not duplicated")

    let duplicateFinal = RecognitionEvent(sessionID: session, revision: 4, audioStart: 0, audioEnd: 3,
                                          text: final.text, stability: .final)
    try checkTrue(accumulator.ingest(duplicateFinal) == nil, "duplicate final adds no evidence")
    try checkTrue(accumulator.ingest(final) == nil, "stale revision is ignored")

    let oldSession = RecognitionEvent(sessionID: UUID(), revision: 99, audioStart: 3, audioEnd: 4,
                                      text: "旧会话文字", stability: .final)
    try checkTrue(accumulator.ingest(oldSession) == nil, "old session is ignored")

    let lateVolatile = RecognitionEvent(sessionID: session, revision: 5, audioStart: 0, audioEnd: 3,
                                        text: "更差的临时猜测", stability: .volatile)
    try checkTrue(accumulator.ingest(lateVolatile) == nil, "late volatile cannot overwrite finalized audio")

    let repeated = RecognitionEvent(sessionID: session, revision: 6, audioStart: 4, audioEnd: 5,
                                   text: "继续", stability: .final)
    try checkEqual(accumulator.ingest(repeated)?.finalText, "很多人都被电话客服折磨过 继续", "different time range preserves repeated words")

    var shrinking = TranscriptAccumulator()
    shrinking.reset(sessionID: session)
    _ = shrinking.ingest(RecognitionEvent(sessionID: session, revision: 1, audioStart: 1, audioEnd: 3,
                                          text: "這是一句臨時預測", stability: .volatile))
    let shorter = RecognitionEvent(sessionID: session, revision: 2, audioStart: 1, audioEnd: 2,
                                   text: "这是一句", stability: .volatile)
    try checkEqual(shrinking.ingest(shorter)?.volatileText, shorter.text, "shrinking volatile range replaces previous range")

    var empty = TranscriptAccumulator()
    empty.reset(sessionID: session)
    try checkTrue(empty.ingest(RecognitionEvent(sessionID: session, revision: 1, audioStart: 1, audioEnd: 1,
                                                text: "空范围", stability: .final)) == nil,
                  "zero length interval is rejected")

    let oversized = String(repeating: "念", count: 2_010)
    let capped = accumulator.ingest(RecognitionEvent(sessionID: session, revision: 7, audioStart: 6, audioEnd: 7,
                                                     text: oversized, stability: .final))
    try checkEqual(capped?.finalText.count, 2_000, "diagnostic transcript is capped")
    try checkEqual(capped?.recentText.count, 80, "matching transcript is capped")
}
