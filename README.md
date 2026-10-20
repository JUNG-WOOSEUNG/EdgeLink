<p align="center">
  <img src="docs/images/icon.png" width="128" alt="EdgeLink 앱 아이콘">
</p>

<h1 align="center">EdgeLink</h1>

<p align="center">
  <b>Mac 키보드·트랙패드로 아이폰까지.</b><br>
  커서를 화면 끝으로 밀면 아이폰으로 넘어가요. 아이폰엔 아무것도 설치하지 않아요.
</p>

<p align="center">
  <a href="https://github.com/JUNG-WOOSEUNG/EdgeLink/releases/latest"><img src="https://img.shields.io/github/v/release/JUNG-WOOSEUNG/EdgeLink?label=%EB%8B%A4%EC%9A%B4%EB%A1%9C%EB%93%9C&color=0077B6" alt="최신 릴리스"></a>
  <img src="https://img.shields.io/badge/macOS-13%2B-0077B6" alt="macOS 13 이상">
  <img src="https://img.shields.io/badge/iOS-13%2B-0077B6" alt="iOS 13 이상">
  <img src="https://img.shields.io/badge/Swift-6-F05138" alt="Swift 6">
  <img src="https://img.shields.io/badge/%EC%83%81%ED%83%9C-%EB%B2%A0%ED%83%80-FFC107" alt="베타">
  <img src="https://img.shields.io/badge/license-MIT-lightgrey" alt="MIT">
</p>

<p align="center">
  <img src="docs/images/hero.png" width="820" alt="EdgeLink 설정 창의 배치 화면과 메뉴 막대 팝오버">
</p>

---

## 개요

EdgeLink는 Mac을 아이폰의 **블루투스 HID 키보드 + 마우스**로 만들어 주는 macOS 메뉴 막대 앱이에요. 아이폰을 둔 쪽 화면 가장자리로 커서를 밀면 그때부터 Mac의 키보드·트랙패드 입력이 아이폰으로 가고, 반대로 밀면 Mac으로 돌아와요.

- **아이폰엔 설치할 게 없어요.** 아이폰 입장에선 평범한 블루투스 키보드·마우스라서 앱·프로필·탈옥이 필요 없어요.
- **화면은 아이폰에서 봐요.** 화면을 Mac으로 가져오는 미러링이 아니라, 조작만 Mac에서 해요.
- **입력은 밖으로 나가지 않아요.** 키 입력은 블루투스로 아이폰에만 가고, 어디에도 저장하지 않아요.

## 동작 구조

<p align="center">
  <img src="docs/images/diagram-architecture.png" width="520" alt="동작 구조: 키보드·트랙패드 입력이 이벤트 탭과 InputRouter를 거쳐 HID 리포트로 바뀌고, 블루투스 도우미 프로세스와 IOBluetooth를 지나 아이폰으로 가는 흐름">
</p>

| 구성 요소 | 역할 |
| --- | --- |
| **이벤트 탭** | 세션 이벤트 탭으로 키·마우스·스크롤을 받아요. 아이폰 조작 중엔 Mac에 가지 않도록 이벤트를 삼켜요. |
| **InputRouter · SwitchEngine** | 커서가 아이폰 쪽 가장자리를 충분히 밀었는지, 돌아올 때 Mac 커서를 어느 높이에 둘지 계산해요. 핫 코너와 겹치지 않게 구석은 비워 둬요. |
| **HID 리포트 변환** | Mac 키 코드를 USB HID 사용 코드로, 트랙패드 이동·스크롤을 마우스 리포트로 바꿔요. |
| **edgelink-hid 도우미** | 블루투스 SDP 등록, L2CAP 채널, 리포트 쓰기를 따로 떨어진 프로세스에서 해요. IOBluetooth가 몇 초씩 멈춰도 메뉴 막대·설정·Mac 복귀는 멈추지 않아요. |

## 입력이 아이폰까지 가는 길

