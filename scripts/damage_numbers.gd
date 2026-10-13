extends Node2D
## 떠오르는 피해·회복·회피 숫자(스펙 §3). hp_bars처럼 화면 공간 Node2D 하나가 모든 숫자를 그린다(숫자당 테두리 1 + 본문 1).
## 영웅·몬스터가 피해가 실제 적용되는 곳에서 정적 함수 DamageNumbers.pop(대상, 양, 종류)를 부른다(씬에 없으면 아무 일도 없다).
## 독은 대상별로 1초 모아 하나로 보인다. 스킬 표시(개정 17 §3, 2026-10-12 사용자 "전부 적용" 개편)도 여기서 그린다 — 숫자보다 위에:
##  - 이름 띠(banner, 액티브·한 판 한 번 패시브): 머리 위 깎인 모서리 상자(영웅 색, 어두운 테두리) + 스킬 그림 + 흰 이름, 1.2초.
##    상대 팀(team 1)은 작게 + 어두운 바탕·붉은 테두리. 띠끼리 겹치면 위로 밀고, 화면 밖으로 나가지 않게 안으로 들인다.
##  - 확률 패시브(text = ""): 이름 없이 스킬 그림 동그라미만 0.8초.
##  - 컷인(cutin, 우리 편 SSR 궁극기): 화면 왼쪽 가운데로 스킬 이름 띠가 미끄러져 들어왔다 나간다. 한 번에 하나, CUTIN_GAP초 간격.
##    2026-10-13 개편: 띠·창은 로우폴리 면(면마다 밝기 조금씩), 속도선 대신 뾰족한 조각, 위아래 금 테, 외곽선은 같은 색을 어둡게.
##    왼쪽은 띠 위로 솟은 금빛 창(도는 빛살 — 금·흰 빛 영웅은 짙은 남보라)이고 그 안에 영웅 일러스트(HeroArt)가 들어간다 — 빛살은 일러스트를
##    두른 테두리로 보인다. 같은 날 잠깐 게임 속 모델 자세로 바꿨다가 사용자 "멋없는걸로 하지말고 일러스트를 써"로 일러스트로 돌아왔다.

enum Kind { HIT, CRIT, SKILL, POISON, HURT, DODGE, HEAL, BANNER }  # BANNER = 스킬 표시(_tags)

