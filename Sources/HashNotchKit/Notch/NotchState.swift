import SwiftUI

/// Observable UI state for the notch HUD: expansion and the measured geometry
/// the layout needs. Features never touch this — it drives the container only.
@MainActor
public final class NotchState: ObservableObject {
    /// Whether the expanded panel below the notch is showing.
    @Published public var isExpanded: Bool = false

    public let totalWidth: CGFloat
    public let notchWidth: CGFloat
    public let notchHeight: CGFloat

    /// Width available on each side of the notch, so the compact readouts line
    /// up precisely against the physical cutout.
    public var sideWidth: CGFloat {
        max(0, (totalWidth - notchWidth) / 2)
    }

    public init(geometry: NotchGeometry) {
        self.totalWidth = geometry.screenFrame.width
        self.notchWidth = geometry.notchRect.width
        self.notchHeight = max(geometry.notchRect.height, 28)
    }

    public func toggleExpanded() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            isExpanded.toggle()
        }
    }
}
