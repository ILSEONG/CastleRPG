extends Node3D
## 캐릭터 모델 래퍼: KayKit 모델 인스턴스, 안 쓰는 부착물 숨김, 무기 부착, 애니메이션 재생, 방향.
## spec = Art.hero_spec(영웅 정의) 또는 Art.MONSTER_MODELS[kind]. KayKit 모델 정면은 +Z.
# ponytail: 성능 한계 — 캐릭터 하나 = AnimationPlayer 1개 + 스킨 메시 드로 ~10개(+ 그림자 패스). 스켈레톤 120개면 애니메이션만
# 데스크톱 네이티브 실측 ~2.2 ms/프레임, 모바일 웹은 5–10배 예상. 올릴 길: 멀리·화면 밖 유닛의 애니메이션 건너뛰기/간헐 갱신,
# 몬스터 그림자 끄기, 스켈레톤당 메시 수 줄이기, 또는 화면 표시 상한 낮추기.

const Art := preload("res://scripts/art.gd")

var _spec: Dictionary = {}
var _anim: AnimationPlayer
var _current := ""


## add_child 전에 호출.
func setup(spec: Dictionary, extra_scale := 1.0) -> void:
	_spec = spec
	scale = Vector3.ONE * Art.CHARACTER_SCALE * extra_scale


func _ready() -> void:
	var model := Art.instance(_spec.scene)
	add_child(model)
	for mesh_name in _spec.hide:
		var n := model.find_child(mesh_name, true, false) as Node3D
		if n != null:
			n.visible = false
	if _spec.has("weapon"):
		var skel := model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		var slot := BoneAttachment3D.new()
		slot.bone_name = Art.WEAPON_BONE
		skel.add_child(slot)
		slot.add_child(Art.instance(_spec.weapon))
	_anim = model.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	for anim_name in [_spec.anims.idle, _spec.anims.walk]:
		_anim.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR  # 공유 리소스라 한 번 바꾸면 전부 적용
	_anim.animation_finished.connect(_on_finished)
	play_idle()


func play_idle() -> void:
	_play(_spec.anims.idle)


func play_walk() -> void:
	_play(_spec.anims.walk)


## 공격 때마다 처음부터. 끝나면 대기로 돌아간다. 공격 간격 interval보다 길면 길이 ≤ 간격 × ATTACK_FIT가 되게 빨리 돈다.
## 반환 = 타격(발사) 순간까지 초(길이 × HIT_FRAC ÷ 속도).
func play_attack(interval: float) -> float:
	_current = _spec.anims.attack
	var length := _anim.get_animation(_current).length
	var speed := maxf(1.0, length / (interval * Art.ATTACK_FIT))
	_anim.play(_current, 0.1, speed)
	_anim.seek(0.0, true)
	return length * Art.HIT_FRAC[_current] / speed


## 사망 애니메이션은 반복하지 않으므로 마지막 자세(쓰러짐)로 멈춘다.
func play_death() -> void:
	_play(_spec.anims.death)


## 리필 때: 사망 자세에서 대기로 즉시 복귀.
func reset_pose() -> void:
	_current = ""
	play_idle()


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
	if anim_name == _spec.anims.attack and _current == _spec.anims.attack:
		_current = ""
		play_idle()
