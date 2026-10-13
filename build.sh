#!/bin/zsh
# TV Kumanda.app paketini oluşturur, imzalar ve /Applications'a kurup başlatır.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

# Desktop (iCloud) klasörü dosyalara Finder öznitelikleri ekleyip imzayı bozabildiği için
# paket geçici bir klasörde hazırlanır ve imzalanır.
STAGE="$(mktemp -d)"
APP="$STAGE/TV Kumanda.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/TVKumanda" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
cp -R Resources/Logos "$APP/Contents/Resources/"
xattr -cr "$APP"

# Sabit bir sertifikayla imzalamak, macOS'un Yerel Ağ iznini her derlemede sıfırlamasını önler.
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk '/Apple Development/ {print $2; exit}')}"
codesign --force --sign "${IDENTITY:--}" "$APP"
codesign --verify --strict "$APP"

pkill -x TVKumanda || true
rm -rf "/Applications/TV Kumanda.app"
ditto "$APP" "/Applications/TV Kumanda.app"
rm -rf "$STAGE"
open "/Applications/TV Kumanda.app"
echo "Kuruldu ve başlatıldı: /Applications/TV Kumanda.app"