<p align="center">
  <img src="docs/images/diagram-input-path.png" width="780" alt="입력 경로: EdgeLink.app이 이벤트를 HID 리포트로 바꿔 edgelink-hid에 넘기고, 도우미가 L2CAP 인터럽트 채널로 아이폰에 쓰는 순서">
</p>

- 리포트는 모아 보내지 않고 바로 써요. 실기기 측정에서 Mac 쪽 쓰기 시간은 평균 0.03ms, 최대 0.09ms였어요.
- 앱은 도우미를 1초 하트비트로 지켜봐요. 응답이 끊기면 먼저 Mac 조작으로 돌아온 뒤 도우미만 다시 띄우고 다시 연결해요.

## 전환과 안전장치

<p align="center">
  <img src="docs/images/diagram-switching.png" width="660" alt="전환: 가장자리 밀기나 단축키로 Mac과 아이폰 조작을 오가고, 비밀번호 칸·화면 잠금·블루투스 끊김 같은 안전장치에서는 자동으로 Mac에 돌아옴">
</p>

## 블루투스 연결 순서

<p align="center">
  <img src="docs/images/diagram-bluetooth.png" width="640" alt="블루투스 연결 순서: SDP 등록, 기본 연결, 제어 채널 0x11, 인터럽트 채널 0x13">
</p>

연결이 끊기면 15·15·30·60·300초 간격으로 다시 시도하고, Mac이 잠에서 깨면 바로 다시 연결해요.

## 기능

### 넘어가기와 돌아오기

- 아이폰을 실제로 둔 쪽을 골라요. 모니터마다 다른 모니터와 맞닿지 않은 가장자리(왼쪽·오른쪽·위·아래)를 쓸 수 있어요.
- 가장자리를 밀기 시작하면 파란 유리 알약이 튀어나와 넘어갈 곳을 보여 줘요. 밀어야 하는 정도는 설정에서 조절해요.
- 파일이나 창을 끄는 중에는 넘어가지 않아요.
- 돌아올 때 Mac 커서는 아이폰 커서가 있던 높이에 나타나요. 어긋나면 "돌아오는 위치 맞추기"로 한 번 맞추면 돼요.

### 입력

| 입력 | 아이폰에서 |
| --- | --- |
| 키보드 | 그대로 입력. 한/영은 Caps Lock |
| 클릭 · 드래그 · 오른쪽 클릭 | 마우스 버튼 1~3 |
| 두 손가락 스크롤 | 세로 휠 + 가로 스크롤. 가로는 관성을 빼서 홈 화면이 한 장씩 넘어가요 |
| 트랙패드 제스처 | 마우스 버튼 4~8 → AssistiveTouch에 등록한 동작 (아래 표) |
| 미디어 키 (선택) | 볼륨 · 재생 |
| 클립보드 보내기 `⌃⌥⌘V` | 복사한 글을 한 글자씩 타이핑 (영문·숫자·기호) |

### 트랙패드 제스처

아이폰 AssistiveTouch의 "추가 버튼 사용자화"에 버튼을 한 번 등록하면 써요. 앱이 단계별로 안내해요(1~2분).

| 제스처 | 보내는 버튼 | 아이폰 동작 | 대신 쓰는 단축키 |
| --- | --- | --- | --- |
| 세 손가락 위로 쓸기 | 버튼 4 | 앱 전환기 | `⌃⌥⌘↑` |
| 네 손가락 모으기 | 버튼 5 | 홈 | `⌃⌥⌘H` |
| 세 손가락 아래로 쓸기 | 버튼 6 | 알림 센터 | `⌃⌥⌘↓` |
| 네 손가락 아래로 쓸기 | 버튼 7 | 제어 센터 | `⌃⌥⌘C` |
| — | 버튼 8 | 잠금 화면 | `⌃⌥⌘L` |

### 단축키

| 동작 | 기본 단축키 |
| --- | --- |
| Mac ↔ 아이폰 전환 | `⌃⌥⌘Space` |
| 클립보드를 아이폰에 입력 | `⌃⌥⌘V` |
| 가장자리 전환 켜기/끄기 | `⌃⌥⌘E` |

