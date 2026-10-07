extends Node3D
## 길드 보스 드래곤 모델(Meshy, dev/meshy_dragon_fit.py). 사람 모양이 아니라 KayKit 뼈대·자동 리깅을 못 써서, 부품(Body·WingL·WingR·Neck·Tail·ArmL·ArmR,
## 노드 원점 = 관절)을 코드로 움직인다: 대기(숨쉬기·날갯짓·목·꼬리 흔들기), 공격 셋(앞발 할퀴기·불 뿜기·날개 바람, 무작위), 피격 번쩍임, 쓰러짐.
## monster.gd가 쓰는 UnitModel 메서드(play_idle·play_walk·play_attack·hit_react·play_death·face)를 같은 뜻으로 낸다. 정면 +Z.
## 공격 연출의 이펙트(불·바람)는 dragon.gd가 타격 순간에 낸다(mouth()·attack_kind()).

const Art := preload("res://scripts/art.gd")
const HitFlashShader := preload("res://shaders/hit_flash.gdshader")
const UnitModelScript := preload("res://scripts/unit_model.gd")

const SCENE := "res://assets/models/meshy/enemies/dragon.glb"
const PARTS := ["Body", "WingL", "WingR", "Neck", "Tail", "ArmL", "ArmR"]
const ATTACKS := ["claw", "breath", "gust"]  # claw = 앞발 할퀴기(예전 물기 자리, 노린 영웅 한 명)
const HIT_FRAC := {"claw": 0.55, "breath": 0.45, "gust": 0.5}  # 모션 중 타격 순간(예전과 같다)
const HIND_Z := -0.13  # 뒷발 위치(키 1 기준 z) — 일어설 때 축
const HIT_FLASH_SEC := 0.14
const HIT_FLASH_GAP_MS := 260
const TURN_RATE := 5.0  # 몸 돌리기 부드러움(1/초) — 노리는 영웅이 바뀌어도 한 프레임에 홱 돌지 않고 따라 돈다

var size := 5.0  # 키(m) — 부품 GLB는 키 1로 맞춰져 있다. add_child 전에
var attack_kind := ""  # 지금(마지막) 공격 모션
var claw_side := 1.0  # 할퀴는 앞발: 1 = 오른발(+X), −1 = 왼발
var _parts := {}  # 이름 → Node3D(관절)
var _rest := {}  # 이름 → 처음 회전
var _t := 0.0
var _act := ""  # "" · 공격 이름 · "death"
var _act_t := 0.0
var _act_len := 1.0
var _atk_i := -1
var _flash_at := -100000
var _flash_meshes: Array = []
var _hit_tw: Tween
var _flash_mat: ShaderMaterial
var _base_scale := Vector3.ONE
var _want_yaw := NAN  # face()가 정한 방향 — _process가 부드럽게 따라 돈다


func _ready() -> void:
	scale = Vector3.ONE * size
	_base_scale = scale
	var src := Art.instance(SCENE)
	Art.stylize(src)
	add_child(src)
	for n in PARTS:
		var p := src.get_node_or_null(n) as Node3D
		if p != null:
			_parts[n] = p
			_rest[n] = p.rotation
	for mi in src.find_children("*", "MeshInstance3D", true, false):
		_flash_meshes.append(mi)


func play_idle() -> void:
	if _act != "death":
		_act = ""


func play_walk() -> void:
	play_idle()


## 공격 모션(앞발 할퀴기·불 뿜기·날개 바람 중 무작위, 바로 앞 것은 빼고 — 2026-10-06). 길이 = 간격 × 0.8(최대 1.6초). 반환 = 타격 순간까지 초.
func play_attack(interval: float) -> float:
	_atk_i = UnitModelScript.pick_next(ATTACKS.size(), _atk_i)
	attack_kind = ATTACKS[_atk_i]
	if attack_kind == "claw":
		claw_side = 1.0 if randf() < 0.5 else -1.0
	_act = attack_kind
	_act_t = 0.0
	_act_len = minf(1.6, interval * 0.8)
	return _act_len * float(HIT_FRAC[attack_kind])


## 공격 모션이 아직 도는가(UnitModel.is_busy와 같은 뜻).
func is_busy() -> bool:
	return _act != "" and _act != "death"


func play_cast(_anim_name: String, at_sec := -1.0, _frac := -1.0) -> float:
	return play_attack(at_sec / 0.5 / 0.8 if at_sec > 0.0 else 2.0)


func play_loop(_anim_name: String, _speed := 1.0) -> void:
	play_idle()


func play_death() -> void:
	_act = "death"
	_act_t = 0.0
	_act_len = 1.4


