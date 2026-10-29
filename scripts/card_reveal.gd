extends Control
## 모집 결과 카드 뒤집기(2026-10-07 디자인 보강 4번, 2026-10-15 "카드 뒤집히는게 답답해" — 더 빠르고 들썩이게): 영웅 카드(hero_card)를
## 자식으로 품고, 처음엔 뒷면(남색 각진 판 + 금 테 + 가운데 큰 보석 문양)을 그린다. 정해진 때(setup의 wait, 음수면 begin을 부를 때까지 뒷면)에
## 살짝 들리며(LIFT) 가로로 접혔다(FLIP_SEC 절반) 앞면으로 펴진다(살짝 크게 → 제자리). SR·SSR은 뒤집기 전 등급 빛이 뒷면 테두리에 번지고
## (SR TEASE_SEC, SSR은 더 길게 SSR_CHARGE 동안 모이며 떨린다), 펴지는 순간 카드가 번쩍이며 빛 조각이 퍼지고, SSR은 그 뒤로도 무지개빛 후광이
## 숨 쉬듯 돈다(SR은 잠깐 보랏빛). 최고 등급을 금색으로 꾸미지 않는다(사용자 2026-10-14). 참고: AFK 아레나·클래시 로얄(전설 = 무지개빛).
## 소리: 펴질 때 "card", SR "gacha_sr", SSR "gacha_ssr"(SoundFx). reveal_now(): 기다리지 않고 바로 앞면(탭으로 건너뛰기 — 창이 모든 카드에 부른다).
## 뒷면·펴지는 중에 누르면 skip_requested. 오토로드 없이 돈다(소리는 SoundFx가 있을 때만 — Sfx.play가 거른다).
## UR(2026-10-29 "UR은 개멋지게 뽑아줘"): SSR보다 길게(UR_CHARGE) 주황 불꽃빛이 모이며 세게 떨리고 뒷면에서 불씨가 오른다. 펴지면 더 밝게
## 번쩍이며 빛 조각이 두 배로 멀리 퍼지고 충격파 고리가 돈다. 그 뒤로 불꽃빛 후광이 일렁이며 불씨가 계속 오른다(소리 gacha_ssr + sk_boom).

const UiKit := preload("res://scripts/ui_kit.gd")
const LowpolyBox := preload("res://scripts/lowpoly_box.gd")
const Sfx := preload("res://scripts/sfx.gd")

const FLIP_SEC := 0.24  # 접힘 + 펴짐
const POP := 0.1  # 펴질 때 이만큼 더 크게(제자리로 줄어든다)
const LIFT := 0.12  # 뒤집는 동안 이만큼 들린다(크게)
const TEASE_SEC := 0.3  # SR: 뒤집기 전 등급 빛 예고
const SSR_CHARGE := 0.75  # SSR: 뒤집기 전 무지개빛이 모이며 떨린다
const UR_CHARGE := 1.1  # UR: 주황 불꽃빛이 더 오래 모인다
const UR_EMBERS := 8  # UR 카드에서 오르는 불씨 수
const FLASH_SEC := 0.4
const BURST_SEC := 0.6
const BURST_SHARDS := 16
const SR_GLOW_SEC := 1.2  # SR 후광이 사라지기까지
const GLOW_PX := 12.0  # 후광 두께(카드 밖으로)
const BACK := Color("2C3557")  # 뒷면 남색
const BACK_TRIM := Color("D9A531")  # 뒷면 금 테
const SummonStage := preload("res://scripts/summon_stage.gd")  # UR 불꽃빛(flame)

signal skip_requested
signal revealed(holder)

var card: Control  # hero_card.gd
var grade := "R"
var delay := 0.0  # 보이기 시작한 뒤 뒤집기 시작까지 초(음수 = begin을 기다린다)
var shown := false  # 앞면이 펴지기 시작했다(소리·조각 한 번)

var _t := 0.0
var _flip_at := 0.0  # 뒤집기 시작 시각(_t 기준)
var _sounded := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	resized.connect(func(): if card != null: card.pivot_offset = size / 2.0)


## 카드를 품고 뒷면부터 시작한다. wait초 뒤 뒤집는다(음수면 begin을 부를 때까지 뒷면 — 모집 창이 소환진이 걷힌 뒤 부른다).
func setup(c: Control, g: String, wait: float) -> void:
	card = c
	grade = g
	delay = wait
	_flip_at = INF if wait < 0.0 else wait
	card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card.pivot_offset = size / 2.0
	add_child(card)
	_apply()