const MAX_NUMBERS := 80
const LIFE := 0.8
const RISE := 32.0
const FADE_FROM := 0.6          # 수명 비율: 마지막 40%에 사라진다
const POP_SEC := 0.14
const CRIT_POP_SCALE := 1.8
const SKILL_POP_SCALE := 1.45
const SHAKE := 12.0
const POISON_SEC := 1.0
const SCREEN_MARGIN := 40.0
const BANNER_LIFE := 1.2  # 이름 띠 수명(초) — 마지막 TAG_FADE에 사라진다
const PROC_LIFE := 0.8  # 확률 패시브 그림 수명(초)
const TAG_FADE := 0.25
const TAG_POP := 0.12  # 처음 이 초 동안 크게 튀어나왔다 줄어든다
const TAG_POP_SCALE := 1.25
const TAG_UP := 40.0  # 띠 아랫변 = 머리(HP 바) 화면 위치에서 이만큼(px) 위
const TAG_RISE := 14.0  # 수명 동안 떠오르는 높이(px)
const TAG_GAP := 3.0  # 겹친 띠를 밀 때 띠 사이 간격(px)
const TAG_EDGE := 6.0  # 화면 가장자리 여백(px)
const TAG_SLIDE := 900.0  # 밀린 띠가 새 자리로 옮겨 가는 속도(px/초)
const MAX_TAGS := 24
const BANNER_PAD := Vector2(10, 5)
## [글자 크기, 그림 반지름] — 우리 편 / 상대 팀
const TAG_MINE := [24, 14.0]
const TAG_ENEMY := [18, 10.0]
const ENEMY_FILL := Color(0.17, 0.15, 0.20)
const ENEMY_EDGE := Color(0.90, 0.26, 0.22)
const CUTIN_LIFE := 1.3  # 컷인 전체 시간(초)
const CUTIN_IN := 0.16  # 들어오는 시간
const CUTIN_OUT := 0.2  # 나가는 시간
const CUTIN_GAP := 5.0  # 컷인 사이 최소 간격(실제 초)
const CUTIN_Y := 0.205  # 띠 윗변 = 화면 높이 × 이 값(위 정보 패널 아래, 화면 가운데 싸움은 가리지 않게)
const CUTIN_H := 128.0  # 띠 높이
const CUTIN_POP := 54.0  # 금빛 창이 띠 위로 솟는 높이(위 정보 패널 아래까지만)
const CUTIN_PANEL := 236.0  # 금빛 창(띠 왼쪽 부분) 윗변 폭
const CUTIN_FRAME := 9.0  # 일러스트 둘레 금빛 창 테두리 두께(빛살이 보이는 곳)
const CUTIN_RAYS := 12  # 금빛 창 빛살 수(천천히 돈다)
const CUTIN_SSR := Color(0.93, 0.66, 0.18)  # 금빛 창: SSR 등급 금색 계열(SSR 카드 창과 같은 결)
const CUTIN_NIGHT := Color(0.25, 0.22, 0.42)  # 금·흰 빛 영웅(일러스트가 금빛 창에 묻힌다 — pale_hero) 창: 짙은 남보라 + 금빛 빛살
const CUTIN_ZOOM := [1.16, 1.06]  # 일러스트 확대: 들어올 때 → 끝날 때(천천히 물러나며 움직임)
const CUTIN_CELL := 84.0  # 띠 로우폴리 면 한 칸 폭(px)
const CUTIN_SLANT := 40.0  # 기울어진 오른쪽 변의 가로 폭
const CUTIN_GOLD := Color(0.96, 0.78, 0.32)
const OUTLINE := Color(0.10, 0.08, 0.12)
const FONT := preload("res://assets/fonts/Pretendard-SemiBold.otf")
## 종류 → [색, 글자 크기]
const STYLE := {
	Kind.HIT: [Color(1, 1, 1), 22], Kind.CRIT: [Color(1.0, 0.62, 0.15), 30], Kind.SKILL: [Color(1.0, 0.9, 0.25), 24],
	Kind.POISON: [Color(0.45, 0.9, 0.35), 16], Kind.HURT: [Color(0.95, 0.25, 0.22), 22],
	Kind.DODGE: [Color(0.7, 0.7, 0.72), 22], Kind.HEAL: [Color(0.45, 0.95, 0.5), 22], Kind.BANNER: [Color(1, 1, 1), 24],
}
const CACHE_MAX := 512
const Prefs := preload("res://scripts/prefs.gd")  # 설정 [피해 숫자 표시]를 끄면 숫자를 띄우지 않는다(스킬 이름 띠는 그대로)
const Sfx := preload("res://scripts/sfx.gd")  # 타격 소리(숫자를 꺼도 난다)
const SkillIcons := preload("res://scripts/skill_icons.gd")
const LowpolyBox := preload("res://scripts/lowpoly_box.gd")
const HeroArt := preload("res://scripts/hero_art.gd")

static var current  # 월드에 있는 하나(없으면 null)

var camera: Camera3D
var draws := 0  # 지난 프레임의 그리기 호출 수(테스트용)
var tag_rects: Array = []  # 지난 프레임에 그린 스킬 표시 자리(Rect2, 테스트용)

var _list: Array = []   # 살아 있는 숫자 {pos: 월드, text, kind, age, dx}. 나이순
var _tags: Array = []   # 스킬 표시 {pos: 월드, text(""면 그림만), skill, kind = BANNER, age, life, bg = 영웅 색, enemy, lift}. 나이순
var _cut := {}          # 지금 컷인 {hero, text, sub, bg, skill, age}(없으면 비어 있다)
var _cut_ms := -1000000  # 마지막 컷인 시작(ms)
var _glyphs := {}       # 그림 이름 → SkillIcons.shapes(매 프레임 새로 만들지 않게)
var _dt := 0.0
var _poison := {}       # 대상 id → {target, sum, age, pos}
var _shown := false
var _cache := {}        # 정수 → 문자열


func _enter_tree() -> void:
	current = self


func _exit_tree() -> void:
	if current == self:
		current = null


## 피해·회복 하나를 알린다. amount는 반올림해 0이면 생략(회피 제외).
static func pop(target, amount: float, kind: int) -> void:
	if current != null and is_instance_valid(target):
		Sfx.damage(target, kind)
	if current != null and Prefs.get_bool("damage_numbers") and is_instance_valid(target):
		current.add(target, amount, kind)