모두 설정 › 입력에서 바꿀 수 있어요. macOS 시스템 단축키와 겹치면 먼저 알려 줘요.

## 설치

1. [Releases](https://github.com/JUNG-WOOSEUNG/EdgeLink/releases/latest)에서 `EdgeLink.dmg`를 받아요.
2. DMG를 열고 EdgeLink를 Applications 폴더로 끌어 놓아요.
3. Applications에서 EdgeLink를 열면 처음 설정이 시작돼요(약 3분).

<p align="center">
  <img src="docs/images/diagram-onboarding.png" width="780" alt="처음 설정 4단계: Mac 권한, 아이폰 연결, 배치, 연습">
</p>

아직 Apple 공증을 받지 않은 베타라 처음 열 때 macOS가 막을 수 있어요. 그러면 시스템 설정 › 개인정보 보호 및 보안 아래쪽의 "그래도 열기"를 눌러 주세요.

### 요구 사항

| | 지원 |
| --- | --- |
| Mac | macOS 13 Ventura 이상, 블루투스 |
| 아이폰 | iOS 13 이상 (AssistiveTouch로 커서 표시) |
| 아이패드 | iPadOS 13.4 이상 |

## 자동 업데이트

<p align="center">
  <img src="docs/images/diagram-update.png" width="450" alt="자동 업데이트: 새 버전 확인, 업데이트 창, DMG 받기, 서명 확인, 바꿔 끼우고 다시 켜기">
</p>

- 인터넷은 이 저장소의 릴리스를 확인할 때만 쓰고, 설정 › 정보에서 끌 수 있어요.
- 바꿔 끼우는 작업은 앱과 떨어진 세션에서 돌아서, 앱이 끝나도 중간에 멈추지 않아요. 다시 켠 뒤 실제로 떠 있는지 확인해요.

## 개인정보와 보안

| 항목 | 처리 |
| --- | --- |
| 키 입력 · 클립보드 내용 | 저장하지 않음. 아이폰 조작 중에만 블루투스로 아이폰에 전달 |
| 연결 로그 | 연결 단계·오류만. 기기 주소는 뒷자리를 가림 (`A4:83:5C:**:**:**`) |
| 연결 허용 | 기본으로 정한 기기만 자동 연결. 처음 보는 기기는 허용할지 물음 |
| 비밀번호 입력 | Mac에 비밀번호 칸(Secure Input)이 열리면 즉시 Mac 조작으로 복귀 |
| 네트워크 | GitHub 릴리스 확인뿐. 설정에서 끌 수 있음 |
| 업데이트 | 같은 인증서로 서명된 번들만 설치 (지정 요구사항 검사) |

## 자주 묻는 질문

<details>
<summary>유니버설 컨트롤과 뭐가 다른가요?</summary>

유니버설 컨트롤은 Mac과 아이패드 사이에서만 동작해요. EdgeLink는 블루투스 HID를 쓰기 때문에 아이폰도 조작할 수 있어요.
</details>

<details>
<summary>클립보드 보내기로 한글도 보낼 수 있나요?</summary>

아직은 안 돼요. 키보드 입력을 흉내 내 한 글자씩 타이핑하는 방식이라 영문·숫자·기호만 보내요. 한글이 섞여 있으면 빼고 보낼 글자를 먼저 보여 주고 물어봐요. 직접 칠 때는 한글 입력이 돼요.
</details>

<details>
<summary>세 손가락 위로 쓸면 Mac의 Mission Control이 열려요.</summary>

Mac이 같은 제스처를 먼저 가져가서 그래요. 시스템 설정 › 트랙패드 › 추가 제스처에서 그 제스처를 끄거나 `⌃⌥⌘↑` 단축키를 쓰면 돼요.
</details>

<details>
<summary>회사 Mac에서도 쓸 수 있나요?</summary>

회사 정책(MDM, 매체 제어)으로 권한이나 블루투스 키보드 장치가 막혀 있으면 쓸 수 없어요. 앱이 이 경우를 알아채면 관리자에게 보낼 안내를 만들어 줘요.
</details>

## 알려진 문제

- 아이폰 블루투스를 껐다 켜면 다시 연결되기까지 오래 걸리거나 붙지 않을 수 있어요. 블루투스 처리를 별도 프로세스로 옮겨 그동안 메뉴 막대가 멈추지는 않게 했고, 재연결 자체는 계속 살펴보고 있어요.
- 아이폰 앱 사이 좌우 넘기기와 뒤로 가기 제스처는 아직 지원하지 않아요.

## 개발

### 저장소 구조

```
Sources/
├── EdgeLink/          메뉴 막대 앱 (SwiftUI) — 화면, InputRouter, 업데이트
├── EdgeLinkCore/      앱·도우미·bthid가 같이 쓰는 핵심
│   ├── BluetoothHID        SDP 등록, L2CAP 채널, 리포트 쓰기
│   ├── HIDReports          HID 디스크립터, 키 코드 변환, 리포트
│   ├── HIDHelperClient     도우미 프로세스 대리 객체 (감시·재시작)
│   ├── HelperMessages      앱 ↔ 도우미 메시지 인코딩
│   ├── SwitchEngine        가장자리 밀기 판정, 스크롤 변환
│   ├── LayoutGeometry      모니터 배치, 돌아오는 위치 계산
│   └── UpdateFeed          릴리스 정보 해석, 버전 비교
├── edgelink-hid/      블루투스 도우미 실행 파일
└── bthid/             연결 검증용 명령줄 도구
Tests/EdgeLinkCoreTests/   단위 테스트 (Swift Testing)
scripts/               빌드 · DMG · 릴리스 · 도식 그리기
docs/diagrams/         README 도식 원본 (Mermaid)
```

### HID 리포트

| Report ID | 장치 | 내용 |
| --- | --- | --- |
| 1 | 키보드 | 수정키 1바이트 + 예약 1 + 키 6개, LED 출력 1바이트 |
| 2 | 마우스 | 버튼 8개 + X · Y · 휠 · 가로 스크롤 (각 −127~127) |
| 3 | Consumer Control | 16비트 사용 코드 1개 (볼륨 · 재생 등) |

### 빌드

Xcode 없이 Command Line Tools(Swift 5.10 이상)만 있어도 돼요.

```sh
./scripts/build-app.sh          # 디버그 앱 → build/EdgeLink.app (도우미 포함, 같은 인증서로 서명)
./scripts/test.sh               # 단위 테스트
./scripts/make-dmg.sh --build   # 릴리스 빌드와 끌어서 설치하는 DMG → build/EdgeLink.dmg
./scripts/release.sh 0.4.0 -F notes.md   # 버전 올림 → 테스트 → DMG → 태그 → GitHub 릴리스
```

개발용 옵션: `EDGELINK_SNAPSHOT=<폴더>`(모든 화면을 PNG로), `EDGELINK_SHOW_DIALOG=<이름>`(확인 창을 실제 창으로), `EDGELINK_UPDATE_FEED=<주소>`(업데이트 확인 주소 바꾸기).

도식 원본은 [docs/diagrams](docs/diagrams)(Mermaid)에 있고 `./scripts/render-diagrams.sh`로 이미지를 다시 만들어요. 설계는 [docs/DESIGN.md](docs/DESIGN.md), 진행 기록은 [docs/DEVLOG.md](docs/DEVLOG.md), 화면 전체는 [docs/screens](docs/screens/README.md)에 있어요. 버그 제보와 아이디어는 [Issues](https://github.com/JUNG-WOOSEUNG/EdgeLink/issues)에 남겨 주세요.

## 라이선스

MIT 라이선스 · 자세한 내용은 [LICENSE](LICENSE)를 보세요.

<sub>iPhone, iPad, Mac, macOS, AssistiveTouch는 Apple Inc.의 상표예요. EdgeLink는 Apple과 관련이 없는 독립 프로젝트예요.</sub>
