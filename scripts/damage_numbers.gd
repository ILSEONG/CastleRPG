extends Node2D
## 떠오르는 피해·회복·회피 숫자(스펙 §3). hp_bars처럼 화면 공간 Node2D 하나가 모든 숫자를 그린다(숫자당 테두리 1 + 본문 1).
## 영웅·몬스터가 피해가 실제 적용되는 곳에서 정적 함수 DamageNumbers.pop(대상, 양, 종류)를 부른다(씬에 없으면 아무 일도 없다).
## 독은 대상별로 1초 모아 하나로 보인다. 스킬 이름 띠(개정 17 §3, banner)도 여기서 그린다: 머리 위 고유 색 띠 + 흰 글자.

enum Kind { HIT, CRIT, SKILL, POISON, HURT, DODGE, HEAL, BANNER }

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
const BANNER_LIFT := 0.9  # 띠는 숫자보다 이만큼(m) 위
const BANNER_PAD := Vector2(12, 4)
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

static var current  # 월드에 있는 하나(없으면 null)

var camera: Camera3D
var draws := 0  # 지난 프레임의 그리기 호출 수(테스트용)

var _list: Array = []   # 살아 있는 숫자 {pos: 월드, text, kind, age, dx}. 나이순
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


## 스킬 이름 띠 하나를 띄운다(LIFE초). color = 띠 색(영웅 고유 색).
static func banner(target, text: String, color: Color) -> void:
	if current == null or not is_instance_valid(target):
		return
	if current._list.size() >= MAX_NUMBERS:
		current._list.pop_front()
	current._list.append({"pos": current._anchor(target) + Vector3(0, BANNER_LIFT, 0), "text": text, "kind": Kind.BANNER, "age": 0.0, "dx": 0.0, "bg": color})


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
	for e in _list:
		e.age += delta
	while not _list.is_empty() and _list[0].age >= LIFE:
		_list.pop_front()
	for id in (_poison.keys() if not _poison.is_empty() else []):
		var p: Dictionary = _poison[id]
		p.age += delta
		if p.age >= POISON_SEC or not is_instance_valid(p.target) or not p.target.is_alive():
			_poison.erase(id)
			if roundi(p.sum) > 0:
				_push(p.pos, 0.0, p.sum, Kind.POISON)
	if not _list.is_empty() or _shown:  # 보일 게 없으면 다시 그리지 않는다(마지막 한 번은 지우려고 그린다)
		queue_redraw()
	_shown = not _list.is_empty()


func _draw() -> void:
	draws = 0
	if camera == null or _list.is_empty():
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
		if e.kind == Kind.BANNER:
			var bg: Color = e.bg
			bg.a = alpha * 0.85
			draw_rect(Rect2(pos - Vector2(BANNER_PAD.x, size * 0.8 + BANNER_PAD.y), Vector2(text_w + BANNER_PAD.x * 2.0, size + BANNER_PAD.y * 2.0)), bg)
			draws += 1
		draw_string_outline(font, pos, e.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 6, oc)
		draw_string(font, pos, e.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
		draws += 2
