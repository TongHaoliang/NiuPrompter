import SwiftUI
import TeleprompterCore
import TeleprompterPresentation
import TeleprompterSpeech

@main
@MainActor
struct SmartTeleprompterMacApp: App {
    private let engine: any SpeechRecognitionEngine

    init() {
        if ProcessInfo.processInfo.arguments.contains("--demo") {
            let fake = FakeSpeechRecognitionEngine()
            fake.configureDemo(texts: ScriptSegmenter.segment(BuiltInScript.text).prefix(3).map(\.originalText))
            engine = fake
        } else {
            engine = AppleSpeechAnalyzerEngine()
        }
    }

    var body: some Scene {
        WindowGroup {
            ProbeView(engine: engine)
        }
    }
}
