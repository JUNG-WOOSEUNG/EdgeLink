#!/bin/sh
# docs/diagrams/*.mmd(Mermaid 원본)를 README용 이미지 docs/images/diagram-*.png로 그린다.
# GitHub 모바일 앱은 Mermaid를 그리지 않아서 README에는 이미지를 넣는다.
# mermaid-cli를 build/mmdc에 설치하고(처음 한 번), 이 Mac의 Chrome으로 2배 해상도로 그린다.
# 테마: docs/diagrams/theme.json, 글꼴: docs/diagrams/style.css
set -e
cd "$(dirname "$0")/.."
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
[ -x "$CHROME" ] || { echo "Google Chrome이 필요해요"; exit 1; }
MMDC=build/mmdc/node_modules/.bin/mmdc
if [ ! -x "$MMDC" ]; then
  mkdir -p build/mmdc
  PUPPETEER_SKIP_DOWNLOAD=1 npm install --prefix build/mmdc --no-audit --no-fund --silent @mermaid-js/mermaid-cli@11.4.2
fi
PP=$(mktemp)
trap 'rm -f "$PP"' EXIT
printf '{"executablePath":"%s","args":["--no-sandbox","--headless=new"]}' "$CHROME" > "$PP"
for f in docs/diagrams/*.mmd; do
  name=$(basename "$f" .mmd)
  "$MMDC" -q -i "$f" -o "docs/images/diagram-$name.png" -c docs/diagrams/theme.json -C docs/diagrams/style.css -p "$PP" -s 2 -b white
  echo "docs/images/diagram-$name.png"
done
