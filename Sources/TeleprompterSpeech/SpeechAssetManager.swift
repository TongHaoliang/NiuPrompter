import Foundation
import Speech

package func makeSpeechTranscriber(locale: Locale) -> SpeechTranscriber {
    SpeechTranscriber(
        locale: locale,
        transcriptionOptions: [],
        reportingOptions: [.volatileResults, .fastResults],
        attributeOptions: [.audioTimeRange]
    )
}

@available(macOS 26.0, iOS 26.0, *)
@MainActor
final class SpeechAssetManager {
    func prepare(
        requestedLocale: Locale,
        updateStatus: @escaping @MainActor (EngineStatus) -> Void
    ) async throws -> Locale {
        guard SpeechTranscriber.isAvailable else {
            throw SpeechEngineError("此设备当前无法使用 Apple SpeechTranscriber")
        }
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: requestedLocale) else {
            throw SpeechEngineError("Apple 本地识别不支持 \(requestedLocale.identifier)")
        }

        let transcriber = makeSpeechTranscriber(locale: locale)
        // Reserve before branching on installation status so preinstalled assets are usable too.
        _ = try await AssetInventory.reserve(locale: locale)

        let inventoryStatus = await AssetInventory.status(forModules: [transcriber])
        switch inventoryStatus {
        case .installed:
            updateStatus(EngineStatus(
                phase: .ready,
                localeIdentifier: locale.identifier,
                speechAvailable: true,
                localeSupported: true,
                modelState: .installed
            ))
        case .unsupported:
            throw SpeechEngineError("此设备无法安装 \(locale.identifier) 的本地语音模型")
        case .supported, .downloading:
            updateStatus(EngineStatus(
                phase: .preparing,
                localeIdentifier: locale.identifier,
                speechAvailable: true,
                localeSupported: true,
                modelState: .downloading
            ))
            guard let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) else {
                updateStatus(EngineStatus(
                    phase: .ready,
                    localeIdentifier: locale.identifier,
                    speechAvailable: true,
                    localeSupported: true,
                    modelState: .installed,
                    downloadProgress: 1
                ))
                return locale
            }

            let progress = request.progress
            let progressTask = Task { @MainActor in
                while !Task.isCancelled {
                    updateStatus(EngineStatus(
                        phase: .preparing,
                        localeIdentifier: locale.identifier,
                        speechAvailable: true,
                        localeSupported: true,
                        modelState: .downloading,
                        downloadProgress: progress.fractionCompleted
                    ))
                    do { try await Task.sleep(for: .milliseconds(150)) }
                    catch { break }
                }
            }
            defer { progressTask.cancel() }
            try await request.downloadAndInstall()
            let finalStatus = await AssetInventory.status(forModules: [transcriber])
            guard finalStatus == .installed else {
                throw SpeechEngineError("中文模型下载结束，但系统仍未报告模型已安装")
            }
            updateStatus(EngineStatus(
                phase: .ready,
                localeIdentifier: locale.identifier,
                speechAvailable: true,
                localeSupported: true,
                modelState: .installed,
                downloadProgress: 1
            ))
        @unknown default:
            throw SpeechEngineError("系统返回了未知的中文语音模型状态")
        }
        return locale
    }
}
