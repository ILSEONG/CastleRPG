extends RefCounted
## 기획 데이터 표(data/*.csv 또는 서버 /v1/gamedata). 처음 쓸 때 한 번 읽고 캐시한다.

const Balance := preload("res://scripts/balance.gd")
const Art := preload("res://scripts/art.gd")
const Skills := preload("res://scripts/skills.gd")
const MONSTERS_PATH := "res://data/monsters.csv"
const STAGES_PATH := "res://data/stages.csv"
const HEROES_PATH := "res://data/heroes.csv"
const RESOURCES_PATH := "res://data/resources.csv"
const CONFIG_PATH := "res://data/config.csv"
const BUILDINGS_PATH := "res://data/buildings.csv"
const SOLDIERS_PATH := "res://data/soldiers.csv"
const INT_COLS := ["waves", "wave_size"]  # 스테이지 연장 시 반올림하는 정수 열
const EXTEND_ROWS := 12  # 표 너머 연장 기울기를 잴 마지막 행 수 — 3의 배수라 3스테이지마다 오르는 waves도 기울기 1/3 그대로
const MIN_IDLE_INTERVAL := 0.5  # 연장해도 방치 스폰 간격이 0 이하로 가지 않게
const MONSTER_COLS := ["hp", "atk", "speed", "range", "atk_interval", "aggro", "scale", "gold"]
const STAGE_COLS := ["hp_mult", "atk_mult", "gold_mult", "waves", "wave_size", "idle_interval"]
const HERO_COLS := ["hp", "atk", "range", "atk_interval", "speed", "aggro"]
const HERO_STR_COLS := ["id", "name", "title", "grade", "role", "archetype", "model", "gear", "color", "desc"]
const HERO_SKILL_COLS := [["skill1", "s1a", "s1b", "s1c"], ["skill2", "s2a", "s2b", "s2c"]]  # 빈 칸 = 없음(서버는 null)
const GRADES := ["R", "SR", "SSR"]
const ROLES := ["melee", "ranged"]
const HERO_POSITIVE_COLS := ["hp", "range", "atk_interval", "speed"]  # 0보다 커야 한다(간격 0이면 매 프레임 공격)
const HERO_NONNEG_COLS := ["atk", "aggro"]
const GACHA_INT_KEYS := ["gacha_cost_1", "gacha_cost_10", "gacha_10_min_sr"]  # 0 이상 정수
const GACHA_RATE_KEYS := ["gacha_rate_ssr", "gacha_rate_sr"]  # 0..1, 합 ≤ 1
const RESOURCE_NUM_COLS := ["per_min", "price"]
const CONFIG_NUM_KEYS := ["castle_hp", "gate_hp_per_level", "max_live_monsters", "countdown_sec", "result_sec", "wave_gap_sec",
	"spawn_spacing_sec", "accum_cap_min", "badge_min", "merchant_jackpot_p", "merchant_jackpot_rate", "merchant_rate_min",
	"merchant_rate_max", "merchant_rate_step", "merchant_low_high_ratio", "kill_rate_cap", "hero_max_stars", "hero_star_bonus",
	"gacha_cost_1", "gacha_cost_10", "gacha_rate_ssr", "gacha_rate_sr", "gacha_10_min_sr",
	"hero_max_level_base", "hero_max_level_per_star", "hero_level_stat", "levelup_gold_R", "levelup_gold_SR", "levelup_gold_SSR"]
const CONFIG_LIST_KEYS := ["starter_heroes"]
# --- 건물(개정 12). 서버 rules.ts·seed.ts와 같은 규칙 ---
const BUILDING_STR_COLS := ["id", "name"]
const BUILDING_NUM_COLS := ["max_level", "wood", "stone", "food", "base_sec"]
const BUILDING_REQ_COLS := ["req1", "req2"]  # 선행 건물 id. 빈 칸(서버는 null) = 없음
const BUILD_RES := ["wood", "stone", "food"]  # 건물 비용 열 = 자원 id
const BUILD_COST_GROWTH := 1.35  # L → L+1 비용 = round(값 × 1.35^(L−1))
const BUILD_TIME_GROWTH := 1.5   # L → L+1 시간 = round(base_sec × 1.5^(L−1))
const KEEP := "keep"  # 다른 건물의 상한·영웅 슬롯·성 내부·성 HP
const GATE := "gate"  # 성문 HP(네 성문이 레벨 하나). 배치(Balance.BUILDINGS)에 없는 성 구조물
const LAB := "lab"  # 영웅 공격
const HOUSES := "houses"  # 인구
const TAVERN := "tavern"  # 모집 확률
const BUILDING_NUM_KEYS := ["castle_hp_per_level", "pop_base", "pop_per_house", "lab_atk_per_level",
	"tavern_ssr_per_level", "tavern_sr_per_level"]  # 0 이상, 주점 증가분은 1 이하, 인구는 정수
