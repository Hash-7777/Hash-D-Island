import CoreAudio
import Foundation

/// Fires the callback the instant system audio starts or stops anywhere — a
/// CoreAudio property listener on the output device's "is running somewhere"
/// flag. Public API, no polling, no permissions; this is what lets the notch
/// react to a play press in well under a second instead of waiting for the
/// next poll. Re-attaches itself when the default output device changes
/// (AirPods connect, speaker switch).
final class AudioActivityObserver {
    private let onChange: () -> Void
    private let queue = DispatchQueue.main
    private var device: AudioObjectID = 0
    private var runningListener: AudioObjectPropertyListenerBlock?
    private var defaultListener: AudioObjectPropertyListenerBlock?

    private var runningAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    private var defaultAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    /// Whether anything on this Mac is playing audio right now.
    ///
    /// The same flag the listener watches, read on demand. Its value is what
    /// makes a paused track interesting: a track that is paused while the
    /// speakers are busy means something ELSE is playing, and that is the one
    /// moment worth looking more often — without which the choice is between a
    /// slow switch and polling hard forever.
    var isAudioRunning: Bool {
        guard device != 0 else { return false }
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(
            device, &runningAddress, 0, nil, &size, &running
        ) == noErr else { return false }
        return running != 0
    }

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange

        let defaultListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.attachToDefaultDevice()
            self?.onChange()
        }
        self.defaultListener = defaultListener
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &defaultAddress, queue, defaultListener
        )
        attachToDefaultDevice()
    }

    deinit {
        detachDevice()
        if let defaultListener {
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &defaultAddress, queue, defaultListener
            )
        }
    }

    private func attachToDefaultDevice() {
        detachDevice()
        var id = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &defaultAddress, 0, nil, &size, &id
        ) == noErr, id != 0 else { return }

        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.onChange()
        }
        runningListener = listener
        device = id
        AudioObjectAddPropertyListenerBlock(id, &runningAddress, queue, listener)
    }

    private func detachDevice() {
        if device != 0, let runningListener {
            AudioObjectRemovePropertyListenerBlock(device, &runningAddress, queue, runningListener)
        }
        device = 0
        runningListener = nil
    }
}
