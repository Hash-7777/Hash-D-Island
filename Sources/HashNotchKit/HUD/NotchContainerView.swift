import SwiftUI

/// Width of the (always-measured) left cluster, used to decide whether it fits
/// beside the app's menus.
private struct LeadingWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Lays the features out around the physical notch, driven entirely by settings.
///
/// Which features show, on which side, in what order, and how far from the notch
/// all come from `SettingsStore`. When "avoid menus" is on and the left readout
/// won't fit beside the frontmost app's menus, it is automatically moved to the
/// right so it never overlaps. Hovering springs the expanded panel open below.
struct NotchContainerView: View {
    @ObservedObject var state: NotchState
    @ObservedObject var settings: SettingsStore
    let registry: FeatureRegistry
    let context: FeatureContext

    @State private var measuredLeadingWidth: CGFloat = 0

    var body: some View {
        VStack(spacing: 6) {
            compactRow
            if state.isExpanded {
                expandedPanel
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .background(measurementProbe)
        .onPreferenceChange(LeadingWidthKey.self) { measuredLeadingWidth = $0 }
    }

    private var compactRow: some View {
        HStack(spacing: 0) {
            HStack(spacing: settings.layout.itemSpacing) {
                Spacer(minLength: 0)
                views(for: leftFeatures)
            }
            .padding(.trailing, settings.layout.leadingInset)
            .frame(width: state.sideWidth, alignment: .trailing)

            Color.clear
                .frame(width: state.notchWidth, height: state.notchHeight)

            HStack(spacing: settings.layout.itemSpacing) {
                views(for: rightFeatures)
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

    /// Always renders the leading features off-screen to measure their width, so
    /// the fit decision is stable no matter where they end up drawn.
    private var measurementProbe: some View {
        HStack(spacing: settings.layout.itemSpacing) {
            views(for: features(for: .leading))
        }
        .fixedSize()
        .hidden()
        .background(GeometryReader { geometry in
            Color.clear.preference(key: LeadingWidthKey.self, value: geometry.size.width)
        })
    }

    @ViewBuilder
    private func views(for features: [NotchFeature]) -> some View {
        ForEach(features, id: \.id) { feature in
            feature.makeView(context: context)
        }
    }

    // MARK: Placement (with automatic menu avoidance)

    /// True when the left readout can't fit beside the app's menus and should
    /// move to the right.
    private var relocateLeading: Bool {
        settings.layout.autoAvoidMenus
            && measuredLeadingWidth > 0
            && measuredLeadingWidth > state.leftFreeWidth
    }

    private var leftFeatures: [NotchFeature] {
        relocateLeading ? [] : features(for: .leading)
    }

    private var rightFeatures: [NotchFeature] {
        relocateLeading
            ? features(for: .leading) + features(for: .trailing)
            : features(for: .trailing)
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
