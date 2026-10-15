extends Node3D
## 파티 퀘스트 거미 여왕·새끼 거미 모델(Meshy, dev/meshy_spider_fit.py). 사람 모양이 아니라 KayKit 뼈대를 못 써서 dragon_model.gd처럼
## 부품(Body·Abdomen·Head·L1~L4·R1~R4, 노드 원점 = 관절)을 코드로 움직인다. Head·Abdomen·다리는 Body 아래로 옮겨 몸과 함께 기운다.
## 대기 = 숨쉬기(배 부풀기·몸 들썩) + 다리 까딱, 걷기 = 다리 넷씩 엇갈리는 걸음(L1·R2·L3·R4 ↔ R1·L2·R3·L4), 공격 = 물기(여왕은 앞다리 내려찍기도),
## 여왕 스킬(play_skill) = web(일어서 거미줄 뱉기)·lunge(웅크렸다 도약)·brood(배를 떨며 알 낳기)·acid(배를 들어 위로 산 뿌리기), 피격 번쩍임, 쓰러짐(다리 오므림).
## monster.gd가 쓰는 UnitModel 메서드(play_idle·play_walk·play_attack·is_busy·play_cast·play_loop·play_death·reset_pose·face·hit_react)를 같은 뜻으로 낸다.
## 정면 +Z. 이펙트 위치는 mouth()·abdomen_tip()(월드). 새끼 거미는 한 화면에 30~60마리라 crowd_lod면 붐빌 때 자세를 몇 프레임에 한 번만 계산한다.

const Art := preload("res://scripts/art.gd")
const HitFlashShader := preload("res://shaders/hit_flash.gdshader")
const UnitModelScript := preload("res://scripts/unit_model.gd")

const QUEEN_SCENE := "res://assets/models/meshy/enemies/spider_queen.glb"
const SPIDERLING_SCENE := "res://assets/models/meshy/enemies/spiderling.glb"
const LEGS := ["L1", "L2", "L3", "L4", "R1", "R2", "R3", "R4"]
const GAIT_A := ["L1", "R2", "L3", "R4"]  # 걸음 한 묶음(나머지 넷은 반 박자 늦게)
const QUEEN_ATTACKS := ["bite", "slam"]
const HIT_FRAC := {"bite": 0.55, "slam": 0.52}  # 공격 모션 중 타격 순간
const SKILLS := {  # 스킬 길이(초)·효과 순간 비율
	"web": {"len": 1.5, "frac": 0.55}, "lunge": {"len": 1.2, "frac": 0.5}, "brood": {"len": 2.0, "frac": 0.6}, "acid": {"len": 1.6, "frac": 0.5},
}
const DEATH_SEC := 1.1  # Art.CORPSE_SEC(1.6)보다 짧게 — 시체가 사라지기 전에 다 쓰러진다
const HIT_FLASH_SEC := 0.14
const HIT_FLASH_GAP_MS := 260
const TURN_RATE := 10.0  # 몸 돌리기 부드러움(1/초)
const OFFSCREEN_EVERY := 4  # crowd_lod: 화면 밖이면 이 프레임마다 자세 계산
const CROWD_EVERY := 3  # crowd_lod: 붐비면(살아 있는 "crowd" ≥ UnitModel.CROWD_AT) 화면 안도 이 프레임마다

static var _crowd_frame := -1
static var _crowd_n := 0

var size := 1.0  # 키(m) — 부품 GLB는 키 1. add_child 전에
var queen := true  # false = 새끼 거미. add_child 전에
var crowd_lod := false  # 붐빌 때 자세 계산 줄이기·그림자 끔(monster.gd와 같은 뜻). add_child 전에
var attack_kind := ""  # 지금(마지막) 공격·스킬 모션 이름
var _parts := {}  # 이름 → Node3D(관절)
var _rest := {}  # 이름 → [처음 위치, 처음 회전]
var _t := 0.0
var _phase := 0.0  # 걸음 위상(라디안)
var _walk := 0.0  # 걷기 섞임(0 = 대기, 1 = 걸음) — 부드럽게 바뀐다
var _walk_on := false
var _walk_speed := 1.0
var _act := ""  # "" · 공격 이름 · 스킬 이름 · "death"
var _act_t := 0.0
var _act_len := 1.0
var _atk_i := -1
var _flash_at := -100000
var _flash_meshes: Array = []
var _hit_tw: Tween
var _flash_mat: ShaderMaterial
var _want_yaw := NAN
var _frame := 0
var _shadows := true
var _seed := 0.0  # 마리마다 다른 까딱임 위상