## dir = 월드 방향. 모델은 dragon.gd 아래에 있고 그 몸통은 길드 보스 판에서 화면 아래로 45° 돌아 있어, 부모 기준 각으로 바꿔 돈다
## (2026-10-07: 월드 각을 그대로 써서 머리가 늘 노린 영웅보다 45° 옆을 봤다).
func face(dir: Vector3) -> void:
	if Vector2(dir.x, dir.z).length() < 0.001:
		return
	var p := get_parent() as Node3D
	_want_yaw = atan2(dir.x, dir.z) - (p.global_rotation.y if p != null else 0.0)


## 입(목 부품 앞 끝) 월드 위치.
func mouth() -> Vector3:
	var neck: Node3D = _parts.get("Neck")
	if neck == null:
		return global_position + Vector3(0, size * 0.7, 0)
	var mi := neck as MeshInstance3D
	var box := mi.get_aabb() if mi != null else AABB(Vector3.ZERO, Vector3.ONE * 0.2)
	return neck.to_global(Vector3(0.0, box.position.y + box.size.y * 0.45, box.end.z))


## 피격 번쩍임. 찌그러짐은 뺐다(2026-10-07 — 영웅 넷이 쉬지 않고 쳐서 큰 몸이 0.1~0.3초마다 움찔거려 보였다).
func hit_react(strong := false) -> void:
	if not is_inside_tree() or _act == "death":
		return
	var now := Time.get_ticks_msec()
	if now - _flash_at < (HIT_FLASH_GAP_MS if not strong else HIT_FLASH_GAP_MS / 2):
		return
	_flash_at = now
	if _flash_mat == null:
		_flash_mat = ShaderMaterial.new()
		_flash_mat.shader = HitFlashShader
	if _hit_tw != null:
		_hit_tw.kill()
	for mi in _flash_meshes:
		mi.material_overlay = _flash_mat
	_hit_tw = create_tween()
	_hit_tw.tween_method(_set_flash, 0.7 if strong else 0.4, 0.0, HIT_FLASH_SEC)
	_hit_tw.tween_callback(_end_flash)


func _set_flash(v: float) -> void:
	for mi in _flash_meshes:
		mi.set_instance_shader_parameter("flash", v)


func _end_flash() -> void:
	for mi in _flash_meshes:
		mi.material_overlay = null
	scale = _base_scale


func _process(delta: float) -> void:
	_t += delta
	if not is_nan(_want_yaw) and _act != "death":
		rotation.y = lerp_angle(rotation.y, _want_yaw, 1.0 - exp(-TURN_RATE * delta))
	if _act != "":
		_act_t += delta
		if _act != "death" and _act_t >= _act_len:
			_act = ""
	pose(_t, _act, clampf(_act_t / _act_len, 0.0, 1.0))


