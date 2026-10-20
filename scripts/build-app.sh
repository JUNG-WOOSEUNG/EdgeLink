#!/bin/sh
# EdgeLink.app 번들을 만든다. Xcode 없이 Command Line Tools만 있어도 된다.
#   ./scripts/build-app.sh          디버그 빌드 → build/EdgeLink.app
#   ./scripts/build-app.sh release  릴리스 빌드
# 서명: EDGELINK_SIGN_ID가 있으면 그 인증서, 없으면 "EdgeLink Dev" 인증서, 그것도 없으면 임시 서명.
# 임시 서명은 빌드마다 서명이 바뀌어 권한(손쉬운 사용·입력 모니터링)이 풀린다 → scripts/make-dev-cert.sh
set -e
cd "$(dirname "$0")/.."
CONFIG=${1:-debug}
swift build -c "$CONFIG" --product EdgeLink
BIN=$(swift build -c "$CONFIG" --show-bin-path)/EdgeLink
APP=build/EdgeLink.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/EdgeLink"
cp Sources/EdgeLink/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

ID=${EDGELINK_SIGN_ID:-}
if [ -z "$ID" ] && security find-certificate -c "EdgeLink Dev" >/dev/null 2>&1; then ID="EdgeLink Dev"; fi
if [ -n "$ID" ]; then
  codesign --force --sign "$ID" --options runtime --timestamp=none "$APP"
  echo "서명: $ID"
else
  codesign --force --sign - "$APP"
  echo "임시 서명이라 빌드마다 권한이 풀려요. scripts/make-dev-cert.sh로 개발용 인증서를 만들면 유지돼요."
fi
echo "만듦: $APP"
