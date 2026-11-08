# Benchmark : whisper.cpp vs WhisperKit (Mac M4, 16 Go, macOS 27)

Audio de test : voix de synthèse française (`say -v Eddy`), 4,1 s et 12,1 s, 16 kHz mono.

## whisper.cpp 1.9.5, large-v3-turbo q5_0, Metal (mesuré)

| Audio | Chargement | Encodeur | Total à chaud (hors chargement) |
|---|---|---|---|
| 4,1 s | ~0,15 s | ~1,26 s | **~1,4 s** |
| 12,1 s | ~0,15 s | ~1,25 s | **~1,5 s** |
| 4,1 s avec `-ac 512` | ~0,15 s | ~0,46 s | **~0,57 s** (dégrade les phrases longues) |

L'encodeur traite toujours une fenêtre de 30 s : le coût est presque constant.

## WhisperKit 1.1.1, large-v3-turbo 626MB, CoreML

**À mesurer** (le téléchargement du modèle a été interrompu pendant la session de
mise en place). Commande prévue : charger une fois le modèle, puis 5 transcriptions
à chaud par fichier.
