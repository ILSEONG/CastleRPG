extends Node3D
## 캐릭터 모델 래퍼: KayKit 모델 인스턴스, 안 쓰는 부착물 숨김, 무기 부착, 애니메이션 재생, 방향.
## spec = Art.hero_spec(영웅 정의) 또는 Art.MONSTER_MODELS[kind]. KayKit 모델 정면은 +Z.
## 월드 유닛(lod, add_child 전에)은 스스로 덜 돈다: 애니메이션은 화면 밖이면 OFFSCREEN_EVERY 프레임마다(쌓인 시간만큼 — 공격 타격 시점은
## 쓰는 쪽 타이머라 그대로), crowd_lod(몬스터·병사)면 붐빌 때(살아 있는 "crowd" 유닛 ≥ CROWD_AT) 화면 안도 CROWD_EVERY 프레임마다,
## 그리고 붐비는 동안(≥ SHADOW_OFF_AT, ≤ SHADOW_ON_AT에서 되돌림) 그림자를 드리우지 않는다 — 그림자 패스가 메시를 한 번 더 그리지 않게.
## 영웅은 lod만(화면 안이면 매 프레임, 그림자 늘). 유닛마다 다른 프레임에 갱신해(인스턴스 id) 한 프레임에 몰리지 않는다.
# ponytail: 성능 한계 — 캐릭터 하나 = AnimationPlayer 1개 + 스킨 메시 드로 ~10개(+ 그림자 패스). 유닛 190이면 메시 ~1900 —
# 모바일 GPU는 그리기 호출 수가 먼저 한계다(tests/perf_check가 메시·그림자 수를 찍는다). 더 줄이려면 스켈레톤당 메시를 합치거나
# 멀리 있는 유닛을 대표 모델로 그린다.

const Art := preload("res://scripts/art.gd")
const ArenaKit := preload("res://scripts/arena_kit.gd")
const HeroKit := preload("res://scripts/hero_kit.gd")
const MeshMerge := preload("res://scripts/mesh_merge.gd")
const HitFlashShader := preload("res://shaders/hit_flash.gdshader")

const OFFSCREEN_EVERY := 4  # 화면 밖: 이 프레임마다 한 번
const CROWD_EVERY := 2  # 붐비면 화면 안도 이 프레임마다 한 번(crowd_lod)
const CROWD_AT := 60
const SHADOW_OFF_AT := 40  # 붐비면 crowd_lod 유닛 그림자 끔
const SHADOW_ON_AT := 30  # 이만큼으로 줄면 다시 켬(경계에서 깜빡이지 않게)
const HIT_FLASH_SEC := 0.14  # 피격 번쩍임(개정 26)
const HIT_SQUASH := Vector3(1.12, 0.86, 1.12)  # 피격 순간 찌그러짐(세게 맞으면 이만큼, 약하면 절반)
const HIT_SQUASH_SEC := 0.16
const HIT_FLASH_GAP_MS := 260  # 피격 번쩍임 최소 간격(약한 타격, 강한 타격은 절반)

static var _crowd_frame := -1
static var _crowd_n := 0
static var _crowd_shadows := true
static var _flash_mat: ShaderMaterial

var manual := false  # true면 애니메이션을 스스로 돌리지 않는다 — 쓰는 쪽이 advance(초)로 돌린다(recruit_art 정지 자세). add_child 전에
var lod := false  # 월드 유닛: 화면 밖이면 간헐 갱신(위). add_child 전에
var crowd_lod := false  # lod + 붐비면 화면 안도 간헐 갱신·그림자 끔(몬스터·병사). add_child 전에
var _spec: Dictionary = {}
var _anim: AnimationPlayer
var _current := ""
var _frame := 0
var _acc := 0.0  # 아직 돌리지 않은 애니메이션 시간(lod)
var _meshes: Array = []  # 그림자를 끄고 켤 메시와 원래 설정 [[MeshInstance3D, cast_shadow], …](crowd_lod)
var _shadows := true
var _base_scale := Vector3.ONE
var _atk_i := -1  # 지난 공격 모션 번호(attacks — 다음엔 이것만 빼고 고른다)
var _flash_at := -100000  # 마지막 피격 번쩍임(밀리초)
var _hit_tw: Tween
var _flash_meshes: Array = []  # 보이는 몸 메시(처음 맞을 때 찾는다)


