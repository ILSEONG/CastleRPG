extends Control
## 모집 결과 카드 뒤집기(2026-10-07 디자인 보강 4번): 영웅 카드(hero_card)를 자식으로 품고, 처음엔 뒷면(남색 각진 판 + 금 테 + 가운데 큰 보석 문양)을
## 그린다. delay초 뒤 가로로 접혔다(FLIP_SEC 절반) 앞면으로 펴진다(살짝 크게 → 제자리). SR·SSR은 뒤집기 전 TEASE_SEC 동안 뒷면 테두리에 그 등급 빛이
## 번지고(SSR은 떨린다), 펴지는 순간 카드가 번쩍이며(modulate) 빛 조각이 퍼지고, SSR은 그 뒤로도 금빛 후광이 숨 쉬듯 빛난다(SR은 잠깐).
## 소리: 펴질 때 "card", SR "gacha_sr", SSR "gacha_ssr"(SoundFx). reveal_now(): 기다리지 않고 바로 앞면(탭으로 건너뛰기 — 창이 모든 카드에 부른다).
## 뒷면·펴지는 중에 누르면 skip_requested. 오토로드 없이 돈다(소리는 SoundFx가 있을 때만 — Sfx.play가 거른다).

const UiKit := preload("res://scripts/ui_kit.gd")
const LowpolyBox := preload("res://scripts/lowpoly_box.gd")
const Sfx := preload("res://scripts/sfx.gd")

const FLIP_SEC := 0.32  # 접힘 + 펴짐
const POP := 0.08  # 펴질 때 이만큼 더 크게(제자리로 줄어든다)
const TEASE_SEC := 0.45  # SR·SSR: 뒤집기 전 등급 빛 예고
const FLASH_SEC := 0.4
const BURST_SEC := 0.6
const BURST_SHARDS := 16
const SR_GLOW_SEC := 1.2  # SR 후광이 사라지기까지
const GLOW_PX := 12.0  # 후광 두께(카드 밖으로)
const BACK := Color("2C3557")  # 뒷면 남색
const BACK_TRIM := Color("D9A531")  # 뒷면 금 테

signal skip_requested
signal revealed(holder)

var card: Control  # hero_card.gd
var grade := "R"
var delay := 0.0  # 보이기 시작한 뒤 뒤집기 시작까지 초
var shown := false  # 앞면이 펴지기 시작했다(소리·조각 한 번)

var _t := 0.0
var _flip_at := 0.0  # 뒤집기 시작 시각(_t 기준)
var _sounded := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	resized.connect(func(): if card != null: card.pivot_offset = size / 2.0)


## 카드를 품고 뒷면부터 시작한다. delay초 뒤 뒤집는다.
func setup(c: Control, g: String, wait: float) -> void:
	card = c
	grade = g
	delay = wait
	_flip_at = wait
	card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card.pivot_offset = size / 2.0
	add_child(card)
	_apply()


## 기다리지 않고 바로 앞면(이미 펴졌으면 그대로).
func reveal_now() -> void:
	if _t < _flip_at:
		_flip_at = _t
	_t = maxf(_t, _flip_at + FLIP_SEC)
	_apply()


## 앞면이 다 펴졌다(연출은 남아 있어도).
func is_revealed() -> bool:
	return _t >= _flip_at + FLIP_SEC


func _gui_input(event: InputEvent) -> void:
	if not is_revealed() and event is InputEventMouseButton and event.pressed:
		skip_requested.emit()


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_t += delta
	_apply()


## 지금 시각에 맞춰 카드 앞면 보임·가로 배율·번쩍임을 둔다.
func _apply() -> void:
	var k := (_t - _flip_at) / FLIP_SEC  # < 0 뒷면, 0~0.5 접힘, 0.5~1 펴짐
	var front := k >= 0.5
	card.visible = front
	if front:
		if not _sounded:
			_sounded = true
			shown = true
			_sound()
			revealed.emit(self)
		var e := clampf((k - 0.5) * 2.0, 0.0, 1.0)  # 펴짐 0 → 1
		var pop := 1.0 + POP * sin(PI * clampf((k - 0.5) / 1.5, 0.0, 1.0))  # 펴지며 커졌다 줄어든다
		card.scale = Vector2(maxf(0.02, e) * pop, pop)
		var f := clampf(1.0 - (_t - _flip_at - FLIP_SEC * 0.5) / FLASH_SEC, 0.0, 1.0)
		var boost := 0.9 if grade == "SSR" else (0.6 if grade == "SR" else 0.35)
		card.modulate = Color(1.0 + boost * f, 1.0 + boost * f, 1.0 + boost * f)
	queue_redraw()


