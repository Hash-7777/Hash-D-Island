import SwiftUI

/// The black interactive notch.
///
/// Three states:
///   • idle    — a black shape the size of the notch (looks like the notch).
///   • live    — content flanks the notch (art left, title right), glassy.
///   • expanded — on hover, a frosted panel drops down with the details.
///
/// The expanded panel sizes to its content (never clipped) and its background is
/// a Control-Center-style frosted glass. The resting notch stays solid black so
/// it blends with the physical notch.
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
        stateContent
            .frame(width: islandWidth, alignment: .top)
            .frame(height: showExpanded ? nil : nonExpandedHeight, alignment: .top)
            .background(islandBackground)
            .animation(.spring(response: 0.46, dampingFraction: 0.80), value: showExpanded)
            .animation(.spring(response: 0.38, dampingFraction: 0.86), value: showLive)
    }

    @ViewBuilder
    private var stateContent: some View {
        if showExpanded {
            expandedContent
                .padding(.top, state.notchHeight + 16)
                .padding(.horizontal, 20)
                .padding(.bottom, 18)
                .transition(.opacity.combined(with: .offset(y: -10)).combined(with: .scale(0.97, anchor: .top)))
        } else if showLive {
            liveContent
                .transition(.opacity.combined(with: .scale(0.92, anchor: .top)))
        } else {
            Color.clear
        }
    }

    private var islandWidth: CGFloat {
        showExpanded ? state.expandedWidth : (showLive ? state.liveWidth : state.collapsedWidth)
    }

    private var nonExpandedHeight: CGFloat {
        showLive ? state.liveHeight : state.collapsedHeight
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

    // MARK: Background

    /// Collapsed and live states are SOLID BLACK so the island reads as one
    /// piece with the physical notch. Only the expanded panel — which drops
    /// clear of the notch — gets the Control-Center frosted glass.
    @ViewBuilder
    private var islandBackground: some View {
        ZStack {
            if showExpanded {
                VisualEffectView(material: .hudWindow)
                Color.black.opacity(0.22)
            } else {
                Color.black
            }
        }
        .clipShape(shape)
        .overlay(
            shape.strokeBorder(Color.white.opacity(showExpanded ? 0.12 : 0), lineWidth: 0.7)
        )
        .shadow(color: .black.opacity(showExpanded ? 0.45 : (showLive ? 0.30 : 0)),
                radius: showExpanded ? 20 : 9, y: showExpanded ? 12 : 5)
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
