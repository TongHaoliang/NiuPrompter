import SwiftUI
import TeleprompterCore

public struct HighlightedScriptView: View {
    let segments: [ScriptSegment]
    let currentSegmentID: Int?
    let fontSize: Double
    let sideMarginFraction: Double
    let compactLayout: Bool
    let onSelect: (Int) -> Void

    public init(segments: [ScriptSegment], currentSegmentID: Int?, fontSize: Double = 40,
                sideMarginFraction: Double = 0.20, compactLayout: Bool = false, onSelect: @escaping (Int) -> Void) {
        self.segments = segments
        self.currentSegmentID = currentSegmentID
        self.fontSize = fontSize
        self.sideMarginFraction = sideMarginFraction
        self.compactLayout = compactLayout
        self.onSelect = onSelect
    }

    public var body: some View {
        GeometryReader { geometry in
            let anchorY = compactLayout ? (geometry.size.height < 300 ? 0.08 : 0.14) : 0.38
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: compactLayout ? 12 : 16) {
                        Color.clear.frame(height: geometry.size.height * anchorY)
                            .accessibilityHidden(true)
                        ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                            let current = segment.id == currentSegmentID
                            Text(segment.originalText)
                                .font(.system(size: min(60, max(24, fontSize)), weight: current ? .semibold : .regular))
                                .lineSpacing(compactLayout ? 6 : 10)
                                .foregroundStyle(current ? Color.white : Color.white.opacity(index < activeIndex ? 0.52 : 0.78))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, compactLayout ? 6 : 10)
                                .padding(.horizontal, 14)
                                .background(current ? (compactLayout ? Color.white.opacity(0.045) : Color(red: 0.24, green: 0.20, blue: 0.12)) : .clear,
                                            in: RoundedRectangle(cornerRadius: 10))
                                .overlay(alignment: .leading) {
                                    if current {
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(Color(red: 0.91, green: 0.74, blue: 0.43))
                                            .frame(width: 3)
                                    }
                                }
                                .contentShape(Rectangle())
                                .onTapGesture { onSelect(segment.id) }
                                .accessibilityAddTraits(current ? [.isSelected] : [])
                                .id(segment.id)
                        }
                        Color.clear.frame(height: geometry.size.height * (1 - anchorY))
                            .accessibilityHidden(true)
                    }
                    // Margin includes row padding: a 1133pt canvas defaults to ~680pt text.
                    .padding(.horizontal, max(0, geometry.size.width * min(0.30, max(0.05, sideMarginFraction)) - 14))
                }
                .onChange(of: currentSegmentID, initial: true) { _, value in
                    guard let target = value ?? segments.first?.id else { return }
                    Task { @MainActor in
                        await Task.yield()
                        withAnimation(.easeInOut(duration: 0.18)) {
                            proxy.scrollTo(target, anchor: UnitPoint(x: 0.5, y: anchorY))
                        }
                    }
                }
                .onChange(of: sideMarginFraction) { _, _ in
                    if let currentSegmentID { proxy.scrollTo(currentSegmentID, anchor: UnitPoint(x: 0.5, y: anchorY)) }
                }
                .onChange(of: geometry.size) { _, _ in
                    if let currentSegmentID { proxy.scrollTo(currentSegmentID, anchor: UnitPoint(x: 0.5, y: anchorY)) }
                }
                .onChange(of: fontSize) { _, _ in
                    if let currentSegmentID { proxy.scrollTo(currentSegmentID, anchor: UnitPoint(x: 0.5, y: anchorY)) }
                }
            }
        }
        .background(Color(red: 0.055, green: 0.062, blue: 0.06))
    }

    private var activeIndex: Int {
        segments.firstIndex { $0.id == currentSegmentID } ?? 0
    }
}