const POP_KEYS := ["pop_base", "pop_per_house"]
# --- 병사(개정 13). 서버 rules.ts·seed.ts와 같은 규칙 ---
const SOLDIER_STR_COLS := ["id", "name", "building", "model"]
const SOLDIER_NUM_COLS := ["hp", "atk", "range", "atk_interval", "speed", "aggro"]  # 1티어 기준
const SOLDIER_POSITIVE_COLS := ["hp", "range", "atk_interval", "speed"]  # 0보다 크다(나머지는 0 이상)
const SOLDIER_NUM_KEYS := ["soldier_max_tier", "soldier_tier_mult", "soldier_prod_sec", "soldier_prod_level_factor", "soldier_merge_count"]
const SOLDIER_INT_KEYS := ["soldier_max_tier", "soldier_merge_count"]  # 1 이상 정수(나머지는 0보다 크다)
const CONFIG_TIER_KEYS := ["keep_slot_tiers", "keep_interior_tiers"]  # 성채 단계 표 "레벨:값|…"(hero_slots·Balance.INTERIOR_TILES를 대신)
const MIN_INTERIOR_TILES := 20  # 건물 배치(Balance.BUILDINGS)가 들어가는 가장 작은 성 내부 — 더 작으면 그릴 수 없다
const LEVELUP_INT_KEYS := ["hero_max_level_per_star", "levelup_gold_R", "levelup_gold_SR", "levelup_gold_SSR"]  # 0 이상 정수(개정 11, 12: 골드만)
const LEVELUP_GOLD_GROWTH := 1.12  # L → L+1 골드 = round(등급 값 × 1.12^(L−1)). 서버 rules.LEVELUP_GOLD_GROWTH

static var errors := 0  # 마지막 읽기·교체의 표 오류 수 (테스트용)
static var _monsters := {}
static var _stages: Array = []
static var _heroes: Array = []  # 파일 순서
static var _resources: Array = []  # 파일 순서
static var _config := {}  # 키 → 문자열
static var _buildings: Array = []  # 파일 순서(개정 12)
static var _soldiers: Array = []  # 파일 순서(개정 13)
static var _loaded := false


## 기본 표를 다시 읽게 한다. 경로를 주면 그 파일을 쓴다(테스트용). 오류가 있어도 읽은 만큼은 쓴다.
static func load_tables(monsters_path := MONSTERS_PATH, stages_path := STAGES_PATH, heroes_path := HEROES_PATH,
		resources_path := RESOURCES_PATH, config_path := CONFIG_PATH, buildings_path := BUILDINGS_PATH, soldiers_path := SOLDIERS_PATH) -> void:
	errors = 0
	_install(_build({
		"monsters": _read(monsters_path, ["id"] + MONSTER_COLS),
		"stages": _read(stages_path, ["stage"] + STAGE_COLS),
		"heroes": _read(heroes_path, HERO_STR_COLS + HERO_COLS + HERO_SKILL_COLS[0] + HERO_SKILL_COLS[1]),
		"resources": _read(resources_path, ["id", "name", "building"] + RESOURCE_NUM_COLS),
		"buildings": _read(buildings_path, BUILDING_STR_COLS + BUILDING_NUM_COLS + BUILDING_REQ_COLS),
		"soldiers": _read(soldiers_path, SOLDIER_STR_COLS + SOLDIER_NUM_COLS),
		"config": _config_map(_read(config_path, ["key", "value"])),
	}))


## 서버 /v1/gamedata 응답(행 배열 + config 문자열 사전)으로 표를 통째로 바꾼다.
## 하나라도 틀리면 아무것도 안 바꾸고 false(오류 수는 errors).
static func apply_remote(payload: Dictionary) -> bool:
	errors = 0
	var raw := {}
	for table in ["monsters", "stages", "heroes", "resources", "buildings", "soldiers"]:
		var rows = payload.get(table)
		var out: Array = []
		if rows is Array:
			for i in rows.size():
				if rows[i] is Dictionary:
					var row: Dictionary = rows[i].duplicate()
					row["_line"] = i + 1
					row["_src"] = "remote " + table
					out.append(row)
				else:
					_err("remote " + table, i + 1, "", "row is not an object")
		else:
			_err("remote", 0, table, "missing or not an array")
		raw[table] = out
	raw.stages.sort_custom(func(a, b): return _num_or_zero(a.get("stage")) < _num_or_zero(b.get("stage")))  # 순서와 무관하게 1부터 이어졌는지 본다
	var cfg = payload.get("config")
	var cfg_map := {}
	if cfg is Dictionary:
		for k in cfg:
			if cfg[k] is String or cfg[k] is float or cfg[k] is int:
				cfg_map[str(k)] = str(cfg[k])
			else:
				_err("remote config", 0, str(k), "value is not a string or number")
	else:
		_err("remote", 0, "config", "missing or not an object")
	raw["config"] = cfg_map
	var t := _build(raw)
	if errors > 0:
		return false
	_install(t)
	return true


static func monster(id: String) -> Dictionary:
	_ensure()
	return _monsters.get(id, {})


## 영웅 표(파일 순서). 행 = CSV 열 + skills {종류: [a, b, c]}(빈 숫자 0).
static func heroes() -> Array:
	_ensure()
	return _heroes


