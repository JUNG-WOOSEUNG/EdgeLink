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
# dmgbuild 1.6.7 이상이어야 한다. 1.6.5 이하는 .DS_Store에 배경 북마크(pBBk)를 넣는데,
# macOS 26 Finder는 그게 있으면 배경을 안 그리고 창을 비워 둔다 (dmgbuild #273).
# 1.6.7은 Python 3.10 이상이라고 적혀 있지만 Command Line Tools의 3.9에서도 잘 돈다.
DMGBUILD_VERSION=1.6.7
[ -x build/.venv/bin/python3 ] || python3 -m venv build/.venv
if [ "$(build/.venv/bin/python3 -c 'import importlib.metadata as m; print(m.version("dmgbuild"))' 2>/dev/null)" != "$DMGBUILD_VERSION" ]; then
  build/.venv/bin/pip install -q --disable-pip-version-check --ignore-requires-python "dmgbuild==$DMGBUILD_VERSION"
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
