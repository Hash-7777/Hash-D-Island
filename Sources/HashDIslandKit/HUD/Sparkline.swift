import SwiftUI

/// A small filled line chart of recent samples, for readouts where the shape of
/// the last half-minute says more than the current number.
///
/// Values are given already normalised to 0...1, because only the caller knows
/// what its own ceiling means — a processor tops out at 1 by definition, where
/// a network graph has to pick a scale from what it has seen.
///
/// Draws nothing at all below two points. One sample is not a trend, and a
/// single dot on an axis reads as a fault rather than as "not enough yet".
public struct Sparkline: View {
    private let values: [Double]
    private let tint: Color

    public init(values: [Double], tint: Color) {
        self.values = values
        self.tint = tint
    }

    public var body: some View {
        GeometryReader { geo in
            if values.count >= 2 {
                let path = shape(in: geo.size)
                ZStack {
                    // The fill under the line does the work at this size; the
                    // line alone is too thin to read at a glance.
                    path.filled(in: geo.size)
                        .fill(
                            LinearGradient(
                                colors: [tint.opacity(0.38), tint.opacity(0.04)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    path.stroked
                        .stroke(tint, style: StrokeStyle(lineWidth: 1.2, lineJoin: .round))
                }
            }
        }
    }

    private func shape(in size: CGSize) -> Line {
        Line(values: values, size: size)
    }

    /// The points, shared by the stroke and the fill so they cannot drift apart.
    private struct Line {
        let values: [Double]
        let size: CGSize

        var points: [CGPoint] {
            guard values.count >= 2 else { return [] }
            let step = size.width / CGFloat(values.count - 1)
            return values.enumerated().map { index, value in
                let clamped = min(max(value, 0), 1)
                // Inset by a hair top and bottom so a flat line at either
                // extreme is still visible rather than welded to the edge.
                let y = size.height - 1 - CGFloat(clamped) * (size.height - 2)
                return CGPoint(x: CGFloat(index) * step, y: y)
            }
        }

        var stroked: Path {
            var path = Path()
            guard let first = points.first else { return path }
            path.move(to: first)
            for point in points.dropFirst() { path.addLine(to: point) }
            return path
        }

        func filled(in size: CGSize) -> Path {
            var path = stroked
            guard let first = points.first, let last = points.last else { return path }
            path.addLine(to: CGPoint(x: last.x, y: size.height))
            path.addLine(to: CGPoint(x: first.x, y: size.height))
            path.closeSubpath()
            return path
        }
    }
}