## 지금부터 wait초 뒤 뒤집는다(SR·SSR은 등급 빛이 다 모일 만큼은 기다린다). 이미 뒤집기 시작했으면 그대로.
func begin(wait: float) -> void:
	if _t < _flip_at:
		_flip_at = _t + maxf(wait, tease_sec())


## 뒤집기 전 등급 빛이 모이는 시간.
func tease_sec() -> float:
	return {"UR": UR_CHARGE, "SSR": SSR_CHARGE, "SR": TEASE_SEC}.get(grade, 0.0)


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
		var pop := 1.0 + POP * sin(PI * clampf((k - 0.5) / 1.5, 0.0, 1.0)) + LIFT * (1.0 - e)  # 들린 채 펴지며 커졌다 줄어든다
		card.scale = Vector2(maxf(0.02, e) * pop, pop)
		var f := clampf(1.0 - (_t - _flip_at - FLIP_SEC * 0.5) / FLASH_SEC, 0.0, 1.0)
		var boost: float = {"UR": 1.3, "SSR": 0.9, "SR": 0.6}.get(grade, 0.35)
		card.modulate = Color(1.0 + boost * f, 1.0 + boost * f, 1.0 + boost * f)
	queue_redraw()


func _sound() -> void:
	Sfx.play("card")
	if grade == "UR":
		Sfx.play("gacha_ssr")
		Sfx.play("sk_boom")
	elif grade == "SSR":
		Sfx.play("gacha_ssr")
	elif grade == "SR":
		Sfx.play("gacha_sr")


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var gc: Color = UiKit.GRADE_COLORS.get(grade, UiKit.GRADE_COLORS.R)
	var k := (_t - _flip_at) / FLIP_SEC
	var rare := grade == "SR" or grade == "SSR" or grade == "UR"
	if k >= 0.5:  # 앞면 뒤: SSR 무지개빛 후광(숨 쉬듯 돌며, 계속), UR 불꽃빛 후광(일렁이며, 계속), SR 보랏빛 후광(잠깐), 펴질 때 빛 조각
		var since := _t - _flip_at - FLIP_SEC * 0.5
		var glow := 0.0
		if grade == "UR":
			glow = 0.8 + 0.12 * sin(_t * 7.0) + 0.08 * sin(_t * 17.0)
		elif grade == "SSR":
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
		if grade == "UR":
			_draw_embers(r, 1.0)
		return
	# 뒷면(접히는 중이면 들리며 가로로 줄인다)
	var lift := 1.0 + LIFT * clampf(k * 2.0, 0.0, 1.0)
	var sx := (1.0 if k < 0.0 else maxf(0.02, 1.0 - k * 2.0)) * lift
	var shake := Vector2.ZERO
	var tease := 0.0
	if rare:
		tease = clampf(1.0 - (_flip_at - _t) / tease_sec(), 0.0, 1.0)
		if (grade == "SSR" or grade == "UR") and tease > 0.0:
			shake = Vector2(sin(_t * 60.0), cos(_t * 47.0)) * (7.0 if grade == "UR" else 4.0) * tease * tease
	draw_set_transform(size / 2.0 + shake, 0.0, Vector2(sx, lift))
	var c := Rect2(-size / 2.0, size)
	if tease > 0.0:  # 등급 빛이 테두리에서 번진다
		_draw_glow(c, gc, tease)
	var geo := UiKit.facet_card_geometry(c, BACK_TRIM, BACK)
	RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), PackedInt32Array(), geo[0], geo[1])
	draw_polyline(geo[2], BACK.darkened(0.5), UiKit.CARD_OUTLINE_W, true)
	var inner := LowpolyBox.octagon(c.grow(-9.0), 8.0)  # 안쪽 금 선
	inner.append(inner[0])
	draw_polyline(inner, Color(BACK_TRIM, 0.7), 1.5, true)
	var gem_col := BACK_TRIM.lerp(_glow_color(gc, 0), tease) if rare else BACK_TRIM
	var gem := UiKit.gem_geometry(Vector2.ZERO, minf(size.x, size.y) * 0.2, gem_col, 6)
	RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), PackedInt32Array(), gem[0], gem[1])
	draw_polyline(gem[2], gem_col.darkened(0.5), 2.0, true)
	for i in 4:  # 보석 둘레 작은 마름모 넷
		var d := Vector2.from_angle(PI / 4.0 + TAU * i / 4.0) * minf(size.x, size.y) * 0.33
		var s := 5.0
		draw_colored_polygon(PackedVector2Array([d + Vector2(0, -s), d + Vector2(s, 0), d + Vector2(0, s), d + Vector2(-s, 0)]), Color(BACK_TRIM, 0.8))
	draw_set_transform(Vector2.ZERO)
	if grade == "UR" and tease > 0.0:
		_draw_embers(Rect2(Vector2.ZERO, size), tease)


