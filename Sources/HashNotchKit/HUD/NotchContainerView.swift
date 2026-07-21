import SwiftUI

/// Lays the features out around the physical notch.
///
/// The compact row is split into a left half and a right half of equal width,
/// with a transparent gap the exact size of the notch between them. Leading
/// features hug the right edge of the left half; trailing features hug the left
/// edge of the right half — so both sit flush against the cutout. Hovering the
/// notch cluster springs the expanded panel open below.
struct NotchContainerView: View {
    @ObservedObject var state: NotchState
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
            HStack(spacing: 12) {
                Spacer(minLength: 0)
                featureViews(for: .leading)
            }
            .frame(width: state.sideWidth, alignment: .trailing)

            Color.clear
                .frame(width: state.notchWidth, height: state.notchHeight)

            HStack(spacing: 12) {
                featureViews(for: .trailing)
                Spacer(minLength: 0)
            }
            .frame(width: state.sideWidth, alignment: .leading)
        }
        .frame(height: state.notchHeight)
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .scaleEffect(state.isExpanded ? 1.03 : 1.0, anchor: .top)
    }

    private var expandedPanel: some View {
        HStack(alignment: .top, spacing: 20) {
            ForEach(registry.features, id: \.id) { feature in
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
        ForEach(registry.features(for: placement), id: \.id) { feature in
            feature.makeView(context: context)
        }
    }
}
