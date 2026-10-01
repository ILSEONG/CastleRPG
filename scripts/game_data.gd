extends RefCounted
## 몬스터·스테이지 데이터 표(data/*.csv). 처음 쓸 때 한 번 읽고 캐시한다.

const MONSTERS_PATH := "res://data/monsters.csv"
const STAGES_PATH := "res://data/stages.csv"
const INT_COLS := ["waves", "wave_size"]  # 스테이지 연장 시 반올림하는 정수 열
const EXTEND_ROWS := 10  # 표 너머 연장 기울기를 잴 마지막 행 수
const MONSTER_COLS := ["hp", "atk", "speed", "range", "atk_interval", "aggro", "scale", "gold"]
const STAGE_COLS := ["hp_mult", "atk_mult", "gold_mult", "waves", "wave_size", "idle_interval"]

static var errors := 0  # 표 오류 수 (테스트용)
static var _monsters := {}
static var _stages: Array = []
static var _loaded := false


## 기본 표를 다시 읽게 한다. 경로를 주면 그 파일을 쓴다(테스트용).
static func load_tables(monsters_path := MONSTERS_PATH, stages_path := STAGES_PATH) -> void:
	errors = 0
	_monsters = {}
	_stages = []
	for row in _read(monsters_path, ["id"] + MONSTER_COLS):
		_monsters[row.id] = row
	for row in _read(stages_path, ["stage"] + STAGE_COLS):
		if int(row.stage) != _stages.size() + 1:
			_err(stages_path, row._line, "stage", "stage must continue from 1 without gaps")
			break
		_stages.append(row)
	_loaded = true


static func monster(id: String) -> Dictionary:
	if not _loaded:
		load_tables()
	return _monsters.get(id, {})


## n번째 스테이지(1부터). 표 끝을 넘으면 마지막 EXTEND_ROWS행의 평균 기울기로 직선 연장 —
## 계단처럼 몇 행마다 오르는 정수 열(waves)도 두 행 차이보다 고르게 이어진다.
static func stage(n: int) -> Dictionary:
	if not _loaded:
		load_tables()
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
		out[col] = roundi(v) if col in INT_COLS else v
	return out


static func kill_gold(id: String, stage_n: int) -> int:
	return maxi(1, roundi(float(monster(id).get("gold", 0)) * float(stage(stage_n).get("gold_mult", 1.0))))


static func _err(path: String, line: int, col: String, why: String) -> void:
	errors += 1
	push_error("%s line %d column '%s': %s" % [path, line, col, why])


## 헤더 이름으로 열을 찾아 [{열: 값, _line: 줄}] 반환. 첫 열(키)만 문자열, 나머지는 숫자.
static func _read(path: String, cols: Array) -> Array:
	var rows: Array = []
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		_err(path, 0, "", "cannot open file")
		return rows
	var lines := f.get_as_text().trim_prefix("﻿").split("\n")
	var header := []
	var idx := {}
	for i in lines.size():
		var line := lines[i].strip_edges()
		if line.is_empty():
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
		var row := {"_line": i + 1}
		var ok := true
		for c in cols:
			var raw := cells[idx[c]].strip_edges() if idx[c] < cells.size() else ""
			if c == cols[0]:
				row[c] = raw
			elif raw.is_valid_float():
				row[c] = raw.to_float()
			else:
				_err(path, i + 1, c, "not a number: '%s'" % raw)
				ok = false
		if ok:
			rows.append(row)
	return rows
