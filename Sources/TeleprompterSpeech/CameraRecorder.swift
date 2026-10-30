#if os(iOS)
import AVFoundation
import Combine
import Foundation
import Photos

public struct RecordedClip: Identifiable, Sendable {
    public var id: URL { url }
    public let url: URL
    public let date: Date
}

private enum CaptureEvent: Sendable {
    case started
    case finished(URL?, String?)
    case interrupted(String)
}

/// The serial capture queue owns session configuration, recording and file finalization.
private final class CameraSessionDriver: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate,
    AVCaptureFileOutputRecordingDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    let audio = CaptureSpeechAudioSource()
    private let queue = DispatchQueue(label: "teleprompter.camera.capture")
    private let audioQueue = DispatchQueue(label: "teleprompter.camera.speech")
    private let movie = AVCaptureMovieFileOutput()
    private let audioOutput = AVCaptureAudioDataOutput()
    private var configured = false
    private var recordingPending = false
    private var observers: [NSObjectProtocol] = []
    private var closing: [CheckedContinuation<Void, Never>] = []
    private var stopping: [CheckedContinuation<Void, Never>] = []
    var onEvent: (@Sendable (CaptureEvent) -> Void)?

    func prepare() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    if !self.configured {
                        self.session.beginConfiguration()
                        do {
                            self.session.sessionPreset = .hd1920x1080
                            self.session.automaticallyConfiguresApplicationAudioSession = false
                            guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
                                  let mic = AVCaptureDevice.default(for: .audio) else {
                                throw SpeechEngineError("找不到前置摄像头或麦克风")
                            }
                            for device in [camera, mic] {
                                let input = try AVCaptureDeviceInput(device: device)
                                guard self.session.canAddInput(input) else { throw SpeechEngineError("无法连接摄像头或麦克风") }
                                self.session.addInput(input)
                            }
                            for output in [self.movie as AVCaptureOutput, self.audioOutput as AVCaptureOutput] {
                                guard self.session.canAddOutput(output) else { throw SpeechEngineError("此设备无法同时录像和语音跟随") }
                                self.session.addOutput(output)
                            }
                            self.movie.minFreeDiskSpaceLimit = 200 * 1_024 * 1_024
                            self.audioOutput.setSampleBufferDelegate(self, queue: self.audioQueue)
                            self.session.commitConfiguration()
                            self.configured = true
                            self.observeInterruptions()
                        } catch {
                            for input in self.session.inputs { self.session.removeInput(input) }
                            for output in self.session.outputs { self.session.removeOutput(output) }
                            self.session.commitConfiguration()
                            throw error
                        }
                    }
                    let audioSession = AVAudioSession.sharedInstance()
                    try audioSession.setCategory(.playAndRecord, mode: .videoRecording, options: [.defaultToSpeaker, .allowBluetoothHFP])
                    try audioSession.setActive(true)
                    self.session.startRunning()
                    guard self.session.isRunning, !self.session.isInterrupted else { throw SpeechEngineError("相机暂时被占用，请稍后重试") }
                    continuation.resume()
                } catch {
                    self.session.stopRunning()
                    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func record(to url: URL, angle: CGFloat) {
        queue.async {
            guard self.session.isRunning, !self.session.isInterrupted, !self.recordingPending,
                  let connection = self.movie.connection(with: .video),
                  self.movie.connection(with: .audio)?.isActive == true else {
                self.onEvent?(.finished(nil, "相机或录音未就绪，请重新打开拍摄模式"))
                return
            }
            if connection.isVideoRotationAngleSupported(angle) { connection.videoRotationAngle = angle }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = false
            }
            self.recordingPending = true
            self.movie.startRecording(to: url, recordingDelegate: self)
        }
    }

    func stopRecording() async {
        await withCheckedContinuation { continuation in
            queue.async {
                if self.recordingPending {
                    self.stopping.append(continuation)
                    if self.movie.isRecording { self.movie.stopRecording() }
                } else { continuation.resume() }
            }
        }
    }

    func close() async {
        await withCheckedContinuation { continuation in
            queue.async {
                if self.recordingPending {
                    self.closing.append(continuation)
                    if self.movie.isRecording { self.movie.stopRecording() }
                } else { self.releaseSession(); continuation.resume() }
            }
        }
    }

    private func releaseSession() {
        audio.stop()
        session.stopRunning()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func observeInterruptions() {
        for name in [AVCaptureSession.wasInterruptedNotification, AVCaptureSession.runtimeErrorNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: session, queue: nil) { [weak self] _ in
                guard let self else { return }
                self.queue.async {
                    self.audio.stop(error: "拍摄被系统中断，请重新开启跟随")
                    if self.movie.isRecording { self.movie.stopRecording() }
                    self.onEvent?(.interrupted("拍摄被系统中断，已尝试保留当前视频；请重新打开相机"))
                }
            })
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        audio.consume(sampleBuffer)
    }

    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        queue.async {
            self.onEvent?(.started)
            if !self.stopping.isEmpty || !self.closing.isEmpty { self.movie.stopRecording() }
        }
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo fileURL: URL,
                    from connections: [AVCaptureConnection], error: Error?) {
        let nsError = error as NSError?
        let succeeded = error == nil || (nsError?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool == true)
        let message = succeeded ? nil : "录像未正常完成：\(error?.localizedDescription ?? "未知错误")"
        queue.async {
            self.recordingPending = false
            self.onEvent?(.finished(succeeded ? fileURL : nil, message))
            for continuation in self.stopping { continuation.resume() }
            self.stopping.removeAll()
            if !self.closing.isEmpty {
                self.releaseSession()
                for continuation in self.closing { continuation.resume() }
                self.closing.removeAll()
            }
        }
    }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }
}

