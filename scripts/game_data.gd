extends RefCounted
## 기획 데이터 표(data/*.csv 또는 서버 /v1/gamedata). 처음 쓸 때 한 번 읽고 캐시한다.

const Balance := preload("res://scripts/balance.gd")
const Art := preload("res://scripts/art.gd")
const MONSTERS_PATH := "res://data/monsters.csv"
const STAGES_PATH := "res://data/stages.csv"
const HEROES_PATH := "res://data/heroes.csv"
const RESOURCES_PATH := "res://data/resources.csv"
const CONFIG_PATH := "res://data/config.csv"
const INT_COLS := ["waves", "wave_size"]  # 스테이지 연장 시 반올림하는 정수 열
const EXTEND_ROWS := 12  # 표 너머 연장 기울기를 잴 마지막 행 수 — 3의 배수라 3스테이지마다 오르는 waves도 기울기 1/3 그대로
const MIN_IDLE_INTERVAL := 0.5  # 연장해도 방치 스폰 간격이 0 이하로 가지 않게
const MONSTER_COLS := ["hp", "atk", "speed", "range", "atk_interval", "aggro", "scale", "gold"]
const STAGE_COLS := ["hp_mult", "atk_mult", "gold_mult", "waves", "wave_size", "idle_interval"]
const HERO_COLS := ["hp", "atk", "range", "atk_interval", "speed", "aggro"]
const RESOURCE_NUM_COLS := ["per_min", "price"]
const CONFIG_NUM_KEYS := ["castle_hp", "gate_hp_per_level", "max_live_monsters", "countdown_sec", "result_sec", "wave_gap_sec",
	"spawn_spacing_sec", "accum_cap_min", "badge_min", "merchant_jackpot_p", "merchant_jackpot_rate", "merchant_rate_min",
	"merchant_rate_max", "merchant_rate_step", "merchant_low_high_ratio", "kill_rate_cap"]
const CONFIG_LIST_KEYS := ["hero_slots", "hero_roster"]

static var errors := 0  # 마지막 읽기·교체의 표 오류 수 (테스트용)
static var _monsters := {}
static var _stages: Array = []
static var _heroes: Array = []  # 파일 순서
static var _resources: Array = []  # 파일 순서
static var _config := {}  # 키 → 문자열
static var _loaded := false


## 기본 표를 다시 읽게 한다. 경로를 주면 그 파일을 쓴다(테스트용). 오류가 있어도 읽은 만큼은 쓴다.
static func load_tables(monsters_path := MONSTERS_PATH, stages_path := STAGES_PATH, heroes_path := HEROES_PATH,
		resources_path := RESOURCES_PATH, config_path := CONFIG_PATH) -> void:
	errors = 0
	_install(_build({
		"monsters": _read(monsters_path, ["id"] + MONSTER_COLS),
		"stages": _read(stages_path, ["stage"] + STAGE_COLS),
		"heroes": _read(heroes_path, ["id", "name"] + HERO_COLS),
		"resources": _read(resources_path, ["id", "name", "building"] + RESOURCE_NUM_COLS),
		"config": _config_map(_read(config_path, ["key", "value"])),
	}))


## 서버 /v1/gamedata 응답(행 배열 + config 문자열 사전)으로 표를 통째로 바꾼다.
## 하나라도 틀리면 아무것도 안 바꾸고 false(오류 수는 errors).
static func apply_remote(payload: Dictionary) -> bool:
	errors = 0
	var raw := {}
	for table in ["monsters", "stages", "heroes", "resources"]:
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


## 영웅 역할 표(파일 순서).
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


static func gate_hp_max(level: int) -> float:
	return config_num("gate_hp_per_level") * level


## index = keep_level - 1, 표 끝을 넘으면 마지막 값.
static func hero_slots(keep_level: int) -> int:
	var slots := config_list("hero_slots")
	return int(slots[clampi(keep_level, 1, slots.size()) - 1])


## 영웅 index의 역할 id = hero_roster[index % 길이].
static func hero_role(index: int) -> String:
	var roster := config_list("hero_roster")
	return roster[index % roster.size()]


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


## 원시 표들 → 검사한 표들. 오류는 errors에 센다(교체 여부는 호출자가 결정).
static func _build(raw: Dictionary) -> Dictionary:
	var t := {"monsters": {}, "stages": [], "heroes": [], "resources": [], "config": raw.config}
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
	for row in _convert(raw.heroes, ["id", "name"], HERO_COLS):
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
	if errors == 0:
		_check_contents(t)
	return t


## 읽기만으로는 못 잡는 필수 내용(게임이 꺼내 쓰는 것들)을 확인한다. 앱이 그릴 수 없는 내용(배치에 없는 건물,
## 모델 없는 영웅)도 거부한다 — 서버 표가 앱보다 앞서 가면 말풍선·영웅 생성에서 깨진다.
static func _check_contents(t: Dictionary) -> void:
	for id in ["grunt", "epic_boss"]:
		if not t.monsters.has(id):
			_err("monsters", 0, "id", "missing required monster '%s'" % id)
	for table in ["stages", "heroes", "resources"]:
		if t[table].is_empty():
			_err(table, 0, "", "table is empty")
	for k in CONFIG_NUM_KEYS:
		if not String(t.config.get(k, "")).is_valid_float():
			_err("config", 0, k, "missing or not a number")
	for k in CONFIG_LIST_KEYS:
		if _split_list(String(t.config.get(k, ""))).is_empty():
			_err("config", 0, k, "missing or empty list")
	for v in _split_list(String(t.config.get("hero_slots", ""))):
		if not (v is float):
			_err("config", 0, "hero_slots", "not a number: '%s'" % str(v))
	var hero_ids: Array = t.heroes.map(func(h): return h.id)
	for h in t.heroes:
		if not Art.HERO_MODELS.has(h.id):
			_err("heroes", h._line, "id", "hero '%s' has no model in this app" % h.id)
	for v in _split_list(String(t.config.get("hero_roster", ""))):
		if not (v is String and v in hero_ids and Art.HERO_MODELS.has(v)):
			_err("config", 0, "hero_roster", "unknown hero or no model '%s'" % str(v))
	for r in t.resources:
		if Balance.building(r.building).is_empty():
			_err("resources", r._line, "building", "building '%s' is not in this app's layout" % r.building)


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
