import AppKit

/// Asks before quitting.
///
/// The quit button sits in the panel's top band, a few points from the settings
/// gear and directly under where the pointer travels to reach the notch. It is
/// one click from "gone", with nothing to undo it and no Dock icon to click to
/// get the app back — the only way back is Spotlight or Finder, which is a lot
/// of work to pay for a slip of the hand.
///
/// So it asks. The confirmation is deliberately a real alert rather than an
/// in-panel "are you sure": the panel closes the moment the pointer leaves it,
/// which would take the question with it.
@MainActor
public enum QuitConfirmation {
    /// Shows the alert and quits if the answer is yes.
    public static func ask() {
        // The app has no Dock icon and never takes focus, so without this the
        // alert can open behind whatever the user is working in — a modal
        // waiting for an answer where nobody can see it.
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Quit Hash D Island?"
        alert.informativeText = """
        The island will disappear from your notch. Everything it was watching \
        stops, and nothing else on your Mac is affected.

        To bring it back, open Hash D Island again from Applications.
        """

        let quit = alert.addButton(withTitle: "Quit")
        // Red, so the button that ends the app never looks like the safe one.
        quit.hasDestructiveAction = true

        let cancel = alert.addButton(withTitle: "Cancel")
        // Escape backs out, which is the reflex when a dialog appears by
        // accident — and appearing by accident is the case this exists for.
        cancel.keyEquivalent = "\u{1b}"

        // Above the island, or it is not a dialog — it is a hidden one.
        //
        // The overlay floats at `.statusBar` so it can draw over the menu bar,
        // and an alert opens far below that. Activating the app brings it
        // forward among other apps but changes nothing about levels WITHIN this
        // one, so the question appeared underneath the very panel whose button
        // asked it, with the app waiting on an answer nobody could see.
        alert.window.level = .popUpMenu

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        NSApp.terminate(nil)
    }
}