func _ready() -> void:
	scale = Vector3.ONE * size
	var src := Art.instance(QUEEN_SCENE if queen else SPIDERLING_SCENE)
	Art.stylize(src)
	add_child(src)
	var body := src.get_node_or_null("Body") as Node3D
	for n in ["Body", "Abdomen", "Head"] + LEGS:
		var p := src.get_node_or_null(n) as Node3D
		if p == null:
			continue
		if body != null and p != body:
			p.reparent(body, true)
		_parts[n] = p
	for n in _parts:
		_rest[n] = [_parts[n].position, _parts[n].rotation]
	for mi in src.find_children("*", "MeshInstance3D", true, false):
		_flash_meshes.append(mi)
	_frame = get_instance_id() % OFFSCREEN_EVERY
	_seed = float(get_instance_id() % 997) * 0.37
	pose(0.0, "", 0.0)


func play_idle() -> void:
	if _act != "death":
		_act = ""
	_walk_on = false


func play_walk() -> void:
	play_idle()
	_walk_on = true
	_walk_speed = 1.0


## 이름 있는 반복 모션(돌진 달리기 등): 거미는 걸음을 speed배로 빨리 돈다.
func play_loop(_anim_name: String, speed := 1.0) -> void:
	play_walk()
	_walk_speed = maxf(0.2, speed) * 1.6


## 공격(여왕 = 물기·앞다리 내려찍기 무작위, 바로 앞 것은 빼고 · 새끼 = 물기). 길이 = 간격 × 0.8(최대 1.2초). 반환 = 타격 순간까지 초.
func play_attack(interval: float) -> float:
	if queen:
		_atk_i = UnitModelScript.pick_next(QUEEN_ATTACKS.size(), _atk_i)
		attack_kind = QUEEN_ATTACKS[_atk_i]
	else:
		attack_kind = "bite"
	_start(attack_kind, minf(1.2 if queen else 0.7, maxf(0.25, interval * 0.8)))
	return _act_len * float(HIT_FRAC[attack_kind])


## 공격·스킬 모션이 아직 도는가(UnitModel.is_busy와 같은 뜻).
func is_busy() -> bool:
	return _act != "" and _act != "death"


## 여왕 스킬 모션: "web"·"lunge"·"brood"·"acid". 반환 = 효과 순간까지 초(web = 거미줄이 입을 떠나는 순간, lunge = 땅을 박차는 순간,
## brood = 알이 배 끝에서 나오는 순간, acid = 산이 배 끝에서 뿜어지는 순간). 모르는 이름이면 공격 모션.
## at_sec > 0이면 효과 순간이 그 초에 오도록 모션 길이를 맞춘다(0.4~3배).
func play_skill(skill: String, at_sec := -1.0) -> float:
	if not SKILLS.has(skill):
		return play_cast(skill, at_sec)
	var s: Dictionary = SKILLS[skill]
	var length: float = s.len
	if at_sec > 0.0:
		length = clampf(at_sec / float(s.frac), length * 0.4, length * 3.0)
	attack_kind = skill
	_start(skill, length)
	return _act_len * float(s.frac)


## UnitModel.play_cast와 같은 뜻: anim_name이 스킬 이름(web·lunge·brood·acid)이면 그 모션, 아니면 공격 모션.
## 반환 = 효과(타격) 순간까지 초. at_sec > 0이면 그 초에 맞춘다. frac은 받기만 한다(모션마다 효과 순간이 정해져 있다).
func play_cast(anim_name: String, at_sec := -1.0, _frac := -1.0) -> float:
	if SKILLS.has(anim_name):
		return play_skill(anim_name, at_sec)
	var hit := play_attack(1.5)
	if at_sec > 0.0:  # 타격 순간을 그 초에 맞춘다(모션 길이 0.4~3배)
		var f := float(HIT_FRAC[attack_kind])
		_act_len = clampf(at_sec / f, _act_len * 0.4, _act_len * 3.0)
		hit = _act_len * f
	return hit


func play_death() -> void:
	if _hit_tw != null and _hit_tw.is_valid():
		_hit_tw.kill()
		_end_flash()
	_start("death", DEATH_SEC)
	_walk_on = false


