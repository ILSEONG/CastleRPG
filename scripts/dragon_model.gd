extends Node3D
## 길드 보스 드래곤 모델(Meshy, dev/meshy_dragon_fit.py). 사람 모양이 아니라 KayKit 뼈대·자동 리깅을 못 써서, 부품(Body·WingL·WingR·Neck·Tail,
## 노드 원점 = 관절)을 코드로 움직인다: 대기(숨쉬기·날갯짓·목·꼬리 흔들기), 공격 셋(물기·불 뿜기·날개 바람, 무작위), 피격 번쩍임, 쓰러짐.
## monster.gd가 쓰는 UnitModel 메서드(play_idle·play_walk·play_attack·hit_react·play_death·face)를 같은 뜻으로 낸다. 정면 +Z.
## 공격 연출의 이펙트(불·바람)는 dragon.gd가 타격 순간에 낸다(mouth()·attack_kind()).

const Art := preload("res://scripts/art.gd")
const HitFlashShader := preload("res://shaders/hit_flash.gdshader")
const UnitModelScript := preload("res://scripts/unit_model.gd")

const SCENE := "res://assets/models/meshy/enemies/dragon.glb"
const PARTS := ["Body", "WingL", "WingR", "Neck", "Tail"]
const ATTACKS := ["bite", "breath", "gust"]
const HIT_FRAC := {"bite": 0.55, "breath": 0.45, "gust": 0.5}  # 모션 중 타격 순간
const HIT_FLASH_SEC := 0.14
const HIT_FLASH_GAP_MS := 260
const TURN_RATE := 5.0  # 몸 돌리기 부드러움(1/초) — 노리는 영웅이 바뀌어도 한 프레임에 홱 돌지 않고 따라 돈다

var size := 5.0  # 키(m) — 부품 GLB는 키 1로 맞춰져 있다. add_child 전에
var attack_kind := ""  # 지금(마지막) 공격 모션
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


## 공격 모션(물기·불 뿜기·날개 바람 중 무작위, 바로 앞 것은 빼고 — 2026-10-06). 길이 = 간격 × 0.8(최대 1.6초). 반환 = 타격 순간까지 초.
func play_attack(interval: float) -> float:
	_atk_i = UnitModelScript.pick_next(ATTACKS.size(), _atk_i)
	attack_kind = ATTACKS[_atk_i]
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


func face(dir: Vector3) -> void:
	if Vector2(dir.x, dir.z).length() < 0.001:
		return
	_want_yaw = atan2(dir.x, dir.z)


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
func pose(t: float, act: String, k: float) -> void:
	var flap := 0.18 + 0.14 * sin(t * 2.4)  # 날개 들기(+ = 위)
	var neck := Vector3(0.05 * sin(t * 1.5), 0.12 * sin(t * 0.7), 0.0)  # x: + = 머리 앞으로 숙임
	var tail := Vector3(0.0, 0.2 * sin(t * 1.1), 0.0)
	var breathe := 1.0 + 0.015 * sin(t * 1.6)
	var body_tilt := 0.0
	var sink := 0.0
	match act:
		"bite":  # 머리를 뒤로 젖혔다가(0~0.5) 앞으로 내리꽂고(0.5~0.6) 돌아온다
			var w := _ease_back(k, 0.5, 0.62)
			neck.x += lerpf(-0.45, 0.6, w) * _env(k)
			body_tilt = lerpf(-0.06, 0.08, w) * _env(k)
		"breath":  # 머리를 젖히고 날개를 들었다가 앞으로 길게 뿜는다
			var w := _ease_back(k, 0.4, 0.5)
			neck.x += lerpf(-0.55, 0.25, w) * _env(k)
			flap += 0.35 * _env(k)
		"gust":  # 날개를 높이 들었다가 세게 내려친다
			var w := _ease_back(k, 0.42, 0.55)
			flap += lerpf(0.75, -0.45, w) * _env(k)
			body_tilt = lerpf(-0.05, 0.05, w) * _env(k)
		"death":
			flap = lerpf(flap, -0.6, k)
			neck.x = lerpf(neck.x, 0.9, k)
			tail.y *= 1.0 - k
			body_tilt = 0.0
			sink = k
	_rot("WingL", Vector3(0, 0, -flap))
	_rot("WingR", Vector3(0, 0, flap))
	_rot("Neck", neck)
	_rot("Tail", tail)
	var body: Node3D = _parts.get("Body")
	if body != null:
		body.scale = Vector3(1.0, breathe, 1.0)
	rotation.x = body_tilt
	rotation.z = 0.5 * sink
	position.y = -0.12 * size * sink


func _rot(n: String, r: Vector3) -> void:
	var p: Node3D = _parts.get(n)
	if p != null:
		p.rotation = _rest[n] + r


## 공격 모션 진행 k → 0(젖힘)·1(내리침) 사이 값: a까지 천천히 젖히고 a~b에 빠르게 내리친다.
static func _ease_back(k: float, a: float, b: float) -> float:
	if k < a:
		return 0.0
	if k < b:
		return (k - a) / (b - a)
	return 1.0


## 모션 처음과 끝을 부드럽게(0에서 시작해 0으로 돌아온다).
static func _env(k: float) -> float:
	return smoothstep(0.0, 0.25, k) * (1.0 - smoothstep(0.75, 1.0, k))