## add_child 전에 호출.
func setup(spec: Dictionary, extra_scale := 1.0) -> void:
	_spec = spec
	scale = Vector3.ONE * Art.CHARACTER_SCALE * extra_scale
	_base_scale = scale


func _ready() -> void:
	var model := Art.instance(_spec.scene)
	add_child(model)
	dress(model, _spec)
	_anim = model.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	if manual or lod or crowd_lod:
		_anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	lod = lod or crowd_lod
	set_process(lod)
	_frame = get_instance_id() % OFFSCREEN_EVERY
	if crowd_lod:
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			_meshes.append([mi, mi.cast_shadow])
	for anim_name in [_spec.anims.idle, _spec.anims.walk]:
		_anim.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR  # 공유 리소스라 한 번 바꾸면 전부 적용
	_anim.animation_finished.connect(_on_finished)
	play_idle()


## 스펙대로 모델을 꾸민다(트리 밖에서도 된다): 안 쓰는 부착물 숨김, 메시 색(tint), 영웅 칸 색(palette, 개정 23), 몸 크기(body_scale),
## 무기 바꿈(swap: gear를 숨기고 같은 손 슬롯에 HeroKit 무기), 무기(gltf)·코드 부품(parts: [뼈, HeroKit 또는 ArenaKit id])을 뼈에 붙임.
## 재질을 그림 방식대로 바꾼 뒤(Art.stylize) 마지막에 보이는 부위 메시를 재질마다 하나로 합친다(MeshMerge — 스펙이 같으면 합친 메시를 공유).
static func dress(model: Node3D, spec: Dictionary) -> void:
	for mesh_name in spec.hide:
		var n := model.find_child(mesh_name, true, false) as Node3D
		if n != null:
			n.visible = false
	for gear_name in spec.get("swap", {}):
		var g := model.find_child(gear_name, true, false) as Node3D
		g.visible = false
		g.get_parent().add_child(HeroKit.part(spec.swap[gear_name]))  # 손 슬롯(BoneAttachment3D) 공간 = 무기 공간
	if spec.has("body"):
		Art.put_body(model, spec.body)  # Meshy 몸(Art.MESHY_HERO_DIR)
	for mesh_name in spec.get("tint", {}):
		var mi := model.find_child(mesh_name, true, false) as MeshInstance3D
		if mi != null:
			Art.tint(mi, spec.tint[mesh_name])
	if spec.has("palette"):
		Art.remap(model, spec.look, spec.palette)
	model.scale = Vector3.ONE * spec.get("body_scale", 1.0)
	var skel := model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var attach := []
	if spec.has("weapon"):
		attach.append([Art.WEAPON_BONE, Art.instance(spec.weapon)])
	for p in spec.get("parts", []):
		attach.append([p[0], HeroKit.part(p[1]) if HeroKit.has_part(p[1]) else ArenaKit.part(p[1])])
	for a in attach:
		var slot := BoneAttachment3D.new()
		slot.bone_name = a[0]
		skel.add_child(slot)
		slot.add_child(a[1])
	Art.stylize(model)  # 영웅·몬스터 그림 방식(Art.unit_style: 실사풍·카툰·로우폴리) — 성·건물·이펙트는 로우폴리 그대로
	MeshMerge.merge(model, str(spec.hash()))  # 부위 메시를 재질마다 하나로(그리기 호출 ~10 → 1~3, mesh_merge.gd)


func play_idle() -> void:
	_play(_spec.anims.idle)


func play_walk() -> void:
	_play(_spec.anims.walk)


