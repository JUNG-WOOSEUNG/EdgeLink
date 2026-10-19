<p align="center">
  <img src="docs/images/icon.png" width="128" alt="EdgeLink 앱 아이콘">
</p>

<h1 align="center">EdgeLink</h1>

<p align="center">
  <b>Mac 키보드 하나로 아이폰까지.</b><br>
  커서를 화면 끝으로 밀면 아이폰으로 넘어가요. 아이폰엔 아무것도 설치하지 않아요.
</p>

<p align="center">
  <a href="https://github.com/JUNG-WOOSEUNG/EdgeLink/releases/latest"><img src="https://img.shields.io/github/v/release/JUNG-WOOSEUNG/EdgeLink?label=다운로드" alt="최신 버전"></a>
  <img src="https://img.shields.io/badge/macOS-13%2B-0077B6" alt="macOS 13 이상">
  <img src="https://img.shields.io/badge/iOS-13%2B-0077B6" alt="iOS 13 이상">
  <img src="https://img.shields.io/badge/상태-개발%20중-FFC107" alt="개발 중">
  <img src="https://img.shields.io/badge/license-MIT-lightgrey" alt="MIT">
</p>

<p align="center">
  <img src="docs/images/demo.gif" width="720" alt="Mac 화면 오른쪽 끝으로 커서를 밀자 아이폰으로 넘어가는 모습">
</p>

---

## 왜 EdgeLink인가요

책상 위 아이폰에 답장 하나 하려고 손을 옮기고, 작은 화면을 두드리고, 다시 Mac으로 돌아오는 일. EdgeLink는 그 왕복을 없애요.

- **밀면 넘어가요.** 아이폰을 놓은 쪽 화면 끝으로 커서를 밀면, 그 순간부터 Mac 키보드와 트랙패드가 아이폰을 조작해요. 반대로 밀면 돌아와요.
- **앱 설치는 Mac에만.** Mac이 아이폰에 블루투스 키보드·마우스로 연결돼요. 아이폰엔 앱도, 프로필도 필요 없어요.
- **책상 그대로.** 모니터가 몇 대든, 아이폰을 위·아래·왼쪽·오른쪽 어디에 두든 실제 위치대로 동작해요.
- **제스처까지.** 세 손가락으로 쓸어 올리면 아이폰 앱 전환기가, 네 손가락을 모으면 홈 화면이 열려요.

## 이런 분께 좋아요

- 메신저·인증번호·업무 앱 때문에 하루에도 수십 번 아이폰을 집는 분
- 아이폰 앱을 테스트하면서 Mac에서 손을 떼고 싶지 않은 개발자·디자이너
- 아이패드를 보조 화면처럼 옆에 두고 쓰는 분

## 작동 방식

```
 Mac 키보드·트랙패드 ──▶ EdgeLink ──블루투스 HID──▶ 아이폰·아이패드
                           │
                 화면 끝을 밀면 전환, 반대로 밀면 복귀
```

1. EdgeLink가 Mac을 블루투스 **키보드 + 마우스** 장치로 보이게 해요.
2. 커서가 아이폰 쪽 화면 끝(파란 구간)을 밀면, 입력을 Mac 대신 아이폰으로 보내요.
3. 아이폰 화면 끝에서 반대로 밀거나 `⌃⌥⌘Space`를 누르면 Mac으로 돌아와요.

## 설치

