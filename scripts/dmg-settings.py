# dmgbuild 설정 (scripts/make-dmg.sh가 쓴다). Finder 없이 창 모양을 정한다.
# -D app=<앱 경로> 로 넘겨받는다.
import os.path

app = defines.get("app", "build/EdgeLink.app")  # noqa: F821 (dmgbuild가 넣어 준다)
format = "UDZO"
compression_level = 9
filesystem = "HFS+"
files = [app]
symlinks = {"Applications": "/Applications"}
icon = "Resources/AppIcon.icns"
badge_icon = None
background = "Resources/dmg-background.tiff"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
window_rect = ((200, 120), (660, 400))
default_view = "icon-view"
arrange_by = None
icon_size = 112
text_size = 13
icon_locations = {
    os.path.basename(app): (165, 190),
    "Applications": (495, 190),
    # 숨김 파일 보기를 켠 Mac에서도 창 안에 보이지 않게 창(660×400) 바깥 먼 곳에 둔다
    ".background.tiff": (1400, 190),
    ".VolumeIcon.icns": (1600, 190),
    ".fseventsd": (1800, 190),
}
