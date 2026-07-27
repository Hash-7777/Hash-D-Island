import AppKit
import CoreAudio
import Foundation

/// Which app, if any, currently has the microphone open.
///
/// ## What this does and does not do
///
/// It asks CoreAudio one question: *is this process running an input stream?*
/// The answer is a boolean. No audio is opened, no samples are read, nothing is
/// recorded, transcribed or inspected, and no microphone permission is asked
/// for or held — reading this flag is not using the microphone, in the same way
/// that seeing a door is shut is not going through it.
///
/// That is the entire mechanism, and it is worth being precise about because
/// "the app knows when you are on a call" is exactly the sentence that should
/// make somebody suspicious. What it knows is that an application has an input
/// stream open. It does not know who you are talking to, whether anybody is
/// talking, or what is being said, and there is nothing in this file that could
/// be extended to find out — the API returns a flag and a process id.
///
/// ## Which app
///
/// The process id is turned into a running application, which gives the name
/// and the icon. Only real applications count: `corespeechd`, Apple's own
/// dictation service, holds an input stream open permanently on a normal Mac,
/// and every other system daemon is free to do the same. A helper with no
/// bundle identifier is not something a person is "in a call" with, so the
/// filter is for an actual app rather than a list of meeting apps by name —
/// FaceTime, Zoom, Teams, Meet in a browser, a game, a voice recorder, or
/// something released next year all work identically, and nothing has to be
/// added to a list for a new one to be recognised.
package enum CallReader {
    /// One app with the microphone open.
    package struct Listener: Equatable {
        package let bundleIdentifier: String
        package let name: String
        package let processID: pid_t
        /// False when the microphone is held by a background service rather
        /// than by something the user would recognise, and no app could be
        /// attributed. The readout then says a microphone is in use without
        /// naming anything, which is the honest answer.
        package var isNamedApp: Bool = true

        package init(
            bundleIdentifier: String,
            name: String,
            processID: pid_t,
            isNamedApp: Bool = true
        ) {
            self.bundleIdentifier = bundleIdentifier
            self.name = name
            self.processID = processID
            self.isNamedApp = isNamedApp
        }
    }

    /// Apple's own audio services, and the app each one works for.
    ///
    /// A list of one, and it is here reluctantly — naming things by identifier
    /// is what this file otherwise avoids, because a list is wrong for
    /// everything not on it. It exists because FaceTime does not hold the
    /// microphone itself: `avconferenced`, a daemon, holds it on FaceTime's
    /// behalf, so the readout said "avconferenced" during a FaceTime call. That
    /// is a true statement about the machine and a useless one about the call.
    ///
    /// Every other app tested holds its own input — Zoom, Teams, a browser, a
    /// voice memo — so nothing else needs an entry, and anything that does show
    /// up through a daemon nobody has mapped is reported as an unnamed
    /// microphone rather than by its internal name.
    private static let serviceOwners: [String: String] = [
        "com.apple.avconferenced": "com.apple.FaceTime",
    ]

    /// Whether the OS exposes per-process audio at all. macOS 14.4 added it;
    /// below that only the device-wide flag exists, which says that *something*
    /// is using the microphone without saying what.
    package static var namesTheApp: Bool {
        var size: UInt32 = 0
        var address = processListAddress
        return AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size
        ) == noErr
    }

    private static var processListAddress = AudioObjectPropertyAddress(
        mSelector: AudioObjectPropertySelector(kAudioHardwarePropertyProcessObjectList),
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    /// The app using the microphone right now, or nil.
    ///
    /// When more than one is, the frontmost wins — on the rare occasion two
    /// apps hold input at once, the one being looked at is the one the notch
    /// should be about.
    package static func current() -> Listener? {
        let listeners = allListeners()
        guard !listeners.isEmpty else { return unattributedIfInputRunning() }

        // An app somebody would recognise, if one of them is holding the
        // microphone directly. This is the ordinary case — Zoom, Teams, a
        // browser, a voice memo all hold their own input.
        let apps = listeners.filter { isRecognisableApp($0.bundleIdentifier) }
        if !apps.isEmpty {
            if let front = NSWorkspace.shared.frontmostApplication?.processIdentifier,
               let match = apps.first(where: { $0.processID == front }) {
                return match
            }
            return apps.first
        }

        // Otherwise a background service has it. Attribute it to the app it
        // serves where that is known and that app is actually running —
        // FaceTime being the case this exists for.
        for listener in listeners {
            guard let ownerID = serviceOwners[listener.bundleIdentifier],
                  let owner = NSRunningApplication
                      .runningApplications(withBundleIdentifier: ownerID).first,
                  let name = owner.localizedName
            else { continue }
            return Listener(
                bundleIdentifier: ownerID,
                name: name,
                processID: owner.processIdentifier
            )
        }

        // Something has the microphone and nothing here can honestly say what.
        // Still worth showing — that the microphone is live is the important
        // half — but named as what it is rather than by a daemon's internal
        // name, which tells the reader nothing and looks like a bug.
        return Listener(
            bundleIdentifier: listeners[0].bundleIdentifier,
            name: "Microphone in use",
            processID: listeners[0].processID,
            isNamedApp: false
        )
    }

    /// The last resort: the input device says it is running, but no process the
    /// app can see owns it.
    ///
    /// This is what dictation looks like. macOS runs it through `corespeechd`,
    /// which has no bundle identifier at all and so never appears as an app —
    /// and which holds an input stream open PERMANENTLY on an ordinary Mac, so
    /// its own flag says nothing about whether anybody is dictating. Measured:
    /// idle, with corespeechd holding input, the device still reported itself
    /// as not running.
    ///
    /// So the two answer different questions. The per-process list answers WHO,
    /// and the device flag answers WHETHER — and when the second says yes while
    /// the first has nobody to offer, the honest readout is that the microphone
    /// is live with no name attached.
    private static func unattributedIfInputRunning() -> Listener? {
        guard inputBusyDeviceWide() else { return nil }
        return Listener(
            bundleIdentifier: "",
            name: "Microphone in use",
            processID: 0,
            isNamedApp: false
        )
    }

    /// Whether a bundle identifier belongs to something a person would call an
    /// app, rather than to a background service.
    ///
    /// macOS already draws this line: a daemon is `.prohibited` — it cannot be
    /// brought to the front because there is nothing to bring. Regular apps and
    /// menu-bar apps both count, since a menu-bar recorder using the microphone
    /// is a real app doing a real thing.
    private static func isRecognisableApp(_ bundleIdentifier: String) -> Bool {
        guard let app = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier).first
        else { return false }
        return app.activationPolicy != .prohibited
    }

    /// Every real app with an input stream open. Package-visible so the checks
    /// can see it returns nothing surprising on a machine with no call running.
    package static func allListeners() -> [Listener] {
        var size: UInt32 = 0
        var address = processListAddress
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size
        ) == noErr, size > 0 else { return [] }

        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        var objects = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &objects
        ) == noErr else { return [] }

        return objects.compactMap(listener(for:))
    }

    private static func listener(for object: AudioObjectID) -> Listener? {
        guard isRunningInput(object), let pid = processID(of: object) else { return nil }
        // A real application, with a bundle identifier and a name. This is what
        // excludes corespeechd and its kind — a system service holding the
        // microphone open is not somebody being on a call, and treating it as
        // one would light the notch permanently on an ordinary Mac.
        guard let app = NSRunningApplication(processIdentifier: pid),
              let bundle = app.bundleIdentifier,
              !bundle.isEmpty,
              let name = app.localizedName
        else { return nil }
        return Listener(bundleIdentifier: bundle, name: name, processID: pid)
    }

    private static func isRunningInput(_ object: AudioObjectID) -> Bool {
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioProcessPropertyIsRunningInput),
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &running) == noErr
        else { return false }
        return running != 0
    }

    private static func processID(of object: AudioObjectID) -> pid_t? {
        var pid: pid_t = 0
        var size = UInt32(MemoryLayout<pid_t>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioProcessPropertyPID),
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &pid) == noErr
        else { return nil }
        return pid
    }

    /// The fallback for macOS below 14.4: is *anything* using the default input?
    ///
    /// Device-wide, so it cannot name the app — and it counts the system's own
    /// dictation service, which is why it is only ever consulted when the
    /// per-process list is unavailable.
    package static func inputBusyDeviceWide() -> Bool {
        var device = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var deviceAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &deviceAddress, 0, nil, &size, &device
        ) == noErr else { return false }

        var running: UInt32 = 0
        var runningSize = UInt32(MemoryLayout<UInt32>.size)
        var runningAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(
            device, &runningAddress, 0, nil, &runningSize, &running
        ) == noErr else { return false }
        return running != 0
    }

    /// How long a call has been running, as the notch says it.
    ///
    /// Counts from when the microphone was first seen open, which is not
    /// necessarily when the call was answered — nothing available here knows
    /// that. Minutes and seconds up to an hour, then hours.
    package static func elapsedText(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        if total < 3_600 {
            return String(format: "%d:%02d", total / 60, total % 60)
        }
        return String(format: "%d:%02d:%02d", total / 3_600, (total % 3_600) / 60, total % 60)
    }
}
