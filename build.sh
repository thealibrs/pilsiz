#!/bin/zsh
# Pilsiz.app paketini oluşturur, imzalar ve /Applications'a kurup başlatır.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

# Desktop (iCloud) klasörü dosyalara Finder öznitelikleri ekleyip imzayı bozabildiği için
# paket geçici bir klasörde hazırlanır ve imzalanır.
STAGE="$(mktemp -d)"
APP="$STAGE/Pilsiz.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/Pilsiz" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
cp -R Resources/Logos "$APP/Contents/Resources/"
cp Resources/tv.png "$APP/Contents/Resources/"
# Uygulama simgesi: macOS 26, asset catalog'dan derlenmemiş simgeleri gri bir çerçeveye koyar.
xcrun actool Resources/Assets.xcassets --compile "$APP/Contents/Resources" --platform macosx \
    --minimum-deployment-target 14.0 --app-icon AppIcon --output-partial-info-plist "$STAGE/icon.plist" >/dev/null
xattr -cr "$APP"

# Sabit bir sertifikayla imzalamak, macOS'un Yerel Ağ iznini her derlemede sıfırlamasını önler.
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk '/Apple Development/ {print $2; exit}')}"
codesign --force --sign "${IDENTITY:--}" "$APP"
codesign --verify --strict "$APP"

# Eski adla ("TV Kumanda") kurulmuş sürüm de kaldırılır.
pkill -x Pilsiz || pkill -x TVKumanda || true
rm -rf "/Applications/Pilsiz.app" "/Applications/TV Kumanda.app"
ditto "$APP" "/Applications/Pilsiz.app"
rm -rf "$STAGE"
open "/Applications/Pilsiz.app"
echo "Kuruldu ve başlatıldı: /Applications/Pilsiz.app"