@MainActor
public final class CameraRecorder: ObservableObject {
    @Published public private(set) var isReady = false
    @Published public private(set) var isRecording = false
    @Published public private(set) var isBusy = false
    @Published public private(set) var startedAt: Date?
    @Published public private(set) var message: String?
    @Published public private(set) var clips: [RecordedClip] = []
    @Published public private(set) var exporting = false
    public var session: AVCaptureSession { driver.session }
    public var audioSource: CaptureSpeechAudioSource { driver.audio }
    private let driver = CameraSessionDriver()
    private let folder = URL.documentsDirectory.appendingPathComponent("口播视频", isDirectory: true)
    private var generation = 0
    private var rotation: AVCaptureDevice.RotationCoordinator?
    private var photosSaved = Set<URL>()

    public init() {
        driver.onEvent = { [weak self] event in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch event {
                case .started:
                    self.isRecording = true
                    self.isBusy = false
                    self.startedAt = Date()
                case let .finished(url, error):
                    self.isRecording = false
                    self.isBusy = false
                    self.startedAt = nil
                    self.message = error ?? (url != nil ? "视频已保存在本机，可从“视频”查看或存入相册" : nil)
                    self.refreshClips()
                case let .interrupted(message):
                    self.isReady = false
                    self.message = message
                }
            }
        }
        refreshClips()
    }

    public func prepare() async {
        guard !isBusy, !isReady else { return }
        generation += 1
        let operation = generation
        isBusy = true
        message = nil
        do {
            for media in [AVMediaType.video, .audio] {
                let authorized = AVCaptureDevice.authorizationStatus(for: media) == .authorized
                // Permission requests are asynchronous; do not start capture before both complete.
                if !authorized {
                    let granted: Bool
                    if AVCaptureDevice.authorizationStatus(for: media) == .notDetermined {
                        granted = await AVCaptureDevice.requestAccess(for: media)
                    } else { granted = false }
                    guard granted else { throw SpeechEngineError("请在系统设置中允许摄像头和麦克风，才能拍摄有声视频") }
                }
                guard generation == operation, !Task.isCancelled else { throw CancellationError() }
            }
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try await driver.prepare()
            guard generation == operation, !Task.isCancelled else { await driver.close(); return }
            if let device = driver.session.inputs.compactMap({ $0 as? AVCaptureDeviceInput }).first(where: { $0.device.hasMediaType(.video) })?.device {
                rotation = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
            }
            isReady = true
        } catch {
            if !(error is CancellationError) { message = error.localizedDescription }
        }
        if generation == operation { isBusy = false }
    }

    public func beginRecording() {
        guard isReady, !isBusy, !isRecording else { return }
        message = nil
        isBusy = true
        driver.record(to: folder.appendingPathComponent("口播-\(UUID().uuidString).mov"), angle: rotation?.videoRotationAngleForHorizonLevelCapture ?? 90)
    }

    public func endRecording() async {
        guard isRecording || isBusy else { return }
        isBusy = true
        await driver.stopRecording()
    }

    public func close() async {
        generation += 1
        isReady = false
        await driver.close()
        isBusy = false
    }

    public func saveToPhotos(_ clip: RecordedClip) async {
        guard !exporting else { return }
        if photosSaved.contains(clip.url) { message = "这段视频已存入相册"; return }
        exporting = true
        defer { exporting = false }
        let authorization = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard authorization == .authorized || authorization == .limited else {
            message = "没有相册写入权限，视频仍保存在本机，也可以通过分享导出"
            return
        }
        do {
            // Photos invokes this block on its private queue. Explicit Sendable prevents
            // inheriting CameraRecorder's MainActor isolation (which traps at runtime).
            let fileURL = clip.url
            let changes: @Sendable () -> Void = {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
            }
            try await PHPhotoLibrary.shared().performChanges(changes)
            photosSaved.insert(clip.url)
            message = "已保存到系统相册"
        } catch { message = "存入相册失败，原视频仍在本机：\(error.localizedDescription)" }
    }

    public func deleteClip(_ clip: RecordedClip) {
        guard !exporting, !isRecording, !isBusy else { return }
        // Only delete clips discovered in our own recording library.
        guard clips.contains(where: { $0.url == clip.url }),
              clip.url.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL else { return }
        do {
            try FileManager.default.removeItem(at: clip.url)
            photosSaved.remove(clip.url)
            refreshClips()
            message = "已删除本机视频，已导出或存入相册的副本不受影响"
        } catch {
            message = "删除失败：\(error.localizedDescription)"
        }
    }

    private func refreshClips() {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.creationDateKey, .fileSizeKey])) ?? []
        clips = files.filter { $0.pathExtension == "mov" }.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: [.creationDateKey, .fileSizeKey]), (values.fileSize ?? 0) > 0 else { return nil }
            return RecordedClip(url: url, date: values.creationDate ?? .distantPast)
        }.sorted { $0.date > $1.date }
    }
}
#endif
