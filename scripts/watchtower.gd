extends Node3D
## 망루(watchtower, 2026-10-13): 성 안에 지은 망루가 성 전투(방치·스테이지 방어)에서 interval초마다 화살 한 발을 쏜다.
## 표적: 망루 부지 가운데에서 수평 range m 안의 산 몬스터("monsters") — 성벽·성문에 붙어 치는 것(성 밖, 성벽 바깥면에서 SIEGE_BAND m 안)을
## 먼저, 그다음 가장 가까운 것. 화살은 망루 꼭대기(MUZZLE_Y)에서 대상까지 포물선으로 날아가 도착 순간 m.take_damage(HIT) —
## 영웅 평타와 같은 피해 길(피해 숫자·처치 골드·처치 수는 몬스터 died → spawner가 센다).
## 피해 = 현재 스테이지 grunt 최대 HP × (grunt_pct_base + grunt_pct_per_level × 레벨) / 100 (GameData 설정, 0이면 기본값).
## 시간은 _process delta(Engine.time_scale = 배속 x1/x1.5/x2·히트스톱, 일시정지면 멈춤 — 영웅 평타와 같다). 성 월드가 던전·길드전 동안
## 트리에서 빠지면 이 노드도 멈춘다. 몬스터가 없으면(방치 화면 빈 때) 쏘지 않는다 — 방치 중 몬스터가 오면 영웅처럼 싸운다.
## 망루 상태는 Economy(is_built·building_level·is_placed)와 Balance.center_of에서 읽는다. 망루가 아직 건물 표에 없거나 짓지 않았으면 아무 일도 없다.
## 테스트: level_override(≥ 1) · pos_override(Vector3)로 Economy 없이 망루를 세운다.
## 길드전 공성(war_battle.gd)은 영웅 대 영웅 별도 시뮬레이션이고 성 안에 건물이 없어 여기 붙이지 않는다.

const GameData := preload("res://scripts/game_data.gd")
const Balance := preload("res://scripts/balance.gd")
const Formation := preload("res://scripts/formation.gd")
const DamageNumbers := preload("res://scripts/damage_numbers.gd")
const Sfx := preload("res://scripts/sfx.gd")

const ID := "watchtower"
const DEF_PCT_BASE := 10.0
const DEF_PCT_PER_LEVEL := 1.0
const DEF_INTERVAL := 2.0
const DEF_RANGE := 60.0
const MUZZLE_Y := 7.0  # 꼭대기 발판 높이(모델 7~9 m)
const ARROW_SPEED := 28.0  # 수평 m/s
const ARC_PER_M := 0.12  # 포물선 꼭짓점 높이 = 수평 거리 × 이만큼(최소 ARC_MIN)
const ARC_MIN := 1.0
const LOOK_SCALE := 1.6  # 화살 모양 배율(영웅 화살 대비)
const SIEGE_BAND := 4.0  # 성벽 바깥면에서 이 거리 안 성 밖 몬스터 = 성문·성벽을 치는 중(먼저 쏜다)

var castle  # main이 넣는다(castle.half) — 없으면 성문 우선 없이 가장 가까운 것
var level_override := -1
var pos_override = null
var shots := 0  # 쏜 화살 수(테스트용)

var _cd := 0.0


## 지금 망루 {level, pos}, 없으면 {}(짓지 않음·건물 표에 없음).
func tower() -> Dictionary:
	if level_override >= 1 and pos_override is Vector3:
		return {"level": level_override, "pos": pos_override}
	if Balance.building(ID).is_empty():
		return {}
	if not (Economy.is_built(ID) and Economy.is_placed(ID)):
		return {}
	return {"level": Economy.building_level(ID), "pos": Balance.center_of(ID)}


static func num(key: String, fallback: float) -> float:
	var v := GameData.config_num(key)
	return v if v > 0.0 else fallback


static func interval() -> float:
	return num("watchtower_interval_sec", DEF_INTERVAL)


static func range_m() -> float:
	return num("watchtower_range_m", DEF_RANGE)


