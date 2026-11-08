import CoreAudio
import Foundation

/// Un périphérique d'entrée audio (micro intégré, micro USB, AirPods…).
public struct AudioInputDevice: Identifiable, Hashable, Sendable {
    /// Identifiant numérique CoreAudio : valable seulement tant que le
    /// périphérique est branché (il change d'une session à l'autre).
    public let deviceID: AudioDeviceID
    /// Identifiant texte **stable** : c'est lui qu'on enregistre dans les réglages.
    public let uid: String
    public let name: String

    public var id: String { uid }
}

/// Lecture de la liste des périphériques via CoreAudio (API C de bas niveau).
///
/// CoreAudio fonctionne par « propriétés » : on demande la taille d'une
/// propriété, on alloue un tampon, puis on lit la valeur. C'est verbeux, mais
/// c'est le seul moyen d'énumérer les micros sur macOS.
public enum AudioDevices {
    /// Tous les périphériques ayant au moins un canal d'entrée.
    public static func inputDevices() -> [AudioInputDevice] {
        allDeviceIDs().compactMap { id in
            guard inputChannelCount(of: id) > 0,
                  let uid = stringProperty(kAudioDevicePropertyDeviceUID, of: id),
                  let name = stringProperty(kAudioObjectPropertyName, of: id)
            else { return nil }
            return AudioInputDevice(deviceID: id, uid: uid, name: name)
        }
    }

    /// Le micro par défaut choisi dans Réglages Système > Son.
    public static func defaultInputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        return status == noErr && deviceID != 0 ? deviceID : nil
    }

    /// Retrouve l'ID courant d'un périphérique à partir de son UID stable.
    public static func deviceID(forUID uid: String) -> AudioDeviceID? {
        inputDevices().first { $0.uid == uid }?.deviceID
    }

    // MARK: - Utilitaires CoreAudio

    private static func allDeviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func inputChannelCount(of id: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        // AudioBufferList a une taille variable : on alloue la taille brute annoncée.
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func stringProperty(_ selector: AudioObjectPropertySelector, of id: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr,
              let value else { return nil }
        return value.takeRetainedValue() as String
    }
}
