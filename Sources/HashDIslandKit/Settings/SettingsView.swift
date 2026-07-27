import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Lightweight description of a feature for the settings list, so the view never
/// holds the live feature objects.
public struct FeatureDescriptor: Identifiable {
    public let id: String
    public let title: String
    public let options: [FeatureOption]

    public init(id: String, title: String, options: [FeatureOption]) {
        self.id = id
        self.title = title
        self.options = options
    }
}

/// The customization window.
///
/// Deliberately not a stock grouped Form: this window is the only face the app
/// has apart from the island itself, so it is dark and tinted to match it. Each
/// concern gets its own page rather than a dozen controls stacked into one
/// scroll, which is what made the previous single list feel thin.
public struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    let features: [FeatureDescriptor]

    @State private var section: Section = .general
    @State private var dragging: String?

    enum Section: String, CaseIterable, Identifiable {
        case general, indicators, appearance, alerts, position, privacy
        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: return "General"
            case .indicators: return "Indicators"
            case .appearance: return "Appearance"
            case .alerts: return "Alerts"
            case .position: return "Position"
            case .privacy: return "Privacy"
            }
        }

        var symbol: String {
            switch self {
            case .general: return "gearshape.fill"
            case .indicators: return "square.stack.3d.up.fill"
            case .appearance: return "paintbrush.fill"
            case .alerts: return "bell.fill"
            case .position: return "arrow.up.and.down.and.arrow.left.and.right"
            case .privacy: return "lock.shield.fill"
            }
        }
    }

    /// Closes the panel. Supplied by the window that owns it, because a
    /// borderless panel has no title bar to close and needs to offer the button
    /// itself.
    private let onClose: () -> Void

    public init(
        settings: SettingsStore,
        features: [FeatureDescriptor],
        onClose: @escaping () -> Void = {}
    ) {
        self.settings = settings
        self.features = features
        self.onClose = onClose
    }

    public var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Color.white.opacity(0.06)).frame(width: 1)
            VStack(spacing: 0) {
                header
                ScrollView {
                    page
                        .padding(.horizontal, 22)
                        .padding(.bottom, 24)
                        // Belt and braces after the picker fix: the page takes
                        // the width it is given rather than asking for more,
                        // so one over-eager control can never push the rest of
                        // the column off the edge again.
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                // Hiding the scrollbar is cosmetic; on macOS 12 it simply shows
                // in the system's usual way, which is not worth a workaround.
                .hideScrollIndicatorsIfPossible()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(panelSurface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            // The hairline that catches the light along the top edge, the same
            // one dark glass surfaces have all over macOS. It is most of what
            // separates a dark rectangle from a piece of the interface.
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.16), .white.opacity(0.04)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        )
        .preferredColorScheme(.dark)
        .tint(settings.accent.color)
    }

    /// Frosted where the system allows it, with a dark wash over the top so the
    /// text stays readable against a bright wallpaper.
    private var panelSurface: some View {
        ZStack {
            VisualEffectView(material: .hudWindow)
            Color.black.opacity(0.55)
        }
    }

    /// The page's own title, and the way out.
    private var header: some View {
        HStack(spacing: 8) {
            // No title here. Every page already opens with its own heading and
            // a line explaining it, and the two stacked read as a stutter.
            Spacer(minLength: 8)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.white.opacity(0.07)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 0)
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Hash D Island")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))
                .padding(.horizontal, 14)
                .padding(.top, 16)
                .padding(.bottom, 10)

            ForEach(Section.allCases) { item in
                sidebarRow(item)
            }
            Spacer()
        }
        .frame(width: 146)
        .frame(maxHeight: .infinity)
        .background(Color.white.opacity(0.03))
        // The sidebar keeps its width no matter how wide the page beside it
        // wants to be. Without this a long row of buttons steals space from
        // here, and the first thing to go is the title's opening letters.
        .fixedSize(horizontal: true, vertical: false)
        .layoutPriority(1)
    }

    private func sidebarRow(_ item: Section) -> some View {
        let selected = section == item
        return Button {
            // Leaving the page abandons any drag that was in progress. Without
            // this a half-finished reorder carried its held id across to
            // another page, where nothing could ever clear it.
            dragging = nil
            section = item
        } label: {
            HStack(spacing: 9) {
                Image(systemName: item.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 16)
                    .foregroundStyle(selected ? settings.accent.color : Color.white.opacity(0.55))
                Text(item.title)
                    .font(.system(size: 12, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Color.white : Color.white.opacity(0.7))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.white.opacity(selected ? 0.09 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }

    // MARK: Pages

    @ViewBuilder
    private var page: some View {
        switch section {
        case .general: general
        case .indicators: indicators
        case .appearance: appearance
        case .alerts: alerts
        case .position: position
        case .privacy: privacy
        }
    }

    private var general: some View {
        VStack(alignment: .leading, spacing: 22) {
            PageHeader("General", detail: "How the app starts, and how hard it works.")

            SettingCard {
                SettingRow(
                    "Open at login",
                    detail: loginDetail
                ) {
                    Toggle("", isOn: launchAtLoginBinding)
                        .labelsHidden()
                        .disabled(!LoginItem.isSupported)
                }

                if LoginItem.needsApproval {
                    Button("Approve in System Settings") {
                        LoginItem.openLoginItemsSettings()
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 10))
                }

                SettingDivider()

                SettingRow(
                    "Battery saver",
                    detail: "Check everything half as often. Nothing disappears."
                ) {
                    Toggle("", isOn: $settings.batterySaver).labelsHidden()
                }

                SettingDivider()

                SettingRow(
                    "Count AI tokens",
                    detail: "Only what your tools have written since the last count is read, so this is cheap at any setting.",
                    stacked: true
                ) {
                    Picker("", selection: $settings.tokenScanInterval) {
                        ForEach(TokenScanInterval.allCases, id: \.self) { interval in
                            Text(interval.label).tag(interval)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 200)
                }
            }

            SettingCard {
                SettingRow(
                    "Quit Hash D Island",
                    detail: "Closes the island and stops everything."
                ) {
                    Button("Quit") { NSApp.terminate(nil) }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                }
            }

            Spacer(minLength: 0)
        }
    }

    private var indicators: some View {
        VStack(alignment: .leading, spacing: 22) {
            PageHeader(
                "Indicators",
                detail: "What shows, how it looks, and in what order. Drag a row to move it."
            )

            SettingCard {
                ForEach(Array(orderedDescriptors.enumerated()), id: \.element.id) { index, feature in
                    if index > 0 { SettingDivider() }
                    indicatorRow(feature)
                }
            }
            // Behind the rows, catching any drag let go between them or beside
            // them. Without it a drag that missed a row left its held id set
            // for the rest of the session — see `ReorderCancel`.
            .onDrop(of: [UTType.text], delegate: ReorderCancel(dragging: $dragging))

            Spacer(minLength: 0)
        }
        // And a drag abandoned by closing the page cannot outlive the page.
        .onDisappear { dragging = nil }
    }

    /// Descriptors in the user's chosen order. Ties break on id so two features
    /// never swap places between launches.
    private var orderedDescriptors: [FeatureDescriptor] {
        features.sorted { left, right in
            let l = settings.features[left.id]?.order ?? 0
            let r = settings.features[right.id]?.order ?? 0
            return l == r ? left.id < right.id : l < r
        }
    }

    private func indicatorRow(_ feature: FeatureDescriptor) -> some View {
        let enabled = settings.isEnabled(feature.id)
        return VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 10) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(dragging == feature.id ? 0.7 : 0.28))
                Text(feature.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(enabled ? Color.white : Color.white.opacity(0.45))
                Spacer(minLength: 0)
                Toggle("", isOn: enabledBinding(feature.id)).labelsHidden()
            }

            if enabled, !feature.options.isEmpty {
                // A menu, not a segmented control.
                //
                // Segmented lays every choice out side by side at whatever
                // width the longest label wants, and refuses to shrink — so
                // "Symbol and number / Number only / Word" simply ran off the
                // page and took the column's whole layout with it, clipping the
                // description above as well. A menu is the same choice in the
                // width of one label, and it does not care how many options a
                // feature grows later.
                HStack {
                    Picker("", selection: styleBinding(feature.id)) {
                        ForEach(feature.options) { option in
                            Text(option.title).tag(option.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .fixedSize()
                    Spacer(minLength: 0)
                }
                .padding(.leading, 24)
            }
        }
        .padding(.vertical, 8)
        .opacity(dragging == feature.id ? 0.45 : 1)
        .contentShape(Rectangle())
        .onDrag {
            dragging = feature.id
            return NSItemProvider(object: feature.id as NSString)
        }
        .onDrop(
            of: [UTType.text],
            delegate: ReorderDrop(
                target: feature.id,
                order: orderedDescriptors.map(\.id),
                dragging: $dragging,
                apply: { settings.setOrder($0) }
            )
        )
    }

    private var appearance: some View {
        VStack(alignment: .leading, spacing: 22) {
            PageHeader(
                "Appearance",
                detail: "Only the panel that drops down. The notch and strip stay black."
            )

            SettingCard {
                SettingRow(
                    "Accent colour",
                    detail: "Tints icons, bars and highlights.",
                    stacked: true
                ) {
                    HStack(spacing: 8) {
                        ForEach(AccentColor.all) { accent in
                            accentDot(accent)
                        }
                    }
                }

                SettingDivider()

                SettingRow(
                    "Panel fill",
                    detail: "Frosted picks up what is behind it. Solid matches the notch.",
                    stacked: true
                ) {
                    Picker("", selection: $settings.appearance.panelFill) {
                        ForEach(AppearanceSettings.PanelFill.allCases, id: \.self) { fill in
                            Text(fill.label).tag(fill)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                }

                SettingDivider()

                SettingRow(
                    "Motion",
                    detail: "How eagerly the island opens and closes.",
                    stacked: true
                ) {
                    Picker("", selection: $settings.appearance.motion) {
                        ForEach(AppearanceSettings.Motion.allCases, id: \.self) { motion in
                            Text(motion.label).tag(motion)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                }

                SettingDivider()

                SettingRow(
                    "Panel roundness",
                    detail: "\(Int(settings.appearance.panelCornerRadius)) pt at the bottom corners.",
                    stacked: true
                ) {
                    Slider(value: whole($settings.appearance.panelCornerRadius), in: 8...36)
                        .frame(maxWidth: .infinity)
                }

                SettingDivider()

                SettingRow(
                    "Dividing lines",
                    detail: separatorDetail,
                    stacked: true
                ) {
                    VStack(spacing: 10) {
                        HStack(spacing: 10) {
                            Text("Thickness")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.55))
                                .frame(width: 62, alignment: .leading)
                            Slider(
                                value: $settings.appearance.separatorThickness,
                                in: AppearanceSettings.separatorThicknessRange,
                                step: 0.5
                            )
                        }
                        HStack(spacing: 10) {
                            Text("Strength")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.55))
                                .frame(width: 62, alignment: .leading)
                            Slider(
                                value: $settings.appearance.separatorOpacity,
                                in: AppearanceSettings.separatorOpacityRange
                            )
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            Spacer(minLength: 0)
        }
    }

    private func accentDot(_ accent: AccentColor) -> some View {
        let selected = settings.appearance.accentID == accent.id
        return Button {
            settings.appearance.accentID = accent.id
        } label: {
            Circle()
                .fill(accent.color)
                .frame(width: 18, height: 18)
                .overlay(
                    Circle().strokeBorder(
                        Color.white.opacity(selected ? 0.95 : 0.16),
                        lineWidth: selected ? 2 : 1
                    )
                )
                .padding(2)
        }
        .buttonStyle(.plain)
        .help(accent.name)
    }

    private var alerts: some View {
        VStack(alignment: .leading, spacing: 22) {
            PageHeader("Alerts", detail: "What happens when something finishes, or wants your attention.")

            SettingCard {
                SettingRow(
                    "Keep a finished alert for",
                    detail: "\(Int(settings.alerts.noticeSeconds)) seconds, then it goes. No timer beside it.",
                    stacked: true
                ) {
                    Slider(value: whole($settings.alerts.noticeSeconds), in: 1...10)
                        .frame(maxWidth: .infinity)
                }

                SettingDivider()

                SettingRow(
                    "Requests wait for you",
                    detail: "An alert asking for something waits, instead of leaving on its own."
                ) {
                    Toggle("", isOn: $settings.alerts.requestsWaitForYou).labelsHidden()
                }

                SettingDivider()

                SettingRow(
                    "Control video in your browser",
                    detail: "Needs Accessibility, so the buttons can press the media keys. Without it they still work for Spotify and Music."
                ) {
                    Toggle("", isOn: mediaKeysBinding).labelsHidden()
                }

                SettingDivider()

                SettingRow(
                    "Switch Low Power Mode from the panel",
                    detail: "Switch it here instead of in System Settings. macOS asks for your password each time."
                ) {
                    Toggle("", isOn: $settings.canSwitchLowPowerMode).labelsHidden()
                }
            }

            Spacer(minLength: 0)
        }
    }

    private var position: some View {
        let screen = NotchGeometry.preferredScreen()
        let key = screen.map { NotchGeometry.displayKey(for: $0) } ?? "display-unknown"
        let measured = screen.map { NotchGeometry.current(for: $0) }
        let current = settings.adjustment(for: key)

        return VStack(alignment: .leading, spacing: 22) {
            PageHeader(
                "Position",
                detail: measured?.hasNotch == true
                    ? "Your display has a notch, and the island is measured to match it exactly. Nudge it here if anything looks off."
                    : "This display has no notch, so the island sits just below the menu bar instead of covering it. Nudge it here to taste."
            )

            SettingCard {
                SettingRow(
                    "Fit",
                    detail: current.isAutomatic ? "Measured automatically." : "Adjusted by hand."
                ) {
                    Button("Reset to automatic") {
                        settings.setAdjustment(IslandAdjustment(), for: key)
                    }
                    .disabled(current.isAutomatic)
                }
            }

            // Two groups rather than four rows in a list. Moving the island and
            // resizing it are different intentions, and a heading over each
            // says which is which faster than a sentence under every slider.
            SettingCard {
                SettingGroupLabel("Move")
                adjustmentSlider(
                    "Sideways",
                    value: adjustmentBinding(key, \.horizontal),
                    range: IslandAdjustment.horizontalRange
                )
                adjustmentSlider(
                    "Down",
                    value: adjustmentBinding(key, \.vertical),
                    range: IslandAdjustment.verticalRange
                )
            }

            SettingCard {
                SettingGroupLabel("Size")
                adjustmentSlider(
                    "Width",
                    value: adjustmentBinding(key, \.width),
                    range: IslandAdjustment.widthRange
                )
                adjustmentSlider(
                    "Height",
                    value: adjustmentBinding(key, \.height),
                    range: IslandAdjustment.heightRange
                )
            }

            Text("Remembered per display.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
    }

    /// Keeps a slider's value whole without asking it for a `step`.
    ///
    /// macOS draws one tick mark under a stepped slider for every step in its
    /// range. Over the sideways range that is 481 of them, which renders as a
    /// solid bar beneath the track and reads as a rendering fault rather than a
    /// scale — the shorter ranges gave it away by showing the individual dashes.
    /// Rounding here keeps the numbers whole and leaves the track clean.
    private func whole(_ binding: Binding<Double>) -> Binding<Double> {
        Binding(
            get: { binding.wrappedValue.rounded() },
            set: { binding.wrappedValue = $0.rounded() }
        )
    }

    /// One adjustment: a short name, its value, and a full-width track.
    ///
    /// The old shape put a name and a sentence of explanation on the left and
    /// the slider in whatever space was left on the right — so four of them
    /// stacked gave four paragraphs and four stubs of track crushed against the
    /// edge, on a page that is nothing but sliders. The words were the problem:
    /// "Move sideways" needs no sentence under it, and "Currently 12 pt" is a
    /// value, not prose.
    ///
    /// So the name and the value share one line, and the track gets the whole
    /// width below them. Nothing is lost — the number is still there, and it is
    /// easier to read where it is now.
    private func adjustmentSlider(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.88))
                Spacer(minLength: 8)
                Text("\(Int(value.wrappedValue)) pt")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(
                        Int(value.wrappedValue) == 0
                            ? .white.opacity(0.35)
                            : settings.accent.color
                    )
                    .monospacedDigit()
            }
            Slider(value: whole(value), in: range)
                .frame(maxWidth: .infinity)
                .controlSize(.small)
        }
        .padding(.vertical, 2)
    }

    private func adjustmentBinding(
        _ key: String,
        _ path: WritableKeyPath<IslandAdjustment, Double>
    ) -> Binding<Double> {
        Binding(
            get: { settings.adjustment(for: key)[keyPath: path] },
            set: { newValue in
                var adjustment = settings.adjustment(for: key)
                adjustment[keyPath: path] = newValue
                settings.setAdjustment(adjustment, for: key)
            }
        )
    }

    private var privacy: some View {
        VStack(alignment: .leading, spacing: 22) {
            PageHeader(
                "Privacy",
                detail: "Everything stays on this Mac."
            )

            // Four words that are each their own answer, before any prose.
            //
            // This page was five dense paragraphs stacked in one card, and the
            // effect of putting every reassurance next to every other one is
            // that none of them lands — a wall of text about privacy reads as
            // something to skip, which is the opposite of the point. The things
            // that are simply NONE are said as one word each, because that is
            // the whole answer and anything added to it is dilution.
            HStack(spacing: 8) {
                PrivacyNone("Network", "no requests at all")
                PrivacyNone("Analytics", "nothing counted")
            }
            HStack(spacing: 8) {
                PrivacyNone("Files written", "settings only")
                PrivacyNone("Audio", "never listened to")
            }

            SettingCard {
                PrivacyLine(
                    "What it may ask for",
                    "Your media apps, to control playback. Your Downloads folder, for the download notice. Notifications, for the timer."
                )
                SettingDivider()
                PrivacyLine(
                    "What it never asks for",
                    "Screen Recording and Full Disk Access. Accessibility only if you switch on browser control yourself."
                )
                SettingDivider()
                PrivacyLine(
                    "Off means off",
                    "An indicator switched off is never started — it reads nothing and asks for nothing."
                )
            }

            Text("Every line here is checkable by reading the source. The full detail is in SECURITY.md.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
    }

    // MARK: Bindings

    private func enabledBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { settings.features[id]?.enabled ?? true },
            set: { value in settings.update(id) { $0.enabled = value } }
        )
    }

    private func styleBinding(_ id: String) -> Binding<String> {
        Binding(
            get: { settings.features[id]?.styleID ?? "default" },
            set: { value in settings.update(id) { $0.styleID = value } }
        )
    }

    private var loginDetail: String {
        // Ask WHY it is unavailable rather than assuming.
        //
        // This used to answer every unavailable case with "available once Hash
        // D Island is running from your Applications folder" — which is the
        // right answer for a bare binary and a false one on macOS 12, where the
        // app IS in Applications and opening at login genuinely cannot work
        // because the system interface for it did not exist yet. Telling
        // somebody to do a thing they have already done is the worst kind of
        // explanation: it costs them the attempt and teaches them not to
        // believe the next message.
        if let reason = LoginItem.unavailableReason {
            return reason
        }
        if LoginItem.needsApproval {
            return "macOS is waiting for you to allow this in System Settings."
        }
        return "Comes back every time you start your Mac."
    }

    /// Turning it on asks macOS for the permission at that moment, which is
    /// the only moment the request makes sense — an app that asks at launch for
    /// something it may never do is an app people say no to.
    private var mediaKeysBinding: Binding<Bool> {
        Binding(
            get: { settings.canPressMediaKeys },
            set: { value in
                settings.canPressMediaKeys = value
                if value { MediaControl.requestPermission() }
            }
        )
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            // Read the OS's actual login-item state, not our stored copy — the
            // user can also change it in System Settings behind our back.
            get: { LoginItem.isSupported ? LoginItem.isEnabled : settings.launchAtLogin },
            set: { value in
                let ok = LoginItem.setEnabled(value)
                settings.launchAtLogin = ok ? value : LoginItem.isEnabled
            }
        )
    }
}

/// Drops one indicator onto another to reorder the list.
private struct ReorderDrop: DropDelegate {
    let target: String
    let order: [String]
    @Binding var dragging: String?
    let apply: ([String]) -> Void

    func dropEntered(info: DropInfo) {
        guard let source = dragging, source != target else { return }
        apply(SettingsReorder.moving(source, before: target, in: order))
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}

/// Catches a drag that ended anywhere other than on a row.
///
/// `performDrop` is the only place the held id was cleared, and it only runs
/// when a drag lands ON a row. Let go over the gap between two rows, over the
/// sidebar, or outside the window, and nothing ran — so the id stayed set for
/// the rest of the session. The row it named stayed dimmed, and every later
/// hover over any row fired a reorder against that stale id, which is what made
/// the settings window appear to freeze after reordering indicators.
///
/// This sits behind the whole list and accepts whatever the rows did not.
private struct ReorderCancel: DropDelegate {
    @Binding var dragging: String?

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .cancel) }
}

/// The reordering itself, kept apart from the view so it can be checked.
public enum SettingsReorder {
    /// `source` lifted out of the list and dropped at `target`'s position.
    /// Unknown ids leave the order untouched rather than corrupting it.
    public static func moving(_ source: String, before target: String, in order: [String]) -> [String] {
        guard source != target,
              let from = order.firstIndex(of: source),
              let to = order.firstIndex(of: target)
        else { return order }

        var ids = order
        ids.remove(at: from)
        ids.insert(source, at: to)
        return ids
    }
}

// MARK: Small building blocks

private struct PageHeader: View {
    let title: String
    let detail: String

    init(_ title: String, detail: String) {
        self.title = title
        self.detail = detail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 19, weight: .semibold, design: .rounded))
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineSpacing(2.5)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct SettingCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.045))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
                    )
            )
    }
}

