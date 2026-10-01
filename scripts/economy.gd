extends Node
## 골드·자원·마지막 수집 시각·건물 레벨의 단일 진실 + 순수 규칙 + 저장. 오토로드 Economy.
## 시간은 인자 now(유닉스 초)로 받는다 — 테스트에서 .new()로 단독 생성 가능(트리에 안 넣으면 _ready 안 돎).

const Balance := preload("res://scripts/balance.gd")

const SAVE_VERSION := 1
const SAVE_INTERVAL := 10.0

signal changed

var gold := 0
var res: Dictionary = {}           # 자원 id → int
var last_collect: Dictionary = {}  # 건물 id → 유닉스 초(float)
var levels: Dictionary = {}        # 건물 id → int
var save_path := "user://save.json"  # ""이면 저장하지 않는다

var _dirty := false   # 처치 골드처럼 즉시 저장하지 않은 변경
var _save_cd := SAVE_INTERVAL


# --- 순수 규칙 ---

static func rate_per_min(res_id: String, level: int) -> int:
	return int(Balance.RESOURCES[res_id].per_min) * level


## 쌓인 양 = floor(min(경과, 상한)/60) × 분당. 경과가 음수면 0.
static func pending_amount(res_id: String, level: int, elapsed_sec: float) -> int:
	if elapsed_sec <= 0.0:
		return 0
	return floori(minf(elapsed_sec, Balance.ACCUM_CAP_MIN * 60.0) / 60.0) * rate_per_min(res_id, level)


static func hour_index(unix: float) -> int:
	return floori(unix / 3600.0)


## 시간 칸만의 결정적 함수(PCG). 0.1 단위 값은 정수 단계에서 만들어 부동소수 오차가 없다.
static func merchant_rate(hour: int) -> float:
	var rng := RandomNumberGenerator.new()
	var s: int = hour * 0x1E3779B97F4A7C15 + 0x2545F4914F6CDD1D
	s ^= s >> 29
	rng.seed = s
	if rng.randf() < Balance.MERCHANT_JACKPOT_P:
		return Balance.MERCHANT_JACKPOT_RATE
	var per_unit := roundi(1.0 / Balance.MERCHANT_RATE_STEP)  # 10
	var lo := roundi(Balance.MERCHANT_RATE_MIN * per_unit)
	var n := roundi((Balance.MERCHANT_RATE_MAX - Balance.MERCHANT_RATE_MIN) / Balance.MERCHANT_RATE_STEP) + 1  # 11단계
	var low_w := 1.0 / Balance.MERCHANT_LOW_HIGH_RATIO
	var total := 0.0
	var ws: Array[float] = []
	for i in n:
		ws.append(1.0 - (1.0 - low_w) * i / (n - 1))  # 1 → 1/3 직선
		total += ws[i]
	var pick := rng.randf() * total
	for i in n:
		pick -= ws[i]
		if pick < 0.0:
			return float(lo + i) / per_unit
	return float(lo + n - 1) / per_unit


## floor(수량 × 단가 × 배율). 배율은 0.1 단위 정수로 바꿔 정수 연산(부동소수 내림 오차 없음).
static func sell_value(res_id: String, amount: int, rate: float) -> int:
	return amount * int(Balance.RESOURCES[res_id].price) * roundi(rate * 10.0) / 10


## 자원 건물이 아니면 "".
static func res_of(building_id: String) -> String:
	for id in Balance.RESOURCES:
		if Balance.RESOURCES[id].building == building_id:
			return id
	return ""


# --- 상태 ---

func _ready() -> void:
	load_save(Time.get_unix_time_from_system())


func _process(delta: float) -> void:
	if not _dirty:
		return
	_save_cd -= delta
	if _save_cd <= 0.0:
		save()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED \
			or what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		save()


