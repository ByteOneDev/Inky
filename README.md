# Inky

Dictée vocale **100 % locale** pour macOS. Tu maintiens un raccourci, tu parles, tu
relâches : le texte apparaît là où se trouve ton curseur, dans n'importe quelle app.

- 🔒 **Privé** : la transcription tourne sur ton Mac (Whisper via CoreML / Neural Engine).
  Aucun audio, aucun texte, aucune statistique n'est envoyé sur Internet.
- ⚡ **Rapide** : le modèle reste chargé en mémoire ; une phrase courte est insérée en
  moins d'une seconde sur Apple Silicon.
- 🇫🇷🇬🇧 **Français par défaut**, anglais ou détection automatique en option. Les mots
  anglais glissés dans une phrase française sont bien transcrits.
- 🧹 **Mise en forme automatique** : hésitations retirées, auto-corrections orales
  (« 14 h, non plutôt 15 h » → « 15 h »), commandes vocales (« à la ligne »,
  « point d'interrogation »), listes numérotées, pas de point final dans les messageries.
- 📖 **Dictionnaire personnel** : mots à reconnaître, corrections automatiques et
  **snippets** (« mon adresse mail » → ton adresse complète).
- 🗂 **Historique local** consultable, avec réécoute et suppression automatique réglable.
- 🔄 **Mises à jour automatiques** depuis les releases GitHub, vérifiées (SHA-256 et
  signature). Désactivables.
- 🎓 **Tutoriel** interactif avec zone d'entraînement.

> Projet personnel, gratuit, sous licence MIT. Inspiré par Wispr Flow, Superwhisper et
> VoiceInk (aucun code n'en est repris).

## Utilisation

| Raccourci (par défaut) | Effet |
|---|---|
| **Maintenir ⌃⌘** (Contrôle + Commande) | Push-to-talk : dicte tant que c'est enfoncé, insère au relâchement |
| **Appuyer sur ⌃⌥** (Contrôle + Option) | Mains libres : un appui démarre, un autre arrête et insère |
| **⎋** pendant un enregistrement | Annule |

Les deux raccourcis se changent dans **Réglages › Général** (modificateurs seuls ou
combinaison avec une touche, par ex. ⌥Espace).

Une petite pastille reste visible en bas de l'écran, même au-dessus des apps en plein
écran (clic = dictée mains libres). Pendant une dictée, elle affiche **« Attends… »**
(jaune) le temps que le micro démarre, puis la forme d'onde et la durée (rouge) :
parle quand elle est rouge. Tout se désactive dans les réglages, et le menu permet de
mettre Inky en pause.

## Installation (release)

1. Télécharge `Inky-x.y.z.zip` depuis la page
   [Releases](https://github.com/ByteOneDev/Inky/releases) et place `Inky.app` dans
   `/Applications`.
2. **L'app n'est pas notarisée par Apple** (pas de compte développeur payant) : au
   premier lancement, macOS la bloque. Va dans *Réglages Système › Confidentialité et
   sécurité*, puis clique sur **« Ouvrir quand même »**. Ou en Terminal :
   ```bash
   xattr -dr com.apple.quarantine /Applications/Inky.app
   ```
3. Suis l'écran d'accueil : autorise le **micro**, puis l'**Accessibilité**, puis
   télécharge le modèle recommandé (626 Mo).

> ⚠️ **Après chaque mise à jour**, macOS peut considérer Inky comme une nouvelle app
> (signature ad hoc) : si les raccourcis ne marchent plus, retire Inky de la liste
> *Accessibilité* avec « − » puis ajoute-le de nouveau.

## Espace disque et mémoire

| Élément | Disque | RAM pendant l'utilisation |
|---|---|---|
| Application | ~15 Mo | ~60 Mo |
| Modèle recommandé (Large v3 Turbo compressé) | 626 Mo | ~0,8 à 1,2 Go |
| Cache CoreML (optimisation pour ta puce, créé au 1er chargement) | ~0,3 à 0,6 Go | — |
| Historique (texte + audio AAC ~4 Ko/s) | quelques Mo par mois | — |
| **Total** | **≈ 1 à 1,3 Go** | **≈ 1 Go** |

Modèles plus légers disponibles : *Small compressé* (217 Mo), *Base* (146 Mo), *Tiny*
(76 Mo). La v0.2 (reformulation par LLM local via Ollama) ajoutera un modèle de 2 à
3 Go, optionnel.

Pour tout supprimer : quitter Inky, supprimer l'app et le dossier
`~/Library/Application Support/Inky/`.

## Compiler depuis les sources

Publier une release depuis ton Mac : `scripts/release.sh 0.2.0` (tests, compilation,
signature avec le certificat de `Local.xcconfig`, archive + SHA-256, release GitHub).

Prérequis : macOS 14+, Apple Silicon, Xcode 16+ et [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
git clone https://github.com/ByteOneDev/Inky.git && cd Inky
cp Config/Local.xcconfig.example Config/Local.xcconfig   # puis indique ton certificat
xcodegen generate
open Inky.xcodeproj
```

**Pourquoi `Local.xcconfig` ?** macOS lie l'autorisation Accessibilité à la signature
de l'app. Avec la signature ad hoc par défaut, elle change à chaque compilation et il
faut réautoriser l'app à chaque fois. Un certificat auto-signé (Trousseau d'accès ›
Assistant de certification › Créer un certificat, type « Signature de code ») règle le
problème une fois pour toutes.

Tests unitaires :

```bash
cd Packages/InkyKit && swift test
```

## Architecture

Le code est découpé en modules (`Packages/InkyKit`) derrière des protocoles :
raccourcis, audio, transcription, insertion, stockage. Les décisions d'architecture et
les pièges macOS connus sont documentés dans [CLAUDE.md](CLAUDE.md), et la comparaison
whisper.cpp / WhisperKit dans [docs/benchmark.md](docs/benchmark.md).

## Feuille de route

- **v0.1** : dictée locale, raccourcis, pastille, gestionnaire de modèles, historique.
- **v0.2** : mise en forme (auto-corrections, commandes vocales, listes), dictionnaire et
  snippets, pastille permanente, tutoriel, mises à jour automatiques.
- **v0.3** : reformulation par LLM (Ollama en local, API en option), modes par app/URL.
- **Plus tard** : transcription de fichiers, mode commande, autres moteurs (whisper.cpp,
  Parakeet, SpeechAnalyzer d'Apple).

## Licence

[MIT](LICENSE) © 2026 ByteOneDev
