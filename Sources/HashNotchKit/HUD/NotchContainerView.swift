import SwiftUI

/// Lays the features out around the physical notch.
///
/// The compact row is split into a left half and a right half of equal width,
/// with a transparent gap the exact size of the notch between them. Leading
/// features hug the right edge of the left half; trailing features hug the left
/// edge of the right half — so both sit flush against the cutout. The expanded
/// panel animates open below the notch.
struct NotchContainerView: View {
    @ObservedObject var state: NotchState
    let registry: FeatureRegistry
    let context: FeatureContext

    var body: some View {
        VStack(spacing: 8) {
            compactRow
            if state.isExpanded {
                expandedPanel
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .padding(.top, 0)
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
    }

    private var expandedPanel: some View {
        HStack(spacing: 16) {
            featureViews(for: .expanded)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: context.theme.cornerRadius, style: .continuous)
                .fill(context.theme.pillBackground)
        )
        .frame(maxWidth: state.notchWidth + 360)
    }

    @ViewBuilder
    private func featureViews(for placement: FeaturePlacement) -> some View {
        ForEach(registry.features(for: placement), id: \.id) { feature in
            feature.makeView(context: context)
        }
    }
}
