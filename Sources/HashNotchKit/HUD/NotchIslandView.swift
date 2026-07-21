import SwiftUI

/// The black interactive notch.
///
/// Three states:
///   • idle    — a black shape the size of the notch (looks like the notch).
///   • live    — content flanks the notch (art on the left, title on the right)
///               like the iPhone's compact Dynamic Island.
///   • expanded — on hover, a rounded black panel drops down with the details.
///
/// Expanded content is padded below the physical notch and inside the panel, so
/// nothing hides under the notch or clips at the edges.
struct NotchIslandView: View {
    @ObservedObject var state: NotchState
    @ObservedObject var settings: SettingsStore
    @ObservedObject var presence: LivePresence
    let registry: FeatureRegistry
    let context: FeatureContext

    private var showExpanded: Bool { state.isExpanded }
    private var showLive: Bool { !state.isExpanded && presence.hasLive }

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
                .shadow(color: .black.opacity(showExpanded ? 0.6 : (showLive ? 0.4 : 0)),
                        radius: showExpanded ? 16 : 10, y: showExpanded ? 10 : 6)

            if showExpanded {
                expandedContent
                    .padding(.top, state.notchHeight + 16)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 18)
                    .frame(width: state.expandedWidth, alignment: .center)
                    .transition(.opacity)
            } else if showLive {
                liveContent
                    .transition(.opacity)
            }
        }
        .frame(width: islandWidth, height: islandHeight)
        .animation(.spring(response: 0.42, dampingFraction: 0.72), value: showExpanded)
        .animation(.spring(response: 0.40, dampingFraction: 0.82), value: showLive)
    }

    private var islandWidth: CGFloat {
        showExpanded ? state.expandedWidth : (showLive ? state.liveWidth : state.collapsedWidth)
    }

    private var islandHeight: CGFloat {
        showExpanded ? state.expandedHeight : (showLive ? state.liveHeight : state.collapsedHeight)
    }

    private var cornerRadius: CGFloat {
        showExpanded ? 26 : (showLive ? 14 : 10)
    }

    private var shape: some InsettableShape {
        UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: cornerRadius,
            bottomTrailingRadius: cornerRadius,
            topTrailingRadius: 0,
            style: .continuous
        )
    }

    // MARK: Live (flanks the notch)

    private var liveContent: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Spacer(minLength: 0)
                ForEach(enabledFeatures, id: \.id) { feature in
                    if let view = feature.makeCompactLeadingView(context: context) { view }
                }
            }
            .frame(width: state.liveLeadingWidth, alignment: .trailing)
            .padding(.trailing, 8)

            Color.clear.frame(width: state.notchWidth, height: state.notchHeight)

            HStack(spacing: 6) {
                ForEach(enabledFeatures, id: \.id) { feature in
                    if let view = feature.makeCompactTrailingView(context: context) { view }
                }
                Spacer(minLength: 0)
            }
            .frame(width: state.liveTrailingWidth, alignment: .leading)
            .padding(.leading, 8)
        }
        .frame(height: state.notchHeight)
        .font(.system(size: 11, weight: .semibold, design: .rounded))
    }

    // MARK: Expanded (clean vertical list, below the notch)

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 13) {
            ForEach(enabledFeatures, id: \.id) { feature in
                if let detail = feature.makeExpandedView(context: context) {
                    detail
                }
            }
        }
        .font(.system(size: 11, weight: .medium, design: .rounded))
    }

    private var enabledFeatures: [NotchFeature] {
        registry.features.enumerated()
            .map { (feature: $0.element, config: settings.config(for: $0.element, index: $0.offset)) }
            .filter { $0.config.enabled }
            .sorted { $0.config.order < $1.config.order }
            .map { $0.feature }
    }
}
