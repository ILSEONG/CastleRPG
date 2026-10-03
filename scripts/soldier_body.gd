extends RefCounted
## 병종 몸(개정 13 §7, 개정 15 다듬기): UnitModel(Art.soldier_spec, 크기 Art.SOLDIER_SCALE) + 기병이면 로우폴리 말(TownKit.horse, 같은 크기)과
## 그 등 위 기사(RIDER_Y). 월드 병사(soldier.gd)와 병사 피규어(Portraits "soldier:<병종>")가 이것 하나로 만든다.
## 오토로드 참조 없음 → 헤드리스 테스트(run_tests -s)와 Portraits에서 preload 가능.

const Art := preload("res://scripts/art.gd")
const GameData := preload("res://scripts/game_data.gd")
const TownKit := preload("res://scripts/town_kit.gd")
const UnitModelScript := preload("res://scripts/unit_model.gd")

const RIDER_HIP := 0.48  # KayKit 기사 엉덩이(다리 뿌리 0.41~0.52) — 말 등에 앉는 높이
const RIDER_Y := (TownKit.HORSE_BACK - RIDER_HIP) * Art.SOLDIER_SCALE  # 기사 모델 높이 = (말 등 − 엉덩이) × 크기

static var _horse_mesh: ArrayMesh  # 말 메시는 하나를 같이 쓴다


## parent 아래에 병종 type의 몸을 만든다(모델 먼저, 그다음 말). 반환 [UnitModel, 말 MeshInstance3D 또는 null].
## world = 월드 병사: UnitModel.crowd_lod(화면 밖·붐빌 때 간헐 갱신, 붐비면 그림자 끔 — add_child 전에 정해야 한다).
static func build(parent: Node3D, type: String, world := false) -> Array:
	var model = UnitModelScript.new()
	model.crowd_lod = world
	model.setup(Art.soldier_spec(type, GameData.soldier(type).model), Art.SOLDIER_SCALE)
	parent.add_child(model)
	if not Art.SOLDIERS[type].get("horse", false):
		return [model, null]
	if _horse_mesh == null:
		_horse_mesh = TownKit.horse()
	var horse := MeshInstance3D.new()
	horse.mesh = _horse_mesh
	horse.material_override = Art.lowpoly_vc_material()
	horse.scale = Vector3.ONE * Art.SOLDIER_SCALE  # 말 길이 ≈ 2.0 m — 기병은 두 줄 건너 선다(Formation.soldier_spots)
	parent.add_child(horse)
	model.position.y = RIDER_Y
	return [model, horse]
