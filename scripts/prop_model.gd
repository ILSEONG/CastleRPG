extends Node3D
## 움직이지 않는 적의 생김새(파티 퀘스트): 영혼 수정(리치 — 떠서 도는 보랏빛 결정 + 빛무리)과 거미 알 주머니(거미 여왕 — 고동치는 알 덩이).
## unit_model.gd와 같은 이름의 함수만 둔다(monster.gd가 부른다) — 걷기·공격 모션은 없다. 맞으면 하얗게 번쩍·찌그러지고, 죽으면 부서지며 사라진다.

const MeshKit := preload("res://scripts/mesh_kit.gd")
const Art := preload("res://scripts/art.gd")
const Fx := preload("res://scripts/fx.gd")

const CRYSTAL := Color(0.45, 0.95, 0.85)
const CRYSTAL_DARK := Color(0.30, 0.20, 0.55)
const EGG := Color(0.90, 0.86, 0.72)
const EGG_VEIN := Color(0.55, 0.85, 0.30)
const WEB := Color(0.80, 0.80, 0.76)

var shape := "crystal"  # crystal | egg
var crowd_lod := false
var pulse := 1.0  # 알: 부화가 가까울수록 빨리 고동친다(party_minion이 올린다)

var _body: Node3D
var _t := 0.0
var _dead := false
var _flash := 0.0


func _ready() -> void:
	_body = Node3D.new()
	add_child(_body)
	var mi := MeshInstance3D.new()
	mi.mesh = _crystal_mesh() if shape == "crystal" else _egg_mesh()
	mi.material_override = Art.lowpoly_vc_material()
	_body.add_child(mi)
	if shape == "crystal":
		_body.position.y = 0.9
		Fx.halo(self, global_position + Vector3(0, 1.4, 0), CRYSTAL, 2.2, 0.0)  # 늘 켜 둔 빛무리
		var l := OmniLight3D.new()
		l.light_color = CRYSTAL
		l.light_energy = 1.2
		l.omni_range = 4.0
		l.position.y = 1.4
		add_child(l)


func _process(delta: float) -> void:
	if _dead:
		return
	_t += delta
	if shape == "crystal":
		_body.rotation.y += delta * 1.2
		_body.position.y = 0.9 + sin(_t * 2.0) * 0.15
	else:
		var s := 1.0 + sin(_t * 4.0 * pulse) * 0.05 * pulse
		_body.scale = Vector3(s, 2.0 - s, s)
	if _flash > 0.0:
		_flash -= delta
		if _flash <= 0.0:
			_body.scale = Vector3.ONE


func _crystal_mesh() -> ArrayMesh:
	var k = MeshKit.new()
	k.prism_n(Vector3(0, 0, 0), 5, 0.05, 0.5, 0.7, CRYSTAL_DARK)
	k.prism_n(Vector3(0, 0.7, 0), 5, 0.5, 0.05, 1.3, CRYSTAL)
	for i in 3:
		var a := TAU * i / 3.0
		var keep: Transform3D = k.xform
		k.xform = keep * Transform3D(Basis(Vector3(cos(a), 0, sin(a)).cross(Vector3.UP).normalized(), 0.6), Vector3(cos(a) * 0.35, 0.4, sin(a) * 0.35))
		k.prism_n(Vector3.ZERO, 4, 0.16, 0.02, 0.7, CRYSTAL.lightened(0.15))
		k.xform = keep
	return k.commit()


func _egg_mesh() -> ArrayMesh:
	var k = MeshKit.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	k.prism_n(Vector3(0, 0, 0), 8, 0.9, 0.95, 0.06, WEB.darkened(0.3))
	for i in 7:
		var a := TAU * i / 7.0
		var r := 0.35 if i > 0 else 0.0
		var c := Vector3(cos(a) * r, 0.45 + (0.35 if i == 0 else 0.0), sin(a) * r)
		k.rock(c, 0.42 if i == 0 else 0.33, EGG.darkened(rng.randf_range(0.0, 0.12)), rng, 1.25, 0.0)
	for i in 5:  # 겉 핏줄(초록 독)
		var a := TAU * i / 5.0
		k.box(Vector3(cos(a) * 0.45, 0.6, sin(a) * 0.45), Vector3(0.06, 0.5, 0.06), EGG_VEIN)
	return k.commit()


func play_idle() -> void:
	pass


func play_walk() -> void:
	pass


func play_loop(_name: String, _speed := 1.0) -> void:
	pass


func play_attack(_interval: float) -> float:
	return 0.3


func play_cast(_name: String, _at := -1.0, _frac := -1.0) -> float:
	return 0.3


func is_busy() -> bool:
	return false


func reset_pose() -> void:
	pass


func face(_dir: Vector3) -> void:
	pass


func hit_react(strong: bool) -> bool:
	_flash = 0.12
	_body.scale = Vector3(1.12, 0.88, 1.12) if strong else Vector3(1.06, 0.94, 1.06)
	return true


func play_death() -> void:
	if _dead:
		return
	_dead = true
	var par := get_parent().get_parent() if get_parent() != null else null
	if par != null:
		var at := global_position + Vector3(0, 0.8, 0)
		if shape == "crystal":
			Fx.blast(par, global_position, CRYSTAL, 1.6, false, 1)
		else:
			Fx.splash(par, global_position, EGG_VEIN, 1.2)
			Fx.spark(par, at, EGG, 0.8)
	var tw := create_tween()
	tw.tween_property(_body, "scale", Vector3(1.4, 0.05, 1.4), 0.25)
	tw.tween_callback(func(): visible = false)