1. [Releases](https://github.com/JUNG-WOOSEUNG/EdgeLink/releases/latest)에서 `EdgeLink.dmg`를 받아요.
2. EdgeLink를 응용 프로그램 폴더로 옮기고 실행해요.
3. 안내에 따라 약 3분이면 설정이 끝나요.
   - Mac 권한 허용 (블루투스, 손쉬운 사용, 입력 모니터링)
   - 아이폰과 블루투스 페어링
   - 아이폰에서 AssistiveTouch 켜기 (커서 표시용)
   - 아이폰을 놓은 위치 고르기

새 버전은 앱이 알아서 알려줘요.

## 단축키

| 동작 | 단축키 |
| --- | --- |
| Mac ↔ 아이폰 전환 | `⌃⌥⌘Space` |
| 클립보드를 아이폰에 입력 | `⌃⌥⌘V` |
| 모서리 전환 켜기/끄기 | `⌃⌥⌘E` |
| 아이폰 앱 전환기 · 홈 | `⌃⌥⌘↑` · `⌃⌥⌘H` |

모든 단축키는 설정에서 바꿀 수 있어요.

## 요구 사항

| | 지원 |
| --- | --- |
| Mac | macOS 13 Ventura 이상 (Apple 실리콘, Intel) |
| 아이폰 | iOS 13 이상 |
| 아이패드 | iPadOS 13.4 이상 |

## 개인정보와 보안

EdgeLink는 키 입력을 다루는 앱이라, 입력이 허락한 기기에만 가는 것을 가장 먼저 지켜요.

- **입력 내용은 어디에도 남지 않아요.** 키 입력과 클립보드 내용은 로그·설정 어디에도 저장하지 않아요.
- **네트워크는 업데이트 확인에만 써요.** 그 외에는 인터넷에 연결하지 않아요.
- **기본 기기만 연결돼요.** 처음 보는 기기가 연결해 오면 허용할지 먼저 물어봐요.
- **비밀번호 입력 중엔 돌아와요.** Mac에서 비밀번호 칸이 열리면 즉시 Mac 조작으로 돌아와요.
- **업데이트는 서명을 확인해요.** 서명이 맞지 않는 업데이트는 설치하지 않아요.

## 자주 묻는 질문

<details>
<summary>애플 유니버설 컨트롤과 뭐가 다른가요?</summary>

유니버설 컨트롤은 Mac과 아이패드 사이에서만 동작해요. EdgeLink는 **아이폰**도 조작할 수 있어요.
</details>

<details>
<summary>아이폰 화면이 Mac에 보이나요?</summary>

아니요. 화면은 아이폰에서 그대로 보고, 조작만 Mac 키보드와 트랙패드로 해요.
</details>

<details>
<summary>한글 입력이 되나요?</summary>

네. 아이폰 조작 중 Caps Lock으로 한/영을 바꿀 수 있어요. 다만 클립보드 보내기는 글자를 하나씩 타이핑하는 방식이라 영문·숫자·기호만 보낼 수 있어요.
</details>

<details>
<summary>회사 Mac에서도 쓸 수 있나요?</summary>

회사 정책(MDM, 매체 제어)으로 권한이나 블루투스 키보드 장치가 막혀 있으면 쓸 수 없어요. 앱이 이 경우를 알아채면 관리자에게 보낼 안내를 만들어줘요.
</details>

## 개발 현황

EdgeLink는 지금 개발 중이에요. 설계와 디자인을 마쳤고, Mac이 블루투스 키보드·마우스로 아이폰에 붙는 것을 확인했어요. 모서리 전환과 설정 화면까지 구현했고 실기기로 확인하고 있어요.

- [x] 설계 문서 · 디자인
- [x] 블루투스 HID 연결 검증 (아이폰에서 커서·글자 입력 확인)
- [x] 첫 실행 설정과 모서리 전환 (구현 완료, 실기기 확인 중)
- [x] 제스처, 클립보드 보내기 (구현 완료, 실기기 확인 중)
- [ ] 첫 공개 버전

### 직접 빌드하기

Xcode 또는 Command Line Tools(Swift 5.10 이상)가 있으면 돼요.

```sh
swift build                # EdgeLinkCore, bthid
./scripts/test.sh          # 단위 테스트
.build/debug/bthid list    # 페어링한 기기 보기
.build/debug/bthid connect <아이폰 주소>
```

자세한 설계는 [docs/DESIGN.md](docs/DESIGN.md), 1단계 연결 검증 방법은 [docs/STAGE1.md](docs/STAGE1.md), 진행 기록은 [docs/DEVLOG.md](docs/DEVLOG.md), 화면은 [docs/screens](docs/screens/README.md)를 보세요.

진행 상황은 [Issues](https://github.com/JUNG-WOOSEUNG/EdgeLink/issues)에서 볼 수 있어요. 버그 제보와 아이디어는 언제든 환영해요.

## 라이선스

MIT 라이선스 · 자세한 내용은 [LICENSE](LICENSE)를 보세요.

<sub>iPhone, iPad, Mac, macOS, AssistiveTouch는 Apple Inc.의 상표예요. EdgeLink는 Apple과 관련이 없는 독립 프로젝트예요.</sub>