## 스킬 표시 하나를 띄운다. text가 ""면 이름 없이 스킬 그림만(확률 패시브). color = 영웅 고유 색, enemy = 상대 팀(작게·붉은 테두리).
static func banner(target, skill: String, text: String, color: Color, enemy := false) -> void:
	if current == null or not is_instance_valid(target):
		return
	if current._tags.size() >= MAX_TAGS:
		current._tags.pop_front()
	current._tags.append({"pos": current._anchor(target), "text": text, "skill": skill, "kind": Kind.BANNER, "age": 0.0,
		"life": BANNER_LIFE if text != "" else PROC_LIFE, "bg": color, "enemy": enemy, "lift": 0.0})


## 우리 편 SSR 궁극기 컷인. 이미 하나가 떠 있거나 CUTIN_GAP초가 안 지났으면 건너뛴다(쌓아 두지 않는다).
static func cutin(hero_id: String, text: String, sub: String, color: Color, skill: String) -> void:
	if current == null:
		return
	var now := Time.get_ticks_msec()
	if not current._cut.is_empty() or now - current._cut_ms < int(CUTIN_GAP * 1000.0):
		return
	current._cut_ms = now
	current._cut = {"hero": hero_id, "text": text, "sub": sub, "bg": color, "skill": skill, "age": 0.0}


## 띠 바탕색: 영웅 색이 밝으면(노랑·연두 …) 흰 글자가 읽히게 어둡게 누른다.
static func band_color(c: Color) -> Color:
	var b := Color(c, 1.0)
	for i in 8:
		if b.get_luminance() <= 0.4:
			break
		b = b.darkened(0.12)
	return b


func add(target, amount: float, kind: int) -> void:
	if kind == Kind.POISON:
		var id: int = target.get_instance_id()
		var e = _poison.get(id)  # 틱마다 새 사전을 만들지 않는다
		if e == null:
			e = {"target": target, "sum": 0.0, "age": 0.0, "pos": Vector3.ZERO}
			_poison[id] = e
		e.sum += amount
		e.pos = _anchor(target)
		return
	if kind != Kind.DODGE and roundi(amount) <= 0:
		return
	# 같은 대상의 연속 숫자는 좌우로 돌아가며 흔든다
	var n: int = int(target.get_meta("dn_n", 0)) + 1
	target.set_meta("dn_n", n)
	_push(_anchor(target), [0.0, -SHAKE, SHAKE][n % 3], amount, kind)


func _anchor(target) -> Vector3:
	return target.global_position + Vector3(0, target.bar_height(), 0)


func _push(pos: Vector3, dx: float, amount: float, kind: int) -> void:
	var text := "회피" if kind == Kind.DODGE else format(amount)
	if kind == Kind.CRIT:
		text += "!"
	elif kind == Kind.HEAL:
		text = "+" + text
	if _list.size() >= MAX_NUMBERS:
		_list.pop_front()  # 가장 오래된 것
	_list.append({"pos": pos, "text": text, "kind": kind, "age": 0.0, "dx": dx})


## 반올림 정수. 1000 이상은 "1.2k". 문자열은 캐시한다.
func format(v: float) -> String:
	var n := roundi(v)
	if _cache.has(n):
		return _cache[n]
	if _cache.size() >= CACHE_MAX:
		_cache.clear()
	var s := "%.1fk" % (n / 1000.0) if n >= 1000 else str(n)
	_cache[n] = s
	return s


func _process(delta: float) -> void:
	_dt = delta
	for e in _list:
		e.age += delta
	while not _list.is_empty() and _list[0].age >= LIFE:
		_list.pop_front()
	for e in _tags:
		e.age += delta
	var i := 0
	while i < _tags.size():  # 수명이 둘(이름 1.2초·그림 0.8초)이라 앞에서만 빼지 않는다
		if _tags[i].age >= _tags[i].life:
			_tags.remove_at(i)
		else:
			i += 1
	if not _cut.is_empty():
		_cut.age += delta
		if _cut.age >= CUTIN_LIFE:
			_cut = {}
	for id in (_poison.keys() if not _poison.is_empty() else []):
		var p: Dictionary = _poison[id]
		p.age += delta
		if p.age >= POISON_SEC or not is_instance_valid(p.target) or not p.target.is_alive():
			_poison.erase(id)
			if roundi(p.sum) > 0:
				_push(p.pos, 0.0, p.sum, Kind.POISON)
	var any := not _list.is_empty() or not _tags.is_empty() or not _cut.is_empty()
	if any or _shown:  # 보일 게 없으면 다시 그리지 않는다(마지막 한 번은 지우려고 그린다)
		queue_redraw()
	_shown = any


