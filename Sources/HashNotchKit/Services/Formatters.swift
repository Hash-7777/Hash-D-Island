import Foundation

/// Shared, allocation-light formatters so numbers read consistently everywhere.
public enum Formatters {
    /// Formats a bytes-per-second rate like "9 KB", "2 MB" (unit split out so the
    /// UI can style value and unit differently, matching the reference HUD).
    public static func rate(_ bytesPerSecond: Double) -> (value: String, unit: String) {
        let units = ["B", "KB", "MB", "GB"]
        var value = max(0, bytesPerSecond)
        var index = 0
        while value >= 1024, index < units.count - 1 {
            value /= 1024
            index += 1
        }
        // One decimal for small scaled values (2.3 MB/s reads better than 2),
        // but drop a trailing ".0" so 9.0 KB shows as a clean "9".
        let rounded: String
        if value < 10, index > 0 {
            let oneDecimal = (value * 10).rounded() / 10
            rounded = oneDecimal == oneDecimal.rounded()
                ? String(format: "%.0f", oneDecimal)
                : String(format: "%.1f", oneDecimal)
        } else {
            rounded = String(format: "%.0f", value)
        }
        return (rounded, units[index] + "/s")
    }
}
