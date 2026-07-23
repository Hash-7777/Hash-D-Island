import SwiftUI

/// The accent colours the island can be tinted with.
///
/// A short, named list rather than a colour well: every one of these is chosen
/// to stay legible against solid black at eleven points, which an arbitrary
/// colour is not. The stored value is the id, so a palette can be re-tuned
/// later without invalidating anyone's saved choice.
public struct AccentColor: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let color: Color

    public static let all: [AccentColor] = [
        AccentColor(id: "blue", name: "Blue", color: Color(red: 0.25, green: 0.55, blue: 1.00)),
        AccentColor(id: "green", name: "Green", color: Color(red: 0.28, green: 0.84, blue: 0.48)),
        AccentColor(id: "orange", name: "Orange", color: Color(red: 1.00, green: 0.62, blue: 0.20)),
        AccentColor(id: "pink", name: "Pink", color: Color(red: 1.00, green: 0.40, blue: 0.62)),
        AccentColor(id: "purple", name: "Purple", color: Color(red: 0.68, green: 0.48, blue: 1.00)),
        AccentColor(id: "white", name: "White", color: Color.white),
    ]

    public static let `default` = all[0]

    /// The accent for a stored id, falling back to the default so an id from a
    /// newer build never leaves the island untinted.
    public static func named(_ id: String) -> AccentColor {
        all.first { $0.id == id } ?? .default
    }
}