## 리필 때: 쓰러진 자세에서 대기로 바로.
func reset_pose() -> void:
	_act = ""
	_act_t = 0.0
	_walk_on = false
	_walk = 0.0
	pose(_t, "", 0.0)


## 수평 방향 dir 쪽을 본다(부모가 돌아 있으면 그만큼 빼서 — dragon_model과 같다). 부드럽게 따라 돈다.
func face(dir: Vector3) -> void:
	if Vector2(dir.x, dir.z).length() < 0.001:
		return
	var p := get_parent() as Node3D
	_want_yaw = atan2(dir.x, dir.z) - (p.global_rotation.y if p != null else 0.0)


## 입(머리 부품 앞 끝) 월드 위치 — 거미줄·물기 이펙트.
func mouth() -> Vector3:
	var head: Node3D = _parts.get("Head")
	if head == null:
		return to_global(Vector3(0.0, 0.4, 0.6))
	var box := (head as MeshInstance3D).get_aabb() if head is MeshInstance3D else AABB(Vector3(-0.1, -0.1, 0.0), Vector3(0.2, 0.2, 0.2))
	return head.to_global(Vector3(0.0, box.position.y + box.size.y * 0.3, box.end.z))


## 배 끝(실젖 — 뒤쪽 아래) 월드 위치 — 알·산 이펙트.
func abdomen_tip() -> Vector3:
	var ab: Node3D = _parts.get("Abdomen")
	if ab == null:
		return to_global(Vector3(0.0, 0.4, -0.6))
	var box := (ab as MeshInstance3D).get_aabb() if ab is MeshInstance3D else AABB(Vector3(-0.3, -0.3, -0.8), Vector3(0.6, 0.6, 0.8))
	return ab.to_global(Vector3(0.0, box.position.y + box.size.y * 0.35, box.position.z + box.size.z * 0.04))


## 피격 번쩍임(UnitModel.hit_react와 같은 뜻 — 번쩍였으면 true). 새끼 거미는 살짝 찌그러졌다 돌아온다.
func hit_react(strong := false) -> bool:
	if not is_inside_tree() or _act == "death":
		return false
	var now := Time.get_ticks_msec()
	if now - _flash_at < (HIT_FLASH_GAP_MS if not strong else HIT_FLASH_GAP_MS / 2):
		return false
	_flash_at = now
	if _flash_mat == null:
		_flash_mat = ShaderMaterial.new()
		_flash_mat.shader = HitFlashShader
	if _hit_tw != null:
		_hit_tw.kill()
	for mi in _flash_meshes:
		mi.material_overlay = _flash_mat
	_hit_tw = create_tween()
	_hit_tw.tween_method(_set_flash, 0.8 if strong else 0.45, 0.0, HIT_FLASH_SEC)
	if not queen:
		scale = Vector3(1.15, 0.8, 1.15) * size
		_hit_tw.parallel().tween_property(self, "scale", Vector3.ONE * size, HIT_FLASH_SEC)
	_hit_tw.tween_callback(_end_flash)
	return true


func _set_flash(v: float) -> void:
	for mi in _flash_meshes:
		mi.set_instance_shader_parameter("flash", v)


func _end_flash() -> void:
	for mi in _flash_meshes:
		mi.material_overlay = null
	scale = Vector3.ONE * size


func _start(act: String, length: float) -> void:
	_act = act
	_act_t = 0.0
	_act_len = maxf(0.05, length)


func _process(delta: float) -> void:
	_t += delta
	_walk = move_toward(_walk, 1.0 if _walk_on and _act == "" else 0.0, delta * 5.0)
	if _walk > 0.0:
		_phase += delta * TAU * (1.6 if queen else 3.2) * _walk_speed
	if not is_nan(_want_yaw) and _act != "death":
		rotation.y = lerp_angle(rotation.y, _want_yaw, 1.0 - exp(-TURN_RATE * delta))
	if _act != "":
		_act_t += delta
		if _act != "death" and _act_t >= _act_len:
			_act = ""
	if crowd_lod and not _due():
		return
	pose(_t, _act, clampf(_act_t / _act_len, 0.0, 1.0))