func _draw() -> void:
	draws = 0
	if camera == null:
		return
	_draw_numbers()
	_draw_tags()
	if not _cut.is_empty():
		_draw_cutin()


func _draw_numbers() -> void:
	if _list.is_empty():
		return
	var view := get_viewport_rect().grow(SCREEN_MARGIN)
	var font: Font = FONT
	for e in _list:
		if camera.is_position_behind(e.pos):
			continue
		var t: float = e.age / LIFE
		var p := camera.unproject_position(e.pos) + Vector2(e.dx, -RISE * t)
		if not view.has_point(p):
			continue
		var st: Array = STYLE[e.kind]
		var size: int = st[1]
		if (e.kind == Kind.CRIT or e.kind == Kind.SKILL) and e.age < POP_SEC:  # 치명타·스킬 숫자는 크게 튀어나왔다 줄어든다(개정 26)
			size = roundi(size * lerpf(CRIT_POP_SCALE if e.kind == Kind.CRIT else SKILL_POP_SCALE, 1.0, ease(e.age / POP_SEC, 0.4)))
		var alpha := 1.0 if t < FADE_FROM else 1.0 - (t - FADE_FROM) / (1.0 - FADE_FROM)
		var col: Color = st[0]
		col.a = alpha
		var oc := OUTLINE
		oc.a = alpha
		var text_w := font.get_string_size(e.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var pos := p - Vector2(text_w / 2.0, 0.0)
		draw_string_outline(font, pos, e.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 6, oc)
		draw_string(font, pos, e.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
		draws += 2


## 스킬 표시: 나이순으로 자리를 잡는다(먼저 뜬 띠가 제자리, 겹치는 새 띠는 그 위로). 밀린 띠는 TAG_SLIDE 속도로 옮겨 간다.
func _draw_tags() -> void:
	tag_rects = []
	if _tags.is_empty():
		return
	var vw := get_viewport_rect().size
	var view := Rect2(Vector2.ZERO, vw).grow(SCREEN_MARGIN)
	var font: Font = FONT
	var placed: Array = []
	for e in _tags:
		if camera.is_position_behind(e.pos):
			continue
		var head := camera.unproject_position(e.pos)
		if not view.has_point(head):
			continue
		var t: float = e.age / e.life
		var pop := lerpf(TAG_POP_SCALE, 1.0, ease(minf(e.age / TAG_POP, 1.0), 0.4))
		var st: Array = TAG_ENEMY if e.enemy else TAG_MINE
		var size := roundi(int(st[0]) * pop)
		var r: float = float(st[1]) * pop
		var named: bool = e.text != ""
		var text_w := font.get_string_size(e.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x if named else 0.0
		var h := maxf(size + BANNER_PAD.y * 2.0, r * 2.0 + 6.0) if named else r * 2.0 + 4.0
		var w := (BANNER_PAD.x + r * 2.0 + 6.0 + text_w + BANNER_PAD.x) if named else h
		var rect := Rect2(head.x - w / 2.0, head.y - TAG_UP - TAG_RISE * t - h, w, h)
		rect.position.x = clampf(rect.position.x, TAG_EDGE, maxf(TAG_EDGE, vw.x - TAG_EDGE - w))
		var want := 0.0  # 겹침을 피하려 더 올릴 높이
		for k in 8:
			var moved := false
			for q in placed:
				var cur := Rect2(rect.position - Vector2(0, want), rect.size)
				if cur.intersects(q):
					want = rect.position.y - (q.position.y - TAG_GAP - h)
					moved = true
			if not moved:
				break
		e.lift = move_toward(e.lift, want, TAG_SLIDE * _dt) if want <= e.lift else want  # 위로는 바로, 내려올 땐 미끄러지게
		rect.position.y -= e.lift
		rect.position.y = maxf(rect.position.y, TAG_EDGE)
		placed.append(rect)
		tag_rects.append(rect)
		var alpha := 1.0 if t < 1.0 - TAG_FADE else (1.0 - t) / TAG_FADE
		var cy := rect.get_center().y
		if named:
			var fill: Color = ENEMY_FILL if e.enemy else band_color(e.bg)
			var edge: Color = ENEMY_EDGE if e.enemy else LowpolyBox.edge_color(fill)
			var box := LowpolyBox.octagon(rect, 6.0 * pop)
			draw_colored_polygon(box, Color(fill, 0.94 * alpha))
			box.append(box[0])
			draw_polyline(box, Color(edge, alpha), 2.0, true)
			_badge(Vector2(rect.position.x + BANNER_PAD.x + r, cy), r, e.skill, alpha)
			var base := Vector2(rect.position.x + BANNER_PAD.x + r * 2.0 + 6.0, cy + (font.get_ascent(size) - font.get_descent(size)) / 2.0)
			draw_string_outline(font, base, e.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 5, Color(OUTLINE, alpha))
			draw_string(font, base, e.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(1, 1, 1, alpha))
			draws += 5
		else:
			var ring: Color = ENEMY_EDGE if e.enemy else Color(1, 1, 1)
			draw_circle(rect.get_center(), r + 2.0, Color(ring, 0.9 * alpha))
			_badge(rect.get_center(), r, e.skill, alpha)
			draws += 2


## 스킬 그림 동그라미(SkillIcons.draw_badge와 같은 모양, 사라질 때 투명도를 따른다).
func _badge(at: Vector2, r: float, skill: String, alpha: float) -> void:
	draw_circle(at, r, Color(SkillIcons.bg_of(skill), alpha))
	var top := PackedVector2Array()
	for i in 13:
		top.append(at + Vector2.from_angle(PI + PI * i / 12.0) * r)
	draw_colored_polygon(top, Color(1, 1, 1, 0.14 * alpha))
	var glyph := SkillIcons.glyph_of(skill)
	if not _glyphs.has(glyph):
		_glyphs[glyph] = SkillIcons.shapes(glyph)
	var size_px := r * 1.5
	var line_w := maxf(1.0, size_px / 28.0)
	for shape in _glyphs[glyph]:
		var pts := PackedVector2Array()
		for q in shape[0]:
			pts.append(at + q * size_px)
		var col: Color = shape[1]
		if col.a > 0.0:
			draw_colored_polygon(pts, Color(col, col.a * alpha))
		if shape[2]:
			pts.append(pts[0])
			draw_polyline(pts, Color(SkillIcons.OUTLINE, alpha), line_w)


## 컷인: 왼쪽에서 기울어진 띠가 미끄러져 들어와 띠 위로 솟은 금빛 창 속 영웅 일러스트 + 영웅 이름 + 스킬 그림·이름을 보이고 왼쪽으로 빠진다.
## 그리는 순서: 띠 면 → 조각 → 금빛 창 면·빛살 → 위 금 테·외곽선 → 일러스트(창 안쪽, 깎은 오른위 모서리) → 아래 금 테 → 글자.
func _draw_cutin() -> void:
	var vs := get_viewport_rect().size
	var age: float = _cut.age
	var x := 0.0
	var alpha := 1.0
	if age < CUTIN_IN:
		x = -vs.x * (1.0 - ease(age / CUTIN_IN, 0.35))
	elif age > CUTIN_LIFE - CUTIN_OUT:
		var k := (age - (CUTIN_LIFE - CUTIN_OUT)) / CUTIN_OUT
		x = -vs.x * ease(k, 2.4)
		alpha = 1.0 - k
	var y0 := roundf(vs.y * CUTIN_Y)
	var y1 := y0 + CUTIN_H
	var bw := minf(vs.x * 0.9, 660.0)
	var band := band_color(_cut.bg)
	var edge := LowpolyBox.edge_color(band)
	var poly := PackedVector2Array([Vector2(x, y0), Vector2(x + bw, y0), Vector2(x + bw - CUTIN_SLANT, y1), Vector2(x, y1)])
	_facets(poly, band, 0.08, 7, alpha * 0.96)
	for i in 4:  # 조각: 가늘고 뾰족한 삼각형이 띠 안을 오른쪽 → 왼쪽으로 빠르게
		var sx := x + bw - fmod(age * 1400.0 + i * 190.0, bw)
		var sy := y0 + CUTIN_H * (0.24 + 0.18 * i)
		var ln := 54.0 + 26.0 * (i % 2)
		draw_colored_polygon(PackedVector2Array([Vector2(sx, sy), Vector2(sx + ln, sy - 3.0), Vector2(sx + ln, sy + 3.0)]), Color(band.lightened(0.55), 0.4 * alpha))
	# 금빛 창: 띠 위로 CUTIN_POP 솟고, 오른쪽 변은 띠와 같은 기울기. 로우폴리 면 + 도는 빛살(창 모양으로 잘라)
	var top := y0 - CUTIN_POP
	var slope := CUTIN_SLANT / CUTIN_H  # 아래로 1px 갈 때 왼쪽으로
	var pw := CUTIN_PANEL
	var panel := PackedVector2Array([Vector2(x, top), Vector2(x + pw, top), Vector2(x + pw - slope * (y1 - top), y1), Vector2(x, y1)])
	var pc := CUTIN_NIGHT if pale_hero(_cut.bg) else CUTIN_SSR
	_facets(panel, pc, 0.12, 11, alpha)
	var c := Vector2(x + pw * 0.45, (top + y1) * 0.5)
	var reach := pw * 1.5
	for i in CUTIN_RAYS:
		var a := age * 0.9 + TAU * i / CUTIN_RAYS
		var ray := PackedVector2Array([c, c + Vector2.from_angle(a) * reach, c + Vector2.from_angle(a + TAU / CUTIN_RAYS * 0.45) * reach])
		for part in Geometry2D.intersect_polygons(ray, panel):
			draw_colored_polygon(part, Color(CUTIN_SSR.lightened(0.6), 0.5 * alpha))
	_trim(Vector2(x, y0 - 1.0), Vector2(x + bw + 1.6, y0 - 1.0), 5.0, alpha)
	poly.append(poly[0])
	draw_polyline(poly, Color(edge, alpha), 2.0, true)
	_trim(Vector2(x, top - 1.0), Vector2(x + pw + 1.6, top - 1.0), 5.0, alpha)
	var pe := PackedVector2Array([panel[0], panel[1], panel[2]])
	draw_polyline(pe, Color(LowpolyBox.edge_color(pc), alpha), 2.5, true)
	# 일러스트: 창 안쪽(위·오른쪽·아래 CUTIN_FRAME, 왼쪽은 화면 끝), 오른위 모서리 깎음. 들어올 때 조금 당겨 있다가 천천히 물러난다
	var f := CUTIN_FRAME
	var wt := top + f + 5.0  # 위 금 테 아래
	var wb := y1 - f - 2.0
	var xr := func(y: float) -> float: return x + pw - slope * (y - top) - f * 1.15  # 그 높이의 창 오른쪽 안쪽 변
	var ch := 12.0
	var win := PackedVector2Array([Vector2(x - 2.0, wt), Vector2(xr.call(wt) - ch, wt), Vector2(xr.call(wt + ch), wt + ch),
		Vector2(xr.call(wb), wb), Vector2(x - 2.0, wb)])
	var wr := Rect2(x - 2.0, wt, xr.call(wt) + 2.0 - x, wb - wt)
	var zoom: float = lerpf(CUTIN_ZOOM[0], CUTIN_ZOOM[1], clampf(age / CUTIN_LIFE, 0.0, 1.0))
	if HeroArt.draw_in(self, _cut.hero, win, wr, 0.34, zoom):
		if alpha < 1.0:
			draw_colored_polygon(win, Color(band, 1.0 - alpha))  # 빠질 때 그림도 흐려지게
	else:
		draw_colored_polygon(win, Color(band.darkened(0.3), alpha))
		_badge(wr.get_center(), 44.0, _cut.skill, alpha)
	var wl := win.duplicate()
	wl.remove_at(0)
	draw_polyline(wl, Color(LowpolyBox.edge_color(pc), alpha), 2.0, true)  # 창 안쪽 선(왼쪽 화면 끝 빼고)
	_trim(Vector2(x, y1 - 4.0), Vector2(x + bw - CUTIN_SLANT, y1 - 4.0), 5.0, alpha)
	# 글자: 영웅 이름(작게) + 스킬 그림 + 스킬 이름(크게)
	var font: Font = FONT
	var tx := x + pw - CUTIN_SLANT * 0.5 + 16.0
	var room := x + bw - CUTIN_SLANT - 16.0 - tx
	draw_string_outline(font, Vector2(tx, y0 + 40.0), _cut.sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, 5, Color(edge, alpha))
	draw_string(font, Vector2(tx, y0 + 40.0), _cut.sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 1, 0.88 * alpha))
	var size := 40
	while size > 24 and font.get_string_size(_cut.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > room - 52.0:
		size -= 2
	_badge(Vector2(tx + 20.0, y0 + 86.0), 20.0, _cut.skill, alpha)
	var base := Vector2(tx + 50.0, y0 + 86.0 + (font.get_ascent(size) - font.get_descent(size)) / 2.0)
	draw_string_outline(font, base, _cut.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 8, Color(edge, alpha))
	draw_string(font, base, _cut.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(1, 1, 1, alpha))
	draws += 14


## 금빛 창에 일러스트가 묻히는 영웅인가(아르테온·루미나 같은 금빛, 프리다 같은 아주 밝은 색): 영웅 색의 밝기(HSL) ≥ 0.8이거나,
## ≥ 0.65이면서 노랑~금 색상(30~70°). 그러면 창을 짙은 남보라로.
static func pale_hero(c: Color) -> bool:
	var l := (maxf(c.r, maxf(c.g, c.b)) + minf(c.r, minf(c.g, c.b))) * 0.5
	return l >= 0.8 or (l >= 0.65 and c.h >= 30.0 / 360.0 and c.h <= 70.0 / 360.0)


## 사각형(4점: 왼위·오른위·오른아래·왼아래) 띠를 로우폴리 면으로: 위·아래 변에 CUTIN_CELL 간격 점(가운데 점은 조금 흔들고 아래는 반 칸
## 엇갈림)을 찍어 삼각형 띠로 잇고, 면마다 LowpolyBox.shade(왼위 밝게 + 해시).
func _facets(q: PackedVector2Array, base: Color, amt: float, seed: int, alpha: float) -> void:
	var n := maxi(2, roundi(q[0].distance_to(q[1]) / CUTIN_CELL))
	var top := PackedVector2Array()
	var bot := PackedVector2Array()
	for i in n + 1:
		var t := float(i) / n
		var tb := clampf((i - 0.5) / n, 0.0, 1.0) if i < n else 1.0
		var j := 0.0 if i == 0 or i == n else (LowpolyBox.hash01(seed, i) - 0.5) * 0.5 / n
		top.append(q[0].lerp(q[1], t + j))
		bot.append(q[3].lerp(q[2], tb))
	var r := Rect2(q[0], Vector2.ZERO).expand(q[1]).expand(q[2]).expand(q[3])
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	for i in n:
		for tri in [PackedVector2Array([top[i], top[i + 1], bot[i]]), PackedVector2Array([top[i + 1], bot[i + 1], bot[i]])]:
			var col := LowpolyBox.shade(base, tri, r, amt, seed, pts.size())
			for p in tri:
				pts.append(p)
				cols.append(Color(col, alpha))
	RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), PackedInt32Array(), pts, cols)


## 금 테(가로 띠 a → b, 두께 h): 위 반 밝게·아래 반 어둡게 + 진한 금 외곽선.
func _trim(a: Vector2, b: Vector2, h: float, alpha: float) -> void:
	draw_colored_polygon(PackedVector2Array([a, b, b + Vector2(-h * 0.2, h * 0.5), a + Vector2(0, h * 0.5)]), Color(CUTIN_GOLD.lightened(0.15), alpha))
	draw_colored_polygon(PackedVector2Array([a + Vector2(0, h * 0.5), b + Vector2(-h * 0.2, h * 0.5), b + Vector2(-h * 0.4, h), a + Vector2(0, h)]), Color(CUTIN_GOLD.darkened(0.12), alpha))
	draw_polyline(PackedVector2Array([a, b, b + Vector2(-h * 0.4, h), a + Vector2(0, h), a]), Color(LowpolyBox.edge_color(CUTIN_GOLD), alpha), 1.2, true)