static func hero(id: String) -> Dictionary:
	for h in heroes():
		if h.id == id:
			return h
	return {}


## 자원 표(파일 순서).
static func resources() -> Array:
	_ensure()
	return _resources


static func resource(id: String) -> Dictionary:
	for r in resources():
		if r.id == id:
			return r
	return {}


## 자원 건물이면 그 자원 id, 아니면 "".
static func resource_of_building(building_id: String) -> String:
	for r in resources():
		if r.building == building_id:
			return r.id
	return ""


static func config_num(key: String) -> float:
	_ensure()
	return String(_config.get(key, "0")).to_float()


## `|`로 나눈 목록. 숫자로 읽히면 float, 아니면 문자열.
static func config_list(key: String) -> Array:
	_ensure()
	return _split_list(String(_config.get(key, "")))


## 성문 HP = gate_hp_per_level × 성문 레벨.
static func gate_hp_max(level: int) -> float:
	return config_num("gate_hp_per_level") * level


# --- 건물(개정 12 §2.2·§2.3). 서버 rules.ts(buildCost·buildSec·parseTiers·tierValue…)와 같은 식 ---

## 건물 표(파일 순서). 행 = {id, name, max_level, wood, stone, food, base_sec, req1, req2}(숫자는 float, 선행 없으면 "").
static func buildings() -> Array:
	_ensure()
	return _buildings


static func building_def(id: String) -> Dictionary:
	for b in buildings():
		if b.id == id:
			return b
	return {}


## L → L+1 비용 {wood, stone, food}(정수) = round(값 × 1.35^(L−1)). 모르는 건물이면 {}.
static func build_cost(id: String, level: int) -> Dictionary:
	var d := building_def(id)
	if d.is_empty():
		return {}
	var out := {}
	for r in BUILD_RES:
		out[r] = roundi(_grown(float(d[r]), BUILD_COST_GROWTH, level - 1))
	return out


## L → L+1 시간(초, 정수) = round(base_sec × 1.5^(L−1)). 모르는 건물이면 0.
static func build_sec(id: String, level: int) -> int:
	var d := building_def(id)
	return roundi(_grown(float(d.base_sec), BUILD_TIME_GROWTH, level - 1)) if not d.is_empty() else 0


## base × growth^n을 곱셈 n번으로 — 서버(JS)와 같은 IEEE 곱셈 순서라 pow 구현 차이로 반올림이 갈리지 않는다.
static func _grown(base: float, growth: float, n: int) -> float:
	var v := base
	for i in n:
		v *= growth
	return v


## 단계 표 "레벨:값|…" → [[레벨(int), 값(float)], …]. 레벨은 1부터 오름차순 정수. 틀리면 [].
static func parse_tiers(s: String) -> Array:
	var out := []
	for part in s.split("|"):
		var kv := part.split(":")
		if kv.size() != 2 or not kv[0].strip_edges().is_valid_int() or not kv[1].strip_edges().is_valid_float():
			return []
		var lv := kv[0].strip_edges().to_int()
		var first_ok := lv == 1 if out.is_empty() else lv > int(out[-1][0])
		if not first_ok:
			return []
		out.append([lv, kv[1].strip_edges().to_float()])
	return out


## 단계 표 key에서 level 이하인 마지막 단계의 값(첫 단계보다 낮으면 첫 값). 표가 틀리면 0(검증이 막는다).
static func tier_value(key: String, level: int) -> float:
	_ensure()
	var tiers := parse_tiers(String(_config.get(key, "")))
	if tiers.is_empty():
		return 0.0
	var v: float = tiers[0][1]
	for t in tiers:
		if level >= int(t[0]):
			v = t[1]
	return v


## 영웅 슬롯 수 = 성채 단계 표 keep_slot_tiers(성채 1~4 → 4, 5~9 → 8, 10+ → 12).
static func hero_slots(keep_level: int) -> int:
	return int(tier_value("keep_slot_tiers", keep_level))


## 성 내부 한 변 타일 수 = 성채 단계 표 keep_interior_tiers(1~4 → 20, 5~9 → 24, 10+ → 28).
static func interior_tiles(keep_level: int) -> int:
	return int(tier_value("keep_interior_tiers", keep_level))


## 성 내부 절반 크기(미터).
static func interior_half(keep_level: int) -> float:
	return interior_tiles(keep_level) * Balance.TILE / 2.0


## 성 HP = castle_hp + castle_hp_per_level × (성채 − 1).
static func castle_hp_max(keep_level: int) -> float:
	return config_num("castle_hp") + config_num("castle_hp_per_level") * (maxi(keep_level, 1) - 1)


## 인구 = pop_base + pop_per_house × (민가 − 1)(사용자 지시 2026-10-01: 민가는 축적 상한 대신 인구 — 병사 배치 상한).
static func population(houses_level: int) -> int:
	return int(config_num("pop_base")) + int(config_num("pop_per_house")) * (maxi(houses_level, 1) - 1)


# --- 병사(개정 13 §3·§4). 서버 rules.soldierUnitSec와 같은 식 ---

