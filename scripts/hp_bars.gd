extends Node2D
## 유닛 머리 위 실시간 HP 바(아군·적군). 매 프레임 두 그룹을 돌며 화면 공간에 한 번에 그린다 —
## 유닛마다 노드를 두지 않아 몬스터가 많아도 가볍다. HUD(CanvasLayer)보다 아래 캔버스에 그려진다.
## 유닛 인터페이스: is_alive(), hp_ratio(), bar_height(), bar_scale().

const BAR_W := 34.0           # 논리 px(720 폭 기준). 줌과 무관
const BAR_H := 5.0
const BORDER := 1.5
const SCREEN_MARGIN := 40.0   # 화면 밖 이만큼까지는 그린다(가장자리 걸친 유닛)
const HERO_COLOR := Color(0.35, 0.85, 0.40)
const MONSTER_COLOR := Color(0.92, 0.28, 0.22)
const BACK := Color(0, 0, 0, 0.55)

var camera: Camera3D


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if camera == null:
		return
	var view := get_viewport_rect().grow(SCREEN_MARGIN)
	_draw_group("heroes", HERO_COLOR, view)
	_draw_group("monsters", MONSTER_COLOR, view)


func _draw_group(group: String, color: Color, view: Rect2) -> void:
	for u in get_tree().get_nodes_in_group(group):
		if not u.is_alive():
			continue
		var p := camera.unproject_position(u.global_position + Vector3(0, u.bar_height(), 0))
		if not view.has_point(p):
			continue
		var w: float = BAR_W * u.bar_scale()
		var top_left := p - Vector2(w / 2.0, BAR_H / 2.0)
		draw_rect(Rect2(top_left - Vector2(BORDER, BORDER), Vector2(w + BORDER * 2.0, BAR_H + BORDER * 2.0)), BACK)
		draw_rect(Rect2(top_left, Vector2(w * clampf(u.hp_ratio(), 0.0, 1.0), BAR_H)), color)
