extends Node
## 골드·자원·마지막 수집 시각·건물 레벨의 단일 진실 + 순수 규칙 + 저장. 오토로드 Economy.
## 시간은 인자 now(유닉스 초)로 받는다 — 테스트에서 .new()로 단독 생성 가능(트리에 안 넣으면 _ready 안 돎).
## 온라인 모드(net이 Net 노드, 개정 9): 상태는 서버 응답(apply_server)으로만 바뀐다. 수집·판매는 요청만 보내고
## 응답이 오면 반영한다. 처치는 쌓아 두고 Net이 보낸다. 표시 골드 = 서버 골드 + 아직 반영 안 된 처치의 예상 골드
## (서버처럼 min(처치 스테이지, 서버 stage)로 매긴다).
## 오토로드 이름(Net·GameState)을 쓰지 않는다 — tests/run_tests.gd(-s, 오토로드 없음)가 이 스크립트를 preload한다.

const GameData := preload("res://scripts/game_data.gd")

const SAVE_VERSION := 2  # 2: gold_tenths(0.1 단위). 1은 gold × 10으로 옮긴다
const SAVE_INTERVAL := 10.0
const WAIT_TEXT := "연결 대기 중"
const MAX_KILL_COUNT := 10000  # 서버 상한: 한 보고에서 몬스터 한 종류의 수(넘으면 400으로 묶음 전체를 버린다)

signal changed
signal collected(building_id: String, res_id: String, amount: int)  # 수집 성공(온라인은 응답이 왔을 때)
signal notice(text: String)  # 짧은 알림(끊긴 동안 수집·판매 탭)

var gold_tenths := 0  # 골드는 0.1 단위 정수로 센다(개정 10). 표시·교환은 gold(= floor(tenths / 10))
var gold: int:  # 정수 골드(표시·판매·모집 비용 판정용). 쓰면 tenths = v × 10
	get:
		return floori(gold_tenths / 10.0)
	set(v):
		gold_tenths = v * 10
var res: Dictionary = {}           # 자원 id → int
var last_collect: Dictionary = {}  # 건물 id → 유닉스 초(float)
var levels: Dictionary = {}        # 건물 id → int
var save_path := "user://save.json"  # ""이면 저장하지 않는다

# --- 온라인 모드 ---
var net = null  # Net(오토로드). null이면 오프라인: 로컬 규칙·저장(개정 7)
var clock_offset := 0.0  # 서버 시각 − 로컬 시각(초)
var server_gold_tenths := 0
var server_stage := 0
var kill_seq := 0  # 서버가 마지막으로 반영한 처치 묶음 번호(player.kill_seq)
var merchant := {}  # {rate, next_change} 서버 값
var kills_pending := {}  # 스테이지 → {몬스터 id → 수}: 아직 안 보낸 처치
var kills_sent := {}     # 스테이지 → {몬스터 id → 수}: 보냈고 응답 전

var _dirty := false   # 처치 골드처럼 즉시 저장하지 않은 변경
var _save_cd := SAVE_INTERVAL
var _waiting := {}  # 응답 대기 중인 요청 키(건물 id, "sell:<자원>") — 재탭 무시


# --- 순수 규칙 ---

static func rate_per_min(res_id: String, level: int) -> int:
	return int(GameData.resource(res_id).per_min) * level


## 쌓인 양 = floor(min(경과, 상한)/60) × 분당. 경과가 음수면 0.
static func pending_amount(res_id: String, level: int, elapsed_sec: float) -> int:
	if elapsed_sec <= 0.0:
		return 0
	return floori(minf(elapsed_sec, GameData.config_num("accum_cap_min") * 60.0) / 60.0) * rate_per_min(res_id, level)


static func hour_index(unix: float) -> int:
	return floori(unix / 3600.0)


## 시간 칸만의 결정적 함수(PCG). 0.1 단위 값은 정수 단계에서 만들어 부동소수 오차가 없다.
static func merchant_rate(hour: int) -> float:
	var rng := RandomNumberGenerator.new()
	var s: int = hour * 0x1E3779B97F4A7C15 + 0x2545F4914F6CDD1D
	s ^= s >> 29
	rng.seed = s
	if rng.randf() < GameData.config_num("merchant_jackpot_p"):
		return GameData.config_num("merchant_jackpot_rate")
	var per_unit := roundi(1.0 / GameData.config_num("merchant_rate_step"))  # 10
	var lo := roundi(GameData.config_num("merchant_rate_min") * per_unit)
	var n := roundi((GameData.config_num("merchant_rate_max") - GameData.config_num("merchant_rate_min")) / GameData.config_num("merchant_rate_step")) + 1  # 11단계
	var low_w := 1.0 / GameData.config_num("merchant_low_high_ratio")
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
	return amount * int(GameData.resource(res_id).price) * roundi(rate * 10.0) / 10