## 병종 표(파일 순서). 행 = {id, name, building, model, hp, atk, range, atk_interval, speed, aggro}(숫자는 float, 1티어 기준).
static func soldiers() -> Array:
	_ensure()
	return _soldiers


static func soldier(id: String) -> Dictionary:
	for s in soldiers():
		if s.id == id:
			return s
	return {}


## 그 건물이 만드는 병종 id, 병사 건물이 아니면 "".
static func soldier_of_building(building_id: String) -> String:
	for s in soldiers():
		if s.building == building_id:
			return s.id
	return ""


## 한 마리 시간(초) = soldier_prod_sec × soldier_prod_level_factor^(L−1)(곱셈 n번 — 서버와 같은 값). Lv 1 3시간, Lv 10 약 1시간 54분.
static func soldier_unit_sec(level: int) -> float:
	return _grown(config_num("soldier_prod_sec"), config_num("soldier_prod_level_factor"), maxi(level, 1) - 1)


## 티어 t 능력치 {hp, atk, range, atk_interval, speed, aggro}: HP·공격 × soldier_tier_mult^(t−1), 나머지는 같다. 모르는 병종이면 {}.
static func soldier_stats(type: String, tier: int) -> Dictionary:
	var d := soldier(type)
	if d.is_empty():
		return {}
	var m := _grown(1.0, config_num("soldier_tier_mult"), maxi(tier, 1) - 1)
	return {"hp": float(d.hp) * m, "atk": float(d.atk) * m, "range": float(d.range), "atk_interval": float(d.atk_interval),
		"speed": float(d.speed), "aggro": float(d.aggro)}


## 연구소: 영웅 공격 + lab_atk_per_level × (L − 1).
static func lab_atk_bonus(level: int) -> float:
	return config_num("lab_atk_per_level") * (maxi(level, 1) - 1)


## 모집 확률(주점) {ssr, sr}: SSR + tavern_ssr_per_level × (L − 1), SR + tavern_sr_per_level × (L − 1). R은 나머지.
static func gacha_rates(tavern_level: int) -> Dictionary:
	var k := maxi(tavern_level, 1) - 1
	return {"ssr": config_num("gacha_rate_ssr") + config_num("tavern_ssr_per_level") * k,
		"sr": config_num("gacha_rate_sr") + config_num("tavern_sr_per_level") * k}


## 오프라인 기본 배치: starter_heroes를 슬롯 수만큼(넘치면 자르고, 모자라면 null).
static func default_deploy(slots: int) -> Array:
	var out := []
	var starters := config_list("starter_heroes")
	for i in slots:
		out.append(starters[i] if i < starters.size() else null)
	return out


## 별 = min(copies − 1, hero_max_stars). HP·공격력 배율 = 1 + hero_star_bonus × 별.
static func star_mult(copies: int) -> float:
	return 1.0 + config_num("hero_star_bonus") * stars(copies)


static func stars(copies: int) -> int:
	return clampi(copies - 1, 0, int(config_num("hero_max_stars")))


# --- 영웅 레벨(개정 11 §2.1). 서버 rules.heroMaxLevel·levelupCost와 같은 식 ---

## 레벨 배율 = 1 + hero_level_stat × (L − 1)(1레벨 기준 직선).
static func level_mult(level: int) -> float:
	return 1.0 + config_num("hero_level_stat") * (level - 1)


## 최대 레벨 = hero_max_level_base + hero_max_level_per_star × 별.
static func max_level(copies: int) -> int:
	return int(config_num("hero_max_level_base")) + int(config_num("hero_max_level_per_star")) * stars(copies)


## level에서 count번 올리는 비용 합계 {gold(정수 골드)}. L → L+1: 골드 = round(levelup_gold_<등급> × 1.12^(L−1)). 식량 없음(개정 12).
static func levelup_cost(grade: String, level: int, count := 1) -> Dictionary:
	var g := config_num("levelup_gold_" + grade)
	var gold := 0
	for l in range(level, level + count):
		gold += roundi(g * pow(LEVELUP_GOLD_GROWTH, l - 1))
	return {"gold": gold}


## 최종 HP = 표 기본값 × 레벨 배율 × 별 배율, 공격 = … × (1 + 연구소 보너스)(개정 12, 개정 13: 막사 HP 보너스 없음). {hp, atk}
## buildings = 건물 id → 레벨(Economy.levels). 비우면 연구소 1(보너스 없음).
static func hero_stats(def: Dictionary, level: int, copies: int, buildings := {}) -> Dictionary:
	var m := level_mult(level) * star_mult(copies)
	return {"hp": float(def.hp) * m, "atk": float(def.atk) * m * (1.0 + lab_atk_bonus(int(buildings.get(LAB, 1))))}


## 전투력(목록 정렬·표시) = round(HP / 10 + 공격 × 2 / 공격 간격). HP·공격은 hero_stats(건물 보너스 포함).
static func hero_power(def: Dictionary, level: int, copies: int, buildings := {}) -> int:
	var s := hero_stats(def, level, copies, buildings)
	return roundi(s.hp / 10.0 + s.atk * 2.0 / float(def.atk_interval))


