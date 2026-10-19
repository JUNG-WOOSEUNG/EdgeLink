# 다른 PC에서 이어서 하기

## 1. 저장소 받기

```sh
gh repo clone JUNG-WOOSEUNG/EdgeLink   # 비공개 저장소라 로그인 필요
cd EdgeLink
```

## 2. Claude Code 대화 이어가기

```sh
./scripts/restore-claude-session.sh   # 대화 기록을 이 PC의 ~/.claude/projects/ 아래로 넣음
claude --resume                       # 목록에서 EdgeLink 대화를 골라요
```

- 대화 기록은 `.claude-session/`에 압축돼 있어요. 원래 PC 경로(`~/Workspace/EdgeLink`)는 이 PC 경로로 바꿔서 넣어요.
- 이 PC에서 대화를 더 한 뒤 다시 옮기려면 `./scripts/save-claude-session.sh` 후 커밋·푸시하면 돼요.
- 대화 기록에는 이메일, 기기 이름·블루투스 주소 등이 들어 있어요. **저장소를 공개로 바꾸기 전에는 `.claude-session/`을 지우세요.**

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
