import SwiftUI

/// The playing indicator: a small set of dancing equalizer bars, like the
/// iPhone's Dynamic Island. The bars move ONLY while audio is actually playing
/// (`isActive`) and rest as small dots when paused — they are driven by the
/// playback state, never by capturing audio (listening to system output would
/// need invasive permissions this app refuses on principle; see SECURITY.md).
struct AudioBarsView: View {
    let isActive: Bool
    var tint: Color = .white

    private let barCount = 4
    private let barWidth: CGFloat = 2.5
    private let spacing: CGFloat = 2.5
    private let minHeight: CGFloat = 3
    private let maxHeight: CGFloat = 12

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: !isActive)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: spacing) {
                ForEach(0..<barCount, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(tint)
                        .frame(width: barWidth, height: height(index, t))
                }
            }
        }
        .frame(height: maxHeight)
        .animation(.easeOut(duration: 0.25), value: isActive)
    }

    private func height(_ index: Int, _ t: Double) -> CGFloat {
        guard isActive else { return minHeight }
        // Two incommensurate sine waves per bar, phase-shifted per index →
        // an organic, never-quite-repeating dance.
        let phase = Double(index) * 1.7
        let a = sin(t * 4.1 + phase)
        let b = sin(t * 2.3 + phase * 1.9 + 0.8)
        let level = 0.5 + 0.5 * (0.6 * a + 0.4 * b)
        return minHeight + CGFloat(level) * (maxHeight - minHeight)
    }
}
