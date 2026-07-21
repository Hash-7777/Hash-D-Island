import SwiftUI
import AppKit

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

/// The customization window: turn indicators on or off, pick a display style per
/// indicator, and toggle open-at-login.
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

            Section("General") {
                Toggle("Open at login", isOn: launchAtLoginBinding)
                    .disabled(!LoginItem.isSupported)
                if !LoginItem.isSupported {
                    Text("Available once HashNotch is installed as an app.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            // With no menu-bar item, this window is also where you quit.
            Section {
                Button("Quit HashNotch", role: .destructive) {
                    NSApp.terminate(nil)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 460)
    }

    @ViewBuilder
    private func featureRow(_ feature: FeatureDescriptor) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(feature.title, isOn: enabledBinding(feature.id))
                .font(.headline)

            if settings.isEnabled(feature.id), !feature.options.isEmpty {
                Picker("Show as", selection: styleBinding(feature.id)) {
                    ForEach(feature.options) { option in
                        Text(option.title).tag(option.id)
                    }
                }
            }
        }
        .padding(.vertical, 4)
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