func _sound() -> void:
	Sfx.play("card")
	if grade == "SSR":
		Sfx.play("gacha_ssr")
	elif grade == "SR":
		Sfx.play("gacha_sr")


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var gc: Color = UiKit.GRADE_COLORS.get(grade, UiKit.GRADE_COLORS.R)
	var k := (_t - _flip_at) / FLIP_SEC
	var rare := grade == "SR" or grade == "SSR"
	if k >= 0.5:  # 앞면 뒤: SSR 금빛 후광(숨 쉬듯, 계속), SR 보랏빛 후광(잠깐), 펴질 때 빛 조각
		var since := _t - _flip_at - FLIP_SEC * 0.5
		var glow := 0.0
		if grade == "SSR":
			glow = 0.75 + 0.25 * sin(_t * 4.0)
		elif grade == "SR":
			glow = clampf(1.0 - since / SR_GLOW_SEC, 0.0, 1.0)
		if glow > 0.0:  # 카드처럼 가로로 펴진다
			draw_set_transform(size / 2.0, 0.0, card.scale)
			_draw_glow(Rect2(-size / 2.0, size), gc, glow)
			draw_set_transform(Vector2.ZERO)
		var bt := since / BURST_SEC
		if rare and bt < 1.0:
			_draw_burst(r, gc, bt)
		return
	# 뒷면(접히는 중이면 가로로 줄인다)
	var sx := 1.0 if k < 0.0 else maxf(0.02, 1.0 - k * 2.0)
	var shake := Vector2.ZERO
	var tease := 0.0
	if rare:
		tease = clampf(1.0 - (_flip_at - _t) / TEASE_SEC, 0.0, 1.0)
		if grade == "SSR" and tease > 0.0:
			shake = Vector2(sin(_t * 60.0), cos(_t * 47.0)) * 2.0 * tease
	draw_set_transform(size / 2.0 + shake, 0.0, Vector2(sx, 1.0))
	var c := Rect2(-size / 2.0, size)
	if tease > 0.0:  # 등급 빛이 테두리에서 번진다
		_draw_glow(c, gc, tease)
	var geo := UiKit.facet_card_geometry(c, BACK_TRIM, BACK)
	RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), PackedInt32Array(), geo[0], geo[1])
	draw_polyline(geo[2], BACK.darkened(0.5), UiKit.CARD_OUTLINE_W, true)
	var inner := LowpolyBox.octagon(c.grow(-9.0), 8.0)  # 안쪽 금 선
	inner.append(inner[0])
	draw_polyline(inner, Color(BACK_TRIM, 0.7), 1.5, true)
	var gem_col := BACK_TRIM.lerp(gc, tease) if rare else BACK_TRIM
	var gem := UiKit.gem_geometry(Vector2.ZERO, minf(size.x, size.y) * 0.2, gem_col, 6)
	RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), PackedInt32Array(), gem[0], gem[1])
	draw_polyline(gem[2], gem_col.darkened(0.5), 2.0, true)
	for i in 4:  # 보석 둘레 작은 마름모 넷
		var d := Vector2.from_angle(PI / 4.0 + TAU * i / 4.0) * minf(size.x, size.y) * 0.33
		var s := 5.0
		draw_colored_polygon(PackedVector2Array([d + Vector2(0, -s), d + Vector2(s, 0), d + Vector2(0, s), d + Vector2(-s, 0)]), Color(BACK_TRIM, 0.8))
	draw_set_transform(Vector2.ZERO)


## 카드 둘레 등급 빛 띠(팔각 테 3겹 — 바깥일수록 넓고 옅다, 안은 비어 있다). r = 카드 칸, a = 세기 0..1.
func _draw_glow(r: Rect2, gc: Color, a: float) -> void:
	for i in 3:
		var w := GLOW_PX * (3 - i) / 3.0
		var ring := LowpolyBox.octagon(r.grow(w * 0.5), 12.0 + w * 0.3)
		ring.append(ring[0])
		draw_polyline(ring, Color(gc.lightened(0.12 * i), a * (0.3 + 0.25 * i)), w, true)


## 빛 조각: 카드 가운데에서 바깥으로 날아가며 작아지고 흐려지는 등급 색·흰 삼각형(방향은 조각 번호 해시).
func _draw_burst(r: Rect2, gc: Color, t: float) -> void:
	var c := r.get_center()
	var reach := r.size.y * 0.7
	for i in BURST_SHARDS:
		var dir := Vector2.from_angle(TAU * i / BURST_SHARDS + LowpolyBox.hash01(i, 7) * 0.4)
		var p := c + dir * reach * (0.25 + 0.75 * t) * (0.7 + 0.3 * LowpolyBox.hash01(i, 9))
		var s := 9.0 * (1.0 - t * 0.6)
		var col := gc.lightened(0.35) if i % 2 == 0 else Color.WHITE
		col.a = 1.0 - t
		draw_colored_polygon(PackedVector2Array([p + dir * s, p + dir.orthogonal() * s * 0.5, p - dir.orthogonal() * s * 0.5]), col)
