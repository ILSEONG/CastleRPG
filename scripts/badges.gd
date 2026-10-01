extends Node2D
## 자원 건물 말풍선(쌓인 게 5분 이상이면 이름표 위에 자원 아이콘)과 수집 "+N" 떠오르기.
## hp_bars 방식: 화면 공간에 매 프레임 한 번에 그린다. 건물 위치·높이는 Balance.BUILDINGS와 TownKit 메시 AABB에서.
## 건물 이름표(buildings.gd)가 높이+1.0m에 있다 — 말풍선 꼬리 끝은 그 위(높이+ANCHOR_UP).

const Balance := preload("res://scripts/balance.gd")
const TownKit := preload("res://scripts/town_kit.gd")
const IconsScript := preload("res://scripts/icons.gd")
const FONT := preload("res://assets/fonts/Pretendard-SemiBold.otf")

const ANCHOR_UP := 1.9   # 건물 지붕 위 m: 이름표(+1.0, 글자 높이 ~1.4) 위
const BUBBLE_R := 22.0   # 논리 px(720 폭 기준)
const BOB_PX := 3.0
const BOB_HZ := 0.8
const POP_RISE_PX := 40.0
const POP_SEC := 1.2
const POP_FONT := 28
const INK := Color(0.16, 0.18, 0.24)

var camera: Camera3D
var last_pop := {}  # 마지막 pop 인자(테스트·디버그용): {pos, kind, amount}

var _anchors := {}  # 건물 id → 말풍선 기준 월드 좌표(지붕 위)
var _pops: Array = []  # {pos, kind, amount, age}
var _t := 0.0


func _ready() -> void:
	for res_id in Balance.RESOURCES:
		var b := Balance.building(Balance.RESOURCES[res_id].building)
		var center := Vector3((b.cell.x + b.size.x / 2.0) * Balance.TILE, 0, (b.cell.y + b.size.y / 2.0) * Balance.TILE)
		_anchors[b.id] = center + Vector3(0, TownKit.building(b.id).get_aabb().end.y, 0)


## 건물 id의 지붕 위 월드 좌표("+N" 시작 지점·말풍선 기준).
func anchor(building_id: String) -> Vector3:
	return _anchors[building_id] + Vector3(0, ANCHOR_UP, 0)


## 지금 말풍선을 띄울 건물 id들.
func badge_ids(now: float) -> Array:
	var out := []
	for id in _anchors:
		if Economy.show_badge(id, now):
			out.append(id)
	return out


func pop(world_pos: Vector3, kind: String, amount: int) -> void:
	last_pop = {"pos": world_pos, "kind": kind, "amount": amount}
	_pops.append({"pos": world_pos, "kind": kind, "amount": amount, "age": 0.0})


func _process(delta: float) -> void:
	_t += delta
	for p in _pops:
		p.age += delta
	_pops = _pops.filter(func(p): return p.age < POP_SEC)
	queue_redraw()


func _draw() -> void:
	if camera == null:
		return
	var view := get_viewport_rect().grow(BUBBLE_R * 2.0)
	var bob := sin(_t * TAU * BOB_HZ) * BOB_PX
	for id in badge_ids(Time.get_unix_time_from_system()):
		var tip := camera.unproject_position(anchor(id)) + Vector2(0, bob)
		if view.has_point(tip):
			_draw_bubble(tip, Economy.res_of(id))
	for p in _pops:
		var at := camera.unproject_position(p.pos) + Vector2(0, -POP_RISE_PX * p.age / POP_SEC)
		_draw_pop(at, p)


## tip = 꼬리 끝(건물 쪽). 흰 둥근 말풍선이 그 위에 뜬다.
func _draw_bubble(tip: Vector2, kind: String) -> void:
	var c := tip + Vector2(0, -BUBBLE_R - 8.0)
	draw_colored_polygon(PackedVector2Array([tip, c + Vector2(-7, BUBBLE_R - 3), c + Vector2(7, BUBBLE_R - 3)]), Color.WHITE)
	draw_circle(c, BUBBLE_R + 1.5, Color(INK, 0.35))
	draw_circle(c, BUBBLE_R, Color.WHITE)
	IconsScript.draw_icon(self, kind, c, BUBBLE_R * 1.3)


## 아이콘 + "+N". 글자는 서서히 사라지고 아이콘은 줄어든다(draw_icon은 투명도를 받지 않는다).
func _draw_pop(at: Vector2, p: Dictionary) -> void:
	var k: float = p.age / POP_SEC
	var a := clampf((1.0 - k) / 0.4, 0.0, 1.0)  # 처음 60%는 또렷하게, 마지막 40%에 사라진다
	var text := "+%d" % p.amount
	var w := FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, POP_FONT).x
	var icon_px := 30.0 * (1.0 - 0.5 * k)
	var x0 := at.x - (icon_px + 4.0 + w) / 2.0
	IconsScript.draw_icon(self, p.kind, Vector2(x0 + icon_px / 2.0, at.y), icon_px)
	var pos := Vector2(x0 + icon_px + 4.0, at.y + POP_FONT * 0.35)
	draw_string_outline(FONT, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, POP_FONT, 8, Color(1, 1, 1, a))
	draw_string(FONT, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, POP_FONT, Color(INK, a))
