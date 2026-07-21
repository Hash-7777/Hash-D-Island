import SwiftUI

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

/// The customization window: turn features on or off, choose a side, pick a
/// display style per feature, tune spacing, and toggle open-at-login.
public struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    let features: [FeatureDescriptor]

    public init(settings: SettingsStore, features: [FeatureDescriptor]) {
        self.settings = settings
        self.features = features
    }

    public var body: some View {
        Form {
            Section("Indicators") {
                ForEach(features) { feature in
                    featureRow(feature)
                }
            }

            Section("Spacing") {
                slider("Gap on the left", value: insetBinding(\.leadingInset), range: 0...80)
                slider("Gap on the right", value: insetBinding(\.trailingInset), range: 0...80)
                slider("Space between items", value: insetBinding(\.itemSpacing), range: 4...40)
            }

            Section("General") {
                Toggle("Open at login", isOn: launchAtLoginBinding)
                    .disabled(!LoginItem.isSupported)
                if !LoginItem.isSupported {
                    Text("Available once HashNotch is installed as an app.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 520)
    }

    @ViewBuilder
    private func featureRow(_ feature: FeatureDescriptor) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(feature.title, isOn: enabledBinding(feature.id))
                .font(.headline)

            if settings.isEnabled(feature.id) {
                Picker("Side", selection: placementBinding(feature.id)) {
                    Text(FeaturePlacement.leading.label).tag(FeaturePlacement.leading)
                    Text(FeaturePlacement.trailing.label).tag(FeaturePlacement.trailing)
                }

                if !feature.options.isEmpty {
                    Picker("Show as", selection: styleBinding(feature.id)) {
                        ForEach(feature.options) { option in
                            Text(option.title).tag(option.id)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func slider(_ label: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack {
            Text(label)
            Slider(value: value, in: range)
            Text("\(Int(value.wrappedValue))")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .trailing)
        }
    }

    // MARK: Bindings

    private func enabledBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { settings.features[id]?.enabled ?? true },
            set: { value in settings.update(id) { $0.enabled = value } }
        )
    }

    private func placementBinding(_ id: String) -> Binding<FeaturePlacement> {
        Binding(
            get: { settings.features[id]?.placement ?? .trailing },
            set: { value in settings.update(id) { $0.placement = value } }
        )
    }

    private func styleBinding(_ id: String) -> Binding<String> {
        Binding(
            get: { settings.features[id]?.styleID ?? "default" },
            set: { value in settings.update(id) { $0.styleID = value } }
        )
    }

    private func insetBinding(_ keyPath: WritableKeyPath<LayoutConfig, Double>) -> Binding<Double> {
        Binding(
            get: { settings.layout[keyPath: keyPath] },
            set: { value in settings.layout[keyPath: keyPath] = value }
        )
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { settings.launchAtLogin },
            set: { value in
                let ok = LoginItem.setEnabled(value)
                settings.launchAtLogin = ok ? value : LoginItem.isEnabled
            }
        )
    }
}