## 자세: 대기 흔들림 + 공격(진행 k 0..1). 테스트·스냅샷이 직접 부를 수 있다.
## 공격마다 젖힘(0~a) → 빠른 내리침(a~b, 타격 순간 HIT_FRAC이 이 사이) → 잠깐 버팀(b~c) → 제자리(c~1). 몸은 뒷발을 축으로 일어섰다 내려온다.
func pose(t: float, act: String, k: float) -> void:
	var flap := 0.18 + 0.14 * sin(t * 2.4)  # 날개 들기(+ = 위)
	var neck := Vector3(0.05 * sin(t * 1.5), 0.12 * sin(t * 0.7), 0.0)  # x: + = 머리 앞으로 숙임, y: 좌우
	var tail := Vector3(0.0, 0.2 * sin(t * 1.1), 0.0)
	var arm_l := Vector3(0.03 * sin(t * 1.6), 0.0, 0.0)  # x: − = 발을 앞으로 든다, z: + = +X쪽
	var arm_r := Vector3(0.03 * sin(t * 1.6 + PI), 0.0, 0.0)
	var breathe := 1.0 + 0.015 * sin(t * 1.6)
	var tilt := 0.0  # − = 앞을 들고 일어선다(뒷발 축)
	var lift := 0.0  # 몸 들림(키 비율)
	var lunge := 0.0  # 앞으로 내딛음(키 비율)
	var sink := 0.0
	match act:
		"claw":  # 앞발 하나를 높이 들고(몸을 일으키며 머리를 젖힘) 대각선으로 내리 할퀸다
			var sd := claw_side
			var a := 0.45
			var b := 0.57
			var c := 0.68
			var swipe := arm_r if sd > 0 else arm_l
			swipe.x += _seq(k, -1.9, 0.35, a, b, c)
			swipe.z += _seq(k, 0.85 * sd, -0.55 * sd, a, b, c)
			var brace := arm_l if sd > 0 else arm_r
			brace.x += _seq(k, 0.18, 0.0, a, b, c)
			if sd > 0:
				arm_r = swipe
				arm_l = brace
			else:
				arm_l = swipe
				arm_r = brace
			tilt = _seq(k, -0.32, 0.1, a, b, c)
			lift = _seq(k, 0.05, 0.0, a, b, c)
			lunge = _seq(k, -0.03, 0.1, a, b, c)
			neck.x += _seq(k, -0.4, 0.45, a, b, c)
			neck.y += _seq(k, 0.25 * sd, -0.12 * sd, a, b, c)
			flap += _seq(k, 0.4, -0.12, a, b, c)
			tail.y += _seq(k, 0.35 * sd, -0.3 * sd, a, b, c)
		"breath":  # 크게 일어서며 날개를 펴고 머리를 젖혔다가, 앞으로 내밀어 불을 길게 뿜는다(뿜는 동안 머리를 살짝 쓸어 준다)
			var a := 0.38
			var b := 0.47
			var c := 0.82
			tilt = _seq(k, -0.22, 0.07, a, b, c)
			lunge = _seq(k, -0.05, 0.07, a, b, c)
			neck.x += _seq(k, -0.75, 0.38, a, b, c)
			if k > b and k < c:
				neck.y += 0.16 * sin((k - b) / (c - b) * TAU)
			flap += _seq(k, 0.75, 0.3, a, b, c)
			arm_l.x += _seq(k, -0.45, 0.12, a, b, c)
			arm_r.x += _seq(k, -0.45, 0.12, a, b, c)
			tail.y += _seq(k, 0.0, 0.25, a, b, c)
		"gust":  # 날개를 하늘 높이 들어 몸을 띄웠다가, 세게 내려치며 쿵 내려앉는다
			var a := 0.4
			var b := 0.52
			var c := 0.66
			flap += _seq(k, 1.05, -0.75, a, b, c)
			lift = _seq(k, 0.16, -0.01, a, b, c)
			tilt = _seq(k, -0.14, 0.06, a, b, c)
			neck.x += _seq(k, -0.3, 0.32, a, b, c)
			arm_l.x += _seq(k, -0.7, 0.2, a, b, c)
			arm_r.x += _seq(k, -0.7, 0.2, a, b, c)
			tail.y *= 1.0 - _seq(k, 0.8, 0.8, a, b, c)
		"death":
			flap = lerpf(flap, -0.6, k)
			neck.x = lerpf(neck.x, 0.9, k)
			tail.y *= 1.0 - k
			arm_l = arm_l.lerp(Vector3(0.5, 0.0, -0.2), k)
			arm_r = arm_r.lerp(Vector3(0.5, 0.0, 0.2), k)
			sink = k
	_rot("WingL", Vector3(0, 0, -flap))
	_rot("WingR", Vector3(0, 0, flap))
	_rot("Neck", neck)
	_rot("Tail", tail)
	_rot("ArmL", arm_l)
	_rot("ArmR", arm_r)
	var body: Node3D = _parts.get("Body")
	if body != null:
		body.scale = Vector3(1.0, breathe, 1.0)
	rotation.x = tilt
	rotation.z = 0.5 * sink
	# 뒷발(HIND_Z)을 축으로 기울인다 — 몸 가운데를 축으로 하면 뒷발이 땅에 박힌다
	var yaw := Basis(Vector3.UP, rotation.y)
	var piv := Vector3(0.0, 0.0, HIND_Z) * size
	position = yaw * piv - Basis.from_euler(rotation) * piv + yaw * Vector3(0.0, lift - 0.12 * sink, lunge) * size


## 공격 채널 하나: 0 → A(0~a, 부드럽게 젖힘) → B(a~b, 빠르게 내리침) → B 버팀(b~c) → 0(c~1, 부드럽게 돌아옴).
static func _seq(k: float, va: float, vb: float, a: float, b: float, c: float) -> float:
	if k < a:
		return va * smoothstep(0.0, a, k)
	if k < b:
		var u := (k - a) / (b - a)
		return lerpf(va, vb, 1.0 - (1.0 - u) * (1.0 - u))
	if k < c:
		return vb
	return lerpf(vb, 0.0, smoothstep(c, 1.0, k))


func _rot(n: String, r: Vector3) -> void:
	var p: Node3D = _parts.get(n)
	if p != null:
		p.rotation = _rest[n] + r