## crowd_lod: 이번 프레임에 자세를 계산할 차례인가(화면 밖 OFFSCREEN_EVERY, 붐비면 CROWD_EVERY 프레임마다). 붐비면 그림자도 끈다.
func _due() -> bool:
	_frame += 1
	var f := Engine.get_process_frames()
	if f != _crowd_frame:
		_crowd_frame = f
		_crowd_n = 0
		for u in get_tree().get_nodes_in_group("crowd"):
			_crowd_n += 1 if not u.has_method("is_alive") or u.is_alive() else 0
	var shadows := _crowd_n < UnitModelScript.SHADOW_OFF_AT if _shadows else _crowd_n <= UnitModelScript.SHADOW_ON_AT
	if shadows != _shadows:
		_shadows = shadows
		for mi in _flash_meshes:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var every := CROWD_EVERY if _crowd_n >= UnitModelScript.CROWD_AT else 1
	var cam := get_viewport().get_camera_3d()
	if cam != null and not cam.is_position_in_frustum(global_position):
		every = OFFSCREEN_EVERY
	return _frame % every == 0 or _act == "death"


## 자세: 대기·걸음 + 모션(진행 k 0..1). 테스트·스냅샷이 직접 부를 수 있다.
## 다리 회전: z = 들기(+ = 다리 끝이 위로, 쪽 부호를 곱한다), y = 앞뒤 휘두르기(+ = 다리 끝이 앞으로). 몸 기울기 x(− = 앞을 든다).
func pose(t: float, act: String, k: float) -> void:
	var lift := {}
	var swing := {}
	var w := _walk
	for n in LEGS:
		var i := LEGS.find(n)
		var ph := _phase + (0.0 if GAIT_A.has(n) else PI)
		# 대기 까딱: 다리마다 다른 위상으로 가끔 살짝 든다(위로 뾰족한 sin^8)
		var twitch := 0.09 * pow(maxf(0.0, sin(t * 0.8 + _seed + i * 1.9)), 8.0)
		lift[n] = lerpf(twitch, 0.32 * maxf(0.0, cos(ph)), w)
		swing[n] = 0.3 * sin(ph) * w
	var tilt := 0.0
	var bob := 0.008 * sin(t * 1.8 + _seed) + 0.015 * w * absf(sin(_phase))
	var lunge := 0.0
	var sink := 0.0
	var roll := 0.0
	var head := Vector3(0.04 * sin(t * 1.1 + _seed), 0.0, 0.0)  # x: + = 머리 숙임
	var abdo := Vector3(0.03 * sin(t * 0.9 + _seed), 0.0, 0.0)  # x: + = 배 들기
	var puff := 1.0 + 0.03 * sin(t * 1.8 + _seed)  # 숨쉬기(배 부풀기)
	match act:
		"bite":  # 앞을 들며 앞다리 둘을 쳐들었다가 머리로 앞을 콱 문다
			var a := 0.45
			var b := 0.58
			var c := 0.7
			tilt = _seq(k, -0.3, 0.1, a, b, c)
			lunge = _seq(k, -0.04, 0.12, a, b, c)
			head.x += _seq(k, -0.35, 0.4, a, b, c)
			for n in ["L1", "R1"]:
				lift[n] += _seq(k, 0.9, 0.1, a, b, c)
				swing[n] += _seq(k, 0.35, 0.2, a, b, c)
			for n in ["L2", "R2"]:
				lift[n] += _seq(k, 0.35, 0.0, a, b, c)
		"slam":  # 앞다리 넷을 높이 들어 일어섰다가 땅을 쾅 내려찍는다(여왕)
			var a := 0.42
			var b := 0.52
			var c := 0.68
			tilt = _seq(k, -0.5, 0.06, a, b, c)
			bob += _seq(k, 0.06, -0.03, a, b, c)
			lunge = _seq(k, -0.05, 0.08, a, b, c)
			abdo.x += _seq(k, 0.35, -0.05, a, b, c)
			for n in ["L1", "R1"]:
				lift[n] += _seq(k, 1.25, -0.1, a, b, c)
				swing[n] += _seq(k, 0.25, 0.35, a, b, c)
			for n in ["L2", "R2"]:
				lift[n] += _seq(k, 0.8, -0.05, a, b, c)
		"web":  # 크게 일어서 머리를 젖혔다가 앞으로 내밀며 거미줄을 뱉는다(앞다리 넷은 들고)
			var a := 0.45
			var b := 0.55
			var c := 0.8
			tilt = _seq(k, -0.55, -0.3, a, b, c)
			bob += _seq(k, 0.05, 0.04, a, b, c)
			abdo.x += _seq(k, 0.45, 0.3, a, b, c)
			head.x += _seq(k, -0.45, 0.35, a, b, c)
			lunge = _seq(k, -0.03, 0.06, a, b, c)
			for n in ["L1", "R1"]:
				lift[n] += _seq(k, 1.1, 0.9, a, b, c)
				swing[n] += _seq(k, 0.4, 0.5, a, b, c)
			for n in ["L2", "R2"]:
				lift[n] += _seq(k, 0.6, 0.5, a, b, c)
		"lunge":  # 다리를 벌리고 납작 웅크렸다가(0~0.5) 몸을 띄워 앞다리를 앞으로 뻗고 뒷다리를 뒤로 편다
			var a := 0.48
			var b := 0.58
			var c := 0.82
			sink = _seq(k, 0.1, -0.12, a, b, c)
			tilt = _seq(k, 0.12, -0.25, a, b, c)
			lunge = _seq(k, -0.06, 0.15, a, b, c)
			head.x += _seq(k, 0.15, -0.2, a, b, c)
			for n in LEGS:
				var front: bool = n.ends_with("1") or n.ends_with("2")
				lift[n] += _seq(k, -0.25, 0.9 if front else -0.15, a, b, c)
				swing[n] += _seq(k, 0.0, (0.45 if front else -0.5), a, b, c)
		"brood":  # 배를 땅으로 내리고 점점 세게 떨며 알을 낳는다(효과 0.6), 다리는 버틴다
			var env := smoothstep(0.0, 0.5, k) * (1.0 - smoothstep(0.75, 1.0, k))
			abdo.x += -0.3 * env
			tilt = 0.08 * env
			puff += env * (0.08 + 0.07 * sin(_act_t * 28.0))
			for n in LEGS:
				lift[n] += -0.1 * env
			head.x += 0.15 * env
		"acid":  # 배를 하늘로 높이 치켜들고 부르르 떨다가 위로 산을 뿜는다(효과 0.5)
			var a := 0.42
			var b := 0.5
			var c := 0.78
			abdo.x += _seq(k, 0.75, 1.0, a, b, c)
			tilt = _seq(k, 0.12, 0.18, a, b, c)
			head.x += _seq(k, 0.2, 0.25, a, b, c)
			if k > a and k < c:
				puff += 0.06 * sin(_act_t * 40.0)
			for n in ["L3", "R3", "L4", "R4"]:
				lift[n] += _seq(k, -0.2, -0.25, a, b, c)
		"death":  # 다리를 몸 아래로 오므리며 주저앉고 옆으로 살짝 기운다
			var e := smoothstep(0.0, 1.0, k)
			for n in LEGS:
				lift[n] = lerpf(lift[n], 1.2, e)
				swing[n] = lerpf(swing[n], 0.0, e)
			sink = 0.22 * e
			roll = 0.25 * e
			head.x = lerpf(head.x, 0.4, e)
			abdo.x = lerpf(abdo.x, -0.15, e)
			puff = lerpf(puff, 0.94, e)
	for n in LEGS:
		var side := -1.0 if n.begins_with("L") else 1.0
		_rot(n, Vector3(0.0, -side * swing[n], side * lift[n]))
	_rot("Head", head)
	_rot("Abdomen", abdo)
	var ab: Node3D = _parts.get("Abdomen")
	if ab != null:
		ab.scale = Vector3.ONE * puff
	var body: Node3D = _parts.get("Body")
	if body != null:
		body.rotation = _rest.Body[1] + Vector3(tilt, 0.0, roll)
		body.position = _rest.Body[0] + Vector3(0.0, bob - sink, lunge)


func _rot(n: String, r: Vector3) -> void:
	var p: Node3D = _parts.get(n)
	if p != null:
		p.rotation = _rest[n][1] + r


## 모션 채널 하나: 0 → A(0~a, 부드럽게) → B(a~b, 빠르게) → B 버팀(b~c) → 0(c~1, 부드럽게). dragon_model._seq와 같다.
static func _seq(k: float, va: float, vb: float, a: float, b: float, c: float) -> float:
	if k < a:
		return va * smoothstep(0.0, a, k)
	if k < b:
		var u := (k - a) / (b - a)
		return lerpf(va, vb, 1.0 - (1.0 - u) * (1.0 - u))
	if k < c:
		return vb
	return lerpf(vb, 0.0, smoothstep(c, 1.0, k))
