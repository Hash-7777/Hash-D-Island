import SwiftUI

/// The black interactive notch.
///
/// Three states:
///   • idle    — a black shape the size of the notch (looks like the notch).
///   • live    — content flanks the notch (art left, title right), black.
///   • expanded — on hover, a glassy panel drops down with the details.
///
/// The notch shape and live strip are solid black so they read as one piece
/// with the hardware; the drop-down panel is Control-Center glass, falls
/// straight down out of the notch like a water drop, and sizes to its
/// content (never clipped).
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

    /// Layered pills instead of one morphing pill: the black notch shape is
    /// ALWAYS present as the base, the live strip and the glass panel each
    /// appear and vanish as their own layer, every one anchored to the top
    /// center. Nothing ever slides sideways — the strip fades out where it is
    /// (at its notch-aligned offset) while the panel drops STRAIGHT DOWN from
    /// the physical notch like a water drop, and returns into it on close.
    private var island: some View {
        ZStack(alignment: .top) {
            collapsedIsland

            if showLive {
                liveIsland
                    // Aligns the strip's internal gap with the PHYSICAL notch
                    // (the sides are unequal, so a centered strip would sit
                    // 64pt off).
                    .offset(x: state.liveCenterOffset)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.85, anchor: .top)),
                        removal: .opacity.combined(with: .scale(scale: 0.93, anchor: .top))
                    ))
            }

            if showExpanded {
                expandedIsland
                    // Water drop: forms small at the notch's lower lip,
                    // stretches downward, and settles with a soft wobble
                    // (the opening spring undershoots damping for that).
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.30, anchor: .top)),
                        removal: .opacity.combined(with: .scale(scale: 0.45, anchor: .top))
                    ))
            }
        }
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { onIslandSize?(geo.size) }
                    .onChange(of: geo.size) { _, size in onIslandSize?(size) }
            }
        )
        .animation(
            showExpanded
                ? .spring(response: 0.55, dampingFraction: 0.72)
                : .spring(response: 0.42, dampingFraction: 0.98),
            value: showExpanded
        )
        .animation(
            showLive
                ? .spring(response: 0.45, dampingFraction: 0.82)
                : .spring(response: 0.38, dampingFraction: 0.98),
            value: showLive
        )
    }

    // MARK: The three pills

    /// The permanent base: a black shape the size of the notch, so the island
    /// reads as one piece with the hardware in every state.
    private var collapsedIsland: some View {
        pillShape(radius: 10)
            .fill(Color.black)
            .frame(width: state.collapsedWidth, height: state.collapsedHeight)
    }

    private var liveIsland: some View {
        liveContent
            .frame(width: state.liveWidth, height: state.liveHeight, alignment: .top)
            .background(
                Color.black
                    .clipShape(pillShape(radius: 14))
                    .shadow(color: .black.opacity(0.35), radius: 9, y: 5)
            )
    }

    /// The drop-down panel: Control-Center glass over the wallpaper, framed by
    /// a hairline — the notch above it stays black, the drop itself is glassy.
    private var expandedIsland: some View {
        expandedContent
            .padding(.top, state.notchHeight + 16)
            .padding(.horizontal, 20)
            .padding(.bottom, 18)
            .frame(width: state.expandedWidth, alignment: .top)
            .background(
                ZStack {
                    VisualEffectView(material: .hudWindow)
                    Color.black.opacity(0.15)
                }
                .clipShape(pillShape(radius: 26))
                .overlay(
                    pillShape(radius: 26)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.7)
                )
                .shadow(color: .black.opacity(0.55), radius: 22, y: 14)
            )
    }

    private func pillShape(radius: CGFloat) -> UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: radius,
            bottomTrailingRadius: radius,
            topTrailingRadius: 0,
            style: .continuous
        )
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
            .offset(x: 6, y: -10)
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