private struct SettingRow<Control: View>: View {
    let title: String
    let detail: String
    @ViewBuilder var control: Control

    /// Whether the control sits below the label rather than beside it.
    ///
    /// Beside is right for a switch, which is small and reads as part of the
    /// same line. It is wrong for a slider or a row of choices: the column here
    /// is about 270 points wide, and a 220-point control beside a label leaves
    /// the label 40 points to live in. Those go underneath, full width, where
    /// they have room and line up with each other down the page.
    ///
    /// **The rule, since this has now been got wrong twice:** anything wider
    /// than about 120 points must be stacked. A control with a fixed width wins
    /// the space outright, and the label does not merely wrap — it runs out of
    /// room to wrap between words and starts breaking them mid-word, so "Accent
    /// colour" comes out as "Accen / t colour". `minimumLabelWidth` below makes
    /// that fail visibly rather than quietly.
    let stacked: Bool

    init(
        _ title: String,
        detail: String,
        stacked: Bool = false,
        @ViewBuilder control: () -> Control
    ) {
        self.title = title
        self.detail = detail
        self.stacked = stacked
        self.control = control()
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 12.5, weight: .medium))
            Text(detail)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                // Explanations are sentences, and sentences need leading. Set
                // solid they read as a wall and the eye skips them, which is
                // the opposite of what an explanation is for.
                .lineSpacing(2.5)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    var body: some View {
        Group {
            if stacked {
                VStack(alignment: .leading, spacing: 11) {
                    label
                    control.frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                HStack(alignment: .center, spacing: 16) {
                    label
                        // The words come first. Without this a control that can
                        // stretch takes what it likes and the label is left
                        // breaking mid-word to fit whatever remains.
                        .layoutPriority(1)
                        .frame(minWidth: settingRowMinimumLabelWidth, alignment: .leading)
                    Spacer(minLength: 8)
                    control
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 9)
    }

}

/// The least room a label may have beside its control before the pairing is
/// simply wrong and the row should be stacked instead. Enough for two words of
/// the title at this size, so a squeeze shows up as a row that overflows its
/// card rather than as text quietly shredded between letters.
///
/// File scope rather than a member: `SettingRow` is generic over its control,
/// and a generic type cannot hold a stored static.
private let settingRowMinimumLabelWidth: CGFloat = 150

private struct PrivacyLine: View {
    let title: String
    let detail: String

    init(_ title: String, _ detail: String) {
        self.title = title
        self.detail = detail
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 11))
                .foregroundStyle(.green)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12, weight: .medium))
                Text(detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 7)
    }
}

