#if os(iOS)
import AVFoundation
import AVKit
import SwiftUI
import TeleprompterSpeech
import UIKit

struct PhoneCameraView: View {
    @ObservedObject var model: ProbeViewModel
    @StateObject private var camera = CameraRecorder()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @State private var settings = false
    @State private var editing = false
    @State private var deletingClip: RecordedClip?
    @State private var library = false
    @State private var setupError: String?
    @State private var leaving = false
    @State private var dragStart: CGPoint?
    @State private var selectingSentence = false
    @AppStorage("teleprompter.camera.font") private var font = 24.0
    @AppStorage("teleprompter.camera.opacity") private var opacity = 0.95
    @AppStorage("teleprompter.camera.landscapeX") private var landscapeX = -1.0
    @AppStorage("teleprompter.camera.landscapeY") private var landscapeY = -1.0
    @AppStorage("teleprompter.camera.portraitX") private var portraitX = -1.0
    @AppStorage("teleprompter.camera.portraitY") private var portraitY = -1.0
    private var followingBusy: Bool { model.isPreparing || model.isStarting }

    var body: some View {
        GeometryReader { geometry in
            let landscape = geometry.size.width > geometry.size.height
            ZStack {
                CameraPreview(session: camera.session).ignoresSafeArea()
                if !camera.isReady && !previewOnly {
                    Color.black.opacity(0.65).ignoresSafeArea()
                    VStack(spacing: 16) {
                        if camera.isBusy { ProgressView("正在打开前置相机") }
                        else {
                            Image(systemName: "video.slash").font(.largeTitle)
                            Text(setupError ?? camera.message ?? "相机已暂停").multilineTextAlignment(.center)
                            Button("重新打开相机") { Task { await prepare() } }.buttonStyle(.borderedProminent)
                            Button("系统权限设置") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                        }
                    }.padding(28)
                }
                if camera.isReady || previewOnly {
                    floatingPrompt(in: geometry, landscape: landscape)
                }
                VStack {
                    HStack {
                        Button { Task { await model.stop(); editing = true } } label: {
                            Label("稿件", systemImage: "doc.text").padding(10)
                        }.disabled(camera.isRecording || camera.isBusy || leaving)
                        Spacer()
                        if let started = camera.startedAt {
                            HStack(spacing: 6) {
                                Circle().fill(.red).frame(width: 8, height: 8)
                                Text(started, style: .timer).monospacedDigit().frame(width: 70)
                            }.padding(8).background(.black.opacity(0.4), in: Capsule())
                        } else {
                            Text("前置视频").font(.subheadline.weight(.semibold)).shadow(color: .black, radius: 3)
                        }
                        Spacer()
                        Button { settings = true } label: { Image(systemName: "slider.horizontal.3").frame(width: 44, height: 44) }
                    }
                    Spacer()
                    if let message = setupError ?? model.errorMessage ?? model.storageWarning ?? camera.message, camera.isReady {
                        Text(message).font(.caption).multilineTextAlignment(.center).padding(8)
                            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
                    }
                    HStack(spacing: landscape ? 24 : 14) {
                        Button {
                            Task { await model.stop(); library = true }
                        } label: {
                            Label("视频", systemImage: "photo.on.rectangle").font(.subheadline)
                        }.disabled(camera.isRecording || camera.isBusy)
                        Spacer(minLength: 0)
                        Button {
                            Task {
                                if camera.isRecording { await camera.endRecording() }
                                else { camera.beginRecording() }
                            }
                        } label: {
                            ZStack {
                                Circle().stroke(.white, lineWidth: 3).frame(width: 64, height: 64)
                                if camera.isBusy { ProgressView().tint(.white) }
                                else if camera.isRecording { RoundedRectangle(cornerRadius: 5).fill(.red).frame(width: 26, height: 26) }
                                else { Circle().fill(.red).frame(width: 52, height: 52) }
                            }
                        }.disabled(!camera.isReady || camera.isBusy || leaving)
                            .accessibilityLabel(camera.isRecording ? "停止录像" : "开始录像")
                        Spacer(minLength: 0)
                        Button {
                            Task { if model.isListening { await model.stop() } else { await model.start() } }
                        } label: {
                            HStack(spacing: 5) {
                                if followingBusy { ProgressView().tint(.white) }
                                else { Image(systemName: model.isListening ? "pause.fill" : "waveform") }
                                Text(model.isListening ? "跟随中" : "跟随")
                            }.font(.subheadline.weight(.semibold)).padding(.horizontal, 12).frame(height: 42)
                                .background(model.isListening ? Color.green.opacity(0.75) : Color.black.opacity(0.5), in: Capsule())
                        }.disabled(!camera.isReady || followingBusy || model.segments.isEmpty || leaving)
                    }
                    .padding(.horizontal, 18).padding(.vertical, 6)
                }
                .padding(.horizontal, 8)
            }
        }
        .foregroundStyle(.white).tint(.white).background(.black).preferredColorScheme(.dark)
        .interactiveDismissDisabled()
        .task {
            if !previewOnly { await prepare() }
#if DEBUG && targetEnvironment(simulator)
            if previewOnly {
                let arguments = ProcessInfo.processInfo.arguments
                if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                    scene.requestGeometryUpdate(.iOS(interfaceOrientations: arguments.contains("--landscape") ? .landscapeRight : .portrait))
                }
                if arguments.contains("--library-preview") { editing = true }
            }
#endif
        }
        .onChange(of: phase) { _, value in
            if value == .background { Task { await model.stop(); await camera.close() } }
        }
        .onChange(of: camera.isReady) { _, ready in
            if !ready { Task { await model.stop() } }
        }
        .onChange(of: camera.isRecording) { _, recording in
            UIApplication.shared.isIdleTimerDisabled = recording || model.isListening
            Task {
                if recording {
                    guard camera.isRecording, !leaving, !model.segments.isEmpty else { return }
                    await model.start()
                } else {
                    await model.stop()
                }
            }
        }
        .onChange(of: model.isListening) { _, listening in
            UIApplication.shared.isIdleTimerDisabled = listening || camera.isRecording
        }
        .onDisappear {
            Task { await model.stop(); await camera.close(); try? await model.setCaptureAudioSource(nil) }
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .sheet(isPresented: $settings) { cameraSettings }
        .sheet(isPresented: $editing) { PhoneScriptLibrary(model: model, presented: $editing) }
        .sheet(isPresented: $library) { clipLibrary }
    }

