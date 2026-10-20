<p align="center">
  <img src="docs/images/icon.png" width="128" alt="EdgeLink 앱 아이콘">
</p>

<h1 align="center">EdgeLink</h1>

<p align="center">
  <b>Mac 키보드·트랙패드로 아이폰까지.</b><br>
  커서를 화면 끝으로 밀면 아이폰으로 넘어가요. 아이폰엔 아무것도 설치하지 않아요.
</p>

<p align="center">
  <a href="https://github.com/JUNG-WOOSEUNG/EdgeLink/releases/latest"><img src="https://img.shields.io/badge/다운로드-EdgeLink.dmg-0077B6" alt="DMG 다운로드"></a>
  <img src="https://img.shields.io/badge/macOS-13%2B-0077B6" alt="macOS 13 이상">
  <img src="https://img.shields.io/badge/iOS-13%2B-0077B6" alt="iOS 13 이상">
  <img src="https://img.shields.io/badge/상태-베타-FFC107" alt="베타">
  <img src="https://img.shields.io/badge/license-MIT-lightgrey" alt="MIT">
</p>

<p align="center">
  <img src="docs/images/hero.png" width="820" alt="EdgeLink 설정 창의 배치 화면과 메뉴 막대 팝오버. 아이폰을 Mac 화면 왼쪽에 두고 '연결됨 · 아이폰 조작 중'으로 표시된 모습">
</p>

---

메신저 답장이나 인증번호 하나 때문에 키보드에서 손을 떼고 아이폰을 집는 일을 없애요. 아이폰을 둔 쪽 화면 끝으로 커서를 밀면 그때부터 Mac 키보드와 트랙패드가 아이폰을 조작하고, 반대로 밀면 Mac으로 돌아와요. 아이폰을 모니터 하나 더 둔 것처럼 쓰는 방식이에요.

## 동작 방식

EdgeLink는 Mac을 아이폰에 **블루투스 키보드 + 마우스**로 연결해요. 아이폰은 평범한 블루투스 키보드·마우스가 붙은 것으로 알기 때문에 앱, 프로필, 탈옥이 필요 없어요. 아이폰 화면을 Mac으로 가져오는 게 아니라, 화면은 아이폰에서 보고 조작만 Mac에서 해요.

```
 Mac 키보드·트랙패드 ──▶ EdgeLink ──블루투스 키보드·마우스──▶ 아이폰
```

## 기능

### 넘어가기와 돌아오기

- 아이폰을 실제로 둔 쪽을 골라요. 모니터마다 왼쪽·오른쪽·위·아래 중 다른 모니터와 맞닿지 않은 가장자리를 쓸 수 있어요.
- 그 가장자리를 밀면 아이폰으로 넘어가요. 밀기 시작하면 가장자리에 파란 유리 알약이 튀어나와 넘어갈 곳을 보여 줘요. 밀어야 하는 정도는 설정에서 조절해요.
- 핫 코너와 겹치지 않게 구석은 비워 두고, 파일이나 창을 끄는 중에는 넘어가지 않아요.
- 아이폰 화면의 반대쪽 끝으로 밀거나 `⌃⌥⌘Space`를 누르면 Mac으로 돌아와요. 돌아올 때 Mac 커서는 아이폰 커서가 있던 높이에 나타나요. 어긋나면 "위치 맞추기"로 한 번 맞추면 돼요.

### 입력

- **키보드**: Mac 키보드로 그대로 입력해요. 한/영 전환은 Caps Lock이에요.
- **트랙패드·마우스**: 클릭, 드래그, 오른쪽 클릭, 두 손가락 스크롤. 포인터 속도와 스크롤 속도는 따로 맞춰요.
- **트랙패드 제스처**: 세 손가락 위로 쓸기 → 앱 전환기, 네 손가락 모으기 → 홈, 세 손가락 아래로 → 알림 센터, 네 손가락 아래로 → 제어 센터. 처음 한 번 아이폰 AssistiveTouch에 버튼을 등록해야 하고, 앱이 단계별로 안내해요(1~2분).
- **미디어 키**: 켜 두면 볼륨·재생 키가 아이폰으로 가요.
- **클립보드 보내기**: `⌃⌥⌘V`를 누르면 Mac에 복사한 글을 아이폰에 대신 타이핑해요.

### 단축키

| 동작 | 기본 단축키 |
| --- | --- |
| Mac ↔ 아이폰 전환 | `⌃⌥⌘Space` |
| 클립보드를 아이폰에 입력 | `⌃⌥⌘V` |
| 가장자리 전환 켜기/끄기 | `⌃⌥⌘E` |
| 앱 전환기 · 홈 · 알림 센터 · 제어 센터 · 잠금 화면 | `⌃⌥⌘↑` · `⌃⌥⌘H` · `⌃⌥⌘↓` · `⌃⌥⌘C` · `⌃⌥⌘L` |

모두 설정 › 입력에서 바꿀 수 있어요. 아이폰 동작 단축키는 버튼 등록만 하면 제스처 없이도 써요.

### 안전장치

키 입력을 다루는 앱이라, 입력이 엉뚱한 곳으로 가지 않게 하는 것을 먼저 챙겨요.

- 아이폰을 조작하는 중에 Mac에 비밀번호 칸이 열리거나, `⌃⌘Q`로 화면을 잠그거나, 블루투스가 끊기면 바로 Mac 조작으로 돌아와요. 이때 눌려 있던 키는 모두 떼고 돌아와요.
- 기본으로 정한 아이폰만 자동으로 연결해요. 처음 보는 기기가 연결해 오면 허용할지 먼저 물어봐요.
- 키 입력과 클립보드 내용은 로그·설정 어디에도 저장하지 않아요. 연결 로그의 기기 주소는 뒷자리를 가려요.
- 인터넷은 하루 한 번 이 저장소의 GitHub 릴리스를 확인할 때만 쓰고, 설정에서 끌 수 있어요. 업데이트는 지금 앱과 같은 인증서로 서명된 앱만 설치해요.