## n번째 스테이지(1부터). 표 끝을 넘으면 마지막 EXTEND_ROWS행의 평균 기울기로 직선 연장(정수 열 ≥ 1, 방치 간격 ≥ MIN_IDLE_INTERVAL) —
## 계단처럼 몇 행마다 오르는 정수 열(waves)도 두 행 차이보다 고르게 이어진다.
static func stage(n: int) -> Dictionary:
	_ensure()
	if _stages.is_empty():
		return {}
	n = maxi(n, 1)
	if n <= _stages.size():
		return _stages[n - 1]
	var last: Dictionary = _stages[-1]
	var back := mini(EXTEND_ROWS, _stages.size() - 1)
	var base: Dictionary = _stages[-1 - back]
	var k := n - _stages.size()
	var out := {"stage": n}
	for col in STAGE_COLS:
		var slope: float = (last[col] - base[col]) / back if back > 0 else 0.0
		var v: float = last[col] + slope * k
		out[col] = maxi(1, roundi(v)) if col in INT_COLS else v
	out.idle_interval = maxf(out.idle_interval, MIN_IDLE_INTERVAL)
	return out


## 처치 골드(tenths, 0.1 단위 정수) = max(1, round(gold × gold_mult × 10)). 서버 killGoldTenths와 같은 식.
static func kill_gold_tenths(id: String, stage_n: int) -> int:
	return maxi(1, roundi(float(monster(id).get("gold", 0)) * float(stage(stage_n).get("gold_mult", 1.0)) * 10.0))


static func _ensure() -> void:
	if not _loaded:
		load_tables()


static func _install(t: Dictionary) -> void:
	_monsters = t.monsters
	_stages = t.stages
	_heroes = t.heroes
	_resources = t.resources
	_buildings = t.buildings
	_soldiers = t.soldiers
	_config = t.config
	_loaded = true


static func _err(src: String, line: int, col: String, why: String) -> void:
	errors += 1
	push_error("%s line %d column '%s': %s" % [src, line, col, why])


static func _num_or_zero(v) -> float:
	if v is float or v is int:
		return float(v)
	return v.to_float() if v is String else 0.0


static func _split_list(s: String) -> Array:
	var out := []
	for part in s.split("|", false):
		var p := part.strip_edges()
		out.append(p.to_float() if p.is_valid_float() else p)
	return out


## 원시 행(CSV 문자열 또는 서버 값)을 검사해 형 변환. strs는 비지 않은 문자열, nums는 숫자. 틀린 행은 오류를 세고 뺀다.
static func _convert(rows: Array, strs: Array, nums: Array) -> Array:
	var out: Array = []
	for row in rows:
		var r := {"_line": row._line}
		var ok := true
		for c in strs:
			var v = row.get(c)
			if v is String and not v.strip_edges().is_empty():
				r[c] = v.strip_edges()
			else:
				_err(row._src, row._line, c, "not a non-empty string: '%s'" % str(v))
				ok = false
		for c in nums:
			var v = row.get(c)
			if v is float or v is int:
				r[c] = float(v)
			elif v is String and v.strip_edges().is_valid_float():
				r[c] = v.strip_edges().to_float()
			else:
				_err(row._src, row._line, c, "not a number: '%s'" % str(v))
				ok = false
		if ok:
			out.append(r)
	return out


static func _blank(v) -> bool:
	return v == null or (v is String and v.strip_edges().is_empty())


## skill1·skill2 열 → {종류: [a, b, c]}(빈 숫자 0). 빈 종류 = 없음. 모르는 종류, 필요한 숫자 빠짐, 숫자 아님, 범위 밖(Skills.RULES),
## 같은 종류 둘 = 오류(null).
static func _hero_skills(row: Dictionary):
	var sk := {}
	for cols in HERO_SKILL_COLS:
		var kind = row.get(cols[0])
		if _blank(kind):
			continue
		if not (kind is String and Skills.KINDS.has(kind.strip_edges())) or sk.has(kind.strip_edges()):
			_err(row._src, row._line, cols[0], "unknown or repeated skill '%s'" % str(kind))
			return null
		kind = kind.strip_edges()
		var nums := []
		for i in 3:
			var v = row.get(cols[i + 1])
			if v is float or v is int:
				nums.append(float(v))
			elif v is String and v.strip_edges().is_valid_float():
				nums.append(v.strip_edges().to_float())
			elif _blank(v) and i >= Skills.KINDS[kind]:
				nums.append(0.0)
			else:
				_err(row._src, row._line, cols[i + 1], "skill %s needs a number: '%s'" % [kind, str(v)])
				return null
		var bad := Skills.bad_num(kind, nums)
		if bad >= 0:
			var rule: String = Skills.RULES[kind][bad]
			_err(row._src, row._line, cols[bad + 1], "skill %s %s must be %s: %s" % [kind, "abc"[bad], Skills.RULE_TEXT[rule], Skills.num_text(nums[bad])])
			return null
		sk[kind] = nums
	return sk


