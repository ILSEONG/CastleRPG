extends Node2D
## 자원 건물 말풍선(쌓인 게 5분 이상이면 이름표 위에 자원 아이콘)과 수집 "+N" 떠오르기.
## hp_bars 방식: 화면 공간에 매 프레임 한 번에 그린다. 건물 위치·높이는 Balance.BUILDINGS와 TownKit 메시 AABB에서.
## 건설 중(개정 12 §2.5): 짓는 건물(성문은 문루 넷) 이름표 위에 진행 막대 + 남은 시간(UiKit.duration, 초가 바뀔 때마다 글자가 바뀐다).
## 그 건물의 말풍선은 막대 위로 올린다. 자리는 scenery(buildings.gd).sites.
## 개정 15: 막대·말풍선은 화면 공간 이름표(world_tags.gd, tags)의 윗변(tags.top) 위에 쌓는다 — 이름표와 한 덩어리로 겹침·병사 대열을 피한다
## (덩어리 크기 = stack_size). tags가 없으면 예전처럼 지붕 위 ANCHOR_UP 월드 좌표에.
## 훈련(개정 16): 병사 건물이 훈련 중이면 건설 막대와 같은 막대 + 남은 시간(h:mm:ss), 끝났으면 병사 피규어 말풍선(자원 말풍선과 같은 8각 면).
## 같은 건물을 짓는 중이면 건설 막대 위에 쌓는다. 쌓는 순서(아래 → 위): 이름표, 건설 막대, 훈련 막대 또는 말풍선.
## 연구(개정 24): 연구가 비어 있고 시작할 수 있는 노드가 있으면(Economy.research_available) 연구소 위에 플라스크 말풍선(자원 말풍선과 같은 모양) —
## 연구소를 탭하면 연구 창이 열린다(unit_picker).

const Balance := preload("res://scripts/balance.gd")
const GameData := preload("res://scripts/game_data.gd")
const TownKit := preload("res://scripts/town_kit.gd")
const IconsScript := preload("res://scripts/icons.gd")
const PortraitsScript := preload("res://scripts/portraits.gd")
const UiKit := preload("res://scripts/ui_kit.gd")
const FONT :=preload("res://assets/fonts/Pretendard-SemiBold.otf")

const ANCHOR_UP := 1.9   # 건물 지붕 위 m: "+N" 시작 지점(이름표 높이쯤), tags가 없을 때 말풍선·막대 자리
const BUBBLE_R := 22.0   # 논리 px(720 폭 기준)
const BOB_PX := 3.0
const BOB_HZ := 0.8
const POP_RISE_PX := 40.0
const POP_SEC := 1.2
const POP_FONT := 28
const INK := Color(0.16, 0.18, 0.24)
const BUILD_BAR := Vector2(96, 12)  # 건설 진행 막대(논리 px)
const BUILD_FONT := 22
const BUILD_LIFT_PX := 44.0  # 막대 + 남은 시간 글자 덩어리 높이 — 짓는 중인 자원 건물의 말풍선을 이만큼 위로 올린다
const BUILD_W := 104.0  # 막대·남은 시간 덩어리 폭
const BUILD_AT_PX := 10.0  # 이름표 윗변 → 막대 가운데
const BUBBLE_BLOCK := 58.0  # 말풍선 덩어리 높이(꼬리 2 + 지름 + 8 + 흔들림)

var camera: Camera3D
var scenery  # 건물(buildings.gd) — 건설 막대 자리(sites). main이 넣는다
var tags  # world_tags.gd — 이름표 자리(top). main이 넣는다(없으면 지붕 위 월드 좌표)
var last_pop := {}  # 마지막 pop 인자(테스트·디버그용): {pos, kind, amount}

var _anchors := {}  # 자원·병사 건물 id → 말풍선 기준 월드 좌표(지붕 위)
var _pops: Array = []  # {pos, kind, amount, age}
var _t := 0.0


