import CoreAudio

/// System output volume via CoreAudio — the public system-audio API, the same
/// control the volume keys drive. Direct calls, so the slider reacts with zero
/// latency (the earlier osascript path cost a subprocess per change).
///
/// Devices expose volume either on the main element or per channel; reading
/// prefers main and falls back to channel 1, setting writes main when it is
/// settable and otherwise both stereo channels.
package enum SystemVolume {
    package static func read() -> Int? {
        guard let device = defaultOutputDevice() else { return nil }
        for element: UInt32 in [0, 1] {
            var address = volumeAddress(element)
            guard AudioObjectHasProperty(device, &address) else { continue }
            var volume = Float32(0)
            var size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectGetPropertyData(device, &address, 0, nil, &size, &volume) == noErr {
                return Int((min(max(volume, 0), 1) * 100).rounded())
            }
        }
        return nil
    }

    package static func set(_ percent: Int) {
        guard let device = defaultOutputDevice() else { return }
        var volume = Float32(min(max(percent, 0), 100)) / 100
        let size = UInt32(MemoryLayout<Float32>.size)
        for element: UInt32 in [0, 1, 2] {
            var address = volumeAddress(element)
            guard AudioObjectHasProperty(device, &address) else { continue }
            var settable = DarwinBoolean(false)
            guard AudioObjectIsPropertySettable(device, &address, &settable) == noErr,
                  settable.boolValue else { continue }
            if AudioObjectSetPropertyData(device, &address, 0, nil, size, &volume) == noErr,
               element == 0 {
                return
            }
        }
    }

    private static func defaultOutputDevice() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
        )
        return status == noErr && deviceID != 0 ? deviceID : nil
    }

    private static func volumeAddress(_ element: UInt32) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )
    }
}