## 화면

<table>
  <tr>
    <td width="50%"><img src="docs/screens/onboarding-1.png" alt="처음 설정 시작 화면"></td>
    <td width="50%"><img src="docs/screens/onboarding-6.png" alt="처음 설정에서 아이폰 둔 자리 고르기"></td>
  </tr>
  <tr>
    <td align="center"><sub>처음 설정: 권한, 아이폰 연결, 배치, 연습 4단계</sub></td>
    <td align="center"><sub>아이폰을 둔 가장자리 고르기</sub></td>
  </tr>
  <tr>
    <td><img src="docs/screens/settings-input.png" alt="설정 입력 탭"></td>
    <td><img src="docs/screens/gesture-setup.png" alt="트랙패드 제스처 설정"></td>
  </tr>
  <tr>
    <td align="center"><sub>단축키, 입력 옵션, 속도</sub></td>
    <td align="center"><sub>트랙패드 제스처 설정 도우미</sub></td>
  </tr>
</table>

다크 모드와 연결 실패·권한 꺼짐 같은 상태별 화면은 [docs/screens](docs/screens/README.md)에 있어요.

## 설치

1. [Releases](https://github.com/JUNG-WOOSEUNG/EdgeLink/releases/latest)에서 `EdgeLink.dmg`를 받아요.
2. DMG를 열고 EdgeLink를 Applications 폴더로 끌어 놓아요.
3. Applications에서 EdgeLink를 열면 처음 설정이 시작돼요. 3분 정도 걸려요.
   - Mac 권한 3가지 허용: 블루투스, 손쉬운 사용, 입력 모니터링
   - 아이폰 설정 › Bluetooth에서 Mac과 페어링
   - 아이폰 설정 › 손쉬운 사용 › 터치 › AssistiveTouch 켜기 (켜야 아이폰에 커서가 보여요)
   - 아이폰을 둔 가장자리 고르기

아직 Apple 공증을 받지 않은 베타라 처음 열 때 macOS가 막을 수 있어요. 그러면 시스템 설정 › 개인정보 보호 및 보안 아래쪽의 "그래도 열기"를 눌러 주세요. 한 번만 하면 돼요.

### 요구 사항

| | 지원 |
| --- | --- |
| Mac | macOS 13 Ventura 이상, 블루투스 |
| 아이폰 | iOS 13 이상 |
| 아이패드 | iPadOS 13.4 이상 |

## 자주 묻는 질문

<details>
<summary>유니버설 컨트롤과 뭐가 다른가요?</summary>

유니버설 컨트롤은 Mac과 아이패드 사이에서만 동작해요. EdgeLink는 아이폰도 조작할 수 있어요.
</details>

<details>
<summary>클립보드 보내기로 한글도 보낼 수 있나요?</summary>

아직은 안 돼요. 키보드 입력을 흉내 내 한 글자씩 타이핑하는 방식이라 영문·숫자·기호만 보내요. 한글이 섞여 있으면 빼고 보낼 글자를 먼저 보여 주고 물어봐요. 직접 칠 때는 한글 입력이 돼요.
</details>

<details>
<summary>세 손가락 위로 쓸면 Mac의 Mission Control이 열려요.</summary>

Mac이 같은 제스처를 먼저 가져가서 그래요. 시스템 설정 › 트랙패드 › 추가 제스처에서 그 제스처를 끄거나, `⌃⌥⌘↑` 단축키를 쓰면 돼요.
</details>

<details>
<summary>회사 Mac에서도 쓸 수 있나요?</summary>

회사 정책(MDM, 매체 제어)으로 권한이나 블루투스 키보드 장치가 막혀 있으면 쓸 수 없어요. 앱이 이 경우를 알아채면 관리자에게 보낼 안내를 만들어 줘요.
</details>

## 알려진 문제

- 아이폰 블루투스를 껐다 켜면 다시 연결되기까지 오래 걸리거나 붙지 않고, 그동안 메뉴 막대 아이콘이 몇 초씩 멈출 수 있어요. 블루투스 처리를 별도 프로세스로 옮기는 작업을 하고 있어요.
- 아이폰 앱 사이 좌우 넘기기와 뒤로 가기 제스처는 아직 지원하지 않아요.

## 직접 빌드하기

Xcode 없이 Command Line Tools(Swift 5.10 이상)만 있어도 돼요.

```sh
./scripts/build-app.sh          # 디버그 앱 → build/EdgeLink.app
./scripts/test.sh               # 단위 테스트
./scripts/make-dmg.sh --build   # 릴리스 빌드와 DMG → build/EdgeLink.dmg
./scripts/release.sh 0.3.0 "고친 것"   # 버전 올리고 GitHub 릴리스까지
```

설계는 [docs/DESIGN.md](docs/DESIGN.md), 진행 기록은 [docs/DEVLOG.md](docs/DEVLOG.md)에 있어요. 버그 제보와 아이디어는 [Issues](https://github.com/JUNG-WOOSEUNG/EdgeLink/issues)에 남겨 주세요.

## 라이선스

MIT 라이선스 · 자세한 내용은 [LICENSE](LICENSE)를 보세요.

<sub>iPhone, iPad, Mac, macOS, AssistiveTouch는 Apple Inc.의 상표예요. EdgeLink는 Apple과 관련이 없는 독립 프로젝트예요.</sub>
