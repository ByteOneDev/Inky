#!/bin/zsh
# ─────────────────────────────────────────────────────────────────────────────
# Publie une release d'Inky depuis CE Mac (alternative au workflow GitHub
# Actions, par exemple si les runners macOS ne sont pas disponibles).
#
#   scripts/release.sh 0.2.0
#
# Pourquoi compiler en local ? L'app est signée avec le certificat déclaré dans
# Config/Local.xcconfig. Ce certificat ne change jamais d'une version à
# l'autre, donc macOS garde l'autorisation Accessibilité après une mise à jour
# (avec une signature ad hoc, il faudrait la redonner à chaque fois).
#
# Prérequis : xcodegen, gh (connecté), docs/release-notes/vX.Y.Z.md
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

VERSION=${1:?"usage : scripts/release.sh X.Y.Z"}
TAG="v$VERSION"
cd "$(dirname "$0")/.."

[[ -f "docs/release-notes/$TAG.md" ]] || { echo "❌ docs/release-notes/$TAG.md manquant"; exit 1; }
[[ -z "$(git status --porcelain)" ]] || { echo "❌ Des modifications ne sont pas commitées"; exit 1; }

echo "▶︎ Tests unitaires"
(cd Packages/InkyKit && swift test 2>&1 | grep -E "Test run with|✘" )

echo "▶︎ Compilation Release $VERSION"
xcodegen generate --quiet
rm -rf build/release
xcodebuild -quiet \
  -project Inky.xcodeproj -scheme Inky -configuration Release \
  -derivedDataPath build/release \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$(git rev-list --count HEAD)" \
  build

APP=build/release/Build/Products/Release/Inky.app
codesign --verify --deep --strict "$APP"
echo "▶︎ Signature : $(codesign -dv "$APP" 2>&1 | grep -m1 Authority || echo 'ad hoc')"

echo "▶︎ Archive"
mkdir -p dist
ZIP="dist/Inky-$VERSION.zip"
rm -f "$ZIP" "$ZIP.sha256"
# ditto préserve la signature et les attributs (contrairement à zip).
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
(cd dist && shasum -a 256 "Inky-$VERSION.zip" > "Inky-$VERSION.zip.sha256")

echo "▶︎ Tag et publication"
if ! git rev-parse "$TAG" >/dev/null 2>&1; then
  git tag -a "$TAG" -m "Inky $VERSION"
fi
git push origin "$TAG"
gh release create "$TAG" "$ZIP" "$ZIP.sha256" \
  --title "Inky $TAG" \
  --notes-file "docs/release-notes/$TAG.md"
echo "✅ Release $TAG publiée"