## 자원 건물이 아니면 "".
static func res_of(building_id: String) -> String:
	return GameData.resource_of_building(building_id)


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
	gold_tenths = 0
	res = {}
	last_collect = {}
	levels = {}
	for r in GameData.resources():
		var id: String = r.id
		var b: String = r.building
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
	return now - float(last_collect.get(building_id, now)) >= GameData.config_num("badge_min") * 60.0 and pending(building_id, now) > 0


## 서버 보정 시각(오프라인은 로컬 시각 그대로).
func time_now() -> float:
	return Time.get_unix_time_from_system() + clock_offset


## 쌓인 양을 보유량에 더하고 마지막 수집 시각을 옮긴다(§2). 수집량을 돌려준다. 온라인은 요청만 보내고 0(결과는 collected).
func collect(building_id: String, now: float) -> int:
	if net != null:
		_collect_online(building_id)
		return 0
	if res_of(building_id) != "" and now < float(last_collect[building_id]):  # 시계를 되돌림: 지금부터 다시 쌓는다
		last_collect[building_id] = now
		save()
		return 0
	var amount := pending(building_id, now)
	if amount == 0:
		return 0
	var id := res_of(building_id)
	var elapsed := now - float(last_collect[building_id])
	if elapsed >= GameData.config_num("accum_cap_min") * 60.0:
		last_collect[building_id] = now
	else:
		last_collect[building_id] = float(last_collect[building_id]) + floori(elapsed / 60.0) * 60.0
	res[id] += amount
	changed.emit()
	collected.emit(building_id, id, amount)
	save()
	return amount


## 온라인은 서버 시세(next_change가 지나면 Net이 /v1/player로 갱신).
func current_rate(now: float) -> float:
	if net != null:
		return float(merchant.get("rate", 1.0))
	return merchant_rate(hour_index(now))


func seconds_to_next_rate(now: float) -> float:
	if net != null:
		return maxf(0.0, float(merchant.get("next_change", now)) - now)
	return (hour_index(now) + 1) * 3600.0 - now


## 그 자원 전부를 현재 시세로 판다. 얻은 골드를 돌려준다. 온라인은 요청만 보내고 0.
func sell(res_id: String, now: float) -> int:
	if net != null:
		_sell_online(res_id)
		return 0
	var g := sell_value(res_id, res[res_id], current_rate(now))
	res[res_id] = 0
	gold_tenths += g * 10  # 판매 골드는 정수
	changed.emit()
	save()
	return g


func sell_all(now: float) -> int:
	if net != null:
		_sell_online("all")
		return 0
	var total := 0
	for r in GameData.resources():
		total += sell(r.id, now)
	return total


func add_gold_tenths(n: int) -> void:
	gold_tenths += n
	_dirty = true
	changed.emit()


## 몬스터 처치. 오프라인은 바로 골드, 온라인은 쌓아 두고 Net이 /v1/kills로 보낸다.
func add_kill(kind: String, stage: int) -> void:
	if net == null:
		add_gold_tenths(GameData.kill_gold_tenths(kind, stage))
		return
	var per: Dictionary = kills_pending.get(stage, {})
	per[kind] = int(per.get(kind, 0)) + 1
	kills_pending[stage] = per
	_recalc_gold()
	changed.emit()


# --- 온라인 ---

## 서버 플레이어 응답 반영. 형이 틀리면 아무것도 안 바꾸고 false.
func apply_server(data: Dictionary) -> bool:
	var p = data.get("player")
	var m = data.get("merchant")
	if not (p is Dictionary and m is Dictionary and _num(p.get("gold_tenths")) and _num(p.get("stage")) and p.get("res") is Dictionary \
			and p.get("buildings") is Dictionary and _num(m.get("rate")) and _num(m.get("next_change"))):
		push_error("bad player response: %s" % str(data))
		return false
	var r := {}
	var lc := {}
	var lv := {}
	for row in GameData.resources():
		var id: String = row.id
		var bid: String = row.building
		var b = p.buildings.get(bid)
		var ok: bool = b is Dictionary and _num(b.get("last_collect")) and _num(b.get("level"))
		r[id] = int(p.res.get(id, 0)) if _num(p.res.get(id)) else 0
		lc[bid] = float(b.last_collect) if ok else time_now()
		lv[bid] = int(b.level) if ok else 1
	res = r
	last_collect = lc
	levels = lv
	server_gold_tenths = int(p.gold_tenths)
	server_stage = int(p.stage)
	if _num(p.get("kill_seq")):
		kill_seq = int(p.kill_seq)
	merchant = {"rate": float(m.rate), "next_change": float(m.next_change)}
	_recalc_gold()
	changed.emit()
	return true


## 쌓인 처치를 보낼 몫으로 옮긴다(Net.flush_kills).
func take_kills() -> Dictionary:
	kills_sent = kills_pending
	kills_pending = {}
	return kills_sent


## 한 스테이지 처치 {몬스터 id: 수}를 종류별 수가 cap 이하인 묶음들로 나눈다.
static func split_kills(per: Dictionary, cap := MAX_KILL_COUNT) -> Array:
	var left := per.duplicate()
	var out := []
	while not left.is_empty():
		var part := {}
		for id in left.keys():
			var n := mini(int(left[id]), cap)
			part[id] = n
			left[id] = int(left[id]) - n
			if left[id] <= 0:
				left.erase(id)
		out.append(part)
	return out


