#!/bin/sh
# ai-wsjung 저장소의 EdgeLink 대화 백업을 이 PC의 Claude Code 대화 기록 위치로 되돌려 넣는다.
# EdgeLink 저장소를 받은 폴더에서 실행한 뒤 같은 폴더에서 `claude --resume`으로 대화를 고르면 이어진다.
#   EDGELINK_NOTES_DIR  ai-wsjung를 받아 둘 폴더 (기본 ~/Workspace/ai-wsjung, 없으면 받는다)
set -e
cd "$(dirname "$0")/.."
NOTES=${EDGELINK_NOTES_DIR:-$HOME/Workspace/ai-wsjung}
[ -d "$NOTES/.git" ] || git clone -q https://github.com/JUNG-WOOSEUNG/ai-wsjung.git "$NOTES"
git -C "$NOTES" pull -q --rebase || echo "최신 백업을 못 받았어요. 받아 둔 것으로 진행해요"
BK="$NOTES/session-backup/EdgeLink"
[ -d "$BK" ] || { echo "백업이 없어요: $BK"; exit 1; }
ENC=$(pwd | sed 's/[^A-Za-z0-9]/-/g')
DST="$HOME/.claude/projects/$ENC"
mkdir -p "$DST"
ORIG=$(sed -n 's/^원래 경로: //p' "$BK/README.txt")
for f in "$BK"/*.jsonl.gz; do
  name=$(basename "$f" .gz)
  if [ -f "$DST/$name" ]; then echo "이미 있어서 건너뜀: $name"; continue; fi
  gunzip -c "$f" > "$DST/$name"
  # 원래 PC 경로를 이 PC 경로로 바꿔서 도구가 파일을 찾게 한다
  if [ -n "$ORIG" ] && [ "$ORIG" != "$(pwd)" ]; then
    python3 - "$DST/$name" "$ORIG" "$(pwd)" <<'PY'
import sys
p, a, b = sys.argv[1:4]
s = open(p, encoding='utf-8').read().replace(a, b)
open(p, 'w', encoding='utf-8').write(s)
PY
  fi
done
[ -f "$BK/sessions-extra.tar.gz" ] && tar -xzf "$BK/sessions-extra.tar.gz" -C "$DST" --keep-old-files 2>/dev/null || true
# 대화 메모리: 이 PC에 이미 있는 파일은 덮어쓰지 않는다
mkdir -p "$DST/memory"
for m in "$BK"/memory/*.md; do
  [ -f "$m" ] && { [ -f "$DST/memory/$(basename "$m")" ] || cp "$m" "$DST/memory/"; }
done
echo "되돌려 넣었어요: $DST"
echo "이제 이 폴더에서 claude --resume 을 실행하세요."
