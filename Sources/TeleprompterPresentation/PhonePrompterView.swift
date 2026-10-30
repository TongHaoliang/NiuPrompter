#if os(iOS)
import SwiftUI
import UIKit
import TeleprompterCore

/// Phone-specific reading surface. Landscape trades a narrow side rail for full text height.
struct PhonePrompterView: View {
    @ObservedObject var model: ProbeViewModel
    @AppStorage("teleprompter.sideMarginFraction") private var margin = 0.10
    @AppStorage("teleprompter.fontSize") private var fontSize = 30.0
    @AppStorage("teleprompter.horizontalMirror") private var mirror = false
    @AppStorage("teleprompter.verticalFlip") private var flip = false
    @State private var editing = false
    @State private var settings = false

    private let background = Color(red: 0.045, green: 0.052, blue: 0.05)
    private var busy: Bool { model.isStarting || model.isPreparing }
    private var runColor: Color { model.isListening ? Color(red: 0.25, green: 0.88, blue: 0.51) : .yellow }

    var body: some View {
        GeometryReader { geometry in
            let landscape = geometry.size.width > geometry.size.height
            Group {
                if landscape {
                    HStack(spacing: 0) {
                        readingArea(landscape: true)
                        landscapeRail
                    }
                } else {
                    VStack(spacing: 0) {
                        readingArea(landscape: false)
                        portraitControls
                    }
                }
            }
            .overlay(alignment: .top) {
                if let error = model.errorMessage {
                    Text(error).font(.callout).padding(10)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                        .padding(.horizontal, landscape ? 80 : 16)
                }
            }
        }
        .foregroundStyle(.white)
        .tint(.white)
        .background(background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $editing) { editor }
        .onDisappear { Task { await model.stop() } }
#if DEBUG && targetEnvironment(simulator)
        .task {
            let arguments = ProcessInfo.processInfo.arguments
            guard arguments.contains("--ui-preview") else { return }
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: arguments.contains("--landscape") ? .landscapeRight : .portrait))
            }
            if arguments.contains("--following") { await model.start() }
            if arguments.contains("--settings") { settings = true }
            if arguments.contains("--editor") { editing = true }
        }
#endif
    }

    @ViewBuilder
    private func readingArea(landscape: Bool) -> some View {
        if model.segments.isEmpty {
            VStack(spacing: 16) {
                Image(systemName: "text.alignleft").font(.system(size: 28)).foregroundStyle(.white.opacity(0.5))
                Text("准备一份口播稿").font(.title3.weight(.semibold))
                Text("粘贴稿件，开始后跟着你的朗读前进")
                    .font(.subheadline).foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                Button { editing = true } label: {
                    Label("添加稿件", systemImage: "plus").font(.headline)
                        .padding(.horizontal, 22).frame(height: 44)
                        .foregroundStyle(.black).background(.yellow, in: Capsule())
                }.buttonStyle(.plain)
            }
            .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            PhoneScriptReader(segments: model.segments, activeID: model.promptSegmentID,
                              fontSize: fontSize, margin: margin, landscape: landscape) { id in
                Task { await model.selectSegment(id) }
            }
            .scaleEffect(x: mirror ? -1 : 1, y: flip ? -1 : 1)
        }
    }

    private var landscapeRail: some View {
        VStack(spacing: 4) {
            editButton
            Spacer(minLength: 4)
            runButton(compact: true)
            Spacer(minLength: 4)
            stepButton(previous: true)
            stepButton(previous: false)
            Spacer(minLength: 4)
            settingsButton
        }
        .padding(.vertical, 8).frame(width: 64)
        .background(Color.white.opacity(0.035))
        .overlay(alignment: .leading) { Color.white.opacity(0.07).frame(width: 1) }
    }

    private var portraitControls: some View {
        HStack(spacing: 8) {
            editButton
            stepButton(previous: true)
            runButton(compact: false)
            stepButton(previous: false)
            settingsButton
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color.white.opacity(0.035))
    }

    private var editButton: some View {
        Button {
            Task {
                if model.isListening { await model.stop() }
                editing = true
            }
        } label: {
            Image(systemName: "doc.text").font(.system(size: 20)).frame(width: 44, height: 44)
        }
        .buttonStyle(.plain).disabled(busy).accessibilityLabel("编辑稿件")
    }

    private func stepButton(previous: Bool) -> some View {
        Button {
            Task {
                if previous { await model.previousSegment() }
                else { await model.nextSegment() }
            }
        } label: {
            Image(systemName: previous ? "chevron.up" : "chevron.down")
                .font(.system(size: 17, weight: .medium)).frame(width: 44, height: 44)
        }
        .buttonStyle(.plain).disabled(busy || model.segments.isEmpty)
        .accessibilityLabel(previous ? "上一句" : "下一句")
    }

    private func runButton(compact: Bool) -> some View {
        Button {
            Task {
                if model.isListening { await model.stop() }
                else { await model.start() }
            }
        } label: {
            HStack(spacing: 6) {
                if busy { ProgressView().tint(.black) }
                else { Image(systemName: model.isListening ? "pause.fill" : "play.fill") }
                if !compact { Text(busy ? "准备" : model.isListening ? "暂停" : "开始") }
            }
            .font(.system(size: 18, weight: .semibold)).lineLimit(1)
            .frame(maxWidth: compact ? 48 : .infinity).frame(height: 48)
            .foregroundStyle(.black)
            .background(model.segments.isEmpty ? Color.white.opacity(0.15) : runColor,
                        in: RoundedRectangle(cornerRadius: 15))
        }
        .buttonStyle(.plain).disabled(busy || model.segments.isEmpty)
        .accessibilityLabel(model.isListening ? "暂停跟随" : "开始跟随")
        .accessibilityValue(busy ? "准备中" : model.isListening ? "已开启" : "已暂停")
    }

    private var settingsButton: some View {
        Button { settings = true } label: {
            Image(systemName: "slider.horizontal.3").font(.system(size: 20)).frame(width: 44, height: 44)
        }
        .buttonStyle(.plain).accessibilityLabel("字号与边距")
        .popover(isPresented: $settings) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("阅读设置").font(.headline)
                    Spacer()
                    Button("完成") { settings = false }
                }
                VStack(spacing: 4) {
                    LabeledContent("字号", value: "\(Int(fontSize))")
                    Slider(value: $fontSize, in: 24...48, step: 2).accessibilityLabel("字体大小")
                    LabeledContent("左右边距", value: "\(Int(margin * 100))%")
                    Slider(value: $margin, in: 0.05...0.25, step: 0.01).accessibilityLabel("左右边距")
                }
                HStack {
                    Toggle("镜像", isOn: $mirror)
                    Toggle("翻转", isOn: $flip)
                }.font(.subheadline)
                Button("恢复默认") { fontSize = 30; margin = 0.10 }
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(20).frame(width: 300)
            .tint(.yellow).preferredColorScheme(.dark)
            .presentationCompactAdaptation(.popover)
        }
    }

    private var editor: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 10) {
                let statistics = ScriptStatistics(text: model.scriptText)
                HStack {
                    Text("\(statistics.characterCount) 字 · 约 \(statistics.durationLabel)")
                        .font(.subheadline.monospacedDigit())
                    Spacer()
                    Button("示例稿") { _ = model.setScriptText(BuiltInScript.text) }
                        .font(.subheadline)
                }.foregroundStyle(.white.opacity(0.65))
                TextEditor(text: Binding(get: { model.scriptText }, set: { _ = model.setScriptText($0) }))
                    .font(.system(size: 19)).lineSpacing(6)
                    .scrollContentBackground(.hidden)
                    .overlay(alignment: .topLeading) {
                        if model.scriptText.isEmpty {
                            Text("在这里输入或粘贴稿件…").foregroundStyle(.white.opacity(0.35))
                                .padding(.top, 8).padding(.leading, 5).allowsHitTesting(false)
                        }
                    }
                Text("不含标点与空格 · 时长按250字/分钟估算")
                    .font(.caption).foregroundStyle(.white.opacity(0.45))
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
            .background(background)
            .navigationTitle("稿件").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { editing = false }.fontWeight(.semibold)
                }
            }
        }.preferredColorScheme(.dark).tint(.yellow)
    }
}

