import AppKit
import ApplicationServices

/// Measures the frontmost app's menu bar using the Accessibility API, so the HUD
/// can avoid sitting on top of the app's menus.
///
/// Accessibility is a user-granted permission. Until it is granted every query
/// returns nil, which callers treat as "no limit" — so the app is always safe:
/// worst case, avoidance simply doesn't kick in.
public enum AccessibilityMenuProbe {
    /// Whether the app currently has Accessibility permission.
    public static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Ask the system to grant Accessibility permission (opens the prompt once).
    public static func requestPermission() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// The screen-space x (points from the left edge) where the frontmost app's
    /// menus end — i.e. the right edge of its last menu title. Returns nil if it
    /// can't be measured (no permission, no menus, etc.).
    public static func frontmostAppMenusRightEdge() -> CGFloat? {
        guard isTrusted,
              let app = NSWorkspace.shared.frontmostApplication else { return nil }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        var menuBarRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXMenuBarAttribute as CFString, &menuBarRef) == .success,
              let menuBar = menuBarRef, CFGetTypeID(menuBar) == AXUIElementGetTypeID() else {
            return nil
        }
        let menuBarElement = menuBar as! AXUIElement

        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(menuBarElement, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let items = childrenRef as? [AXUIElement] else {
            return nil
        }

        var rightEdge: CGFloat = 0
        for item in items {
            var positionRef: CFTypeRef?
            var sizeRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(item, kAXPositionAttribute as CFString, &positionRef) == .success,
                  AXUIElementCopyAttributeValue(item, kAXSizeAttribute as CFString, &sizeRef) == .success else {
                continue
            }

            var position = CGPoint.zero
            var size = CGSize.zero
            AXValueGetValue(positionRef as! AXValue, .cgPoint, &position)
            AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
            rightEdge = max(rightEdge, position.x + size.width)
        }

        return rightEdge > 0 ? rightEdge : nil
    }
}
