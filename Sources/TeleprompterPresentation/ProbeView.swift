import SwiftUI
#if os(iOS)
import UIKit
#endif
import TeleprompterCore
import TeleprompterSpeech

public struct ProbeView: View {
    @StateObject private var viewModel: ProbeViewModel
    @State private var isEditorPresented = false
    @State private var isDiagnosticsPresented = false
    @State private var isDisplayPresented = false
    @AppStorage("teleprompter.sideMarginFraction") private var sideMarginFraction = 0.20
    @AppStorage("teleprompter.fontSize") private var readingFontSize = 40.0
    @AppStorage("teleprompter.horizontalMirror") private var isHorizontallyMirrored = false
    @AppStorage("teleprompter.verticalFlip") private var isVerticallyFlipped = false

    private static var isPhone: Bool {
#if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone
#else
        false
#endif
    }
    private var defaultMargin: Double { Self.isPhone ? 0.10 : 0.20 }
    private var defaultFontSize: Double { Self.isPhone ? 30 : 40 }

    public init(engine: any SpeechRecognitionEngine) {
        _sideMarginFraction = AppStorage(wrappedValue: Self.isPhone ? 0.10 : 0.20, "teleprompter.sideMarginFraction")
        _readingFontSize = AppStorage(wrappedValue: Self.isPhone ? 30.0 : 40.0, "teleprompter.fontSize")
        let model = ProbeViewModel(engine: engine)
#if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--ui-preview") {
            _ = model.setScriptText(BuiltInScript.text)
        }
#endif
        _viewModel = StateObject(wrappedValue: model)
    }

    public var body: some View {
#if os(iOS)
        if Self.isPhone { PhonePrompterView(model: viewModel) }
        else { iPadBody }
#else
        macBody
#endif
    }

    private var iPadBody: some View {
        VStack(spacing: 0) {
            if !viewModel.isListening {
                HStack {
                    Button { isEditorPresented = true } label: {
                        Label("编辑稿件", systemImage: "doc.text.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .padding(.horizontal, 8)
                            .frame(minHeight: 36)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.91, green: 0.74, blue: 0.43))
                    .foregroundStyle(.black)
                    .accessibilityHint("打开稿件编辑")
                    .disabled(viewModel.isStarting || viewModel.isPreparing)
                    Spacer()
                }
                .padding(.horizontal, 24).frame(height: 56)
            }

            scriptPanel.frame(maxWidth: .infinity, maxHeight: .infinity)

            if viewModel.isPreparing {
                ProgressView(value: viewModel.engineStatus.downloadProgress)
                    .tint(.yellow).padding(.horizontal, 24)
            }
            if let error = viewModel.errorMessage {
                Text(error).font(.callout).foregroundStyle(.orange).padding(8)
            }
            if Self.isPhone {
                phoneControls
            } else {
            HStack(spacing: 20) {
                Text("\((viewModel.currentSegmentID ?? -1) + 1) / \(viewModel.segments.count)")
                    .font(.subheadline.monospacedDigit()).foregroundStyle(.white.opacity(0.6))
                Spacer()
                Button { Task { await viewModel.previousSegment() } } label: {
                    Image(systemName: "arrow.up").frame(width: 44, height: 44)
                }.accessibilityLabel("上一句")
                    .disabled(viewModel.isPreparing || viewModel.isStarting || viewModel.currentSegmentID == nil)
                iPadFollowButton
                Button { Task { await viewModel.nextSegment() } } label: {
                    Image(systemName: "arrow.down").frame(width: 44, height: 44)
                }.accessibilityLabel("下一句")
                    .disabled(viewModel.isPreparing || viewModel.isStarting || viewModel.currentSegmentID == nil)
                Spacer()
                Button { isHorizontallyMirrored.toggle() } label: {
                    Label("镜像", systemImage: "arrow.left.and.right").frame(minHeight: 44)
                }.tint(isHorizontallyMirrored ? .yellow : .white)
                Button { isDisplayPresented = true } label: {
                    Label("字号 / 边距", systemImage: "textformat.size").frame(minHeight: 44)
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 12)
            .background(Color.white.opacity(0.035))
            }
        }
        .foregroundStyle(.white)
        .tint(.white)
        .background(Color(red: 0.055, green: 0.062, blue: 0.06).ignoresSafeArea())
        .preferredColorScheme(.dark)
        .sheet(isPresented: $isDisplayPresented) {
            NavigationStack {
                Form {
                    Section("左右间距") {
                        LabeledContent("左右边距（每侧）", value: "\(Int(sideMarginFraction * 100))%")
                        Slider(value: $sideMarginFraction, in: Self.isPhone ? 0.05...0.25 : 0.10...0.30, step: 0.01)
                            .accessibilityLabel("左右边距")
                        Text("增加边距，让视线更集中；只调整正文，不影响操作按钮。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Section("字体大小") {
                        LabeledContent("字体大小", value: "\(Int(readingFontSize))")
                        Slider(value: $readingFontSize, in: Self.isPhone ? 24...48 : 28...60, step: 2).accessibilityLabel("字号")
                        Text("当前句最亮，后文稍暗但清晰，已读内容再暗一级。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Section("提词器方向") {
                        Toggle("左右镜像", isOn: $isHorizontallyMirrored)
                        Toggle("上下翻转", isOn: $isVerticallyFlipped)
                    }
                    Section {
                        Button("恢复阅读默认值") { sideMarginFraction = defaultMargin; readingFontSize = defaultFontSize }
                        NavigationLink("诊断信息") { debugPanel.navigationTitle("诊断信息") }
                    }
                }
                .navigationTitle("字号与边距")
                .toolbar { ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { isDisplayPresented = false }
                } }
            }.preferredColorScheme(.dark)
        }
        .sheet(isPresented: $isEditorPresented) {
            NavigationStack {
                editorPanel
                    .padding(18)
                    .frame(maxWidth: 820, maxHeight: .infinity)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.ignoresSafeArea())
                    .navigationTitle("稿件")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("完成") { isEditorPresented = false }
                        }
                    }
            }
            .preferredColorScheme(.dark)
            .presentationDetents([.large])
        }
        .sheet(isPresented: $isDiagnosticsPresented) {
            NavigationStack {
                debugPanel
                    .padding(18)
                    .frame(maxWidth: 820, maxHeight: .infinity)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.ignoresSafeArea())
                    .navigationTitle("诊断信息")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("完成") { isDiagnosticsPresented = false }
                        }
                    }
            }
            .preferredColorScheme(.dark)
            .presentationDetents([.large])
        }