## 공격 때마다 처음부터. 끝나면 대기로 돌아간다. 공격 간격 interval보다 길면 길이 ≤ 간격 × ATTACK_FIT가 되게 빨리 돈다.
## 스펙에 "attacks"(모션 이름 목록 — 근접 영웅 Art.ATTACK_SETS, 보스 MONSTER_MODELS)가 있으면 공격마다 그중 하나를 무작위로, 바로 앞 것은 빼고 고른다
## (2026-10-06 — 개정 26의 차례 돌기 대신). 반환 = 타격(발사) 순간까지 초(길이 × HIT_FRAC ÷ 속도).
func play_attack(interval: float) -> float:
	var list: Array = _spec.get("attacks", [_spec.anims.attack])
	_atk_i = pick_next(list.size(), _atk_i)
	_current = list[_atk_i]
	var length := _anim.get_animation(_current).length
	var speed := maxf(1.0, length / (interval * Art.ATTACK_FIT))
	_anim.play(_current, 0.15, speed)
	_anim.seek(0.0, true)
	return length * float(Art.HIT_FRAC.get(_current, 0.5)) / speed


## n개 중 하나를 무작위로, last(지난 번호, 처음엔 -1)는 빼고.
static func pick_next(n: int, last: int) -> int:
	if n <= 1:
		return 0
	if last < 0 or last >= n:
		return randi() % n
	var i := randi() % (n - 1)
	return i + 1 if i >= last else i


## 공격·발동 모션(반복 없는 것)이 아직 돌고 있는가 — 보스는 이게 끝날 때까지 걷기·대기로 끊지 않는다(monster.gd).
func is_busy() -> bool:
	if _current == "" or _current == _spec.anims.death or _anim == null or _anim.current_animation != _current:
		return false
	return _anim.get_animation(_current).loop_mode == Animation.LOOP_NONE


## 스킬 발동 모션(개정 25): anim_name을 처음부터. 발동 순간(길이 × Art.CAST_FRAC)이 Art.CAST_WINDUP초보다 늦으면 그만큼 빨리 돈다.
## 끝나면 대기로 돌아간다(공격과 같다). 이 모델에 없는 이름이면 공격 모션으로. 반환 = 발동 순간까지 초.
## at_sec > 0이면 발동 순간이 정확히 그 초에 오도록 빠르게·느리게(0.5~3배) 돈다(개정 26 — 보스 범위 예고에 맞춘다).
## frac > 0이면 발동 순간 비율을 Art.CAST_FRAC 대신 이것으로.
func play_cast(anim_name: String, at_sec := -1.0, frac := -1.0) -> float:
	if not _anim.has_animation(anim_name):
		anim_name = _spec.anims.attack
	_current = anim_name
	var f: float = frac if frac > 0.0 else float(Art.CAST_FRAC.get(anim_name, Art.HIT_FRAC.get(anim_name, 0.5)))
	var at: float = _anim.get_animation(anim_name).length * f
	var speed := maxf(1.0, at / Art.CAST_WINDUP) if at_sec <= 0.0 else clampf(at / at_sec, 0.5, 3.0)
	_anim.play(anim_name, 0.15, speed)
	_anim.seek(0.0, true)
	return at / speed


## 피격 반응(개정 26 — 타격감): 몸이 HIT_FLASH_SEC초 하얗게 번쩍이고(덧그림 재질, 끝나면 뗀다) 잠깐 찌그러졌다 돌아온다.
## strong(스킬·치명타)이면 더 밝고 크게. 연달아 맞으면 처음부터 다시. 번쩍였으면 true(간격 안이라 건너뛰면 false).
func hit_react(strong := false) -> bool:
	if not is_inside_tree():
		return false
	var now := Time.get_ticks_msec()
	if now - _flash_at < (HIT_FLASH_GAP_MS if not strong else HIT_FLASH_GAP_MS / 2):  # 여럿이 연달아 치면 깜빡임이 끊이지 않는다 — 간격을 둔다
		return false
	_flash_at = now
	if _flash_mat == null:
		_flash_mat = ShaderMaterial.new()
		_flash_mat.shader = HitFlashShader
	if _flash_meshes.is_empty():
		for mi in find_children("*", "MeshInstance3D", true, false):
			if mi.is_visible_in_tree():
				_flash_meshes.append(mi)
	if _hit_tw != null:
		_hit_tw.kill()
	for mi in _flash_meshes:
		if is_instance_valid(mi):
			mi.material_overlay = _flash_mat
	var peak := 1.0 if strong else 0.6
	var squash := Vector3.ONE.lerp(HIT_SQUASH, 1.0 if strong else 0.5)
	scale = _base_scale * squash
	_hit_tw = create_tween()
	_hit_tw.tween_method(_set_flash, peak, 0.0, HIT_FLASH_SEC)
	_hit_tw.parallel().tween_property(self, "scale", _base_scale, HIT_SQUASH_SEC).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_hit_tw.tween_callback(_end_flash)
	return true


