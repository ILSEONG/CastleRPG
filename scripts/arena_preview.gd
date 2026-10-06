extends Node3D
## 개발용 던전 무대 미리보기(개정 18 웹 캡처): `-- --arena=plains|castle`(웹 `?arena=`), 디버그·오프라인에서만 main이 붙인다(월드 대신).
## 무대 + 조명 + 스폰 자리에 선 적(대기 동작, 영웅 쪽을 봄)·영웅 + 성 전장 카메라 리그. 성 내부는 드랍 상자 6등급과 LR 빛기둥도 놓는다. 전투 없음.

const ArenaKit := preload("res://scripts/arena_kit.gd")
const Art := preload("res://scripts/art.gd")
const GameData := preload("res://scripts/game_data.gd")
const UnitModelScript := preload("res://scripts/unit_model.gd")
const CameraRigScript := preload("res://scripts/camera_rig.gd")
const CASTLE_CAMERA_SIZE := 40.0  # 홀(30 m)과 기둥 줄이 화면 폭에 들어오게
const PLAINS_CAMERA_SIZE := 50.0  # 전장(66)보다 조금 당겨 고블린 무리가 보이게(캡처용)


func _ready() -> void:
	var castle := Net.arg_value("arena") == "castle"
	var stage: Dictionary = ArenaKit.castle() if castle else ArenaKit.plains()
	add_child(ArenaKit.lighting(stage.light))
	add_child(stage.root)
	for p in stage.enemies:
		_unit(Art.monster_spec("goblin"), p, ArenaKit.DOWN)
	_unit(Art.monster_spec("death_knight" if castle else "goblin_king"), stage.boss, ArenaKit.DOWN)
	var heroes: Array = GameData.heroes()
	for i in stage.heroes.size():
		_unit(Art.hero_spec(heroes[i % heroes.size()]), stage.heroes[i], -ArenaKit.DOWN)
	if castle:
		var grades: Array = Art.ITEM_GRADE_COLORS.keys()
		for i in grades.size():
			var chest := ArenaKit.drop_chest(grades[i])
			chest.position = ArenaKit.spot(2.0, -6.5 + i * 1.6)
			add_child(chest)
		var pillar := ArenaKit.light_pillar("LR")
		pillar.position = ArenaKit.spot(2.0, 4.5)
		add_child(pillar)
	var rig = CameraRigScript.new()
	add_child(rig)
	rig.camera.size = CASTLE_CAMERA_SIZE if castle else PLAINS_CAMERA_SIZE
	rig.zoom_by(1.0)  # 줌에 맞춰 깊이(near/far) 다시 맞춤
	print("[arena] %s heroes %d enemies %d + boss" % ["castle" if castle else "plains", stage.heroes.size(), stage.enemies.size()])


func _unit(spec: Dictionary, pos: Vector3, facing: Vector3) -> void:
	var m = UnitModelScript.new()
	m.setup(spec, spec.get("scale", 1.0))
	m.position = pos
	add_child(m)
	m.face(facing)