private struct SettingDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.07))
            .frame(height: 1)
            // A hairline with nothing either side of it does not separate
            // anything; it just draws a line through a wall of text.
            .padding(.vertical, 2)
    }
}

private extension View {
    /// `scrollIndicators(.never)` where it exists, and nothing where it does
    /// not. Kept as one modifier so the call site reads as intent rather than
    /// as a version check in the middle of a layout.
    @ViewBuilder
    func hideScrollIndicatorsIfPossible() -> some View {
        if #available(macOS 13, *) {
            self.scrollIndicators(.never)
        } else {
            self
        }
    }
}

private extension SettingsView {
    /// Says what the sliders currently amount to, including the case where they
    /// amount to nothing — turning the lines off is a preference, not a fault,
    /// and the row should say so rather than describing a line that is not there.
    var separatorDetail: String {
        let thickness = settings.appearance.separatorThickness
        guard thickness > 0, settings.appearance.separatorOpacity > 0 else {
            return "Off — the indicators run together."
        }
        let percent = Int((settings.appearance.separatorOpacity * 100).rounded())
        return String(format: "%.1f pt at %d%% between each indicator.", thickness, percent)
    }
}

/// A single-word answer, for the things that are simply none.
///
/// The word carries it. A tile that says "None" in the accent colour, with four
/// words under it saying what of, is read in the time it takes to glance —
/// where the same fact inside a paragraph is read by nobody. Reserved for
/// claims that really are absolute, so the format itself means something.
struct PrivacyNone: View {
    let title: String
    let detail: String

    init(_ title: String, _ detail: String) {
        self.title = title
        self.detail = detail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
            Text("None")
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(detail)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.42))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.045))
        )
    }
}

/// A quiet heading inside a card, for when a group of controls needs naming but
/// does not need a sentence.
struct SettingGroupLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .semibold))
            .kerning(1.0)
            .foregroundStyle(.white.opacity(0.4))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 2)
    }
}
