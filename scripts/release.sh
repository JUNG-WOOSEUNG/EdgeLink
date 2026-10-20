#!/bin/sh
# 새 버전을 GitHub 릴리스로 올린다. 앱의 자동 업데이트가 이 릴리스의 EdgeLink.dmg를 받아 간다.
#   ./scripts/release.sh 0.3.0 "고친 것 요약"      (요약 대신 -F 파일도 가능: ./scripts/release.sh 0.3.0 -F notes.md)
# 하는 일: Info.plist 버전 올림 → 릴리스 빌드 → DMG → 커밋·태그 v<버전> → 푸시 → gh release create
# 서명: 앱과 DMG는 "EdgeLink Dev"(또는 EDGELINK_SIGN_ID) 인증서로. 업데이트는 같은 인증서로 서명된 앱만 설치하므로
#       인증서를 바꾸면 기존 사용자는 자동 업데이트를 못 받는다 (손으로 한 번 새 DMG를 설치해야 함).
set -e
cd "$(dirname "$0")/.."
V=${1:?버전을 적어 주세요. 예: ./scripts/release.sh 0.3.0 "고친 것"}
shift
[ -z "$(git status --porcelain)" ] || { echo "커밋하지 않은 변경이 있어요. 먼저 정리해 주세요"; exit 1; }
git rev-parse "v$V" >/dev/null 2>&1 && { echo "v$V 태그가 이미 있어요"; exit 1; }

PLIST=Sources/EdgeLink/Info.plist
BUILD=$(( $(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" $PLIST) + 1 ))
/usr/libexec/PlistBuddy -c "Set CFBundleShortVersionString $V" -c "Set CFBundleVersion $BUILD" $PLIST
./scripts/test.sh
./scripts/make-dmg.sh --build

git add $PLIST
git commit -m "버전 $V"
git tag "v$V"
git push origin HEAD "v$V"
if [ "$1" = "-F" ]; then
  gh release create "v$V" build/EdgeLink.dmg --title "EdgeLink $V" --notes-file "$2"
else
  gh release create "v$V" build/EdgeLink.dmg --title "EdgeLink $V" --notes "${1:-EdgeLink $V}"
fi
echo "릴리스 v$V를 올렸어요"
