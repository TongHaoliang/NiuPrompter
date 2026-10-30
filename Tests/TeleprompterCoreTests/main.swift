import Foundation

@main
struct TeleprompterChecks {
    @MainActor
    static func main() async {
        do {
            try await runCaptureSpeechAudioTests()
            print("PASS CaptureSpeechAudio")
            try await runScriptLibraryTests()
            print("PASS ScriptLibrary")
            try await runReadingSessionTests()
            print("PASS ReadingSession")
            try runScriptStatisticsTests()
            print("PASS ScriptStatistics")
            try runTextNormalizerTests()
            print("PASS TextNormalizer")
            try runScriptSegmenterTests()
            print("PASS ScriptSegmenter")
            try runTranscriptAccumulatorTests()
            print("PASS TranscriptAccumulator")
            try runSimilarityTests()
            print("PASS Similarity")
            try await runSentenceLeadViewModelTests()
            print("PASS SentenceLeadViewModel")
            try await runSpeechAndViewModelTests()
            print("PASS SpeechAndViewModel")
            try runScriptMatcherTests()
            print("PASS ScriptMatcher")
            try runPromptStabilityTests()
            print("PASS PromptStability")
            try runSentenceEndLeadTests()
            print("PASS SentenceEndLead")
            try runPacePromptTests()
            print("PASS PacePrompt")
            try runAdjacentHandoffTests()
            print("PASS AdjacentHandoff")
            try runFollowingContinuityTests()
            print("PASS FollowingContinuity")
            try runRecoveryTests()
            print("PASS Recovery")
            try await runAudioTapIsolationTests()
            print("PASS AudioTapIsolation")
            try runAudioTimelineTests()
            print("PASS AudioTimeline")
            try runFreshTranscriberTests()
            print("PASS FreshTranscriber")
            try await runFakeDemoTests()
            print("PASS FakeDemo")
            print("\(TestCounter.count) checks passed")
        } catch {
            fputs("FAIL checks: \(error)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }
}