func reset(now: float) -> void:
	gold = 0
	res = {}
	last_collect = {}
	levels = {}
	for id in Balance.RESOURCES:
		var b: String = Balance.RESOURCES[id].building
		res[id] = 0
		last_collect[b] = now
		levels[b] = 1
	_dirty = false
	changed.emit()


func pending(building_id: String, now: float) -> int:
	var id := res_of(building_id)
	if id == "":
		return 0
	return pending_amount(id, levels[building_id], now - float(last_collect[building_id]))


func show_badge(building_id: String, now: float) -> bool:
	return now - float(last_collect.get(building_id, now)) >= Balance.BADGE_MIN * 60.0 and pending(building_id, now) > 0


## 쌓인 양을 보유량에 더하고 마지막 수집 시각을 옮긴다(§2). 수집량을 돌려준다.
func collect(building_id: String, now: float) -> int:
	var amount := pending(building_id, now)
	if amount == 0:
		return 0
	var id := res_of(building_id)
	var elapsed := now - float(last_collect[building_id])
	if elapsed >= Balance.ACCUM_CAP_MIN * 60.0:
		last_collect[building_id] = now
	else:
		last_collect[building_id] = float(last_collect[building_id]) + floori(elapsed / 60.0) * 60.0
	res[id] += amount
	changed.emit()
	save()
	return amount


func current_rate(now: float) -> float:
	return merchant_rate(hour_index(now))


func seconds_to_next_rate(now: float) -> float:
	return (hour_index(now) + 1) * 3600.0 - now


## 그 자원 전부를 현재 시세로 판다. 얻은 골드를 돌려준다.
func sell(res_id: String, now: float) -> int:
	var g := sell_value(res_id, res[res_id], current_rate(now))
	res[res_id] = 0
	gold += g
	changed.emit()
	save()
	return g


func sell_all(now: float) -> int:
	var total := 0
	for id in Balance.RESOURCES:
		total += sell(id, now)
	return total


func add_gold(n: int) -> void:
	gold += n
	_dirty = true
	changed.emit()


# --- 저장 ---

func save() -> void:
	_dirty = false
	_save_cd = SAVE_INTERVAL
	if save_path == "":
		return
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f == null:
		push_warning("economy save failed: %s" % error_string(FileAccess.get_open_error()))
		return
	f.store_string(JSON.stringify({"version": SAVE_VERSION, "gold": gold, "res": res, "last_collect": last_collect, "levels": levels}))


## 없는 파일은 조용히, 깨진 파일은 경고와 함께 기본값으로 시작한다.
func load_save(now: float) -> void:
	reset(now)
	if save_path == "" or not FileAccess.file_exists(save_path):
		return
	var json := JSON.new()  # parse_string은 깨진 입력에 엔진 오류를 찍는다
	if json.parse(FileAccess.get_file_as_string(save_path)) != OK or not _apply(json.data):
		push_warning("economy save is corrupt; starting from defaults")
		reset(now)
		return
	changed.emit()


## 형 검사 후 반영. JSON 숫자는 float이라 int로 되돌린다. 하나라도 틀리면 false(부분 반영 없음).
func _apply(data) -> bool:
	if not (data is Dictionary) or int(data.get("version", 0)) != SAVE_VERSION or not (data.get("gold") is float):
		return false
	var r := {}
	var lc := {}
	var lv := {}
	for id in Balance.RESOURCES:
		var b: String = Balance.RESOURCES[id].building
		var rs = data.get("res")
		var ls = data.get("last_collect")
		var vs = data.get("levels")
		if not (rs is Dictionary and ls is Dictionary and vs is Dictionary):
			return false
		if not (rs.get(id) is float and ls.get(b) is float and vs.get(b) is float):
			return false
		r[id] = maxi(0, int(rs[id]))
		lc[b] = float(ls[b])
		lv[b] = maxi(1, int(vs[b]))
	gold = maxi(0, int(data.gold))
	res = r
	last_collect = lc
	levels = lv
	return true