func _ready() -> void:
	for id in GameData.resources().map(func(r): return r.building) + GameData.soldiers().map(func(x): return x.building) + [GameData.LAB]:
		var b := Balance.building(id)
		var center := Vector3((b.cell.x + b.size.x / 2.0) * Balance.TILE, 0, (b.cell.y + b.size.y / 2.0) * Balance.TILE)
		_anchors[b.id] = center + Vector3(0, TownKit.building(b.id).get_aabb().end.y, 0)


## 건물 id의 지붕 위 월드 좌표("+N" 시작 지점·말풍선 기준).
func anchor(building_id: String) -> Vector3:
	return _anchors[building_id] + Vector3(0, ANCHOR_UP, 0)


## 지금 자원 말풍선을 띄울 건물 id들.
func badge_ids(now: float) -> Array:
	var out := []
	for id in _anchors:
		if Economy.res_of(id) != "" and Economy.show_badge(id, now):
			out.append(id)
	return out


## 지금 훈련 중(막대)·완료(병사 말풍선)인 병사 건물 id들 {bars, ready}(개정 16).
func training_ids() -> Dictionary:
	var out := {"bars": [], "ready": []}
	for s in GameData.soldiers():
		var q := Economy.training(s.building)
		if q.count > 0:
			out["ready" if q.ready else "bars"].append(s.building)
	return out


## 연구소 플라스크 말풍선을 띄우나(개정 24): 연구가 비어 있고 지금 시작할 수 있는 노드가 있다.
func research_bubble() -> bool:
	return Economy.research_available()


## 지금 말풍선이 뜬 건물 id들(자원·훈련 완료·연구 플라스크) — 말풍선 탭 판정(unit_picker)용. stack_size의 말풍선 조건과 같다.
func bubble_ids(now: float) -> Array:
	var out: Array = badge_ids(now) + training_ids().ready
	if research_bubble():
		out.append(GameData.LAB)
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
	var now := Economy.time_now()
	var bid := str(Economy.build.get("id", ""))
	var bars := build_anchors()
	for i in bars.size():
		var at = _base(bid if bid != GameData.GATE else "gate:%d" % i, bars[i])
		if at != null and view.has_point(at):
			_draw_build_bar(at + Vector2(0, -BUILD_AT_PX if tags != null else 0.0), Economy.build_progress(now), UiKit.duration(Economy.build_left(now)))
	for id in badge_ids(now):
		var at = _base(id, anchor(id))
		if at == null:
			continue
		var tip: Vector2 = at + Vector2(0, bob - (2.0 if tags != null else 0.0) - (BUILD_LIFT_PX if Economy.is_building(id) else 0.0))
		if view.has_point(tip):
			_draw_bubble(tip, Economy.res_of(id))
	var tr := training_ids()
	for id in tr.bars:
		var at = _base(id, anchor(id))
		if at != null:
			at += Vector2(0, (-BUILD_AT_PX if tags != null else 0.0) - (BUILD_LIFT_PX if Economy.is_building(id) else 0.0))
			if view.has_point(at):
				_draw_build_bar(at, Economy.train_progress(id), UiKit.clock(maxf(0.0, Economy.training(id).finish - now)))
	for id in tr.ready:
		var at = _base(id, anchor(id))
		if at == null:
			continue
		var tip: Vector2 = at + Vector2(0, bob - (2.0 if tags != null else 0.0) - (BUILD_LIFT_PX if Economy.is_building(id) else 0.0))
		if view.has_point(tip):
			_draw_bubble(tip, "", GameData.soldier_of_building(id))
	if research_bubble():
		var at = _base(GameData.LAB, anchor(GameData.LAB))
		if at != null:
			var tip: Vector2 = at + Vector2(0, bob - (2.0 if tags != null else 0.0) - (BUILD_LIFT_PX if Economy.is_building(GameData.LAB) else 0.0))
			if view.has_point(tip):
				_draw_bubble(tip, "flask")
	for p in _pops:
		var at := camera.unproject_position(p.pos) + Vector2(0, -POP_RISE_PX * p.age / POP_SEC)
		_draw_pop(at, p)


