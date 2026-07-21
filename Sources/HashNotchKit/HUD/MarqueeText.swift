import SwiftUI

private struct MarqueeTextWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// A single-line text that scrolls continuously when it does not fit — like
/// track titles on the iPhone. Short text renders as a plain label; long text
/// dwells briefly, glides left through a soft edge fade, and loops seamlessly.
///
/// Sizing works like `Text`: the view hugs short content and respects whatever
/// width cap the caller applies (`.frame(maxWidth:)`). Font and color are
/// inherited from the environment, so style it exactly like a `Text`.
public struct MarqueeText: View {
    private let text: String
    /// Scroll speed in points per second.
    private let speed: Double
    /// Gap between the end of the text and its looping copy.
    private let gap: CGFloat
    /// Pause at the start of every loop, in seconds.
    private let dwell: Double

    @State private var textWidth: CGFloat = 0

    public init(_ text: String, speed: Double = 30, gap: CGFloat = 36, dwell: Double = 1.4) {
        self.text = text
        self.speed = speed
        self.gap = gap
        self.dwell = dwell
    }

    private var label: some View {
        Text(text).lineLimit(1)
    }

    public var body: some View {
        label
            .opacity(0) // reserves the height and (capped) width
            .overlay(alignment: .leading) { marquee }
            .background(
                // Measure the full, uncapped text width.
                label.fixedSize().hidden().background(
                    GeometryReader { geo in
                        Color.clear.preference(key: MarqueeTextWidthKey.self, value: geo.size.width)
                    }
                )
            )
            .onPreferenceChange(MarqueeTextWidthKey.self) { textWidth = $0 }
            .id(text) // new title → fresh measurement and loop
    }

    @ViewBuilder
    private var marquee: some View {
        GeometryReader { geo in
            let available = geo.size.width
            if textWidth > available + 1 {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    let span = textWidth + gap
                    let cycle = dwell + Double(span) / speed
                    let t = context.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: cycle)
                    let distance = CGFloat(max(0, t - dwell) * speed)
                    HStack(spacing: gap) {
                        label.fixedSize()
                        label.fixedSize()
                    }
                    .offset(x: -min(distance, span))
                }
                .frame(width: available, height: geo.size.height, alignment: .leading)
                .clipped()
                .mask(
                    // Narrow fades: enough to soften glyphs entering/leaving,
                    // never wide enough to make the title's start look
                    // swallowed by the adjacent notch.
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: 0.035),
                            .init(color: .black, location: 0.965),
                            .init(color: .clear, location: 1),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
            } else {
                label
            }
        }
    }
}
