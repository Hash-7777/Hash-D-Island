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

    /// Whether the strip *should* be on screen — which is not the same as
    /// whether it is drawn yet. See `liveShown`.
    private var wantsLive: Bool { !state.isExpanded && presence.hasLive }

    private var motionScale: Double { settings.appearance.motion.responseScale }
    private var panelRadius: CGFloat { CGFloat(settings.appearance.panelCornerRadius) }

    /// The panel drops as a SOLID BLACK box first, then — once this flips true
    /// ~0.2s later — the glass and its contents fade in. That black beat makes
    /// the panel read as the physical notch stretching open before it reveals.
    @State private var panelRevealed = false

    /// Whether the live strip is actually drawn.
    ///
    /// The panel and the strip are different shapes holding different layouts.
    /// Letting both animate at once cross-fades two layouts through each other
    /// — the same artwork and title visible twice, in two places, sliding past
    /// the desktop — which is what made closing the panel look cheap. Only one
    /// of them is ever on screen now: the panel retracts fully into the notch,
    /// and only then does the strip emerge from it.
    @State private var liveShown = false
    @State private var liveHandoff: DispatchWorkItem?

    /// How long the strip waits after the panel starts closing. Slightly longer
    /// than the closing spring, so the hand-off happens on an empty notch.
    private var handoffDelay: TimeInterval { 0.30 * motionScale }

    var body: some View {
        VStack(spacing: 0) {
            island
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { liveShown = wantsLive }
        .onChange(of: showExpanded) { _, expanded in
            if expanded {
                panelClosedAt = nil
                panelRevealed = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    guard state.isExpanded else { return }
                    withAnimation(.easeOut(duration: 0.28)) { panelRevealed = true }
                }
            } else {
                panelClosedAt = Date()
                panelRevealed = false
            }
            updateLive(animated: true)
        }
        .onChange(of: wantsLive) { _, _ in updateLive(animated: true) }
    }

    /// Bring the strip in or out, never at the same moment as the panel.
    ///
    /// Going away is immediate: the strip must be gone before the panel starts
    /// opening. Coming back waits for the panel to finish retracting — but only
    /// when a panel was actually open, so a track starting on an idle notch
    /// still appears at once.
    private func updateLive(animated: Bool) {
        liveHandoff?.cancel()
        liveHandoff = nil

        guard wantsLive else {
            if liveShown { withAnimation(.easeOut(duration: 0.16)) { liveShown = false } }
            return
        }
        guard !liveShown else { return }

        let panelStillClearing = panelClosedAt.map { Date().timeIntervalSince($0) < handoffDelay } ?? false
        guard panelStillClearing else {
            withAnimation(.spring(response: 0.45 * motionScale, dampingFraction: 0.82)) {
                liveShown = true
            }
            return
        }

        let work = DispatchWorkItem {
            guard wantsLive else { return }
            withAnimation(.spring(response: 0.45 * motionScale, dampingFraction: 0.82)) {
                liveShown = true
            }
        }
        liveHandoff = work
        DispatchQueue.main.asyncAfter(deadline: .now() + handoffDelay, execute: work)
    }

    /// When the panel last began closing, so the strip knows whether the notch
    /// is still busy. Nil while the panel is open or has long since gone.
    @State private var panelClosedAt: Date?

    /// Layered pills instead of one morphing pill: the black notch shape is
    /// ALWAYS present as the base, the live strip and the glass panel each
    /// appear and vanish as their own layer, every one anchored to the top
    /// center. Nothing ever slides sideways — the strip fades out where it is
    /// (at its notch-aligned offset) while the panel drops STRAIGHT DOWN from
    /// the physical notch like a water drop, and returns into it on close.
    private var island: some View {
        ZStack(alignment: .top) {
            collapsedIsland

            if liveShown {
                liveIsland
                    // Aligns the strip's internal gap with the PHYSICAL notch
                    // (the sides are unequal, so a centered strip would sit
                    // 64pt off).
                    .offset(x: state.liveCenterOffset)
                    // Grows sideways OUT of the notch: it starts exactly as wide
                    // as the notch, at full height, and stretches outward. The
                    // anchor is the notch's place inside the strip, not the
                    // strip's own centre — the sides are unequal, so anchoring
                    // to the centre would have it converge to a point that is
                    // not the notch.
                    .transition(.drop(
                        widthRatio: state.notchWidth / max(state.liveWidth, 1),
                        heightRatio: 1,
                        anchor: UnitPoint(x: state.notchAnchorInLiveStrip, y: 0)
                    ))
            }

            if showExpanded {
                expandedIsland
                    // The water drop. It forms at exactly the notch's width and
                    // almost no height — so it reads as the notch itself
                    // swelling — then stretches DOWN and OUT, and settles with a
                    // soft wobble (the opening spring undershoots its damping
                    // for precisely that). Uniform scaling was the old mistake:
                    // it made the panel balloon from a point in the middle of
                    // nowhere, which at speed is indistinguishable from a pop.
                    .transition(.drop(
                        widthRatio: state.notchWidth / max(state.expandedWidth, 1),
                        heightRatio: 0.04,
                        anchor: .top
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
        // Opening springs overshoot slightly for the water-drop wobble; closing
        // springs are fully damped, because a bouncing close reads as a crash.
        // The motion setting scales all four responses together, so calm and
        // lively stay recognisably the same animation.
        .animation(
            showExpanded
                ? .spring(response: 0.55 * motionScale, dampingFraction: 0.72)
                : .spring(response: 0.42 * motionScale, dampingFraction: 0.98),
            value: showExpanded
        )
        .animation(
            liveShown
                ? .spring(response: 0.45 * motionScale, dampingFraction: 0.82)
                : .spring(response: 0.30 * motionScale, dampingFraction: 1.0),
            value: liveShown
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
        VStack(spacing: 0) {
            notchShoulders
            expandedContent
                .padding(.top, 16)
                .padding(.horizontal, 20)
                .padding(.bottom, 18)
        }
            .opacity(panelRevealed ? 1 : 0)
            .frame(width: state.expandedWidth, alignment: .top)
            .background(
                ZStack {
                    Color.black
                    // Solid black is not "no glass" — it is the black beat held
                    // permanently, which is why the reveal still crossfades.
                    if settings.appearance.panelFill == .glass {
                        ZStack {
                            VisualEffectView(material: .hudWindow)
                            // A heavy scrim, not a hint of one.
                            //
                            // Frosted glass takes its brightness from whatever
                            // is behind the window, and every label in this
                            // panel is white. Over a dark desktop 0.15 was
                            // plenty; over a white document the glass came up
                            // pale and the text sat on it almost invisibly. The
                            // panel has to be readable over ANY background, and
                            // the only thing that guarantees that is darkening
                            // it enough that what shows through is texture
                            // rather than brightness. It still reads as glass —
                            // shapes and motion behind it are still there.
                            Color.black.opacity(0.45)
                        }
                        .opacity(panelRevealed ? 1 : 0)
                    }
                }
                .clipShape(pillShape(radius: panelRadius))
                .overlay(
                    pillShape(radius: panelRadius)
                        .strokeBorder(Color.white.opacity(panelRevealed ? 0.12 : 0), lineWidth: 0.7)
                )
                // Softer and closer in than it was. The old shadow was strong
                // enough to read as a shape of its own against a light
                // background rather than as depth under the panel.
                .shadow(color: .black.opacity(0.4), radius: 18, y: 8)
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
                if let feature = liveFeature,
                   let view = feature.makeCompactLeadingView(context: context) { view }
            }
            .padding(.trailing, 6)
            .frame(width: state.liveLeadingWidth, alignment: .trailing)

            Color.clear.frame(width: state.notchWidth, height: state.notchHeight)

            HStack(spacing: 6) {
                if let feature = liveFeature,
                   let view = feature.makeCompactTrailingView(context: context) { view }
            }
            .padding(.leading, 18)
            .padding(.trailing, 12)
            // The trailing side is what actually overran: two features' titles
            // came to roughly twice the strip's whole budget, so the pill grew
            // past the width its own centring is computed from and slid across
            // the notch. One feature fits; the cap makes that structural rather
            // than a thing each feature has to remember.
            .frame(maxWidth: state.liveTrailingWidth, alignment: .leading)
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
    }

    /// The app's controls, in the band of panel that shows either side of the
    /// physical notch: quit on the left, settings on the right.
    ///
    /// These used to hang off the row stack as an `.overlay(alignment:
    /// .topTrailing)` with a hand-tuned offset — which meant they were not in
    /// the layout at all, and simply floated above whichever feature happened to
    /// be first. That worked only while Now Playing led the panel, because its
    /// artwork block left a convenient hole in the top-right corner. Reordering
    /// the panel put a full-width row there instead and the buttons landed on
    /// top of its value. Placing them by layout, in a band nothing else can
    /// occupy, means no ordering of features can collide with them again.
    ///
    /// The middle cell is the hardware. Nothing is ever drawn in it — the notch
    /// is physically in front of the panel — so it is reserved rather than
    /// filled, and the two buttons are pushed out to the panel's own edges.
    private var notchShoulders: some View {
        HStack(spacing: 0) {
            CornerButton(symbol: "power", hoverTint: .red) {
                NSApplication.shared.terminate(nil)
            }
            .padding(.leading, Self.shoulderInset)
            .frame(width: state.shoulderWidth, alignment: .leading)

            Color.clear
                .frame(width: state.notchWidth, height: state.notchHeight)

            CornerButton(symbol: "gearshape.fill") { context.openSettings() }
                .padding(.trailing, Self.shoulderInset)
                .frame(width: state.shoulderWidth, alignment: .trailing)
        }
        .frame(width: state.expandedWidth, height: state.notchHeight)
    }

    /// How far each control sits in from the panel's outer edge.
    private static let shoulderInset: CGFloat = 8

    /// The one feature that owns the strip right now.
    ///
    /// Highest `livePriority` among those that are actually live, ties going to
    /// whichever was registered first so the choice never wobbles between
    /// redraws. When the winner's moment passes — a notice dismissing itself,
    /// a warning timing out — it drops out of `activeIDs` and the strip hands
    /// straight back to whatever was underneath, usually the music.
    private var liveFeature: NotchFeature? {
        var best: (feature: NotchFeature, priority: Int, index: Int)?
        for (index, feature) in enabledFeatures.enumerated()
        where presence.activeIDs.contains(feature.id) {
            let priority = feature.livePriority
            if let current = best,
               priority < current.priority || (priority == current.priority && index > current.index) {
                continue
            }
            best = (feature, priority, index)
        }
        return best?.feature
    }

    /// The enabled features in draw order. Derived once per settings change by
    /// the registry rather than re-sorted here on every body evaluation — this
    /// is read twice per body (once to pick the strip's owner, once to build the
    /// panel) and the body runs at animation frequency.
    private var enabledFeatures: [NotchFeature] {
        registry.orderedEnabled(using: settings)
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
        .help(symbol == "power" ? "Quit Hash D Island" : "Settings")
    }
}
