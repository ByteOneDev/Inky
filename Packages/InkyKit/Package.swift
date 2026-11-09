// swift-tools-version: 6.0
// ─────────────────────────────────────────────────────────────────────────────
// InkyKit — tout le code « métier » d'Inky, découpé en modules indépendants.
//
// Pourquoi un package séparé de l'app ?
//  • chaque module a des frontières claires (ce qui est `public` est son API) ;
//  • la logique pure se teste avec `swift test`, sans lancer l'app ;
//  • remplacer un moteur = remplacer un module, sans toucher au reste.
// ─────────────────────────────────────────────────────────────────────────────
import PackageDescription

let package = Package(
    name: "InkyKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "InkyCore", targets: ["InkyCore"]),
        .library(name: "InkyAudio", targets: ["InkyAudio"]),
        .library(name: "InkyHotkeys", targets: ["InkyHotkeys"]),
        .library(name: "InkyTranscription", targets: ["InkyTranscription"]),
        .library(name: "InkyInsertion", targets: ["InkyInsertion"]),
        .library(name: "InkyStorage", targets: ["InkyStorage"]),
        .library(name: "InkyUpdates", targets: ["InkyUpdates"]),
    ],
    dependencies: [
        // Transcription Whisper via CoreML (Argmax, licence MIT).
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "1.1.1"),
        // SQLite en Swift (Gwendal Roué, licence MIT).
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.12.0"),
    ],
    targets: [
        // Protocoles et types partagés. Aucune dépendance : c'est le « contrat ».
        .target(name: "InkyCore"),

        // Capture micro (AVAudioEngine) et liste des périphériques (CoreAudio).
        .target(name: "InkyAudio", dependencies: ["InkyCore"]),

        // Raccourcis globaux (CGEventTap) + machine à états pure.
        .target(name: "InkyHotkeys", dependencies: ["InkyCore"]),

        // Moteur WhisperKit + gestionnaire de modèles.
        .target(name: "InkyTranscription", dependencies: [
            "InkyCore",
            .product(name: "WhisperKit", package: "WhisperKit"),
        ]),

        // Insertion du texte dans l'app active (presse-papier + ⌘V).
        .target(name: "InkyInsertion", dependencies: ["InkyCore"]),

        // Historique local (SQLite).
        .target(name: "InkyStorage", dependencies: [
            "InkyCore",
            .product(name: "GRDB", package: "GRDB.swift"),
        ]),

        // Mises à jour automatiques depuis les releases GitHub.
        .target(name: "InkyUpdates"),

        .testTarget(name: "InkyCoreTests", dependencies: ["InkyCore"]),
        .testTarget(name: "InkyHotkeysTests", dependencies: ["InkyHotkeys"]),
        .testTarget(name: "InkyStorageTests", dependencies: ["InkyStorage"]),
        .testTarget(name: "InkyAudioTests", dependencies: ["InkyAudio"]),
        .testTarget(name: "InkyInsertionTests", dependencies: ["InkyInsertion"]),
        .testTarget(name: "InkyUpdatesTests", dependencies: ["InkyUpdates"]),
    ]
)
