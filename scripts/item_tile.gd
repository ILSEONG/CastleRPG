extends Control
## 장비 칸(개정 18 §8): Icons.draw_item — 등급 색 바탕·테두리 + 부위(무기는 종류) 아이콘. grade ""면 빈 칸(흐린 회색 아이콘).
## LR은 테두리가 흐른다(보일 때 매 프레임 다시 그린다). 입력은 받지 않는다(버튼 안에 넣어 쓴다). 보관함·영웅 장비 칸·던전 결과가 쓴다.

const IconsScript := preload("res://scripts/icons.gd")

var kind := ""  # hat·top·…·sword·axe…(IconsScript.ITEM_KINDS). ""면 아무것도 안 그린다
var grade := ""


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_item(p_kind: String, p_grade: String) -> void:
	kind = p_kind
	grade = p_grade
	modulate.a = 1.0 if grade != "" else 0.35
	set_process(grade == "LR")
	queue_redraw()


func _ready() -> void:
	set_process(grade == "LR")


func _process(_delta: float) -> void:
	if is_visible_in_tree():
		queue_redraw()


func _draw() -> void:
	if kind != "":
		IconsScript.draw_item(self, kind, grade if grade != "" else "N", size / 2.0, minf(size.x, size.y))
