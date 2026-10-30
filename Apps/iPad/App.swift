import SwiftUI
import TeleprompterPresentation
import TeleprompterSpeech

@main
@MainActor
struct SmartTeleprompteriPadApp: App {
    private let engine: any SpeechRecognitionEngine = {
#if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--ui-preview") {
            return FakeSpeechRecognitionEngine()
        }
#endif
        return AppleSpeechAnalyzerEngine()
    }()

    var body: some Scene {
        WindowGroup {
            ProbeView(engine: engine)
        }
    }
}
