#!/bin/sh
# 이 프로젝트의 Claude Code 대화 기록을 저장소(.claude-session/)에 압축해서 넣는다.
# 다른 PC에서는 scripts/restore-claude-session.sh로 되돌려 넣고 `claude --resume`으로 이어간다.
# 대화 기록에는 이메일, 기기 정보 등이 들어 있으니 비공개 저장소에서만 쓴다.
set -e
cd "$(dirname "$0")/.."
ENC=$(pwd | sed 's/[^A-Za-z0-9]/-/g')
SRC="$HOME/.claude/projects/$ENC"
[ -d "$SRC" ] || { echo "대화 기록이 없어요: $SRC"; exit 1; }
OUT=.claude-session
rm -rf "$OUT"; mkdir -p "$OUT"
# 대화 본문(세션마다 .jsonl 하나)
for f in "$SRC"/*.jsonl; do gzip -9 -c "$f" > "$OUT/$(basename "$f").gz"; done
# 하위 에이전트 기록, 큰 도구 결과 (메모리는 아래에서 따로)
tar -czf "$OUT/sessions-extra.tar.gz" -C "$SRC" $(cd "$SRC" && ls -d */ 2>/dev/null | sed 's#/$##' | grep -v '^memory$')
# 이 프로젝트의 대화 메모리: 읽을 수 있는 파일 그대로 .claude-memory/에
if [ -d "$SRC/memory" ]; then
  rm -rf .claude-memory; mkdir -p .claude-memory
  cp "$SRC"/memory/*.md .claude-memory/ 2>/dev/null || true
  echo "메모리: $(ls .claude-memory | wc -l | tr -d ' ')개 파일 → .claude-memory/"
fi
echo "원래 경로: $(pwd)" > "$OUT/README.txt"
echo "저장 시각: $(date '+%Y-%m-%d %H:%M')" >> "$OUT/README.txt"
du -sh "$OUT"/*
