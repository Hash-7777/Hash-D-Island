import AppKit
import SwiftUI

/// Owns the overlay window and hosts the SwiftUI HUD inside it.
///
/// This is the top-level object the app creates. Hand it a registry of features
/// and it positions a full-width strip across the top of the notched screen and
/// renders the HUD there.
@MainActor
public final class NotchWindowController {
    private let window: NotchWindow
    private let state: NotchState
    private let registry: FeatureRegistry
    private let context: FeatureContext

    /// Height of the top strip the overlay reserves — enough for the compact row
    /// plus room for the expanded panel to animate open.
    private static let stripHeight: CGFloat = 260

    public init(registry: FeatureRegistry, context: FeatureContext) {
        self.registry = registry
        self.context = context

        let screen = NotchGeometry.preferredScreen() ?? NSScreen.main!
        let geometry = NotchGeometry.current(for: screen)
        self.state = NotchState(geometry: geometry)

        let frame = NSRect(
            x: screen.frame.minX,
            y: screen.frame.maxY - Self.stripHeight,
            width: screen.frame.width,
            height: Self.stripHeight
        )
        self.window = NotchWindow(contentRect: frame)

        let root = NotchContainerView(
            state: state,
            settings: context.settings,
            registry: registry,
            context: context
        )
        .frame(width: frame.width, height: frame.height, alignment: .top)

        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(origin: .zero, size: frame.size)
        hosting.autoresizingMask = [.width, .height]

        // Only the notch cluster (centered at the top) should catch the mouse;
        // the rest of the strip passes clicks through to the menu bar.
        let container = PassthroughContainerView(frame: NSRect(origin: .zero, size: frame.size))
        let clusterWidth = state.notchWidth + 400
        let clusterHeight: CGFloat = state.notchHeight + 140
        container.interactiveFrame = CGRect(
            x: (frame.width - clusterWidth) / 2,
            y: frame.height - clusterHeight,
            width: clusterWidth,
            height: clusterHeight
        )
        container.addSubview(hosting)
        window.contentView = container
    }

    public func show() {
        window.orderFrontRegardless()
    }

    public func hide() {
        window.orderOut(nil)
    }
}
