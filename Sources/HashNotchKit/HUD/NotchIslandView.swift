import SwiftUI
import AppKit

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

    /// The panel drops as a SOLID BLACK box first, then — once this flips true
    /// ~0.2s later — the glass and its contents fade in. That black beat makes
    /// the panel read as the physical notch stretching open before it reveals.
    @State private var panelRevealed = false

    var body: some View {
        VStack(spacing: 0) {
            island
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: showExpanded) { _, expanded in
            if expanded {
                panelRevealed = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    guard state.isExpanded else { return }
                    withAnimation(.easeOut(duration: 0.28)) { panelRevealed = true }
                }
            } else {
                panelRevealed = false
            }
        }
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
        // The black pill HUGS its content (no trailing dead space after the
        // name), but sits left-anchored inside a fixed-width positioning box.
        // Keeping the box fixed means the notch gap stays pinned and the strip
        // never shifts as the title changes; only the visible pill shrinks to
        // fit.
        liveContent
            .background(
                Color.black
                    .clipShape(pillShape(radius: 14))
                    .shadow(color: .black.opacity(0.35), radius: 9, y: 5)
            )
            .frame(width: state.liveWidth, height: state.liveHeight, alignment: .leading)
    }

    /// The drop-down panel. It first appears as a solid-black box (matching the
    /// notch) and, once `panelRevealed` flips ~0.2s later, crossfades to
    /// Control-Center glass while its contents fade in. The content is always
    /// laid out (just invisible at first) so the black box is full panel size
    /// from the start and nothing resizes on the reveal.
    private var expandedIsland: some View {
        expandedContent
            .opacity(panelRevealed ? 1 : 0)
            .padding(.top, state.notchHeight + 16)
            .padding(.horizontal, 20)
            .padding(.bottom, 18)
            .frame(width: state.expandedWidth, alignment: .top)
            .background(
                ZStack {
                    Color.black
                    ZStack {
                        VisualEffectView(material: .hudWindow)
                        Color.black.opacity(0.15)
                    }
                    .opacity(panelRevealed ? 1 : 0)
                }
                .clipShape(pillShape(radius: 26))
                .overlay(
                    pillShape(radius: 26)
                        .strokeBorder(Color.white.opacity(panelRevealed ? 0.12 : 0), lineWidth: 0.7)
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
            // Leading stays a FIXED width so the artwork hugs the notch (6pt,
            // iPhone-style) and the notch gap lands in the same place every
            // time. The trailing side HUGS its content — the title's own cap
            // (it marquees past it) plus a little breathing room — so the pill
            // ends right after the name instead of reserving dead black space.
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
            }
            .padding(.leading, 18)
            .padding(.trailing, 12)
        }
        .fixedSize(horizontal: true, vertical: false)
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
        .overlay(alignment: .topTrailing) { cornerControls }
    }

    /// The app's controls, quiet in the panel's top corner: settings gear and
    /// a quit button (there is no menu-bar item).
    private var cornerControls: some View {
        HStack(spacing: 2) {
            CornerButton(symbol: "gearshape.fill") { context.openSettings() }
            CornerButton(symbol: "power", hoverTint: .red) {
                NSApplication.shared.terminate(nil)
            }
        }
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

/// A quiet corner icon that brightens on hover. `hoverTint` colors the icon
/// on hover (e.g. red for quit); default is plain white.
private struct CornerButton: View {
    let symbol: String
    var hoverTint: Color = .white
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(hovering ? hoverTint.opacity(0.9) : Color.white.opacity(0.35))
                .frame(width: 24, height: 24)
                .background(Circle().fill((hovering ? hoverTint : .white).opacity(hovering ? 0.14 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help(symbol == "power" ? "Quit HashNotch" : "Settings")
    }
}
