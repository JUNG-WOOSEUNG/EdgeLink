#!/bin/sh
# 이 프로젝트의 Claude Code 대화 기록과 메모리를 비공개 저장소 ai-wsjung(Claude 설정 백업)에 올린다.
# 다른 PC에서는 scripts/restore-claude-session.sh로 되돌려 넣고 `claude --resume`으로 이어간다.
# 대화 기록에는 이메일, 기기 정보 등이 들어 있어서 EdgeLink 저장소(공개)에는 넣지 않는다.
#   EDGELINK_NOTES_DIR  ai-wsjung를 받아 둘 폴더 (기본 ~/Workspace/ai-wsjung, 없으면 받는다)
set -e
cd "$(dirname "$0")/.."
NOTES=${EDGELINK_NOTES_DIR:-$HOME/Workspace/ai-wsjung}
REPO=https://github.com/JUNG-WOOSEUNG/ai-wsjung.git
ENC=$(pwd | sed 's/[^A-Za-z0-9]/-/g')
SRC="$HOME/.claude/projects/$ENC"
[ -d "$SRC" ] || { echo "대화 기록이 없어요: $SRC"; exit 1; }
[ -d "$NOTES/.git" ] || git clone -q "$REPO" "$NOTES"
git -C "$NOTES" pull -q --rebase

OUT="$NOTES/session-backup/EdgeLink"
rm -rf "$OUT"; mkdir -p "$OUT/memory"
# 대화 본문(세션마다 .jsonl 하나)
for f in "$SRC"/*.jsonl; do gzip -9 -c "$f" > "$OUT/$(basename "$f").gz"; done
# 하위 에이전트 기록, 큰 도구 결과 (메모리는 아래에서 따로)
EXTRA=$(cd "$SRC" && ls -d */ 2>/dev/null | sed 's#/$##' | grep -v '^memory$' || true)
[ -n "$EXTRA" ] && tar -czf "$OUT/sessions-extra.tar.gz" -C "$SRC" $EXTRA
# 대화 메모리는 읽을 수 있게 그대로
cp "$SRC"/memory/*.md "$OUT/memory/" 2>/dev/null || true
echo "원래 경로: $(pwd)" > "$OUT/README.txt"
echo "저장 시각: $(date '+%Y-%m-%d %H:%M')" >> "$OUT/README.txt"
du -sh "$OUT"/* | sed "s#$OUT/##"

git -C "$NOTES" add session-backup/EdgeLink
if git -C "$NOTES" diff --cached --quiet; then echo "바뀐 게 없어요"; exit 0; fi
git -C "$NOTES" commit -q -m "EdgeLink 대화 백업 $(date '+%Y-%m-%d %H:%M')"
git -C "$NOTES" push -q
echo "올렸어요: $REPO (session-backup/EdgeLink)"