## 원시 표들 → 검사한 표들. 오류는 errors에 센다(교체 여부는 호출자가 결정).
static func _build(raw: Dictionary) -> Dictionary:
	var t := {"monsters": {}, "stages": [], "heroes": [], "resources": [], "buildings": [], "soldiers": [], "config": raw.config}
	for row in _convert(raw.monsters, ["id"], MONSTER_COLS):
		if t.monsters.has(row.id):
			_err("monsters", row._line, "id", "duplicate id '%s'" % row.id)
		else:
			t.monsters[row.id] = row
	for row in _convert(raw.stages, [], ["stage"] + STAGE_COLS):
		if int(row.stage) != t.stages.size() + 1:
			_err("stages", row._line, "stage", "stage must continue from 1 without gaps")
			break
		t.stages.append(row)
	var ids := {}
	for src in raw.heroes:
		var conv := _convert([src], HERO_STR_COLS, HERO_COLS)
		var sk = _hero_skills(src)
		if conv.is_empty() or sk == null:
			continue
		var row: Dictionary = conv[0]
		for cols in HERO_SKILL_COLS:  # 원래 열도 그대로 둔다(같은 행을 다시 넣어도 통과하게)
			for c in cols:
				row[c] = src.get(c)
		row.skills = sk
		if ids.has(row.id):
			_err("heroes", row._line, "id", "duplicate id '%s'" % row.id)
		else:
			ids[row.id] = true
			t.heroes.append(row)
	ids = {}
	var buildings := {}
	for row in _convert(raw.resources, ["id", "name", "building"], RESOURCE_NUM_COLS):
		if ids.has(row.id) or buildings.has(row.building):
			_err("resources", row._line, "id", "duplicate id or building '%s'" % row.id)
		else:
			ids[row.id] = true
			buildings[row.building] = true
			t.resources.append(row)
	ids = {}
	for src in raw.buildings:  # 개정 12: 선행 칸은 비면 ""(CSV 빈 칸·서버 null)
		var conv := _convert([src], BUILDING_STR_COLS, BUILDING_NUM_COLS)
		if conv.is_empty():
			continue
		var row: Dictionary = conv[0]
		var ok := true
		for c in BUILDING_REQ_COLS:
			var v = src.get(c)
			if _blank(v):
				row[c] = ""
			elif v is String:
				row[c] = v.strip_edges()
			else:
				_err(src._src, src._line, c, "not a building id: '%s'" % str(v))
				ok = false
		if not ok:
			continue
		if ids.has(row.id):
			_err("buildings", row._line, "id", "duplicate id '%s'" % row.id)
		else:
			ids[row.id] = true
			t.buildings.append(row)
	ids = {}
	for row in _convert(raw.soldiers, SOLDIER_STR_COLS, SOLDIER_NUM_COLS):  # 개정 13
		if ids.has(row.id):
			_err("soldiers", row._line, "id", "duplicate id '%s'" % row.id)
		else:
			ids[row.id] = true
			t.soldiers.append(row)
	if errors == 0:
		_check_contents(t)
	return t


## 읽기만으로는 못 잡는 필수 내용(게임이 꺼내 쓰는 것들)을 확인한다. 앱이 그릴 수 없는 내용(배치에 없는 건물,
## 모델 없는 영웅)도 거부한다 — 서버 표가 앱보다 앞서 가면 말풍선·영웅 생성에서 깨진다.
static func _check_contents(t: Dictionary) -> void:
	for id in ["grunt", "epic_boss"]:
		if not t.monsters.has(id):
			_err("monsters", 0, "id", "missing required monster '%s'" % id)
	for table in ["stages", "heroes", "resources", "buildings", "soldiers"]:
		if t[table].is_empty():
			_err(table, 0, "", "table is empty")
	for k in CONFIG_NUM_KEYS:
		if not String(t.config.get(k, "")).is_valid_float():
			_err("config", 0, k, "missing or not a number")
	for k in CONFIG_LIST_KEYS:
		if _split_list(String(t.config.get(k, ""))).is_empty():
			_err("config", 0, k, "missing or empty list")
	_check_buildings(t)
	_check_soldiers(t)
	var hero_ids: Array = t.heroes.map(func(h): return h.id)
	for h in t.heroes:
		if not h.grade in GRADES:
			_err("heroes", h._line, "grade", "grade must be R, SR or SSR: '%s'" % h.grade)
		if not h.role in ROLES:
			_err("heroes", h._line, "role", "role must be melee or ranged: '%s'" % h.role)
		if not (h.color.length() == 7 and h.color.begins_with("#") and h.color.substr(1).is_valid_hex_number()):
			_err("heroes", h._line, "color", "color must be #RRGGBB: '%s'" % h.color)
		for c in HERO_POSITIVE_COLS:
			if not h[c] > 0.0:
				_err("heroes", h._line, c, "must be greater than 0: %s" % h[c])
		for c in HERO_NONNEG_COLS:
			if not h[c] >= 0.0:
				_err("heroes", h._line, c, "must be 0 or more: %s" % h[c])
		if not Art.HERO_MODELS.has(h.model):
			_err("heroes", h._line, "model", "model '%s' is not in this app" % h.model)
			continue
		for g in h.gear.split("|"):
			if not g in Art.HERO_MODELS[h.model].gear:
				_err("heroes", h._line, "gear", "model %s has no attachment '%s'" % [h.model, g])
	for v in _split_list(String(t.config.get("starter_heroes", ""))):
		if not (v is String and v in hero_ids):
			_err("config", 0, "starter_heroes", "unknown hero '%s'" % str(v))
	for r in t.resources:
		if Balance.building(r.building).is_empty():
			_err("resources", r._line, "building", "building '%s' is not in this app's layout" % r.building)
	_check_gacha(t.config)
	for g in GRADES:  # 모집은 등급을 먼저 정하고 그 등급 안에서 뽑는다 — 빈 등급이면 roll_gacha가 깨진다
		if not t.heroes.any(func(h): return h.grade == g):
			_err("heroes", 0, "grade", "no %s heroes to recruit" % g)


