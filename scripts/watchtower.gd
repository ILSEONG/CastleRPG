extends Node3D
## 망루(watchtower, 2026-10-13 · 2026-11-07 성벽 네 모서리로): 망루를 지으면 성벽 네 모서리 탑이 망루가 되어 성 전투(방치·스테이지 방어)에서
## 탑마다 interval초마다 화살 한 발을 쏜다(사용자 2026-11-07 "망루는 성벽 양 끝 모서리" → 네 모서리 전부). 성 안 부지는 없다(Balance "wall").
## 표적: 그 탑에서 수평 range m 안의 산 몬스터("monsters") — 성벽·성문에 붙어 치는 것(성 밖, 성벽 바깥면에서 SIEGE_BAND m 안)을
## 먼저, 그다음 가장 가까운 것. 화살은 탑 꼭대기에서 대상까지 포물선으로 날아가 도착 순간 m.take_damage(HIT) —
## 영웅 평타와 같은 피해 길(피해 숫자·처치 골드·처치 수는 몬스터 died → spawner가 센다).
## 피해 = 망루 레벨로만 정한 고정값(사용자 2026-11-07 "딜은 망루 레벨에 따라 고정으로"): watchtower_dmg_base + watchtower_dmg_per_level × 레벨
## (GameData 설정, 0이면 기본값 2 + 1.2 × 레벨 — Lv 1 3.2, Lv 10 14, Lv 30 38). 스테이지가 올라도 그대로다.
## 시간은 _process delta(Engine.time_scale = 배속 x1/x1.5/x2·히트스톱, 일시정지면 멈춤 — 영웅 평타와 같다). 성 월드가 던전·길드전 동안
## 트리에서 빠지면 이 노드도 멈춘다. 몬스터가 없으면(방치 화면 빈 때) 쏘지 않는다 — 방치 중 몬스터가 오면 영웅처럼 싸운다.
## 망루 상태는 Economy(is_built·building_level)에서, 탑 자리·높이는 castle(half·look)에서 읽는다. 짓지 않았으면 아무 일도 없다.
## 테스트: level_override(≥ 1)로 Economy 없이 망루를 세운다(pos_override(Vector3)를 주면 그 한 곳에서만 쏜다).
## 길드전 공성(war_battle.gd)은 영웅 대 영웅 별도 시뮬레이션이라 여기 붙이지 않는다.

const GameData := preload("res://scripts/game_data.gd")
const Balance := preload("res://scripts/balance.gd")
const Formation := preload("res://scripts/formation.gd")
const DamageNumbers := preload("res://scripts/damage_numbers.gd")
const Sfx := preload("res://scripts/sfx.gd")
const TownKit := preload("res://scripts/town_kit.gd")

const ID := "watchtower"
const DEF_DMG_BASE := 2.0
const DEF_DMG_PER_LEVEL := 1.2
const DEF_INTERVAL := 2.0
const DEF_RANGE := 60.0
const MUZZLE_Y := 7.0  # pos_override(테스트)일 때 쏘는 높이
const MUZZLE_UP := 0.6  # 모서리 탑 흉벽 위로
const ARROW_SPEED := 28.0  # 수평 m/s
const ARC_PER_M := 0.12  # 포물선 꼭짓점 높이 = 수평 거리 × 이만큼(최소 ARC_MIN)
const ARC_MIN := 1.0
const LOOK_SCALE := 1.6  # 화살 모양 배율(영웅 화살 대비)
const SIEGE_BAND := 4.0  # 성벽 바깥면에서 이 거리 안 성 밖 몬스터 = 성문·성벽을 치는 중(먼저 쏜다)

var castle  # main이 넣는다(castle.half·look) — 없으면 탑 자리를 모른다(쏘지 않는다, pos_override 빼고)
var level_override := -1
var pos_override = null
var shots := 0  # 쏜 화살 수(테스트용)

var _cd := {}  # 탑 번호 → 남은 쿨다운(초). 처음엔 탑마다 interval/4씩 엇갈려 한꺼번에 쏘지 않는다


## 지금 망루 {level, towers: [쏘는 자리(탑 꼭대기)…]}, 없으면 {}(짓지 않음·건물 표에 없음·성을 모름).
func tower() -> Dictionary:
	var lv := level_override
	if lv < 1:
		if Balance.building(ID).is_empty() or not Economy.is_built(ID):
			return {}
		lv = Economy.building_level(ID)
	if pos_override is Vector3:
		return {"level": lv, "towers": [pos_override + Vector3(0, MUZZLE_Y, 0)], "r": 0.0}
	if castle == null:
		return {}
	var lk := int(castle.get("look") if castle.get("look") != null else 0)
	return {"level": lv, "towers": corner_muzzles(float(castle.half), lk), "r": float(TownKit.LOOK_TOWER_R[clampi(lk, 0, TownKit.LOOK_TOWER_R.size() - 1)])}


## 네 모서리 탑 꼭대기(흉벽 위) — castle._build_look의 탑 자리와 같다.
static func corner_muzzles(half: float, look: int) -> Array:
	var c := half + Balance.WALL_T / 2.0
	var lk := clampi(look, 0, TownKit.LOOK_TOWER_H.size() - 1)
	var y := float(TownKit.LOOK_TOWER_H[lk]) + (0.5 if lk >= 3 else 0.0) + MUZZLE_UP
	var out := []
	for k in 4:
		var p: Vector3 = (Formation.SIDE_DIR[k] + Formation.SIDE_DIR[(k + 1) % 4]) * c
		out.append(Vector3(p.x, y, p.z))
	return out


static func num(key: String, fallback: float) -> float:
	var v := GameData.config_num(key)
	return v if v > 0.0 else fallback


static func interval() -> float:
	return num("watchtower_interval_sec", DEF_INTERVAL)


static func range_m() -> float:
	return num("watchtower_range_m", DEF_RANGE)


## 화살 한 발 피해: 망루 레벨만으로 정한다(스테이지와 무관).
static func damage(level: int) -> float:
	return num("watchtower_dmg_base", DEF_DMG_BASE) + num("watchtower_dmg_per_level", DEF_DMG_PER_LEVEL) * level


func _process(delta: float) -> void:
	var t := tower()
	if t.is_empty():
		return
	var towers: Array = t.towers
	for i in towers.size():
		var cd: float = _cd.get(i, interval() * i / 4.0) - delta
		_cd[i] = maxf(0.0, cd)
		if cd > 0.0:
			continue
		var at: Vector3 = towers[i]
		var m = pick_target(Vector3(at.x, 0, at.z))
		if m == null:
			continue
		_cd[i] = interval()
		var out := Vector3(m.global_position.x - at.x, 0, m.global_position.z - at.z)
		if out.length() > 0.01:
			at += out.normalized() * (float(t.get("r", 0.0)) + 0.3)  # 흉벽 앞(표적 쪽)에서 — 탑 지붕 속에서 나오지 않게
		_fire(m, damage(int(t.level)), at)


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
	a.launch(at)
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
