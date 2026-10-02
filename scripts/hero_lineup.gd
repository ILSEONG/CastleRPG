extends Node3D
## 개발용 영웅 줄 세우기(웹 캡처로 생김새 검토): `-- --lineup`(웹 `?lineup`), 디버그·오프라인에서만 main이 붙인다(월드 대신).
## 영웅 22명을 표 순서로 COLS열 격자에 세워 카메라 쪽을 보게 하고, 발밑에 이름표. 성 전장과 같은 조명·카메라 리그(가장 가까운 줌). 전투 없음.

const ArenaKit := preload("res://scripts/arena_kit.gd")
const Art := preload("res://scripts/art.gd")
const Balance := preload("res://scripts/balance.gd")
const GameData := preload("res://scripts/game_data.gd")
const UnitModelScript := preload("res://scripts/unit_model.gd")
const CameraRigScript := preload("res://scripts/camera_rig.gd")
const FONT := preload("res://assets/fonts/Pretendard-SemiBold.otf")

const COLS := 4
const GAP_V := 3.6  # 화면 가로 간격(m)
const GAP_U := 5.6  # 화면 세로(깊이) 간격(m) — 피치 35°에서 키 큰 모자(≈3 m)와 이름표가 앞줄과 겹치지 않게

var units: Array = []  # 세운 UnitModel(표 순서) — 테스트가 본다


func _ready() -> void:
	add_child(ArenaKit.lighting({"background": Color(0.86, 0.91, 0.96), "ambient": Color(0.78, 0.80, 0.86), "ambient_energy": 0.9,
		"sun_color": Color(1.0, 0.96, 0.88), "sun_energy": 1.1, "sun_rot": Vector3(-50, -45, 0), "shadows": true, "omni": []}))
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	ground.mesh = plane
	var mat := StandardMaterial3D.new()  # 풀색 평면
	mat.albedo_color = Color(0.47, 0.58, 0.36)
	mat.roughness = 1.0
	ground.material_override = mat
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ground)
	var heroes: Array = GameData.heroes()
	var rows := ceili(heroes.size() / float(COLS))
	for i in heroes.size():
		var h: Dictionary = heroes[i]
		var pos := ArenaKit.spot((i / COLS - (rows - 1) / 2.0) * GAP_U, (i % COLS - (COLS - 1) / 2.0) * GAP_V)
		var m = UnitModelScript.new()
		m.setup(Art.hero_spec(h))
		m.position = pos
		add_child(m)
		m.face(ArenaKit.DOWN)
		units.append(m)
		var label := Label3D.new()
		label.text = "%s\n%s" % [h.name, h.title]  # 두 줄 — 한 줄이면 옆 칸 이름표와 겹친다
		label.font = FONT
		label.font_size = 32
		label.pixel_size = 0.01
		label.outline_size = 10
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.position = pos + ArenaKit.DOWN * 0.9 + Vector3(0, 0.05, 0)
		add_child(label)
	var rig = CameraRigScript.new()
	add_child(rig)
	rig.camera.size = Balance.CAMERA_SIZE_MIN
	rig.zoom_by(1.0)  # 줌에 맞춰 깊이(near/far) 다시 맞춤
	print("[lineup] heroes %d" % heroes.size())
