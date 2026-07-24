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
                .scrollIndicators(.never)
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
        return Button { section = item } label: {
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

            Spacer(minLength: 0)
        }
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
                SettingRow("Accent colour", detail: "Tints icons, bars and highlights.") {
                    HStack(spacing: 6) {
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
                    detail: current.isAutomatic
                        ? "Automatic — measured from this display."
                        : "Adjusted by hand for this display."
                ) {
                    Button("Reset to automatic") {
                        settings.setAdjustment(IslandAdjustment(), for: key)
                    }
                    .disabled(current.isAutomatic)
                }
            }

            SettingCard {
                adjustmentSlider(
                    "Move sideways",
                    value: adjustmentBinding(key, \.horizontal),
                    range: IslandAdjustment.horizontalRange,
                    detail: "Left and right, in points."
                )
                SettingDivider()
                adjustmentSlider(
                    "Move down",
                    value: adjustmentBinding(key, \.vertical),
                    range: IslandAdjustment.verticalRange,
                    detail: "Away from the top edge of the screen."
                )
                SettingDivider()
                adjustmentSlider(
                    "Width",
                    value: adjustmentBinding(key, \.width),
                    range: IslandAdjustment.widthRange,
                    detail: "Added to the island's resting width. It grows evenly from its centre."
                )
                SettingDivider()
                adjustmentSlider(
                    "Height",
                    value: adjustmentBinding(key, \.height),
                    range: IslandAdjustment.heightRange,
                    detail: "Added to the island's resting height."
                )
            }

            Text("Adjustments are remembered per display, so a correction for your laptop never follows you onto an external monitor.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

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

    private func adjustmentSlider(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        detail: String
    ) -> some View {
        SettingRow(title, detail: "\(detail) Currently \(Int(value.wrappedValue)) pt.") {
            Slider(value: whole(value), in: range).frame(maxWidth: .infinity)
        }
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

            SettingCard {
                PrivacyLine(
                    "Network",
                    "One request only: album and video artwork, from Spotify's and YouTube's image hosts. Nothing else ever leaves."
                )
                SettingDivider()
                PrivacyLine(
                    "Files written",
                    "None. The only thing kept is these settings, where every Mac app keeps them."
                )
                SettingDivider()
                PrivacyLine(
                    "Audio",
                    "Never listened to. The bars follow the play state, not the sound."
                )
                SettingDivider()
                PrivacyLine(
                    "Permissions",
                    "Automation for your media apps, and for your browser only while a web video is playing. Your Downloads folder, for the download notice. Notifications, for the timer. Never Accessibility, Screen Recording or Full Disk Access."
                )
                SettingDivider()
                PrivacyLine(
                    "Turning one off",
                    "Stops the work, not just the display. An indicator switched off in Indicators is never started, so it reads nothing and asks for nothing."
                )
            }

            Text("The full detail, and how to check every line of it yourself, is in SECURITY.md.")
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
        if !LoginItem.isSupported {
            return "Available once Hash D Island is running from your Applications folder."
        }
        if LoginItem.needsApproval {
            return "macOS is waiting for you to allow this in System Settings."
        }
        return "Comes back every time you start your Mac."
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
                    Spacer(minLength: 8)
                    control
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 9)
    }
}

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