## tip = 꼬리 끝(건물 쪽). 흰 둥근 말풍선이 그 위에 뜬다. 안에는 자원 아이콘(kind) 또는 병종 피규어(soldier — 훈련 완료, 개정 16).
func _draw_bubble(tip: Vector2, kind: String, soldier := "") -> void:
	var c := tip + Vector2(0, -BUBBLE_R - 8.0)
	var tail := PackedVector2Array([tip, c + Vector2(-7, BUBBLE_R - 3), c + Vector2(7, BUBBLE_R - 3)])
	draw_colored_polygon(tail, UiKit.CREAM)
	draw_polyline(PackedVector2Array([tail[1], tail[0], tail[2]]), UiKit.OUTLINE, 1.5, true)
	UiKit.draw_gem(self, c, BUBBLE_R, UiKit.CREAM, 8)  # 8각 면 말풍선
	if soldier != "":
		draw_texture_rect(PortraitsScript.portrait("soldier:" + soldier), Rect2(c - Vector2.ONE * BUBBLE_R * 0.95, Vector2.ONE * BUBBLE_R * 1.9), false)
	else:
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


## 막대·말풍선을 쌓을 바닥 화면 좌표: 이름표(tag_id)의 윗변 가운데(이름표가 화면 밖이면 null). tags가 없으면 월드 좌표 world를 그대로.
func _base(tag_id: String, world: Vector3):
	return tags.top(tag_id) if tags != null else camera.unproject_position(world)


## 이름표 tag_id(건물 id, 성문은 "gate:<면>") 위에 쌓을 덩어리 크기 Vector2(최소 폭, 높이) — world_tags가 이름표와 한 덩어리로 놓는다.
## 짓는 중이면 막대 + 남은 시간, 그 위에 훈련 막대(개정 16), 말풍선(자원·훈련 완료)이 뜨면 맨 위에 말풍선.
func stack_size(tag_id: String, now: float) -> Vector2:
	var id := tag_id.get_slice(":", 0)
	var out := Vector2.ZERO
	if Economy.is_building(id):
		out = Vector2(BUILD_W, BUILD_LIFT_PX)
	var q := Economy.training(id)
	if q.count > 0 and not q.ready:
		out = Vector2(BUILD_W, out.y + BUILD_LIFT_PX)
	if (Economy.res_of(id) != "" and Economy.show_badge(id, now)) or (q.count > 0 and q.ready) or (id == GameData.LAB and research_bubble()):
		out = Vector2(maxf(out.x, BUBBLE_R * 2.0 + 4.0), out.y + BUBBLE_BLOCK)
	return out


## 지금 짓는 건물의 진행 막대 자리(월드, 지붕 위 ANCHOR_UP). 쉬면 [].
func build_anchors() -> Array:
	if scenery == null:
		return []
	return scenery.sites.get(str(Economy.build.get("id", "")), []).map(
		func(box: AABB): return Vector3(box.get_center().x, box.end.y + ANCHOR_UP, box.get_center().z))


## 각진 막대(어두운 바탕 + 호박색 채움) + 그 위 남은 시간.
func _draw_build_bar(at: Vector2, ratio: float, text: String) -> void:
	var r := Rect2(at - BUILD_BAR / 2.0, BUILD_BAR)
	draw_colored_polygon(UiKit.LowpolyBox.octagon(r.grow(2.0), 4.0), Color(0, 0, 0, 0.55))
	var fw := r.size.x * ratio
	if fw >= 2.0:  # 깎기를 폭의 절반 아래로 — 같으면 꼭짓점이 겹쳐 다각형이 깨진다
		draw_colored_polygon(UiKit.LowpolyBox.octagon(Rect2(r.position, Vector2(fw, r.size.y)), minf(3.0, (fw - 1.0) / 2.0)), UiKit.AMBER)
	var w := FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, BUILD_FONT).x
	var pos := Vector2(at.x - w / 2.0, r.position.y - 6.0)
	draw_string_outline(FONT, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, BUILD_FONT, 6, Color.WHITE)
	draw_string(FONT, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, BUILD_FONT, INK)
