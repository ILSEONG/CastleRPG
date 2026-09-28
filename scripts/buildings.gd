extends Node3D
## 성 안 건물 플레이스홀더 (Balance.BUILDINGS). 기능 없음 — 크기·배치 확인용.
## 건물 기능(자원·업그레이드)은 서브프로젝트 2.

const Balance := preload("res://scripts/balance.gd")
const Flat := preload("res://scripts/flat.gd")
const FONT := preload("res://assets/fonts/Pretendard-SemiBold.otf")

const GAP := 0.4  # 타일 경계와 건물 벽 사이 여유 (격자선이 보이게)


func _ready() -> void:
	for b in Balance.BUILDINGS:
		var size := Vector3(b.size.x * Balance.TILE - GAP, b.height, b.size.y * Balance.TILE - GAP)
		var center := Vector3((b.cell.x + b.size.x / 2.0) * Balance.TILE, 0, (b.cell.y + b.size.y / 2.0) * Balance.TILE)
		var box := Flat.box(size, b.color)
		box.position += center
		add_child(box)
		var label := Label3D.new()
		label.text = b.name
		label.font = FONT
		label.font_size = 48
		label.outline_size = 12
		label.pixel_size = 0.03
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.modulate = Color(0.18, 0.18, 0.22)
		label.outline_modulate = Color(1, 1, 1, 0.9)
		label.position = center + Vector3(0, b.height + 1.2, 0)
		add_child(label)