func _set_flash(v: float) -> void:
	for mi in _flash_meshes:
		if is_instance_valid(mi):
			mi.set_instance_shader_parameter("flash", v)


func _end_flash() -> void:
	for mi in _flash_meshes:
		if is_instance_valid(mi):
			mi.material_overlay = null
	scale = _base_scale


## 이름 있는 모션을 반복 재생(돌진 달리기 등 — 대기·걷기·공격 밖의 것). 없는 이름이면 걷기.
func play_loop(anim_name: String, speed := 1.0) -> void:
	if not _anim.has_animation(anim_name):
		anim_name = _spec.anims.walk
	if _current == anim_name:
		return
	_anim.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
	_current = anim_name
	_anim.play(anim_name, 0.12, speed)


## 사망 애니메이션은 반복하지 않으므로 마지막 자세(쓰러짐)로 멈춘다.
func play_death() -> void:
	if _hit_tw != null and _hit_tw.is_valid():
		_hit_tw.kill()
		_end_flash()
	_play(_spec.anims.death)


## 리필 때: 사망 자세에서 대기로 즉시 복귀.
func reset_pose() -> void:
	_current = ""
	play_idle()


## manual일 때 애니메이션을 dt초 돌린다.
func advance(dt: float) -> void:
	_anim.advance(dt)


func _process(delta: float) -> void:
	tick(delta)


## lod 한 프레임(테스트가 직접 부른다): 시간을 쌓고, 이번 프레임이 갱신 차례면 쌓인 만큼 돌린다. 돌렸으면 true.
## crowd_lod면 붐빔에 따라 그림자를 맞춘다.
func tick(delta: float) -> bool:
	_frame += 1
	_acc += delta
	var crowded := false
	if crowd_lod:
		_count_crowd()
		crowded = _crowd_n >= CROWD_AT
		if _shadows != _crowd_shadows:
			_set_shadows(_crowd_shadows)
	var every := CROWD_EVERY if crowded else 1
	var cam := get_viewport().get_camera_3d()
	if cam != null and not cam.is_position_in_frustum(global_position):
		every = OFFSCREEN_EVERY
	if _frame % every != 0:
		return false
	_anim.advance(_acc)
	_acc = 0.0
	return true


## 이번 프레임 붐빔(살아 있는 겹침 유닛 수)을 한 번만 센다 — 그림자는 경계 사이에서 그대로(히스테리시스).
func _count_crowd() -> void:
	var f := Engine.get_process_frames()
	if f == _crowd_frame:
		return
	_crowd_frame = f
	_crowd_n = 0
	for u in get_tree().get_nodes_in_group("crowd"):
		_crowd_n += 1 if u.is_alive() else 0
	if _crowd_n >= SHADOW_OFF_AT:
		_crowd_shadows = false
	elif _crowd_n <= SHADOW_ON_AT:
		_crowd_shadows = true


func _set_shadows(on: bool) -> void:
	_shadows = on
	for m in _meshes:
		m[0].cast_shadow = m[1] if on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## 수평 방향 dir 쪽을 본다.
func face(dir: Vector3) -> void:
	if Vector2(dir.x, dir.z).length() < 0.001:
		return
	rotation.y = atan2(dir.x, dir.z)


func _play(anim_name: String) -> void:
	if _current == anim_name:
		return
	_current = anim_name
	_anim.play(anim_name, 0.15)


func _on_finished(anim_name: StringName) -> void:
	if anim_name == _current and anim_name != _spec.anims.death and anim_name != _spec.anims.idle and anim_name != _spec.anims.walk:  # 공격·발동 모션
		_current = ""
		play_idle()
