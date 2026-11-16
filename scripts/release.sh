#!/bin/zsh
# ─────────────────────────────────────────────────────────────────────────────
# Publie une release d'Inky depuis CE Mac (alternative au workflow GitHub
# Actions, par exemple si les runners macOS ne sont pas disponibles).
#
#   scripts/release.sh 0.5.0              compile, signe, publie
#   scripts/release.sh 0.5.0 --no-publish compile et prépare dist/ sans publier
#
# Pourquoi compiler en local ? L'app est signée avec le certificat déclaré dans
# Config/Local.xcconfig. Ce certificat ne change jamais d'une version à
# l'autre, donc macOS garde l'autorisation Accessibilité après une mise à jour
# (avec une signature ad hoc, il faudrait la redonner à chaque fois).
#
# Produit deux fichiers :
#  - Inky-X.Y.Z.dmg : image disque signée, pour installer à la main (glisser
#    Inky dans Applications) ;
#  - Inky-X.Y.Z.zip (+ .sha256) : utilisé par les mises à jour automatiques.
#
# Prérequis : xcodegen, gh (connecté), docs/release-notes/vX.Y.Z.md
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

VERSION=${1:?"usage : scripts/release.sh X.Y.Z [--no-publish]"}
PUBLISH=1
[[ "${2:-}" == "--no-publish" ]] && PUBLISH=0
TAG="v$VERSION"
cd "$(dirname "$0")/.."

[[ -f "docs/release-notes/$TAG.md" ]] || { echo "❌ docs/release-notes/$TAG.md manquant"; exit 1; }
if (( PUBLISH )); then
  [[ -z "$(git status --porcelain)" ]] || { echo "❌ Des modifications ne sont pas commitées"; exit 1; }
fi

echo "▶︎ Tests unitaires"
(cd Packages/InkyKit && swift test 2>&1 | grep -E "Test run with|✘" )

echo "▶︎ Compilation Release $VERSION"
xcodegen generate --quiet
rm -rf build/release
xcodebuild -quiet \
  -project Inky.xcodeproj -scheme Inky -configuration Release \
  -derivedDataPath build/release \
  -skipPackagePluginValidation -skipMacroValidation \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$(git rev-list --count HEAD)" \
  build

APP=build/release/Build/Products/Release/Inky.app
codesign --verify --deep --strict "$APP"
SIGNATURE_INFO="$(codesign -dvv "$APP" 2>&1)"
if [[ "$SIGNATURE_INFO" == *"Authority="* ]]; then
  echo "▶︎ Signature : ${${SIGNATURE_INFO#*Authority=}%%$'\n'*}"
else
  echo "▶︎ Signature : ad hoc (pas de certificat dans Config/Local.xcconfig)"
fi

echo "▶︎ Archive"
mkdir -p dist
ZIP="dist/Inky-$VERSION.zip"
rm -f "$ZIP" "$ZIP.sha256"
# ditto préserve la signature et les attributs (contrairement à zip).
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
(cd dist && shasum -a 256 "Inky-$VERSION.zip" > "Inky-$VERSION.zip.sha256")

echo "▶︎ Image disque (.dmg)"
# Le même certificat que l'app (Config/Local.xcconfig) signe l'image disque.
IDENTITY="$(sed -n 's/^CODE_SIGN_IDENTITY *= *//p' Config/Local.xcconfig 2>/dev/null | tail -1)"
DMG="dist/Inky-$VERSION.dmg"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
ditto "$APP" "$STAGING/Inky.app"
# Raccourci vers /Applications : on glisse Inky dessus pour l'installer.
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"
hdiutil create -quiet -volname "Inky $VERSION" -srcfolder "$STAGING" -fs HFS+ -format UDZO -ov "$DMG"
if [[ -n "$IDENTITY" && "$IDENTITY" != "-" ]]; then
  codesign --sign "$IDENTITY" --identifier com.byteonedev.inky.dmg --timestamp=none "$DMG"
  codesign --verify "$DMG"
  echo "▶︎ Image disque signée : $IDENTITY"
else
  echo "▶︎ Image disque non signée (pas de certificat dans Config/Local.xcconfig)"
fi
(cd dist && shasum -a 256 "Inky-$VERSION.dmg" > "Inky-$VERSION.dmg.sha256")

if (( ! PUBLISH )); then
  echo "✅ Fichiers prêts dans dist/ (non publiés)"
  exit 0
fi

echo "▶︎ Tag et publication"
if ! git rev-parse "$TAG" >/dev/null 2>&1; then
  git tag -a "$TAG" -m "Inky $VERSION"
fi
git push origin "$TAG"
gh release create "$TAG" "$DMG" "$DMG.sha256" "$ZIP" "$ZIP.sha256" \
  --title "Inky $TAG" \
  --notes-file "docs/release-notes/$TAG.md"
echo "✅ Release $TAG publiée"
