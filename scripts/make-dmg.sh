#!/bin/sh
# build/EdgeLink.app을 끌어서 설치하는 DMG로 만든다 → build/EdgeLink.dmg
#   ./scripts/make-dmg.sh            지금 있는 build/EdgeLink.app으로
#   ./scripts/make-dmg.sh --build    릴리스로 앱부터 다시 빌드
# 창 모양(배경·아이콘 위치)은 dmgbuild가 Finder 없이 정한다. 처음 한 번 build/.venv에 설치한다.
set -e
cd "$(dirname "$0")/.."
[ "$1" = "--build" ] && ./scripts/build-app.sh release
APP=build/EdgeLink.app
[ -d "$APP" ] || { echo "$APP이 없어요. ./scripts/build-app.sh release 먼저"; exit 1; }
if [ ! -x build/.venv/bin/dmgbuild ]; then
  python3 -m venv build/.venv
  build/.venv/bin/pip install -q dmgbuild
fi
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
OUT=build/EdgeLink.dmg
rm -f "$OUT"
build/.venv/bin/dmgbuild -s scripts/dmg-settings.py -D app="$APP" "EdgeLink $VERSION" "$OUT" >/dev/null

# 앱과 같은 인증서로 DMG도 서명한다 (없으면 넘어감)
ID=${EDGELINK_SIGN_ID:-}
if [ -z "$ID" ] && security find-certificate -c "EdgeLink Dev" >/dev/null 2>&1; then ID="EdgeLink Dev"; fi
if [ -n "$ID" ]; then codesign --force --sign "$ID" --timestamp=none "$OUT"; echo "DMG 서명: $ID"; fi
echo "만듦: $OUT ($VERSION, $(du -h "$OUT" | cut -f1))"
