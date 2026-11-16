# CLAUDE.md — Inky

Ce fichier documente les **décisions d'architecture** d'Inky et les conventions du
projet. Il sert de mémoire au projet : à relire avant toute modification importante,
à mettre à jour quand une décision change.

## En une phrase

Inky est une app de dictée vocale pour macOS, dans la barre de menus. On maintient un
raccourci, on parle, on relâche : le texte est transcrit **localement** puis collé là
où se trouve le curseur, dans n'importe quelle app.

## Principes non négociables

1. **Local par défaut.** Aucun audio ni texte ne quitte le Mac. Le seul accès réseau
   du MVP est le téléchargement des modèles depuis Hugging Face, à la demande.
2. **Pas de télémétrie.** Pas d'analytics, pas de rapport de plantage envoyé. Les
   logs (`os.Logger`, sous-système `com.byteonedev.inky`) restent sur la machine et
   ne contiennent jamais le texte dicté en clair (`privacy: .private`).
3. **Modulaire.** Le moteur de transcription, le post-traitement du texte et la
   méthode d'insertion sont derrière des protocoles (`InkyCore`).
4. **Lisible.** Le code est commenté pour qu'un étudiant comprenne le *pourquoi*,
   pas seulement le *quoi*. Les commentaires sont en français, les identifiants
   en anglais.

## Décisions tranchées (v0.1)