## 화살 한 발 피해: stage 라운드 grunt 최대 HP(monster.setup과 같은 식) × (base + per_level × level) / 100.
static func damage(level: int, stage: int) -> float:
	var grunt_hp := float(GameData.monster("grunt").get("hp", 0.0)) * float(GameData.stage(stage).get("hp_mult", 1.0))
	var pct := num("watchtower_grunt_pct_base", DEF_PCT_BASE) + num("watchtower_grunt_pct_per_level", DEF_PCT_PER_LEVEL) * level
	return grunt_hp * pct / 100.0


func _process(delta: float) -> void:
	_cd = maxf(0.0, _cd - delta)
	if _cd > 0.0:
		return
	var t := tower()
	if t.is_empty():
		return
	var m = pick_target(t.pos)
	if m == null:
		return
	_cd = interval()
	_fire(m, damage(int(t.level), GameState.stage), t.pos)


## 수평 range_m 안 산 몬스터: 성문·성벽을 치는 것(성 밖, 성벽 띠 안)이 먼저, 같은 무리 안에서는 가장 가까운 것.
func pick_target(from: Vector3):
	var r := range_m()
	var best = null
	var best_d := INF
	var best_siege := false
	for m in get_tree().get_nodes_in_group("monsters"):
		if not m.has_method("take_damage") or not m.is_alive():
			continue
		var mp: Vector3 = m.global_position
		var d := Formation.flat_distance(from, mp)
		if d > r:
			continue
		var siege := _sieging(mp)
		if (siege and not best_siege) or (siege == best_siege and d < best_d):
			best = m
			best_d = d
			best_siege = siege
	return best


func _sieging(p: Vector3) -> bool:
	if castle == null:
		return false
	var half: float = castle.half
	var out := maxf(absf(p.x), absf(p.z)) - (half + Balance.WALL_T)
	return out >= 0.0 and out <= SIEGE_BAND


func _fire(m, dmg: float, at: Vector3) -> void:
	shots += 1
	var a := Arrow.new()
	a.target = m
	a.kind = "arrow"
	a.speed = ARROW_SPEED
	a.on_hit = _hit.bind(dmg)
	var host: Node = get_parent() if get_parent() != null else self
	host.add_child(a)
	a.launch(at + Vector3(0, MUZZLE_Y, 0))
	Sfx.shot("arrow", a)


func _hit(m, dmg: float) -> void:
	if is_instance_valid(m) and m.is_alive():
		m.take_damage(dmg, DamageNumbers.Kind.HIT)


## 포물선 화살: 영웅 화살(projectile.gd)과 같은 모양·도착 규칙, 경로만 포물선(대상을 따라가며 꼭짓점이 거리에 비례).
class Arrow extends "res://scripts/projectile.gd":
	var _from := Vector3.ZERO
	var _t := 0.0
	var _dur := 1.0
	var _arc := ARC_MIN

	func launch(from: Vector3) -> void:
		_from = from
		global_position = from
		var dest: Vector3 = target.global_position + AIM
		var flat := Formation.flat_distance(from, dest)
		_dur = maxf(0.25, flat / speed)
		_arc = maxf(ARC_MIN, flat * ARC_PER_M)
		if _look != null:
			_look.scale *= LOOK_SCALE  # 멀리 날아 영웅 화살보다 조금 크게

	func _process(delta: float) -> void:
		if not is_instance_valid(target) or not target.is_alive():
			queue_free()
			return
		_t += delta / _dur
		var dest: Vector3 = target.global_position + AIM
		if _t >= 1.0:
			global_position = dest
			queue_free()
			if on_hit.is_valid():
				on_hit.call(target)
			return
		var p := _from.lerp(dest, _t) + Vector3(0, _arc * 4.0 * _t * (1.0 - _t), 0)
		var ahead := minf(1.0, _t + 0.02)
		var q := _from.lerp(dest, ahead) + Vector3(0, _arc * 4.0 * ahead * (1.0 - ahead), 0)
		global_position = p
		var dir := q - p
		if dir.length() > 0.001:
			look_at(p + dir, Vector3.UP if absf(dir.normalized().y) < 0.99 else Vector3.FORWARD)
