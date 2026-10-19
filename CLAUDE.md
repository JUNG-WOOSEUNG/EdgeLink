# EdgeLink 작업 규칙

## 언어
- 모든 답변과 설명은 **무조건 한국어**로 한다. 진행 상황 보고, 도구 실행 전후 설명, 요약, 질문 모두 포함.
- 코드 식별자, 명령어, 로그 원문은 그대로 두되 설명은 한국어로 쓴다.

## 기준 문서
- 설계 기준: claude.ai "EdgeLink 설계 문서" (사본: `docs/DESIGN.md`). 수치가 다르면 원본을 따른다.
- 디자인: `EdgeLink-design/design-canvas/*.dc.html`
- 1단계 연결 검증 절차: `docs/STAGE1.md`

## 빌드·테스트
- `swift build`
- `./scripts/test.sh` (Command Line Tools만 있을 때 Swift Testing 경로를 넘겨준다)