| Sujet | Décision | Pourquoi |
|---|---|---|
| Base de code | Écrite de zéro, VoiceInk lu comme référence seulement | VoiceInk est GPL-3.0 : un fork imposerait la GPL. Inky est sous **MIT**. Ne jamais copier de code de VoiceInk. |
| Moteur de transcription | **Parakeet TDT 0.6B v3** (NVIDIA, via **FluidAudio**, CoreML) par défaut ; **WhisperKit** en option | Mesuré sur de vraies dictées : 0,05 à 0,4 s pour 3 à 44 s de parole (Whisper : 1,2 à 2,7 s), ponctuation comprise, ~480 Mo. La dictée Apple (`SpeechAnalyzer`) a été essayée en 0.4.0 puis **retirée** en 0.5 : qualité jugée insuffisante par l'utilisateur. Un seul moteur chargé à la fois. Voir `docs/benchmark.md`. |
| Modèle par défaut | `openai_whisper-large-v3-v20240930_626MB` (large-v3-turbo compressé) | Qualité proche de large-v3 en FR/EN, ~626 Mo sur disque. |
| Raccourcis | `CGEventTap` maison (module `InkyHotkeys`) | Les raccourcis par défaut sont des **modificateurs seuls** (⌃⌘, ⌃⌥), que KeyboardShortcuts ne sait pas gérer. Un seul mécanisme pour tout. |
| Stockage | **SQLite via GRDB** pour l'historique, `UserDefaults` pour les réglages | SQL explicite, migrations claires. SwiftData sur macOS 14 est trop jeune. |
| Insertion | Presse-papier + ⌘V simulé, puis restauration | Méthode la plus universelle. Alternative future : `AXUIElement` (kAXSelectedTextAttribute). |
| Projet Xcode | Généré par **XcodeGen** depuis `project.yml` | Le `.xcodeproj` n'est pas versionné (pas de conflits git illisibles). |
| Signature | Ad hoc en CI, certificat auto-signé stable en local | Pas de compte Apple Developer payant → pas de notarisation. Voir « Pièges ». |
| Architecture CPU | arm64 uniquement | Le Neural Engine n'existe que sur Apple Silicon. |
| Langue | Français par défaut, anglais et détection auto en option | L'utilisateur mélange FR/EN ; pas de modèles `.en`. |
| Mises à jour | Module maison `InkyUpdates` (API GitHub Releases), pas Sparkle | Pas d'appcast ni de clé EdDSA à gérer. Vérification : HTTPS + SHA-256 + **même certificat** que l'app installée (si elle n'est pas ad hoc). Désactivable. |
| Releases | `scripts/release.sh X.Y.Z` en local (signature stable) : un **.dmg signé** (installation manuelle) et un .zip + SHA-256 (mises à jour automatiques) ; workflow GitHub Actions en secours | Le compte GitHub ne peut pas lancer de runners macOS (facturation). La signature locale stable évite de perdre l'Accessibilité à chaque mise à jour. |
| Mise en forme | Règles locales, sans IA (`InkyCore/Formatting`) | Hésitations, auto-corrections orales, commandes vocales, listes, dictionnaire, style messagerie. Le LLM (v0.3) viendra en complément. |
| Dictionnaire | Fichier JSON `dictionary.json` | Lisible, facile à sauvegarder et à éditer à la main. |
| IA (LLM) | **Apple Intelligence** (`FoundationModels`, module `InkyLLM`) par défaut, ou un **modèle ouvert local** via **MLX** (package séparé `InkyMLX` : Qwen3, Ministral 3, Llama 3.2, Phi-4 mini, Gemma 3, Mistral 7B, en 4 bits, 1 à 4 Go), tous derrière `LanguageModelProvider` | 100 % local, choix de l'utilisateur (pas de cloud : Claude/GPT exclus). Modèles téléchargés depuis `mlx-community` sur Hugging Face dans notre dossier, chargés au premier usage, libérés après 15 min. MLX exige Xcode (shaders Metal) : d'où le package séparé et `-skipPackagePluginValidation -skipMacroValidation`. |
| Prompts IA | Phrase déclencheuse **au début** de la dictée + consigne écrite à l'avance (`PromptTemplate`, `templates.json`) | Pas de raccourci en plus à retenir. Option « lire le texte déjà écrit » (AX) pour compléter un mail. |
| Pause musique / vidéo | Commande « pause » / « lecture » du système via le framework privé `MediaRemote` (chargé avec `dlopen`), détection par CoreAudio (`kAudioProcessPropertyIsRunningOutput`) | Seul moyen de couvrir Musique, Spotify et les vidéos des navigateurs. On ne relance que si un processus qui jouait s'est arrêté après notre pause. |
| Restructuration | `Restructuring.plan` : rien (phrase courte), IA (liste, longue phrase sans ponctuation, ≤ 160 mots), paragraphes par règles (au-delà) | « IA si utile » : aucune latence ajoutée aux phrases courtes. Consigne avec exemples (few-shot), nettoyage des puces, garde-fou de fidélité (85 % des mots), délai maximal, jamais dans un terminal. |
| Statistiques | Table SQLite `usage` séparée de l'historique, **sans texte** | Doit survivre à la purge de l'historique ; ne garde que mots, durée, app. Calcul pur dans `UsageSummary` (testé). |
| Interface | Fenêtre principale à barre latérale (style Wispr Flow) + pastille au choix : capsule, magnétoscope ou radio (4 finitions), ces deux derniers rangés contre le bord de l'écran | Une seule fenêtre pour accueil/stats, historique, dictionnaire, snippets, prompts IA, style et réglages. Thème dans `App/Design/Theme.swift`. |

## Architecture

```
┌──────────────────────────── App (cible Xcode « Inky ») ─────────────────────────────┐
│  InkyApp (MenuBarExtra)   WindowCoordinator (Réglages, Historique, Bienvenue)       │
│  AppSettings (UserDefaults)   PermissionsManager (micro, Accessibilité)             │
│                                                                                     │
│                  ┌──────────── DictationController ─────────────┐                  │
│                  │  machine à états : idle → recording →        │                  │
│                  │  transcribing → inserting → idle             │                  │
│                  └──────────────────────────────────────────────┘                  │
│        │ actions        │ audio          │ texte         │ texte       │ entrée     │
│        ▼                ▼                ▼               ▼             ▼            │
│  OverlayController   (pastille NSPanel non activante, forme d'onde)                 │
└────────┼────────────────┼────────────────┼───────────────┼─────────────┼────────────┘
         │                │                │               │             │
┌────────┼────────────────┼──── Swift Package local « InkyKit » ─────────┼────────────┐
│  InkyHotkeys       InkyAudio      InkyTranscription   InkyInsertion   InkyStorage   │
│  CGEventTap +      AVAudioEngine  WhisperKitEngine    Pasteboard-     HistoryStore  │
│  HotkeyState-      → 16 kHz mono  ModelManager        Inserter        (GRDB/SQLite) │
│  Machine (pure)    AudioDevices   ModelCatalog        KeyboardLayout  + fichiers    │
│                    AudioFileWriter                                    audio .m4a    │
│                                                                                     │
│  InkyUpdates : SemanticVersion · UpdateClient (GitHub) · UpdateInstaller            │
│  InkyLLM : AppleLanguageModel (FoundationModels, macOS 26+)                         │
│  InkyTranscription : WhisperKitEngine · ParakeetEngine (FluidAudio)                 │
│  Package InkyMLX : LocalLanguageModel (MLX) · LocalModelStore · catalogue           │
│                         InkyCore : protocoles + types partagés                       │
│      TranscriptionEngine · TextInserter · TextProcessor · AudioClip                 │
│      LanguageModelProvider · Templates/ (PromptTemplate, TemplateMatcher)           │
│      Stats/ (UsageSummary, WordCounter)                                             │
│      Formatting/ : TextPipeline = TextCleanup → SelfCorrection → VoiceCommands      │
│                    → ListFormatter → Replacements → style messagerie                │
└─────────────────────────────────────────────────────────────────────────────────────┘
```

### Flux d'une dictée

1. `InkyHotkeys` reçoit les événements clavier globaux via un `CGEventTap`, les passe
   à `HotkeyStateMachine` (logique pure, testée) qui émet `pushToTalkBegan`,
   `pushToTalkEnded`, `handsFreeToggled` ou `cancel`.
2. `DictationController` passe en `preparing` (pastille jaune « Attends… ») et
   démarre `AudioRecorder` : `AVAudioEngine` capture le micro choisi et convertit à la
   volée en **16 kHz mono Float32**. Au **premier tampon reçu** (`onReady`), on passe
   en `recording` (pastille rouge, chronomètre) : c'est le signal pour parler.
3. À l'arrêt, on obtient un `AudioClip`. Trop court (< 0,3 s) ou silencieux → ignoré.
4. `TranscriptionEngine` (WhisperKit, modèle **déjà chargé et préchauffé**) transcrit.
5. `TextPipeline` met en forme selon les réglages et le dictionnaire, en tenant compte
   de l'app cible ; puis l'espacement intelligent lit le caractère avant le curseur (AX).
6. Si la dictée commence par la phrase déclencheuse d'un **prompt IA**
   (`TemplateMatcher`), la consigne + la dictée (+ le texte déjà écrit dans le champ si
   demandé) partent à `LanguageModelProvider` ; la pastille affiche « ✦ nom du modèle ».
   En cas d'échec, on insère la dictée telle quelle (jamais rien perdre).
7. `TextInserter` colle le texte dans l'app active puis restaure le presse-papier.
8. `HistoryStore` enregistre l'entrée (et l'audio si l'option est activée) et, dans la
   même transaction, une ligne de statistiques `usage` (mots de la dictée, pas du texte IA).

### Où ajouter quoi

- **Autre LLM (Ollama / API)** : une nouvelle conformité à `LanguageModelProvider`
  dans `InkyLLM`, choisie dans les réglages.
- **Modes** : un type `DictationMode` (modèle, langue, prompt, règles d'activation)
  résolu par le contrôleur au début de la dictée selon l'app au premier plan.
- **Autre moteur** (whisper.cpp, Parakeet, SpeechAnalyzer) : une nouvelle conformité à
  `TranscriptionEngine`.

## Pièges macOS (à garder en tête)

- **TCC et signature.** Les autorisations (Accessibilité surtout) sont liées à la
  signature du code. Une signature ad hoc change à chaque build → l'entrée dans
  Réglages Système reste cochée mais **ne marche plus**. Solution locale :
  `Config/Local.xcconfig` avec un certificat auto-signé stable. Pour une release ad
  hoc : retirer Inky de la liste Accessibilité (bouton −) puis le rajouter après
  chaque mise à jour.
- **Gatekeeper.** App non notarisée téléchargée → bloquée au premier lancement.
  Réglages Système > Confidentialité et sécurité > « Ouvrir quand même », ou
  `xattr -dr com.apple.quarantine /Applications/Inky.app`.
- **Champs sécurisés.** Quand un champ mot de passe a le focus (ou que Terminal a
  « Entrée clavier sécurisée »), `IsSecureEventInputEnabled()` est vrai : macOS
  bloque les événements clavier synthétiques et ceux vus par l'event tap. Inky laisse
  alors le texte dans le presse-papier et le signale.
- **Apps qui bloquent ou retardent le collage.** Certaines apps (bureaux distants,
  VM, terminaux en mode particulier, apps Electron lentes) lisent le presse-papier
  tard : si on restaure trop tôt, c'est l'ancien contenu qui est collé. Le délai de
  restauration est réglable.
- **Disposition clavier.** ⌘V correspond au *caractère* « v » de la disposition
  active : sur BÉPO ou Dvorak la touche physique diffère. `KeyboardLayout` cherche le
  bon code de touche via `UCKeyTranslate`.
- **Plein écran et Spaces.** La pastille est un `NSPanel` avec
  `.canJoinAllSpaces` + `.fullScreenAuxiliary`, niveau `.statusBar`, non activant
  (elle ne vole **jamais** le focus, sinon ⌘V collerait dans la pastille).
- **Survol de la pastille.** Elle change de taille au survol : les zones de suivi
  d'AppKit envoyaient alors sortie/entrée en boucle (clignotement). On interroge la
  position de la souris 10 fois par seconde, avec une hystérésis (`checkHover`).
- **`EmptyView` ne dessine rien**, même pas le fond qu'on lui applique : utiliser
  `Color.clear` pour un contenu vide qui garde son arrière-plan.
- **Plusieurs écrans.** La pastille s'affiche sur l'écran de la fenêtre active (lue
  via l'API d'Accessibilité), sinon sur l'écran de la souris. Coordonnées AX
  (origine en haut à gauche) ≠ coordonnées Cocoa (origine en bas à gauche).
- **Event tap désactivé.** macOS désactive un event tap trop lent
  (`tapDisabledByTimeout`). Le callback doit rester très rapide ; on le réactive
  automatiquement.
- **Raccourcis modificateurs seuls.** ⌃⌥ est aussi le préfixe VoiceOver ; ⌃⌘ sert à
  ⌃⌘Q (verrouiller), ⌃⌘Espace (émojis)… Si une autre touche est pressée pendant le
  push-to-talk, l'enregistrement est **annulé** et la touche passe normalement.
- **Bluetooth.** Utiliser le micro d'AirPods bascule le casque en profil « appel »
  (son dégradé). Préférer le micro intégré.
- **Démarrage du micro.** `AVAudioEngine` met ~50 à 200 ms à démarrer (bien plus en
  Bluetooth). D'où l'état « Attends… » de la pastille et la mesure affichée dans
  Réglages › Audio › Diagnostic.
- **Fenêtres créées trop tôt.** `AppModel.init` s'exécute pendant que SwiftUI construit
  la scène : y créer une fenêtre (la pastille) fait planter SwiftUI (réentrance).
  Tout ce qui touche à l'AppKit démarre dans une `Task` au tour suivant.
- **Deux instances.** Deux Inky en même temps colleraient le texte deux fois : au
  lancement, Inky ferme les autres instances.
- **Parakeet.** Garde des « euh » et des mots bégayés (« tu tu ») : `TextCleanup` les
  retire (sauf « nous nous », « vous vous », « très très »…). Indice de langue
  (`Language.french`) pour écarter les jetons d'autres alphabets.
- **MLX et Metal.** Compiler MLX demande le composant « Metal Toolchain » d'Xcode
  (`xcodebuild -downloadComponent MetalToolchain`). `swift build`/`swift test` ne
  suffisent pas pour `InkyMLX` : c'est pour ça qu'il n'est pas dans InkyKit.
- **Apple Intelligence.** `SystemLanguageModel.default.availability` peut valoir
  `modelNotReady` longtemps après l'activation (téléchargement du modèle par macOS).
  Contexte limité (~4 000 tokens) : on coupe le texte du champ à 6 000 caractères.
- **MediaRemote.** Depuis macOS 15.4, une app tierce ne peut plus demander « quelque
  chose joue-t-il ? » (réponse toujours fausse) ; envoyer des commandes marche encore.
  Un navigateur met ~8 s à libérer sa sortie audio après une pause : d'où la
  surveillance de 12 s dans `MediaPlayback`. Des apps gardent une sortie ouverte en
  permanence (égaliseurs, jeux) : elles ne déclenchent jamais de reprise.
- **Locale.** L'app n'a pas de `.lproj` : `CFBundleDevelopmentRegion = fr` (project.yml)
  pour que dates et jours soient en français.
- **Mise à jour et TCC.** L'autorisation Accessibilité survit à une mise à jour
  seulement si la nouvelle version est signée par le même certificat.

## Conventions

- Swift 6 (concurrence stricte). L'UI et l'orchestration sont `@MainActor` ; les
  moteurs sont des `actor`.
- Pas de dépendance tierce sans l'inscrire dans le tableau ci-dessus.
  Actuelles : WhisperKit (MIT), GRDB (MIT), FluidAudio (Apache 2.0), mlx-swift-lm
  (MIT), swift-transformers (Apache 2.0). Frameworks Apple : FoundationModels, Charts. Pas de Sparkle (voir Mises à jour).
- Les tests de logique pure vivent dans `Packages/InkyKit/Tests` : `swift test`.
- Un commit par jalon minimum, messages en français.

## Commandes utiles

```bash
xcodegen generate                                   # régénère Inky.xcodeproj
xcodebuild -scheme Inky -configuration Debug -skipPackagePluginValidation -skipMacroValidation build  # compile
cd Packages/InkyKit && swift test                   # tests unitaires
scripts/release.sh 0.5.0                            # compile, signe, publie la release
```

## Emplacements des données

- Réglages : `UserDefaults` (domaine `com.byteonedev.inky`)
- Modèles : `~/Library/Application Support/Inky/Models/` (Whisper sous `models/`,
  Parakeet sous `parakeet/`, modèles de langage sous `llm/`)
- Historique : `~/Library/Application Support/Inky/history.sqlite`
- Dictionnaire : `~/Library/Application Support/Inky/dictionary.json`
- Prompts IA : `~/Library/Application Support/Inky/templates.json`
- Statistiques : table `usage` de `history.sqlite`
- Audio de l'historique : `~/Library/Application Support/Inky/Audio/`
