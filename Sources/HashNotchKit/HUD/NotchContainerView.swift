import SwiftUI

/// Lays the features out around the physical notch, driven entirely by settings.
///
/// Which features show, on which side, in what order, and how far from the notch
/// all come from `SettingsStore`, so the customization window can rearrange the
/// HUD live. The compact row keeps a transparent gap the exact size of the notch
/// between the two halves; hovering springs the expanded panel open below.
struct NotchContainerView: View {
    @ObservedObject var state: NotchState
    @ObservedObject var settings: SettingsStore
    let registry: FeatureRegistry
    let context: FeatureContext

    var body: some View {
        VStack(spacing: 6) {
            compactRow
            if state.isExpanded {
                expandedPanel
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .onHover { hovering in
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                state.isExpanded = hovering
            }
        }
    }

    private var compactRow: some View {
        HStack(spacing: 0) {
            HStack(spacing: settings.layout.itemSpacing) {
                Spacer(minLength: 0)
                featureViews(for: .leading)
            }
            .padding(.trailing, settings.layout.leadingInset)
            .frame(width: state.sideWidth, alignment: .trailing)

            Color.clear
                .frame(width: state.notchWidth, height: state.notchHeight)

            HStack(spacing: settings.layout.itemSpacing) {
                featureViews(for: .trailing)
                Spacer(minLength: 0)
            }
            .padding(.leading, settings.layout.trailingInset)
            .frame(width: state.sideWidth, alignment: .leading)
        }
        .frame(height: state.notchHeight)
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .scaleEffect(state.isExpanded ? 1.03 : 1.0, anchor: .top)
    }

    private var expandedPanel: some View {
        HStack(alignment: .top, spacing: 20) {
            ForEach(enabledFeatures, id: \.id) { feature in
                if let view = feature.makeExpandedView(context: context) {
                    view
                }
            }
        }
        .font(.system(size: 11, weight: .medium, design: .rounded))
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: context.theme.cornerRadius, style: .continuous)
                .fill(context.theme.pillBackground)
        )
        .fixedSize()
    }

    @ViewBuilder
    private func featureViews(for placement: FeaturePlacement) -> some View {
        ForEach(features(for: placement), id: \.id) { feature in
            feature.makeView(context: context)
        }
    }

    /// Enabled features assigned to a placement, in the user's chosen order.
    private func features(for placement: FeaturePlacement) -> [NotchFeature] {
        registry.features.enumerated()
            .map { (feature: $0.element, config: settings.config(for: $0.element, index: $0.offset)) }
            .filter { $0.config.enabled && $0.config.placement == placement }
            .sorted { $0.config.order < $1.config.order }
            .map { $0.feature }
    }

    private var enabledFeatures: [NotchFeature] {
        registry.features.enumerated()
            .filter { settings.config(for: $0.element, index: $0.offset).enabled }
            .map { $0.element }
    }
}
