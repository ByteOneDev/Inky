import CoreAudio
import Foundation
import os

/// Met en pause la musique ou la vidéo en cours pendant une dictée, puis la
/// relance — seulement si c'est Inky qui l'a mise en pause.
///
/// Comment ça marche, et pourquoi c'est un peu détourné :
///
/// 1. **Mettre en pause** : on envoie la commande « pause » du système (celle
///    des touches multimédia du clavier) via le framework privé `MediaRemote`.
///    Elle s'adresse à l'app « en lecture » (Musique, Spotify, YouTube dans un
///    navigateur…). « Pause » ne démarre jamais rien : sans risque.
/// 2. **Savoir s'il faut relancer** : depuis macOS 15.4, Apple interdit aux
///    apps tierces de demander à `MediaRemote` « quelque chose joue-t-il ? ».
///    On regarde donc CoreAudio : quels processus envoient du son au haut-parleur
///    (`kAudioProcessPropertyIsRunningOutput`). Si l'un d'eux s'arrête juste
///    après notre pause, c'est qu'il jouait : on le relancera à la fin.
///    Un navigateur peut mettre ~8 s à libérer sa sortie audio : on surveille
///    jusqu'à 12 s.
/// 3. **Relancer** : commande « lecture », seulement dans ce cas. Ainsi Inky ne
///    démarre jamais une musique que tu n'écoutais pas.
@MainActor
public final class MediaPlayback {
    private var detection: Task<Void, Never>?
    private var resume: Task<Void, Never>?
    /// Vrai si notre pause a réellement arrêté quelque chose.
    private var pausedSomething = false
    private let logger = Logger(subsystem: "com.byteonedev.inky", category: "media")

    /// Durée maximale de surveillance après la pause.
    private let detectionWindow: Duration = .seconds(12)

    public init() {}

    /// Début de dictée.
    public func pauseForDictation() {
        resume?.cancel()
        resume = nil
        // Déjà en pause par nous (dictées rapprochées) : rien à refaire.
        if detection != nil || pausedSomething { return }

        let before = AudioOutputProcesses.current()
        guard !before.isEmpty, MediaRemote.send(.pause) else { return }

        detection = Task { [weak self, detectionWindow] in
            let deadline = ContinuousClock.now + detectionWindow
            while ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(250))
                // Un processus qui jouait a arrêté sa sortie audio : c'est notre pause.
                if !before.subtracting(AudioOutputProcesses.current()).isEmpty {
                    self?.pausedSomething = true
                    self?.logger.info("Lecture en cours mise en pause pendant la dictée")
                    break
                }
            }
            self?.detection = nil
        }
    }

    /// Fin de dictée (terminée ou annulée).
    public func resumeAfterDictation() {
        guard detection != nil || pausedSomething else { return }
        resume?.cancel()
        resume = Task { [weak self] in
            // Attendre la fin de la surveillance (immédiate le plus souvent).
            await self?.detection?.value
            guard let self, !Task.isCancelled, self.pausedSomething else { return }
            self.pausedSomething = false
            _ = MediaRemote.send(.play)
        }
    }
}

/// Commandes multimédia du système, via le framework privé `MediaRemote`
/// (chargé à l'exécution : s'il disparaît un jour, la fonction ne fait rien).
enum MediaRemote {
    enum Command: UInt32 {
        case play = 0
        case pause = 1
    }

    private typealias SendCommand = @convention(c) (UInt32, CFDictionary?) -> Bool

    private static let sendCommand: SendCommand? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY),
              let symbol = dlsym(handle, "MRMediaRemoteSendCommand")
        else { return nil }
        return unsafeBitCast(symbol, to: SendCommand.self)
    }()

    @discardableResult
    static func send(_ command: Command) -> Bool {
        sendCommand?(command.rawValue, nil) ?? false
    }
}

/// Processus qui envoient actuellement du son vers une sortie audio
/// (CoreAudio, macOS 14.2+). Inky lui-même est exclu (ses petits sons).
enum AudioOutputProcesses {
    static func current() -> Set<AudioObjectID> {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        return Set(ids.filter { id in
            uint32(id, kAudioProcessPropertyIsRunningOutput) == 1 && pid(of: id) != ownPID
        })
    }

    private static func uint32(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    private static func pid(of id: AudioObjectID) -> pid_t? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyPID, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: pid_t = 0
        var size = UInt32(MemoryLayout<pid_t>.size)
        return AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr ? value : nil
    }
}
