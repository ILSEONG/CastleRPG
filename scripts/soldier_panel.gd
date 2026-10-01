extends "res://scripts/ui_window.gd"
## [병사] 탭 시트(개정 13 §7.1) 자리. 지금은 "병사 준비 중" 빈 시트 — 병사 시트(다음 작업 S2)가 채운다.
## 영웅 시트처럼 칩 줄 아래 ~ 탭 바 위를 채우고 뒤 입력을 막는다.

const EMPTY_TEXT := "병사 준비 중"


func _ready() -> void:
	_build_window(0, 10)
	dialog.get_parent().color = Color(0, 0, 0, 0)  # 시트가 화면을 채운다
	content.add_child(_title("병사"))
	content.add_child(_label(EMPTY_TEXT, 28, HudScript.INK.lightened(0.3)))
	_fit()


func _fit() -> void:
	_fit_sheet()