## 건물 표·설정(개정 12, 서버 seed.checkBuildings와 같은 규칙): 최대 레벨 1 이상 정수, 비용 0 이상 정수, base_sec > 0, 선행은 표 안,
## 성채·성문 필수, 자원 건물은 건물 표에, 비용 자원(wood·stone·food)은 자원 표에. 효과 설정은 0 이상(주점 증가분 ≤ 1, 인구는 정수),
## 단계 표는 "레벨:값|…"(1부터 오름차순, 값은 1 이상 정수). 앱이 그릴 수 없는 내용도 거부한다: 배치(Balance.BUILDINGS)에 없는
## 건물(성문 제외), 성 내부 MIN_INTERIOR_TILES 미만.
static func _check_buildings(t: Dictionary) -> void:
	var ids := {}
	for b in t.buildings:
		ids[b.id] = true
	for b in t.buildings:
		if not (b.max_level >= 1.0 and b.max_level == floorf(b.max_level)):
			_err("buildings", b._line, "max_level", "must be an integer of at least 1: %s" % b.max_level)
		for r in BUILD_RES:
			if not (b[r] >= 0.0 and b[r] == floorf(b[r])):
				_err("buildings", b._line, r, "must be a non-negative integer: %s" % b[r])
		if not b.base_sec > 0.0:
			_err("buildings", b._line, "base_sec", "must be greater than 0: %s" % b.base_sec)
		for c in BUILDING_REQ_COLS:
			if b[c] != "" and not ids.has(b[c]):
				_err("buildings", b._line, c, "unknown building '%s'" % b[c])
		if b.id != GATE and Balance.building(b.id).is_empty():
			_err("buildings", b._line, "id", "building '%s' is not in this app's layout" % b.id)
	for id in [KEEP, GATE]:
		if not ids.has(id):
			_err("buildings", 0, "id", "missing required building '%s'" % id)
	var res_ids := {}
	for r in t.resources:
		res_ids[r.id] = true
		if not ids.has(r.building) and not Balance.building(r.building).is_empty():  # 배치에 없는 건물은 이미 알렸다
			_err("resources", r._line, "building", "building '%s' is not in the buildings table" % r.building)
	for r in BUILD_RES:
		if not res_ids.has(r) and not t.resources.is_empty():  # 빈 표는 이미 알렸다
			_err("resources", 0, "id", "building cost resource '%s' is missing" % r)
	for k in BUILDING_NUM_KEYS:
		var s := String(t.config.get(k, ""))
		var tavern: bool = k.begins_with("tavern_")
		var pop: bool = k in POP_KEYS
		if not s.is_valid_float():
			_err("config", 0, k, "missing or not a number")
		elif not (s.to_float() >= 0.0 and (not tavern or s.to_float() <= 1.0) and (not pop or s.to_float() == floorf(s.to_float()))):
			_err("config", 0, k, "must be %s: '%s'" % ["in 0..1" if tavern else ("a non-negative integer" if pop else "0 or more"), s])
	for k in CONFIG_TIER_KEYS:
		var low := MIN_INTERIOR_TILES if k == "keep_interior_tiers" else 1
		var tiers := parse_tiers(String(t.config.get(k, "")))
		if tiers.is_empty() or not tiers.all(func(x): return x[1] == floorf(x[1]) and x[1] >= low):
			_err("config", 0, k, "must be a tier table 'level:value|…' (levels from 1 ascending, integer values of at least %d): '%s'" % [low, t.config.get(k, "")])


