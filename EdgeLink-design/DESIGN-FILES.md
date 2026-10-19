# EdgeLink 디자인 파일 안내

이 폴더는 디자인 캔버스 "EdgeLink 메뉴바 & 설정"의 원본 파일이에요.

- `design-canvas/*.dc.html`: 화면 하나당 파일 하나. HTML과 인라인 스타일로 되어 있어서, 색·간격·글자 크기·문구를 그대로 확인하고 SwiftUI로 옮길 때 참고할 수 있어요.
- 이 파일들은 캔버스 뷰어에서 보이도록 만든 형식이라, 브라우저로 바로 열면 화면이 제대로 그려지지 않아요. 화면을 보려면 claude.ai의 캔버스를 열거나, 캔버스의 Share › Export로 이미지나 PDF를 받으세요.
- `canvas.json`: 화면 배치와 순서
- `README-github.md`: GitHub 공개 저장소에 올릴 소개 문서

## 화면 목록 (캔버스 순서)

| 번호 | 화면 | 파일 |
| --- | --- | --- |
| 1-1 | 시작 | `Onboarding-1-Welcome.dc.html` |
| 1-2 | Mac 권한 | `Onboarding-2-Permissions.dc.html` |
| 1-3 | 아이폰 페어링 | `Onboarding-3-Pairing.dc.html` |
| 1-4 | AssistiveTouch | `Onboarding-4-AssistiveTouch.dc.html` |
| 1-5 | 연결 확인 | `Onboarding-5-Test.dc.html` |
| 1-6 | 배치 | `Onboarding-6-Layout.dc.html` |
| 1-7 | 연습 | `Onboarding-7-Practice.dc.html` |
| 1-8 | 완료 | `Onboarding-8-Done.dc.html` |
| 1-9 | 제스처 버튼 등록 (선택) | `GestureSetup.dc.html` |
| 2-1 | 연결됨 (기기 버튼을 눌러 메뉴 보기) | `Main.dc.html` |
| 2-2 | 설정 중 | `Offline.dc.html` |
| 2-3 | 연결 끊김 (설정 완료 후) | `OfflineDisconnected.dc.html` |
| 2-4 | 문제 있음 (권한 / 블루투스 / 회사 정책) | `PopoverWarning.dc.html` |
| 3-1 | 설정 창 (탭을 눌러 이동) | `Settings.dc.html` |
| 3-2 | 배치 · 모니터 아래 + Dock 안내 | `LayoutBottom.dc.html` |
| 4-1 | 확인 창 · 연결 요청, 클립보드, 단축키 겹침 | `Dialogs.dc.html` |
| 4-2 | 보정 도우미 · 알림 | `Extras.dc.html` |
| 4-3 | 빈 상태 · 실패 상태 | `EmptyStates.dc.html` |
| 4-4 | 진행 · 로그 · 초기화 · 권한 거부 | `SmallDialogs.dc.html` |
| 5-1 | 개발용 디자인 규격 | `DesignSpec.dc.html` |
| 5-2 | 아이콘 · 앱, 메뉴바 | `Icons.dc.html` |
| 5-3 | 다크 모드 | `DarkMode.dc.html` |
| 5-4 | 모서리 효과 · 움직임 시안 | `EdgeMotion.dc.html` |

## 기준 문서

동작, 예외 처리, 보안, 구조, 검증 체크리스트는 claude.ai의 "EdgeLink 설계 문서"가 기준이에요. 수치가 다르면 설계 문서를 따르세요.