private struct PhoneScriptReader: View {
    let segments: [ScriptSegment]
    let activeID: Int?
    let fontSize: Double
    let margin: Double
    let landscape: Bool
    let select: (Int) -> Void

    var body: some View {
        GeometryReader { geometry in
            let topSpace: CGFloat = landscape ? 16 : 40
            let anchor = topSpace / max(1, geometry.size.height)
            let activeIndex = segments.firstIndex { $0.id == activeID } ?? 0
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        Color.clear.frame(height: topSpace)
                        ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                            let current = segment.id == activeID
                            Text(segment.originalText)
                                .font(.system(size: min(48, max(24, fontSize)), weight: current ? .semibold : .regular))
                                .lineSpacing(6)
                                .foregroundStyle(current ? .white : .white.opacity(index < activeIndex ? 0.40 : 0.76))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 4)
                                .overlay(alignment: .leading) {
                                    if current {
                                        Capsule().fill(Color.yellow.opacity(0.85))
                                            .frame(width: 3).offset(x: -14)
                                    }
                                }
                                .contentShape(Rectangle()).onTapGesture { select(segment.id) }
                                .accessibilityAddTraits(current ? [.isSelected] : [])
                                .id(segment.id)
                        }
                        Color.clear.frame(height: max(0, geometry.size.height - topSpace))
                    }
                    .padding(.horizontal, max(22, geometry.size.width * min(0.25, max(0.05, margin))))
                }
                .scrollIndicators(.hidden)
                .onChange(of: activeID, initial: true) { _, _ in
                    Task { @MainActor in
                        await Task.yield()
                        withAnimation(.easeOut(duration: 0.18)) {
                            if let target = activeID ?? segments.first?.id {
                                proxy.scrollTo(target, anchor: UnitPoint(x: 0.5, y: anchor))
                            }
                        }
                    }
                }
                .onChange(of: geometry.size) { _, _ in
                    if let target = activeID { proxy.scrollTo(target, anchor: UnitPoint(x: 0.5, y: anchor)) }
                }
                .onChange(of: fontSize) { _, _ in
                    if let target = activeID { proxy.scrollTo(target, anchor: UnitPoint(x: 0.5, y: anchor)) }
                }
                .onChange(of: margin) { _, _ in
                    if let target = activeID { proxy.scrollTo(target, anchor: UnitPoint(x: 0.5, y: anchor)) }
                }
            }
        }
    }
}
#endif