## 그 스테이지 보고 한 묶음(part)이 끝났다(반영됐거나 버림). 보낸 몫에서 그만큼 뺀다. 다음 apply_server가 골드를 다시 계산한다.
func kills_done(stage: int, part: Dictionary) -> void:
	var per: Dictionary = kills_sent.get(stage, {})
	for id in part:
		per[id] = int(per.get(id, 0)) - int(part[id])
		if per[id] <= 0:
			per.erase(id)
	if per.is_empty():
		kills_sent.erase(stage)
	_recalc_gold()


func _recalc_gold() -> void:
	gold_tenths = server_gold_tenths + _kills_tenths(kills_pending) + _kills_tenths(kills_sent)


## 서버는 처치를 min(보낸 stage, player.stage)로 매긴다 — 예상도 같게(서버 stage를 아직 모르면 그대로).
func _kills_tenths(kills: Dictionary) -> int:
	var g := 0
	for stage in kills:
		var s: int = mini(stage, server_stage) if server_stage > 0 else stage
		for id in kills[stage]:
			g += GameData.kill_gold_tenths(id, s) * int(kills[stage][id])
	return g


func _collect_online(building_id: String) -> void:
	if res_of(building_id) == "" or _waiting.has(building_id):
		return  # 응답 전 같은 건물 재탭은 무시
	if not net.up:
		notice.emit(WAIT_TEXT)
		return
	_waiting[building_id] = true
	net.send("POST", "/v1/collect", {"building": building_id}, _on_collected.bind(building_id), _unwait.bind(building_id))


func _on_collected(data: Dictionary, building_id: String) -> void:
	_waiting.erase(building_id)
	apply_server(data)
	var amount := int(data.get("amount", 0))
	if amount > 0:
		collected.emit(building_id, res_of(building_id), amount)


func _sell_online(target: String) -> void:
	var key := "sell:" + target
	if _waiting.has(key):
		return
	if not net.up:
		notice.emit(WAIT_TEXT)
		return
	_waiting[key] = true
	net.send("POST", "/v1/sell", {"res": target}, _on_sold.bind(key), _unwait.bind(key))


func _on_sold(data: Dictionary, key: String) -> void:
	_waiting.erase(key)
	apply_server(data)


func _unwait(key: String) -> void:
	_waiting.erase(key)


# --- 저장 ---

func save() -> void:
	_dirty = false
	_save_cd = SAVE_INTERVAL
	if save_path == "":
		return
	# 임시 파일에 다 쓴 뒤 바꿔 끼운다 — 쓰다 끊겨도 이전 저장은 남는다.
	var tmp := save_path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("economy save failed: %s" % error_string(FileAccess.get_open_error()))
		return
	f.store_string(JSON.stringify({"version": SAVE_VERSION, "gold_tenths": gold_tenths, "res": res, "last_collect": last_collect, "levels": levels}))
	f.close()
	var err := DirAccess.rename_absolute(tmp, save_path)
	if err != OK:
		push_warning("economy save rename failed: %s" % error_string(err))


## 없는 파일은 조용히, 깨진 파일은 경고와 함께 기본값으로 시작한다.
func load_save(now: float) -> void:
	reset(now)
	if save_path == "" or not FileAccess.file_exists(save_path):
		return
	var json := JSON.new()  # parse_string은 깨진 입력에 엔진 오류를 찍는다
	if json.parse(FileAccess.get_file_as_string(save_path)) != OK or not _apply(json.data):
		push_warning("economy save is corrupt; starting from defaults")
		return
	changed.emit()


## 형 검사 후 반영. JSON 숫자는 float(혹시 int여도 받는다)이라 int로 되돌린다. 하나라도 틀리면 false(부분 반영 없음).
func _apply(data) -> bool:
	if not (data is Dictionary) or not _num(data.get("version")) or not int(data.version) in [1, SAVE_VERSION]:
		return false
	var v1: bool = int(data.version) == 1  # v1: gold(정수) → × 10
	if not _num(data.get("gold" if v1 else "gold_tenths")):
		return false
	var r := {}
	var lc := {}
	var lv := {}
	for r_row in GameData.resources():
		var id: String = r_row.id
		var b: String = r_row.building
		var rs =data.get("res")
		var ls = data.get("last_collect")
		var vs = data.get("levels")
		if not (rs is Dictionary and ls is Dictionary and vs is Dictionary):
			return false
		if not (_num(rs.get(id)) and _num(ls.get(b)) and _num(vs.get(b))):
			return false
		r[id] = maxi(0, int(rs[id]))
		lc[b] = float(ls[b])
		lv[b] = maxi(1, int(vs[b]))
	gold_tenths = maxi(0, int(data.gold) * 10 if v1 else int(data.gold_tenths))
	res = r
	last_collect = lc
	levels = lv
	return true


static func _num(v) -> bool:
	return v is float or v is int