    private var previewOnly: Bool {
#if DEBUG && targetEnvironment(simulator)
        ProcessInfo.processInfo.arguments.contains("--camera-preview")
#else
        false
#endif
    }

    private func prepare() async {
        setupError = nil
        do {
            try await model.setCaptureAudioSource(camera.audioSource)
            guard !Task.isCancelled, !leaving else { return }
            await camera.prepare()
        } catch { setupError = error.localizedDescription }
    }

    private func leave() async {
        guard !leaving else { return }
        leaving = true
        await model.stop()
        await camera.close()
        try? await model.setCaptureAudioSource(nil)
        dismiss()
    }

    private func floatingPrompt(in geometry: GeometryProxy, landscape: Bool) -> some View {
        let width = min(landscape ? 330.0 : geometry.size.width * 0.88, geometry.size.width - 24)
        let height = min(landscape ? geometry.size.height - 115 : geometry.size.height * 0.32, 245)
        let maxX = max(0, geometry.size.width - width - 24)
        let maxY = max(0, geometry.size.height - height - 136)
        let cameraOnLeft = geometry.safeAreaInsets.leading > geometry.safeAreaInsets.trailing
        let savedX = landscape ? landscapeX : portraitX
        let savedY = landscape ? landscapeY : portraitY
        let x = min(1, max(0, savedX < 0 ? (landscape ? (cameraOnLeft ? 0 : 1) : 0.5) : savedX))
        let y = min(1, max(0, savedY < 0 ? (landscape ? 0.35 : 0) : savedY))
        return VStack(spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                Text("拖动提词")
                Spacer()
                Button { Task { await model.previousSegment() } } label: { Image(systemName: "chevron.up").frame(width: 32, height: 24) }
                Button { Task { await model.nextSegment() } } label: { Image(systemName: "chevron.down").frame(width: 32, height: 24) }
            }
            .font(.caption2).shadow(color: .black, radius: 3)
            .contentShape(Rectangle())
            .gesture(DragGesture().onChanged { value in
                if dragStart == nil { dragStart = CGPoint(x: x, y: y) }
                let origin = dragStart ?? CGPoint(x: x, y: y)
                let nextX = min(1, max(0, origin.x + value.translation.width / max(1, maxX)))
                let nextY = min(1, max(0, origin.y + value.translation.height / max(1, maxY)))
                if landscape { landscapeX = nextX; landscapeY = nextY }
                else { portraitX = nextX; portraitY = nextY }
            }.onEnded { _ in dragStart = nil })
            if model.segments.isEmpty {
                Text("点击左上角“稿件”粘贴口播内容\n也可以直接录像")
                    .font(.system(size: 20)).shadow(color: .black, radius: 3)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(model.segments) { segment in
                                Text(segment.originalText)
                                    .font(.system(size: font, weight: segment.id == model.promptSegmentID ? .semibold : .regular))
                                    .foregroundStyle(.white.opacity(segment.id == model.promptSegmentID ? opacity : opacity * 0.68))
                                    .shadow(color: .black.opacity(0.9), radius: 2, x: 0, y: 1)
                                    .shadow(color: .black.opacity(0.7), radius: 4)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        guard !selectingSentence, !leaving else { return }
                                        selectingSentence = true
                                        Task {
                                            await model.selectSegment(segment.id)
                                            if camera.isRecording, !leaving { await model.start() }
                                            selectingSentence = false
                                        }
                                    }
                                    .accessibilityAddTraits(.isButton)
                                    .accessibilityHint("从这句继续提词")
                                    .id(segment.id)
                            }
                            Color.clear.frame(height: height)
                        }
                    }.scrollIndicators(.hidden)
                    .onChange(of: model.promptSegmentID, initial: true) { _, id in
                        Task { @MainActor in
                            await Task.yield()
                            withAnimation(.easeOut(duration: 0.18)) { if let id { proxy.scrollTo(id, anchor: .top) } }
                        }
                    }
                    .onChange(of: font) { _, _ in if let id = model.promptSegmentID { proxy.scrollTo(id, anchor: .top) } }
                    .onChange(of: geometry.size) { _, _ in if let id = model.promptSegmentID { proxy.scrollTo(id, anchor: .top) } }
                }
            }
        }
        .frame(width: width, height: max(80, height))
        .position(x: 12 + width / 2 + maxX * x, y: 52 + max(80, height) / 2 + maxY * y)
    }

    private var cameraSettings: some View {
        NavigationStack {
            Form {
                Section("悬浮文字") {
                    LabeledContent("字号", value: "\(Int(font))")
                    Slider(value: $font, in: 18...36, step: 1)
                    LabeledContent("文字亮度", value: "\(Int(opacity * 100))%")
                    Slider(value: $opacity, in: 0.55...1)
                    Button("恢复靠近镜头的位置") { landscapeX = -1; landscapeY = -1; portraitX = -1; portraitY = -1 }
                }
                Section {
                    Text("人物预览铺满屏幕，文字背景透明。预览像照镜子，成片为正常方向，不包含提词文字。")
                    Text("开始录像自动跟随；暂停跟随不会停止录像。成片方向在开始录像时确定。")
                }.font(.footnote)
                Section {
                    Button("切换到纯提词模式", systemImage: "text.alignleft") {
                        settings = false
                        Task { await leave() }
                    }.disabled(camera.isRecording || camera.isBusy)
                } footer: {
                    Text("适合配合独立相机或提词器使用。点击摄像机按钮可回到拍摄。")
                }
            }.navigationTitle("拍摄设置").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { settings = false } } }
        }.presentationDetents([.medium, .large])
    }

    private var clipLibrary: some View {
        NavigationStack {
            Group {
                if camera.clips.isEmpty { ContentUnavailableView("还没有视频", systemImage: "video") }
                else {
                    List(camera.clips) { clip in
                        VStack(alignment: .leading, spacing: 12) {
                            NavigationLink { ClipPlayer(url: clip.url) } label: {
                                Label(clip.date.formatted(date: .abbreviated, time: .standard), systemImage: "play.rectangle")
                            }
                            HStack {
                                ShareLink(item: clip.url) { Label("导出", systemImage: "square.and.arrow.up") }
                                Spacer()
                                Button("存入相册") { Task { await camera.saveToPhotos(clip) } }.disabled(camera.exporting)
                            }.buttonStyle(.borderless)
                            Button("删除视频", role: .destructive) { deletingClip = clip }
                                .disabled(camera.exporting)
                                .buttonStyle(.borderless)
                        }.padding(.vertical, 8)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("删除", role: .destructive) { deletingClip = clip }
                                .disabled(camera.exporting)
                        }
                    }
                }
            }
            .alert("删除这段视频？", isPresented: Binding(get: { deletingClip != nil }, set: { if !$0 { deletingClip = nil } }), presenting: deletingClip) { clip in
                Button("删除", role: .destructive) { camera.deleteClip(clip); deletingClip = nil }
                Button("取消", role: .cancel) { deletingClip = nil }
            } message: { _ in
                Text("将删除 App 内的视频，无法撤销。已存入系统相册或导出的视频不会受影响。")
            }
            .navigationTitle("本机视频").navigationBarTitleDisplayMode(.inline)
                .safeAreaInset(edge: .bottom) {
                    if let message = camera.message { Text(message).font(.footnote).padding().frame(maxWidth: .infinity).background(.ultraThinMaterial) }
                }
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { library = false } } }
        }
    }
}

