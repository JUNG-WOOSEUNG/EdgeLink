# 다른 PC에서 이어서 하기

## 1. 저장소 받기

```sh
gh repo clone JUNG-WOOSEUNG/EdgeLink
cd EdgeLink
```

## 2. Claude Code 대화 이어가기

대화 기록과 대화 메모리는 이 저장소가 아니라 **비공개 저장소 `JUNG-WOOSEUNG/ai-wsjung`**(Claude 설정 백업)의 `session-backup/EdgeLink/`에 있어요. 대화에는 이메일, 기기 이름 같은 개인정보가 들어 있어서 공개 저장소에는 넣지 않아요.

```sh
./scripts/restore-claude-session.sh   # ai-wsjung를 ~/Workspace/ai-wsjung에 받고, 대화를 이 PC의 ~/.claude/projects/ 아래로 넣음
claude --resume                       # 목록에서 EdgeLink 대화를 골라요
```

- 원래 PC 경로는 이 PC 경로로 바꿔서 넣어요. 이미 있는 메모리 파일은 덮어쓰지 않아요.
- 이 PC에서 대화를 더 한 뒤 다시 옮기려면 `./scripts/save-claude-session.sh` — 압축해서 ai-wsjung에 커밋·푸시까지 해요.
- ai-wsjung를 다른 곳에 받아 두었다면 `EDGELINK_NOTES_DIR=<폴더>`를 붙여 실행하세요.

## 3. 빌드 환경

- Xcode 또는 Command Line Tools (Swift 5.10 이상)
- 개발용 서명 인증서: `./scripts/make-dev-cert.sh` (PC마다 따로 만들어요. 서명이 바뀌므로 이 PC에서 손쉬운 사용·입력 모니터링을 다시 허용해야 해요)
- 빌드·테스트·실행

```sh
swift build
./scripts/test.sh
./scripts/build-app.sh && open build/EdgeLink.app
```

## 4. 이어서 할 일

`docs/DEVLOG.md` 맨 위 "아침에 먼저 보실 것", "정해주실 것"과 `docs/DEVICE-CHECK.md`부터 보면 돼요.
