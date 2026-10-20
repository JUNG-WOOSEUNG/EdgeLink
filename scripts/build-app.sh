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
swift build -c "$CONFIG" --product edgelink-hid
BINDIR=$(swift build -c "$CONFIG" --show-bin-path)
APP=build/EdgeLink.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINDIR/EdgeLink" "$APP/Contents/MacOS/EdgeLink"
# 블루투스 도우미: 앱이 자식 프로세스로 띄운다 (블루투스 권한은 앱 것을 따른다)
cp "$BINDIR/edgelink-hid" "$APP/Contents/MacOS/edgelink-hid"
cp Sources/EdgeLink/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

ID=${EDGELINK_SIGN_ID:-}
if [ -z "$ID" ] && security find-certificate -c "EdgeLink Dev" >/dev/null 2>&1; then ID="EdgeLink Dev"; fi
# 도우미를 먼저 서명하고 앱을 서명한다 (앱 서명이 도우미 서명을 봉인해서, 업데이트 때 kSecCSCheckNestedCode가 같이 확인함)
HELPER="$APP/Contents/MacOS/edgelink-hid"
if [ -n "$ID" ]; then
  codesign --force --sign "$ID" --options runtime --timestamp=none --identifier com.edgelink.EdgeLink.hid "$HELPER"
  codesign --force --sign "$ID" --options runtime --timestamp=none "$APP"
  echo "서명: $ID"
else
  codesign --force --sign - --identifier com.edgelink.EdgeLink.hid "$HELPER"
  codesign --force --sign - "$APP"
  echo "임시 서명이라 빌드마다 권한이 풀려요. scripts/make-dev-cert.sh로 개발용 인증서를 만들면 유지돼요."
fi
echo "만듦: $APP"
