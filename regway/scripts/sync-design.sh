#!/usr/bin/env bash
# Копирует нужные для сборки ассеты Дизайнера в branding/design (чтобы CI-репозиторий был самодостаточным).
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"; SRC="${1:-$HERE/../design}"; DST="$HERE/branding/design"
mkdir -p "$DST/icon" "$DST/installer" "$DST/tray"
cp -r "$SRC"/icon/{icon.ico,icon.png,mac-icon.icns,png} "$DST/icon/"
cp "$SRC"/installer/{wix-banner-493x58.bmp,wix-dialog-493x312.bmp,dmg-background.png,dmg-background@2x.png,nsis-welcome-164x314.bmp,nsis-header-150x57.bmp} "$DST/installer/"
cp "$SRC"/tray/{tray-icon.ico,mac-tray-dark-x2.png,mac-tray-light-x2.png} "$DST/tray/"
echo "synced $SRC -> $DST"
