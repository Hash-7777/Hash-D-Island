import SwiftUI

/// The black interactive notch.
///
/// Three states:
///   • idle    — a black shape the size of the notch (looks like the notch).
///   • live    — content flanks the notch (art left, title right).
///   • expanded — on hover, a black panel drops down with the details.
///
/// The whole island is solid black in every state so it reads as one piece
/// with the physical notch; the expanded panel sizes to its content (never
/// clipped) and gets its depth from a shadow, not a material.
struct NotchIslandView: View {
    @ObservedObject var state: NotchState
    @ObservedObject var settings: SettingsStore
    @ObservedObject var presence: LivePresence
    let registry: FeatureRegistry
    let context: FeatureContext
    /// Reports the island's rendered size so the controller can keep the
    /// overlay WINDOW hugging the island (a window-sized screenshot then
    /// captures just the notch, not a huge transparent strip).
    var onIslandSize: ((CGSize) -> Void)? = nil

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
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { onIslandSize?(geo.size) }
                        .onChange(of: geo.size) { _, size in onIslandSize?(size) }
                }
            )
            .background(islandBackground)
            // Direction-aware motion: opening gets a soft settle so the panel
            // feels like it emerges from the physical notch; closing is calm
            // and fully damped — smooth, never snapping shut.
            .animation(
                showExpanded
                    ? .spring(response: 0.52, dampingFraction: 0.80)
                    : .spring(response: 0.44, dampingFraction: 0.98),
                value: showExpanded
            )
            .animation(
                showLive
                    ? .spring(response: 0.45, dampingFraction: 0.82)
                    : .spring(response: 0.38, dampingFraction: 0.98),
                value: showLive
            )
    }

    @ViewBuilder
    private var stateContent: some View {
        if showExpanded {
            expandedContent
                .padding(.top, state.notchHeight + 16)
                .padding(.horizontal, 20)
                .padding(.bottom, 18)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .offset(y: -14)).combined(with: .scale(scale: 0.94, anchor: .top)),
                    removal: .opacity.combined(with: .offset(y: -8)).combined(with: .scale(scale: 0.97, anchor: .top))
                ))
        } else if showLive {
            liveContent
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.85, anchor: .top)),
                    removal: .opacity.combined(with: .scale(scale: 0.93, anchor: .top))
                ))
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

    /// SOLID BLACK in every state — the island must read as one piece with the
    /// physical notch, exactly like the iPhone's Dynamic Island. Depth comes
    /// from the shadow alone; a faint hairline appears only on the open panel
    /// so it stays legible over black wallpapers.
    @ViewBuilder
    private var islandBackground: some View {
        Color.black
            .clipShape(shape)
            .overlay(
                shape.strokeBorder(Color.white.opacity(showExpanded ? 0.09 : 0), lineWidth: 0.7)
            )
            .shadow(color: .black.opacity(showExpanded ? 0.55 : (showLive ? 0.35 : 0)),
                    radius: showExpanded ? 22 : 9, y: showExpanded ? 14 : 5)
    }

    // MARK: Live (flanks the notch)

    private var liveContent: some View {
        HStack(spacing: 0) {
            // Clearance paddings live INSIDE the fixed side widths, so content
            // stays within the island's black pill and clear of the notch.
            // Artwork hugs the notch (6pt, iPhone-style); text keeps a wider
            // 18pt gap so glyphs never look tucked under the notch's curve.
            HStack(spacing: 6) {
                Spacer(minLength: 0)
                ForEach(enabledFeatures, id: \.id) { feature in
                    if let view = feature.makeCompactLeadingView(context: context) { view }
                }
            }
            .padding(.trailing, 6)
            .frame(width: state.liveLeadingWidth, alignment: .trailing)

            Color.clear.frame(width: state.notchWidth, height: state.notchHeight)

            HStack(spacing: 6) {
                ForEach(enabledFeatures, id: \.id) { feature in
                    if let view = feature.makeCompactTrailingView(context: context) { view }
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, 18)
            .frame(width: state.liveTrailingWidth, alignment: .leading)
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
        .overlay(alignment: .topTrailing) { settingsButton }
    }

    /// The app's only settings entry point — a quiet gear in the panel corner
    /// (there is no menu-bar item).
    private var settingsButton: some View {
        SettingsGearButton { context.openSettings() }
            .offset(x: 6, y: -2)
    }

    private var enabledFeatures: [NotchFeature] {
        registry.features.enumerated()
            .map { (feature: $0.element, config: settings.config(for: $0.element, index: $0.offset)) }
            .filter { $0.config.enabled }
            .sorted { $0.config.order < $1.config.order }
            .map { $0.feature }
    }
}

/// A quiet gear that brightens on hover.
private struct SettingsGearButton: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white.opacity(hovering ? 0.85 : 0.35))
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.white.opacity(hovering ? 0.12 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}
