import SwiftUI

/// The black interactive notch.
///
/// Collapsed, it is a black shape the size of the physical notch with a small
/// rounded lip — it looks like the notch itself. On hover it grows into a
/// rounded black panel that drops down below the menu bar and reveals the
/// readouts. Everything appears below the menu bar, so it never overlaps menus
/// or status items.
struct NotchIslandView: View {
    @ObservedObject var state: NotchState
    @ObservedObject var settings: SettingsStore
    let registry: FeatureRegistry
    let context: FeatureContext

    var body: some View {
        VStack(spacing: 0) {
            island
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var island: some View {
        ZStack(alignment: .top) {
            shape
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.10), Color.black],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(shape.strokeBorder(Color.white.opacity(0.10), lineWidth: 0.6))
                .shadow(color: .black.opacity(state.isExpanded ? 0.6 : 0), radius: 16, y: 10)

            if state.isExpanded {
                content
                    .padding(.top, state.notchHeight + 12)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                    .transition(.opacity.combined(with: .offset(y: -10)))
            }
        }
        .frame(
            width: state.isExpanded ? state.expandedWidth : state.collapsedWidth,
            height: state.isExpanded ? state.expandedHeight : state.collapsedHeight
        )
    }

    private var shape: some InsettableShape {
        UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: state.isExpanded ? 26 : 10,
            bottomTrailingRadius: state.isExpanded ? 26 : 10,
            topTrailingRadius: 0,
            style: .continuous
        )
    }

    private var content: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                ForEach(enabledFeatures, id: \.id) { feature in
                    feature.makeView(context: context)
                }
            }
            .font(.system(size: 12, weight: .semibold, design: .rounded))

            ForEach(enabledFeatures, id: \.id) { feature in
                if let detail = feature.makeExpandedView(context: context) {
                    detail
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var enabledFeatures: [NotchFeature] {
        registry.features.enumerated()
            .map { (feature: $0.element, config: settings.config(for: $0.element, index: $0.offset)) }
            .filter { $0.config.enabled }
            .sorted { $0.config.order < $1.config.order }
            .map { $0.feature }
    }
}