private struct ClipPlayer: View {
    @State private var player: AVPlayer
    init(url: URL) { _player = State(initialValue: AVPlayer(url: url)) }
    var body: some View { VideoPlayer(player: player).onDisappear { player.pause() }.navigationTitle("视频预览") }
}

private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    func makeUIView(context: Context) -> PreviewSurface { PreviewSurface() }
    func updateUIView(_ view: PreviewSurface, context: Context) {
        if view.preview.session !== session { view.preview.session = session }
        view.updateRotation()
    }
}

private final class PreviewSurface: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    private var rotation: AVCaptureDevice.RotationCoordinator?
    private var observation: NSKeyValueObservation?
    override init(frame: CGRect) { super.init(frame: frame); preview.videoGravity = .resizeAspectFill }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() { super.layoutSubviews(); updateRotation() }
    func updateRotation() {
        guard let device = preview.session?.inputs.compactMap({ $0 as? AVCaptureDeviceInput }).first(where: { $0.device.hasMediaType(.video) })?.device else { return }
        if rotation == nil {
            let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: preview)
            rotation = coordinator
            observation = coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.initial, .new]) { [weak self] _, change in
                guard let angle = change.newValue else { return }
                Task { @MainActor [weak self] in self?.apply(angle) }
            }
        }
        if let angle = rotation?.videoRotationAngleForHorizonLevelPreview { apply(angle) }
    }
    private func apply(_ angle: CGFloat) {
        guard let connection = preview.connection else { return }
        if connection.isVideoRotationAngleSupported(angle) { connection.videoRotationAngle = angle }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
    }
}
#endif
