extends "res://scripts/ui_window.gd"
## [성장] 탭 시트(개정 20) 자리 — 내용은 성장 작업이 채운다. 지금은 제목만 있는 빈 시트.


func _ready() -> void:
	_build_window(0, 10)
	dialog.get_parent().color = Color(0, 0, 0, 0)  # 시트가 화면을 채운다
	content.add_child(_title("성장"))
	_fit_sheet()
