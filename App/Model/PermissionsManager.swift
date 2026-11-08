import AppKit
import AVFoundation
import ApplicationServices
import Observation

/// État des deux autorisations dont Inky a besoin.
///
/// Sur macOS, ces autorisations sont gérées par **TCC** (Transparency, Consent
/// and Control). Points importants :
/// - **Micro** : macOS affiche lui-même la demande, une seule fois. Si
///   l'utilisateur refuse, l'app ne peut plus redemander : il faut aller dans
///   Réglages Système.
/// - **Accessibilité** : aucune boîte de dialogue « Autoriser » ; l'utilisateur
///   doit cocher Inky dans Réglages Système > Confidentialité et sécurité >
///   Accessibilité. macOS ne prévient pas l'app du changement : on vérifie
///   donc régulièrement (« polling ») tant que la fenêtre d'accueil est ouverte.
@MainActor
@Observable
final class PermissionsManager {
    enum MicrophoneStatus {
        case notDetermined, granted, denied
    }

    private(set) var microphone: MicrophoneStatus = .notDetermined
    private(set) var accessibility = false

    var allGranted: Bool { microphone == .granted && accessibility }

    @ObservationIgnored private var pollingTask: Task<Void, Never>?

    init() {
        refresh()
    }

    func refresh() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: microphone = .granted
        case .notDetermined: microphone = .notDetermined
        default: microphone = .denied // .denied ou .restricted (contrôle parental, MDM)
        }
        let trusted = AXIsProcessTrusted()
        if trusted != accessibility { accessibility = trusted }
    }

    /// Affiche la demande système d'accès au micro (seulement la première fois).
    func requestMicrophone() async {
        if microphone == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        } else if microphone == .denied {
            open(.microphone)
        }
        refresh()
    }

    /// Ajoute Inky à la liste Accessibilité (décoché) et ouvre le bon panneau.
    func requestAccessibility() {
        // L'option « prompt » fait apparaître l'alerte système qui propose
        // d'ouvrir les Réglages, et inscrit l'app dans la liste.
        // (Clé écrite en dur : la constante C `kAXTrustedCheckOptionPrompt`
        // n'est pas « concurrency-safe » aux yeux de Swift 6.)
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        open(.accessibility)
    }

    enum Pane { case microphone, accessibility }

    func open(_ pane: Pane) {
        let anchor = pane == .microphone ? "Privacy_Microphone" : "Privacy_Accessibility"
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Vérifie l'état chaque seconde (à activer pendant l'onboarding).
    func startPolling() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }
}