#if DEBUG && targetEnvironment(simulator)
        .task {
            let arguments = ProcessInfo.processInfo.arguments
            guard arguments.contains("--ui-preview") else { return }
            if arguments.contains("--landscape"),
               let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight))
            }
            if arguments.contains("--following") { await viewModel.start() }
        }
#endif
        .onDisappear { Task { await viewModel.stop() } }
    }

    private var phoneControls: some View {
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                Button { Task { await viewModel.previousSegment() } } label: {
                    Image(systemName: "chevron.up").frame(width: 44, height: 44)
                }.accessibilityLabel("上一句")
                Button { Task { await viewModel.nextSegment() } } label: {
                    Image(systemName: "chevron.down").frame(width: 44, height: 44)
                }.accessibilityLabel("下一句")
            }
            .font(.system(size: 17, weight: .semibold))
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
            .disabled(viewModel.isPreparing || viewModel.isStarting || viewModel.currentSegmentID == nil)

            Button {
                Task {
                    if viewModel.isListening { await viewModel.stop() }
                    else { await viewModel.start() }
                }
            } label: {
                HStack(spacing: 8) {
                    if viewModel.isPreparing || viewModel.isStarting {
                        ProgressView().tint(.black)
                        Text("准备中")
                    } else {
                        Image(systemName: viewModel.isListening ? "pause.fill" : "play.fill")
                        Text(viewModel.isListening ? "跟随中" : "开始跟随")
                    }
                }
                .font(.system(size: 17, weight: .semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity).frame(height: 48)
                .foregroundStyle(.black)
                .background(followingColor, in: RoundedRectangle(cornerRadius: 14))
                .opacity(viewModel.segments.isEmpty ? 0.45 : 1)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isStarting || viewModel.isPreparing || viewModel.segments.isEmpty)
            .accessibilityLabel(viewModel.isListening ? "暂停跟随" : "开始跟随")
            .accessibilityValue(followingStatus)

            Button { isDisplayPresented = true } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 20, weight: .medium))
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
            }
            .accessibilityLabel("字号与边距设置")
        }
        .buttonStyle(.plain)
        .frame(maxWidth: 440)
        .padding(.horizontal, 16).padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(Color(red: 0.075, green: 0.082, blue: 0.08))
    }

    private var followingNeedsAttention: Bool {
        viewModel.errorMessage != nil || viewModel.engineStatus.phase == .failed
    }

    // Color conveys only whether the microphone session is running.
    // Transient matching hypotheses must not distract the speaker.
    private var followingColor: Color {
        viewModel.isListening ? Color(red: 0.25, green: 0.88, blue: 0.51) : .yellow
    }

    private var followingStatus: String {
        if followingNeedsAttention { return "识别已停止，请重新开始" }
        if viewModel.isPreparing { return "准备中文识别…" }
        if viewModel.isStarting { return "正在启动…" }
        return viewModel.isListening ? "跟随已开启" : "已暂停"
    }

    private var iPadFollowButton: some View {
        Button {
            Task {
                if viewModel.isListening { await viewModel.stop() }
                else { await viewModel.start() }
            }
        } label: {
            HStack(spacing: 10) {
                if viewModel.isPreparing || viewModel.isStarting {
                    ProgressView().tint(.black)
                    Text(viewModel.isPreparing ? "准备识别…" : "正在启动…")
                } else if viewModel.isListening {
                    Image(systemName: "pause.fill")
                    Text("跟随中 · 暂停")
                } else {
                    Image(systemName: "play.fill")
                    Text(followingNeedsAttention ? "重新开始" : "开始跟随")
                }
            }
            .font(.system(size: Self.isPhone ? 18 : 20, weight: .bold))
            .frame(minWidth: Self.isPhone ? 140 : 190, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(followingColor)
        .foregroundStyle(.black)
        .disabled(viewModel.isStarting || viewModel.isPreparing || viewModel.segments.isEmpty)
        .accessibilityLabel(viewModel.isListening ? "暂停跟随" : "开始跟随")
        .accessibilityValue(followingStatus)
    }

    private var macBody: some View {
        VStack(spacing: 12) {
            statusPanel
            controlPanel
            liveRecognitionPanel
            GeometryReader { geometry in
                if geometry.size.width >= 1_100 {
                    HStack(spacing: 14) {
                        editorPanel.frame(width: 330)
                        scriptPanel.frame(maxWidth: .infinity)
                        debugPanel.frame(width: 320)
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 14) {
                            editorPanel.frame(minHeight: 260)
                            scriptPanel.frame(minHeight: 380)
                            debugPanel.frame(minHeight: 300)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .frame(minWidth: 760, minHeight: 620)
        .onDisappear { Task { await viewModel.stop() } }
    }

    private var statusPanel: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text("智能跟随提词器")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("系统：\(ProcessInfo.processInfo.operatingSystemVersionString)  ·  locale：\(viewModel.engineStatus.localeIdentifier ?? "zh-CN（尚未准备）")")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 5) {
                Text("引擎：\(phaseText(viewModel.engineStatus.phase))")
                Text("zh-CN：\(viewModel.engineStatus.localeSupported ? "支持" : "未确认")  ·  模型：\(modelText(viewModel.engineStatus.modelState))")
                Text("麦克风：\(micText(viewModel.engineStatus.microphoneAuthorization))  ·  Speech：\(viewModel.engineStatus.speechAvailable ? "可用" : "未确认")")
            }
            .font(.caption)
            .foregroundStyle(.white.opacity(0.82))
        }
        .padding(14)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private var controlPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                startFollowingButton
                Button("停止") { Task { await viewModel.stop() } }
                    .disabled(viewModel.isPreparing || (!viewModel.isListening && !viewModel.isStarting))
                Button("上一段") { Task { await viewModel.previousSegment() } }
                    .disabled(viewModel.currentSegmentID == nil)
                Button("下一段") { Task { await viewModel.nextSegment() } }
                    .disabled(viewModel.currentSegmentID == nil)
                Button("清空识别缓存") { Task { await viewModel.clearRecognitionCache() } }
                    .disabled(viewModel.isPreparing)
#if os(iOS)
                Button("稿件") { isEditorPresented = true }
                Button("诊断") { isDiagnosticsPresented = true }
#endif
                Spacer(minLength: 0)
            }
            if viewModel.engineStatus.modelState == .downloading {
                ProgressView(value: viewModel.engineStatus.downloadProgress)
                    .tint(.yellow)
                    .accessibilityLabel("中文模型下载进度")
            }
            if let error = viewModel.errorMessage ?? viewModel.engineStatus.message {
                Text(error).font(.callout).foregroundStyle(.orange)
            }
        }
        .buttonStyle(.bordered)
    }

    private var startFollowingButton: some View {
        Button {
            Task { await viewModel.start() }
        } label: {
            if viewModel.isPreparing {
                Label("准备模型中…", systemImage: "arrow.down.circle")
            } else if viewModel.isStarting {
                Label("正在启动…", systemImage: "hourglass")
            } else {
                Label("开始跟随", systemImage: "play.fill")
            }
        }
        .disabled(viewModel.isListening || viewModel.isStarting || viewModel.isPreparing || viewModel.segments.isEmpty)
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .font(.headline)
        .tint(.yellow)
    }

    private var iPadControlSidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("智能跟随提词器")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 5) {
                    Label(phaseText(viewModel.engineStatus.phase), systemImage: "waveform")
                    Text("中文模型：\(modelText(viewModel.engineStatus.modelState))")
                    Text("麦克风：\(micText(viewModel.engineStatus.microphoneAuthorization))")
                }
                .font(.caption)
                .foregroundStyle(.white.opacity(0.75))

                Divider().overlay(Color.white.opacity(0.2))

                VStack(spacing: 8) {
                    startFollowingButton
                        .frame(maxWidth: .infinity)
                    Button("停止") { Task { await viewModel.stop() } }
                        .disabled(viewModel.isPreparing || (!viewModel.isListening && !viewModel.isStarting))

                    HStack(spacing: 8) {
                        Button("上一段") { Task { await viewModel.previousSegment() } }
                            .disabled(viewModel.currentSegmentID == nil)
                        Button("下一段") { Task { await viewModel.nextSegment() } }
                            .disabled(viewModel.currentSegmentID == nil)
                    }

                    Button("稿件") { isEditorPresented = true }
                    Button("诊断信息") { isDiagnosticsPresented = true }
                    Button("清空识别缓存") { Task { await viewModel.clearRecognitionCache() } }
                        .disabled(viewModel.isPreparing)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .frame(maxWidth: .infinity)

                Divider().overlay(Color.white.opacity(0.2))

                Text("画面方向")
                    .font(.caption.bold())
                    .foregroundStyle(.white.opacity(0.75))
                flipButton(
                    title: "左右镜像",
                    symbol: "arrow.left.and.right",
                    isEnabled: $isHorizontallyMirrored
                )
                flipButton(
                    title: "上下翻转",
                    symbol: "arrow.up.and.down",
                    isEnabled: $isVerticallyFlipped
                )

                if viewModel.engineStatus.modelState == .downloading {
                    ProgressView(value: viewModel.engineStatus.downloadProgress)
                        .tint(.yellow)
                        .accessibilityLabel("中文模型下载进度")
                }
                if let error = viewModel.errorMessage ?? viewModel.engineStatus.message {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
        }
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    private var iPadInfoSidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Label("实时识别", systemImage: "waveform")
                    .font(.headline)
                    .foregroundStyle(.yellow)

                if let event = viewModel.latestRecognitionEvent {
                    Text(event.text.isEmpty ? "识别文本为空" : event.text)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("\(event.stability == .volatile ? "临时结果" : "最终结果") · #\(event.revision)")
                        .font(.caption)
                        .foregroundStyle(event.stability == .volatile ? .yellow : .green)
                    Text("音频位置：\(event.audioStart.formatted(.number.precision(.fractionLength(1))))–\(event.audioEnd.formatted(.number.precision(.fractionLength(1)))) 秒")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.65))
                } else {
                    Text(viewModel.isListening ? "正在听你说话，识别结果会显示在这里。" : "开始跟随后，实时识别内容会显示在这里。")
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.65))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider().overlay(Color.white.opacity(0.2))

                Text("跟读进度")
                    .font(.caption.bold())
                    .foregroundStyle(.white.opacity(0.7))
                Text("第 \((viewModel.currentSegmentID ?? -1) + 1) / \(viewModel.segments.count) 段")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                if let candidate = viewModel.currentCandidate {
                    Text("候选第 \(candidate.segmentID + 1) 段 · \(candidate.confidence.formatted(.number.precision(.fractionLength(2))))")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider().overlay(Color.white.opacity(0.2))

                Text("Speech：\(viewModel.engineStatus.speechAvailable ? "可用" : "未确认")")
                Text("中文：\(viewModel.engineStatus.localeSupported ? "支持" : "未确认")")
                Text("事件：\(viewModel.receivedEventCount)")
            }
            .font(.caption)
            .foregroundStyle(.white.opacity(0.72))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    private func flipButton(title: String, symbol: String, isEnabled: Binding<Bool>) -> some View {
        Button {
            isEnabled.wrappedValue.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                Text(title)
                Spacer(minLength: 0)
                if isEnabled.wrappedValue {
                    Image(systemName: "checkmark")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .tint(isEnabled.wrappedValue ? .yellow : .gray)
        .accessibilityLabel(title)
        .accessibilityValue(isEnabled.wrappedValue ? "开启" : "关闭")
    }

    private var editorPanel: some View {
        let statistics = ScriptStatistics(text: viewModel.scriptText)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("稿件").font(.headline).foregroundStyle(.white)
                Spacer()
                Button("载入测试稿") {
                    _ = viewModel.setScriptText(BuiltInScript.text)
                }
            }
            HStack(spacing: 16) {
                Label("\(statistics.characterCount) 字", systemImage: "textformat.123")
                Label("预计 \(statistics.durationLabel)", systemImage: "clock")
            }
            .font(.subheadline.weight(.semibold).monospacedDigit())
            .foregroundStyle(.white)
            Text("不含标点与空格 · 按每分钟约250字估算，实际随语速和停顿变化")
                .font(.caption).foregroundStyle(.white.opacity(0.65))
            TextEditor(text: Binding(
                get: { viewModel.scriptText },
                set: { _ = viewModel.setScriptText($0) }
            ))
            .font(.system(size: 16))
            .scrollContentBackground(.hidden)
            .padding(8)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
            .disabled(viewModel.isListening || viewModel.isStarting)

            Text("\(viewModel.segments.count) 段 · 自动切分 · 点选段落可跳转")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.65))
        }
    }

    private var liveRecognitionPanel: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: "waveform")
                    .foregroundStyle(.yellow)
                Text("实时识别")
                    .font(.headline)
                    .foregroundStyle(.white)
                if let event = viewModel.latestRecognitionEvent {
                    Text(event.stability == .volatile ? "临时" : "最终")
                        .font(.caption.bold())
                        .foregroundStyle(event.stability == .volatile ? .yellow : .green)
                    Text("#\(event.revision)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.55))
                }
                Spacer()
            }

            if let event = viewModel.latestRecognitionEvent {
                Text(event.text.isEmpty ? "已收到识别事件，但文本为空" : event.text)
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(.white)
                    .textSelection(.enabled)
                    .lineLimit(3)

                HStack(spacing: 12) {
                    Text("音频位置：\(event.audioStart.formatted(.number.precision(.fractionLength(1))))–\(event.audioEnd.formatted(.number.precision(.fractionLength(1)))) 秒")
                    if let receivedAt = viewModel.latestRecognitionReceivedAt {
                        Text("收到：\(receivedAt.formatted(date: .omitted, time: .standard))")
                    }
                    Spacer(minLength: 0)
                    if let candidate = viewModel.currentCandidate {
                        Text("候选第 \(candidate.segmentID + 1) 段 · \(candidate.confidence.formatted(.number.precision(.fractionLength(2)))) · \(candidate.reason)")
                    } else {
                        Text("当前稿件：第 \((viewModel.currentSegmentID ?? -1) + 1) 段 · 尚无匹配候选")
                    }
                }
                .font(.caption)
                .foregroundStyle(.white.opacity(0.66))
                .lineLimit(2)
            } else {
                Text(viewModel.isListening ? "正在听你说话；识别文本会在说话过程中持续更新。" : "开始跟随后，这里会显示临时和最终识别结果。")
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.65))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(Color.yellow.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.yellow.opacity(0.28), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private var scriptPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            if viewModel.segments.isEmpty {
                ContentUnavailableView("还没有稿件", systemImage: "text.alignleft", description: Text("载入测试稿或粘贴自己的稿件，稿件会自动切分。"))
                    .foregroundStyle(.white)
            } else {
                HighlightedScriptView(
                    segments: viewModel.segments,
                    currentSegmentID: viewModel.promptSegmentID,
                    fontSize: readingFontSize,
                    sideMarginFraction: sideMarginFraction,
                    compactLayout: Self.isPhone,
                    onSelect: { id in Task { await viewModel.selectSegment(id) } }
                )
                .scaleEffect(
                    x: isHorizontallyMirrored ? -1 : 1,
                    y: isVerticallyFlipped ? -1 : 1
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private var debugPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 11) {
                Text("诊断信息").font(.headline).foregroundStyle(.white)
                debugText("最终识别", value: viewModel.finalTranscript)
                debugText("临时识别", value: viewModel.volatileTranscript)
                debugText("最近匹配缓冲", value: viewModel.recentRecognition)
                if let candidate = viewModel.currentCandidate {
                    debugText("当前候选", value: "段 \(candidate.segmentID) · 分数 \(candidate.confidence.formatted(.number.precision(.fractionLength(3))))\n\(candidate.reason)")
                } else {
                    debugText("当前候选", value: "暂无可靠候选")
                }
                debugText("当前段", value: viewModel.currentSegment?.originalText ?? "—")
                debugText("收到事件", value: "\(viewModel.receivedEventCount)")
                VStack(alignment: .leading, spacing: 5) {
                    Text("最近 5 次游标变化").font(.caption.bold()).foregroundStyle(.white.opacity(0.7))
                    ForEach(viewModel.cursorHistory) { change in
                        Text("段 \(change.segmentID) · \(change.reason)")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        }
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }

    private func debugText(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.bold()).foregroundStyle(.white.opacity(0.7))
            Text(value.isEmpty ? "—" : value)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(.white)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func phaseText(_ phase: EngineStatus.Phase) -> String {
        switch phase {
        case .idle: "空闲"
        case .preparing: "准备中"
        case .ready: "就绪"
        case .listening: "监听中"
        case .stopping: "停止中"
        case .failed: "错误"
        }
    }

    private func modelText(_ model: EngineStatus.ModelState) -> String {
        switch model {
        case .notInstalled: "未安装"
        case .downloading: "下载中 \(Int(viewModel.engineStatus.downloadProgress * 100))%"
        case .installed: "已安装"
        case .failed: "失败"
        }
    }

    private func micText(_ mic: EngineStatus.MicrophoneAuthorization) -> String {
        switch mic {
        case .notDetermined: "未询问"
        case .granted: "已授权"
        case .denied: "已拒绝"
        case .restricted: "受限制"
        }
    }
}
