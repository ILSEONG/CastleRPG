extends RefCounted
## 던전 탭 카드 그림 띠의 3D 장면(scene_snap.gd가 한 번 찍어 캐시). 무대·조명 = ArenaKit, 몬스터·영웅 = UnitModel + Art 스펙. 오토로드 참조 없음.
## 골드: 평야 — 낮은 옆 시점(망원). 왼쪽 영웅들이 오른쪽을 보고, 오른쪽엔 고블린 무리와 그 뒤 큰 고블린 왕, 멀리 산.
## 장비: 불타는 성 홀 — 앞에서 낮게 올려다본다. 부서진 아치 앞 데스나이트가 가운데, 양옆 앞에 영웅들의 등, 화로·바닥 불·불씨.
## 골드 자리는 카메라 기준 (옆 x = 화면 오른쪽, 깊이 z = 카메라 앞, m), 장비 자리는 홀 좌표(ArenaKit: +Z = 화면 아래).

const ArenaKit := preload("res://scripts/arena_kit.gd")
const Art := preload("res://scripts/art.gd")
const GameData := preload("res://scripts/game_data.gd")
const UnitModelScript := preload("res://scripts/unit_model.gd")

const SIZE := Vector2i(1256, 360)  # 카드 띠(720 화면에서 628×180)의 2배 — 줄여 그려 선명하게
const WARM := 4  # 찍기 전 프레임: 대기 자세 적용·불씨
const HEROES := 3  # 띠에 세우는 영웅 수(출전 편성 앞에서부터)

const GOLD_EYE := Vector2(14.0, -1.0)  # 카메라 바닥 자리 spot(u, v)
const GOLD_EYE_H := 1.3
const GOLD_LOOK := Vector3(0.5, 2.3, 20.0)  # 바라보는 점 (옆, 높이, 깊이)
const GOLD_FOV := 19.2  # 세로(가로 ≈ 61°)
const GOLD_HEROES := [Vector2(-1.7, 15.0), Vector2(-5.75, 14.0), Vector2(-4.3, 16.0)]  # (옆, 깊이) — 화면 x ≈ 0.38, 0.13, 0.25
const GOLD_GOBLINS := [Vector2(1.4, 17.0), Vector2(2.7, 19.0), Vector2(4.3, 16.5), Vector2(6.2, 20.0), Vector2(7.0, 17.5),
	Vector2(9.4, 21.0), Vector2(9.9, 19.0)]  # 화면 x ≈ 0.55 ~ 0.92
const GOLD_KING := Vector2(5.6, 23.5)  # 화면 x ≈ 0.68, 고블린 너머(상체가 무리 위로)

const HALL_EYE := Vector3(0, 1.2, 13.0)
const HALL_LOOK := Vector3(0, 3.5, -6.0)  # 데스나이트 가슴 위(무대 boss = 홀 (0, 0, −6)) — 7° 올려다봄
const HALL_FOV := 28.6  # 세로(가로 ≈ 84° — 홀 폭이 다 든다)
const HALL_HEROES := [Vector3(-5.6, 0, 4.5), Vector3(5.2, 0, 5.0), Vector3(-3.0, 0, 0.5)]  # 앞 양옆(발끝만 잘림) + 왼쪽 가운데 — 화면 x ≈ 0.13, 0.87, 0.37
const HALL_FILL := [Vector3(0, 2.5, -1.0), Color(1.0, 0.5, 0.25), 1.4, 9.0]  # 데스나이트 앞면 채움 빛 [자리, 색, 세기, 범위]


## type "gold" | "equip". hero_ids = 출전 편성 영웅 id(앞 HEROES개만, 표에 없는 id는 뺀다). SceneSnap.snap의 build로 bind해서 쓴다.
static func build(root: Node3D, type: String, hero_ids: Array) -> void:
	var heroes := []
	for id in hero_ids:
		if heroes.size() < HEROES and not GameData.hero(id).is_empty():
			heroes.append(Art.hero_spec(GameData.hero(id)))
	if type == "gold":
		_gold(root, heroes)
	else:
		_hall(root, heroes)


static func _gold(root: Node3D, heroes: Array) -> void:
	var st: Dictionary = ArenaKit.plains()
	root.add_child(ArenaKit.lighting(st.light))
	root.add_child(st.root)
	var right := ArenaKit.RIGHT * 0.87 + ArenaKit.DOWN * 0.5  # 오른쪽 + 카메라 쪽 30°(얼굴이 보이게)
	var left := -ArenaKit.RIGHT * 0.87 + ArenaKit.DOWN * 0.5
	for i in mini(heroes.size(), HEROES):
		_unit(root, heroes[i], _gold_at(GOLD_HEROES[i]), right)
	for p in GOLD_GOBLINS:
		_unit(root, Art.MONSTER_MODELS.goblin, _gold_at(p), left)
	_unit(root, Art.MONSTER_MODELS.goblin_king, _gold_at(GOLD_KING), left)
	_camera(root, _gold_at(Vector2.ZERO) + Vector3(0, GOLD_EYE_H, 0), _gold_at(Vector2(GOLD_LOOK.x, GOLD_LOOK.z)) + Vector3(0, GOLD_LOOK.y, 0), GOLD_FOV)


## 카메라 기준 (옆, 깊이) → 월드 바닥. 카메라는 화면 위쪽(−DOWN, 먼 산 쪽)을 본다.
static func _gold_at(p: Vector2) -> Vector3:
	return ArenaKit.spot(GOLD_EYE.x - p.y, GOLD_EYE.y + p.x)


static func _hall(root: Node3D, heroes: Array) -> void:
	var st: Dictionary = ArenaKit.castle()
	root.add_child(ArenaKit.lighting(st.light))
	root.add_child(st.root)
	var hw := Basis(Vector3.UP, ArenaKit.HALL_YAW)
	_unit(root, Art.MONSTER_MODELS.death_knight, st.boss, ArenaKit.DOWN)
	for i in mini(heroes.size(), HEROES):
		var p: Vector3 = hw * HALL_HEROES[i]
		_unit(root, heroes[i], p, st.boss - p)
	var fill := OmniLight3D.new()
	fill.position = hw * HALL_FILL[0]
	fill.light_color = HALL_FILL[1]
	fill.light_energy = HALL_FILL[2]
	fill.omni_range = HALL_FILL[3]
	root.add_child(fill)
	_camera(root, hw * HALL_EYE, hw * HALL_LOOK, HALL_FOV)


static func _unit(root: Node3D, spec: Dictionary, pos: Vector3, facing: Vector3) -> void:
	var m = UnitModelScript.new()
	m.setup(spec, spec.get("scale", 1.0))
	m.position = pos
	m.face(facing)
	root.add_child(m)


## 원근 카메라(세로 화각 fov°). 트리 밖에서도 된다(look_at 대신 Basis.looking_at).
static func _camera(root: Node3D, eye: Vector3, target: Vector3, fov: float) -> void:
	var cam := Camera3D.new()
	cam.fov = fov
	cam.near = 0.3
	cam.far = 400.0
	cam.transform = Transform3D(Basis.looking_at(target - eye), eye)
	root.add_child(cam)