## 카드 둘레 등급 빛 띠(팔각 테 3겹 — 바깥일수록 넓고 옅다, 안은 비어 있다). r = 카드 칸, a = 세기 0..1.
## SSR은 꼭짓점마다 다른 무지개 색이 돈다(금색 후광 대신). UR은 불꽃빛으로 더 두껍다.
func _draw_glow(r: Rect2, gc: Color, a: float) -> void:
	for i in 3:
		var w := GLOW_PX * (3 - i) / 3.0 * (1.7 if grade == "UR" else 1.0)
		var ring := LowpolyBox.octagon(r.grow(w * 0.5), 12.0 + w * 0.3)
		ring.append(ring[0])
		if grade == "SSR" or grade == "UR":
			var cols := PackedColorArray()
			for j in ring.size():
				cols.append(Color(_glow_color(gc, j % 8).lightened(0.12 * i), a * (0.3 + 0.25 * i)))
			draw_polyline_colors(ring, cols, w, true)
		else:
			draw_polyline(ring, Color(gc.lightened(0.12 * i), a * (0.3 + 0.25 * i)), w, true)


## 빛 색: SSR은 무지개(꼭짓점 j마다, 시간에 따라 돈다), UR은 불꽃빛(더 빨리 일렁인다), 나머지는 등급 색.
func _glow_color(gc: Color, j: int) -> Color:
	if grade == "UR":
		return SummonStage.flame(j / 8.0 + _t * 0.6)
	if grade != "SSR":
		return gc
	return Color.from_hsv(fposmod(j / 8.0 + _t * 0.35, 1.0), 0.5, 1.0)


## 빛 조각: 카드 가운데에서 바깥으로 날아가며 작아지고 흐려지는 등급 색·흰 삼각형(방향은 조각 번호 해시).
## UR은 조각이 두 배로 크고 멀리 날며, 충격파 고리가 퍼진다.
func _draw_burst(r: Rect2, gc: Color, t: float) -> void:
	var c := r.get_center()
	var ur := grade == "UR"
	var reach := r.size.y * (1.1 if ur else 0.7)
	var shards := BURST_SHARDS * (2 if ur else 1)
	if ur:
		var ring := LowpolyBox.octagon(r.grow(r.size.y * 0.5 * t), 12.0)
		ring.append(ring[0])
		draw_polyline(ring, Color(SummonStage.flame(t * 0.5 + 0.3), 1.0 - t), 10.0 * (1.0 - t) + 1.0, true)
	for i in shards:
		var dir := Vector2.from_angle(TAU * i / shards + LowpolyBox.hash01(i, 7) * 0.4)
		var p := c + dir * reach * (0.25 + 0.75 * t) * (0.7 + 0.3 * LowpolyBox.hash01(i, 9))
		var s := (12.0 if ur else 9.0) * (1.0 - t * 0.6)
		var col := _glow_color(gc, i).lightened(0.35) if i % 2 == 0 else Color.WHITE
		col.a = 1.0 - t
		draw_colored_polygon(PackedVector2Array([p + dir * s, p + dir.orthogonal() * s * 0.5, p - dir.orthogonal() * s * 0.5]), col)


## UR 불씨: 카드 아래 반에서 위로 오르며 흔들리고 흐려지는 불꽃빛 마름모. a = 세기 0..1.
func _draw_embers(r: Rect2, a: float) -> void:
	for i in UR_EMBERS:
		var u := fmod(_t * (0.5 + 0.4 * LowpolyBox.hash01(i, 51)) + LowpolyBox.hash01(i, 52), 1.0)
		var px := r.position.x + r.size.x * (0.1 + 0.8 * LowpolyBox.hash01(i, 53)) + sin(_t * 3.0 + i) * 5.0
		var py := r.end.y - r.size.y * (0.2 + u * 1.0)
		var s := 2.5 + 3.0 * LowpolyBox.hash01(i, 54)
		draw_colored_polygon(PackedVector2Array([Vector2(px, py - s * 1.4), Vector2(px + s * 0.6, py), Vector2(px, py + s), Vector2(px - s * 0.6, py)]),
			SummonStage.flame(0.15 + 0.6 * LowpolyBox.hash01(i, 55), (1.0 - u) * 0.95 * a))