## 병종 표·설정(개정 13, 서버 seed.checkSoldiers와 같은 규칙): 건물은 건물 표에 있고 병종마다 다르다, hp·range·atk_interval·speed > 0,
## atk·aggro ≥ 0. 최대 티어·합성 수는 1 이상 정수, 티어 배율·한 마리 시간·레벨 계수는 0보다 크다. 앱이 그릴 수 없는 병종(Art.SOLDIERS에
## 없는 id, 없는 모델)도 거부한다.
static func _check_soldiers(t: Dictionary) -> void:
	var buildings := {}
	for b in t.buildings:
		buildings[b.id] = true
	var used := {}
	for s in t.soldiers:
		if not buildings.has(s.building):
			_err("soldiers", s._line, "building", "building '%s' is not in the buildings table" % s.building)
		elif used.has(s.building):
			_err("soldiers", s._line, "building", "building '%s' already makes another soldier" % s.building)
		used[s.building] = true
		for c in SOLDIER_NUM_COLS:
			if not (s[c] > 0.0 if c in SOLDIER_POSITIVE_COLS else s[c] >= 0.0):
				_err("soldiers", s._line, c, "must be %s: %s" % ["greater than 0" if c in SOLDIER_POSITIVE_COLS else "0 or more", s[c]])
		if not Art.SOLDIERS.has(s.id) or not Art.HERO_MODELS.has(s.model):
			_err("soldiers", s._line, "id", "soldier '%s' (model %s) cannot be drawn by this app" % [s.id, s.model])
	for k in SOLDIER_NUM_KEYS:
		var v := String(t.config.get(k, ""))
		var int_key: bool = k in SOLDIER_INT_KEYS
		if not v.is_valid_float():
			_err("config", 0, k, "missing or not a number")
		elif not ((v.to_float() >= 1.0 and v.to_float() == floorf(v.to_float())) if int_key else v.to_float() > 0.0):
			_err("config", 0, k, "must be %s: '%s'" % ["an integer of at least 1" if int_key else "greater than 0", v])


## 모집 설정(스펙 §3.6, 서버 seed와 같은 규칙): 비용·10연차 보장 수는 0 이상 정수, 확률은 0..1이고 SSR + SR ≤ 1.
## 숫자가 아닌 값은 CONFIG_NUM_KEYS 검사가 이미 알렸다.
static func _check_gacha(cfg: Dictionary) -> void:
	for k in GACHA_INT_KEYS:
		var s := String(cfg.get(k, ""))
		if s.is_valid_float() and not (s.to_float() >= 0.0 and s.to_float() == floorf(s.to_float())):
			_err("config", 0, k, "must be a non-negative integer: '%s'" % s)
	var rates := []
	for k in GACHA_RATE_KEYS:
		var s := String(cfg.get(k, ""))
		if not s.is_valid_float():
			continue
		if s.to_float() >= 0.0 and s.to_float() <= 1.0:
			rates.append(s.to_float())
		else:
			_err("config", 0, k, "must be in 0..1: '%s'" % s)
	if rates.size() == 2 and rates[0] + rates[1] > 1.0 + 1e-9:
		_err("config", 0, "gacha_rate_sr", "gacha_rate_ssr + gacha_rate_sr must be at most 1: %s + %s" % [cfg.gacha_rate_ssr, cfg.gacha_rate_sr])
	# 레벨업(개정 11, 서버 seed와 같은 규칙): 비용·별당 상한은 0 이상 정수, 최대 레벨 기본은 1 이상 정수, 레벨 배율은 0 이상
	for k in LEVELUP_INT_KEYS + ["hero_max_level_base"]:
		var s := String(cfg.get(k, ""))
		var low := 1.0 if k == "hero_max_level_base" else 0.0
		if s.is_valid_float() and not (s.to_float() >= low and s.to_float() == floorf(s.to_float())):
			_err("config", 0, k, "must be an integer of at least %d: '%s'" % [low, s])
	var stat := String(cfg.get("hero_level_stat", ""))
	if stat.is_valid_float() and not stat.to_float() >= 0.0:
		_err("config", 0, "hero_level_stat", "must be 0 or more: '%s'" % stat)


## key,value 행 → {키: 문자열}. 키가 겹치면 오류.
static func _config_map(rows: Array) -> Dictionary:
	var out := {}
	for row in rows:
		if row.key.is_empty() or out.has(row.key):
			_err(row._src, row._line, "key", "empty or duplicate key '%s'" % row.key)
		else:
			out[row.key] = row.value
	return out


## 헤더 이름으로 열을 찾아 [{열: 원시 문자열, _line: 줄, _src: 경로}] 반환. 변환·검사는 _convert가 한다.
static func _read(path: String, cols: Array) -> Array:
	var rows: Array = []
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		_err(path, 0, "", "cannot open file")
		return rows
	var lines := f.get_as_text().trim_prefix("﻿").split("\n")  # 엑셀 BOM(Godot가 이미 떼지만 안전하게)
	var header := []
	var idx := {}
	for i in lines.size():
		var line := lines[i].strip_edges()
		if line.replace(",", "").strip_edges().is_empty():  # 빈 줄, 엑셀이 남기는 ",,,,," 줄
			continue
		var cells := line.split(",")
		if header.is_empty():
			header = Array(cells).map(func(c): return c.strip_edges())
			for c in cols:
				idx[c] = header.find(c)
				if idx[c] < 0:
					_err(path, i + 1, c, "missing column")
			if idx.values().has(-1):
				return rows
			continue
		var row := {"_line": i + 1, "_src": path}
		for c in cols:
			row[c] = cells[idx[c]].strip_edges() if idx[c] < cells.size() else ""
		rows.append(row)
	return rows
