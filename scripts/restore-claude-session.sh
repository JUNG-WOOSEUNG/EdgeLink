#!/bin/sh
# 저장소의 .claude-session/을 이 PC의 Claude Code 대화 기록 위치로 되돌려 넣는다.
# 저장소를 받은 폴더에서 실행한 뒤 같은 폴더에서 `claude --resume`을 실행해 대화를 고르면 이어진다.
set -e
cd "$(dirname "$0")/.."
ENC=$(pwd | sed 's/[^A-Za-z0-9]/-/g')
DST="$HOME/.claude/projects/$ENC"
mkdir -p "$DST"
for f in .claude-session/*.jsonl.gz; do
  name=$(basename "$f" .gz)
  if [ -f "$DST/$name" ]; then echo "이미 있어서 건너뜀: $name"; continue; fi
  gunzip -c "$f" > "$DST/$name"
  # 원래 PC 경로를 이 PC 경로로 바꿔서 도구가 파일을 찾게 한다
  ORIG=$(sed -n 's/^원래 경로: //p' .claude-session/README.txt)
  if [ -n "$ORIG" ] && [ "$ORIG" != "$(pwd)" ]; then
    python3 - "$DST/$name" "$ORIG" "$(pwd)" <<'PY'
import sys
p, a, b = sys.argv[1:4]
s = open(p, encoding='utf-8').read().replace(a, b)
open(p, 'w', encoding='utf-8').write(s)
PY
  fi
done
[ -f .claude-session/sessions-extra.tar.gz ] && tar -xzf .claude-session/sessions-extra.tar.gz -C "$DST" --keep-old-files 2>/dev/null || true
echo "되돌려 넣었어요: $DST"
echo "이제 이 폴더에서 claude --resume 을 실행하세요."
