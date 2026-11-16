# Benchmark : whisper.cpp vs WhisperKit

Machine : Mac M4 (10 cœurs GPU), 16 Go, macOS 27.2. Mesures du 9 novembre 2026.

Audio de test : voix de synthèse française (`say -v Eddy`), 16 kHz mono :
- **court** (4,1 s) : « Il faut redémarrer le serveur Docker avant la réunion. »
- **long** (12,1 s) : « Bonjour, je teste la dictée vocale sur mon Mac. Il faut redémarrer le
  serveur Docker avant la réunion de demain, puis envoyer le compte rendu à toute l'équipe. »

« À chaud » = modèle déjà chargé en mémoire, comme dans Inky (moyenne des essais 2 à 5).

## Latence

| Moteur | Modèle | Chargement | Court, à chaud | Long, à chaud |
|---|---|---|---|---|
| whisper.cpp 1.9.5 (Metal) | large-v3-turbo q5_0 (574 Mo) | 0,15 s | ~1,40 s | ~1,50 s |
| whisper.cpp, `-ac 512` | idem | 0,15 s | ~0,57 s | non testé (fenêtre trop courte) |
| **WhisperKit 1.1.1 (CoreML)** | large-v3-turbo 626MB | 67 s la 1re fois (compilation ANE), ensuite quelques s | **~0,90 s** | **~1,34 s** |

Les deux moteurs encodent toujours une fenêtre de 30 s : le coût varie peu avec la
durée réelle. `-ac 512` réduit cette fenêtre (environ 10 s), ce qui accélère beaucoup mais
tronque les phrases longues.

## Qualité (sur voix de synthèse)

| | Court | Long |
|---|---|---|
| whisper.cpp | « …serveur d'accord avant la réunion » | Correct, à part « d'accord » et « comprendu » |
| WhisperKit 626MB | « …serveur de caravans la réunion » | **Dégradé** : plusieurs segments inventés |

Aucun des deux ne reconnaît « Docker » sans aide : c'est le rôle du **dictionnaire
personnel** (le mot est donné au modèle comme amorce).

## Conclusion

- **Vitesse** : WhisperKit gagne (sous 1 s pour une phrase courte, l'objectif du projet).
- **Qualité** : la version **compressée** de WhisperKit (626 Mo) semble perdre en
  robustesse sur cette voix artificielle, très peu naturelle. À vérifier sur une vraie voix.
- **Choix maintenu : WhisperKit**, mais à surveiller. Si la qualité déçoit sur ta voix :
  1. essayer le modèle non compressé « Large v3 Turbo » (1,6 Go) dans Réglages › Modèles ;
  2. sinon, ajouter un moteur whisper.cpp derrière le protocole `TranscriptionEngine`
     (prévu par l'architecture).

## Reproduire

```bash
# whisper.cpp
brew install whisper-cpp
whisper-cli -m ggml-large-v3-turbo-q5_0.bin -f court.wav -l fr -nt
# WhisperKit : petit exécutable qui utilise InkyTranscription (load puis 5 × transcribe)
```


## 2026-11-16 — Dictée Apple (SpeechAnalyzer) vs WhisperKit, sur de vraies dictées

Six dictées réelles de l'utilisateur (micro du Mac, français mêlé de mots anglais),
MacBook M4, macOS 27. WhisperKit : temps relevés dans l'historique (modèle 626 Mo).
Apple : `SpeechTranscriber(locale: fr_FR, preset: .transcription)`, fichier entier.

| Audio | WhisperKit 626 Mo | Apple `SpeechTranscriber` | Apple `DictationTranscriber` |
|---|---|---|---|
| 2,8 s | 1,20 s | 0,30 s | 0,24 s |
| 8,9 s | 1,62 s | 0,14 s | 0,39 s |
| 12,7 s | 1,76 s | 0,18 s | 0,54 s |
| 18,1 s | 1,87 s | 0,23 s | 0,37 s |
| 43,6 s | 2,65 s | 0,40 s | 0,87 s |
| 111,6 s | 8,06 s | 1,06 s | 2,56 s |

Qualité : proche. Whisper ponctue mieux les longues phrases et retire les mots
répétés ; Apple garde les bégaiements (« l'ancien l'ancien ») et fait des phrases
plus longues, mais a mieux reconnu certains noms (« minpack.fr »).
`DictationTranscriber` est plus lent et fait plus d'erreurs (« sûr 1000 pack.fr »).

**Décision** : `SpeechTranscriber` par défaut (macOS 26+), complété par la
suppression des mots répétés (`TextCleanup`) et la restructuration par IA, qui
reponctue les longues phrases (~1,5 s, seulement quand c'est utile). Whisper reste
proposé pour la qualité maximale. Parakeet (NVIDIA, via FluidAudio) n'a pas été
retenu : Apple est déjà sous la demi-seconde, sans dépendance ni téléchargement.

### Restructuration par Apple Intelligence (même machine)

| Cas | Plan | Temps |
|---|---|---|
| Phrase courte (< 12 mots, ou ponctuée) | rien | 0 s |
| Longue phrase sans ponctuation (43,6 s d'audio) | IA | 1,4 s |
| Liste de courses avec sous-niveaux | IA | 1,4 s |
| Réunion, trois points | IA | 2,6 s |
| Dictée de 112 s (~300 mots) | paragraphes par règles | < 1 ms (l'IA prenait 9,4 s) |
