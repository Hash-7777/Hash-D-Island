import SwiftUI

/// Shared building blocks so every feature's expanded detail reads as one clean,
/// consistent list — a section header and an aligned label/value row.
public enum Panel {
    /// Standard width for a detail row, so values line up across features.
    public static let rowWidth: CGFloat = 250
}

/// Uppercase, muted section title.
public struct NotchSectionHeader: View {
    let title: String
    let theme: Theme

    public init(_ title: String, theme: Theme) {
        self.title = title
        self.theme = theme
    }

    public var body: some View {
        Text(title)
            .font(.system(size: 9, weight: .bold))
            .kerning(0.6)
            .foregroundStyle(theme.subtitleColor)
    }
}

/// A label on the left and caller-styled trailing content on the right, aligned
/// to a shared width so columns line up.
public struct NotchRow<Trailing: View>: View {
    let label: String
    let emphasized: Bool
    let theme: Theme
    let trailing: Trailing

    public init(
        _ label: String,
        emphasized: Bool = false,
        theme: Theme,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.label = label
        self.emphasized = emphasized
        self.theme = theme
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .foregroundStyle(emphasized ? theme.textColor : theme.subtitleColor)
            Spacer(minLength: 8)
            trailing
        }
        .frame(width: Panel.rowWidth)
    }
}
