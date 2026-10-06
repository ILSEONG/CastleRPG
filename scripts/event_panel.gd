extends "res://scripts/ui_window.gd"
## 이벤트 창(오른쪽 아래 메뉴 [이벤트]). 이벤트 기능이 아직 없어 "준비 중" 안내와 [닫기]만 있다.

const SideMenu := preload("res://scripts/side_menu.gd")


func _ready() -> void:
	_build_window(560, 16)
	content.add_child(_title("이벤트"))
	var icon := Control.new()
	icon.custom_minimum_size = Vector2(0, 120)
	icon.draw.connect(func(): SideMenu.draw_gift(icon, Vector2(icon.size.x / 2.0, 64), 100.0))
	content.add_child(icon)
	content.add_child(_label("이벤트 준비 중입니다", 30))
	content.add_child(_label("곧 새로운 이벤트로 찾아올게요", 22, Color(HudScript.INK, 0.62)))
	var close_button := _button("닫기", UiKit.STEEL)
	close_button.pressed.connect(close)
	content.add_child(close_button)
