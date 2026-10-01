extends Node
## 골드·자원·마지막 수집 시각·건물 레벨·보유 영웅(copies·레벨)·배치의 단일 진실 + 순수 규칙 + 저장. 오토로드 Economy.
## 시간은 인자 now(유닉스 초)로 받는다 — 테스트에서 .new()로 단독 생성 가능(트리에 안 넣으면 _ready 안 돎).
## 온라인 모드(net이 Net 노드, 개정 9): 상태는 서버 응답(apply_server)으로만 바뀐다. 수집·판매는 요청만 보내고
## 응답이 오면 반영한다. 처치는 쌓아 두고 Net이 보낸다. 표시 골드 = 서버 골드 + 아직 반영 안 된 처치의 예상 골드
## (서버처럼 min(처치 스테이지, 서버 stage)로 매긴다).
## 건물(개정 12): 모든 건물 레벨(levels)과 일꾼(build)도 여기 있다. UI(건물 창·[성] 탭)가 쓰는 API는 아래 "건물 레벨업" 한 곳 —
## upgrade_block·requirements·upgrade_cost·upgrade_sec·upgrade·build_left·build_progress·population, 시그널 build_started·building_done.
## 완료는 보정 시각으로 판정한다: 오프라인은 여기서 게으른 완료(complete_due), 온라인은 서버가 완료하고 /v1/player로 받는다.
## 오토로드 이름(Net·GameState)을 쓰지 않는다 — tests/run_tests.gd(-s, 오토로드 없음)가 이 스크립트를 preload한다.

const GameData := preload("res://scripts/game_data.gd")

const SAVE_VERSION := 4  # 2: gold_tenths(0.1 단위). 1은 gold × 10으로 옮긴다. 3: heroes {id: {copies, level}}(2 이하는 level 1)
# 4: levels = 모든 건물, build = {id, finish} 또는 null(개정 12). 3 이하는 건물 레벨 1(성채·성문은 GameState 값인데 오프라인
# GameState 레벨은 저장된 적이 없어 늘 1이다), 일꾼 없음
const SAVE_INTERVAL := 10.0
const WAIT_TEXT := "연결 대기 중"
const MAX_KILL_COUNT := 10000  # 서버 상한: 한 보고에서 몬스터 한 종류의 수(넘으면 400으로 묶음 전체를 버린다)
const NO_GOLD_TEXT := "골드가 부족합니다"
const GACHA_FAIL_TEXT := "모집 결과를 받지 못했습니다 — 보유 영웅을 다시 확인합니다"
const DEPLOY_FAIL_TEXT := "배치를 저장하지 못했습니다"
const LEVELUP_FAIL_TEXT := "레벨업 결과를 받지 못했습니다 — 영웅 상태를 다시 확인합니다"
const FOOD := "food"  # 레벨업 식량 자원 id
const BUILD_FAIL_TEXT := "건설 결과를 받지 못했습니다 — 건물 상태를 다시 확인합니다"
const BUILD_POLL_SEC := 2.0  # 온라인: 끝나는 시각이 지난 건설을 서버에 다시 물어보는 간격
## 업그레이드 못 하는 이유 코드 → 문구(upgrade_block, 서버 409 코드와 같다. in_progress·waiting은 앱만).
const BLOCK_TEXT := {
	"unknown": "알 수 없는 건물", "max_level": "최대 레벨", "keep_cap": "성채 레벨이 부족합니다", "prereq": "선행 조건 미충족",
	"in_progress": "건설 중", "builder_busy": "다른 건물 건설 중", "not_enough": "자원 부족", "waiting": "응답 대기 중",
}

signal changed
signal collected(building_id: String, res_id: String, amount: int)  # 수집 성공(온라인은 응답이 왔을 때)
signal notice(text: String)  # 짧은 알림(끊긴 동안 수집·판매 탭)
signal roster_changed  # 보유 영웅(copies)이나 배치가 바뀌었다
signal gacha_done(results: Array)  # 모집 결과 [{hero_id, grade, new, copies}]. 실패(온라인)면 빈 배열
signal leveled(hero_id: String, level: int)  # 레벨업 성공(온라인은 응답이 왔을 때)
signal build_started(building_id: String, finish: float)  # 건설 시작(온라인은 응답이 왔을 때). finish = 끝나는 시각(보정 시각, 유닉스 초)
signal building_done(building_id: String, level: int)  # 건설 완료 — 새 레벨(온라인은 서버 응답에서 레벨이 오른 것을 봤을 때)

var gold_tenths := 0  # 골드는 0.1 단위 정수로 센다(개정 10). 표시·교환은 gold(= floor(tenths / 10))
var gold: int:  # 정수 골드(표시·판매·모집 비용 판정용). 쓰면 tenths = v × 10
	get:
		return floori(gold_tenths / 10.0)
	set(v):
		gold_tenths = v * 10
var res: Dictionary = {}           # 자원 id → int
var last_collect: Dictionary = {}  # 자원 건물 id → 유닉스 초(float)
var levels: Dictionary = {}        # 건물 id → int(개정 12: 건물 표의 모든 건물)
var build: Dictionary = {}         # 일꾼(개정 12): {id, finish(유닉스 초, 보정 시각)}, 쉬면 {}
var heroes: Dictionary = {}        # 영웅 id → copies(≥ 1). 별 = min(copies − 1, hero_max_stars)
var hero_levels: Dictionary = {}   # 영웅 id → 레벨(≥ 1, 없으면 1). 개정 11
var deploy: Array = []             # 배치 슬롯 i → 영웅 id 또는 null(저장된 그대로 — 쓰는 쪽은 deploy_slots)
var rng := RandomNumberGenerator.new()  # 오프라인 모집 난수(테스트는 seed를 정한다)
var save_path := "user://save.json"  # ""이면 저장하지 않는다

# --- 온라인 모드 ---
var net = null  # Net(오토로드). null이면 오프라인: 로컬 규칙·저장(개정 7)
var clock_offset := 0.0  # 서버 시각 − 로컬 시각(초)
var server_gold_tenths := 0
var server_stage := 0
var kill_seq := 0  # 서버가 마지막으로 반영한 처치 묶음 번호(player.kill_seq)
var merchant := {}  # {rates: {자원 id → 배율}, next_change} 서버 값
var kills_pending := {}  # 스테이지 → {몬스터 id → 수}: 아직 안 보낸 처치
var kills_sent := {}     # 스테이지 → {몬스터 id → 수}: 보냈고 응답 전

var _dirty := false   # 처치 골드처럼 즉시 저장하지 않은 변경
var _save_cd := SAVE_INTERVAL
var _waiting := {}  # 응답 대기 중인 요청 키(건물 id, "sell:<자원>", "gacha") — 재탭 무시
var _pending_deploy = null  # 온라인: 보냈고 답을 기다리는 배치(그동안 다른 응답의 옛 배치로 되돌리지 않는다)
var _deploys_out := 0
var _synced := false  # 온라인: 서버 응답을 한 번이라도 반영했다(첫 반영의 레벨 차이는 완료가 아니다)
var _build_poll_at := 0.0  # 온라인: 다 지은 건설을 다시 물어볼 시각


func _init() -> void:
	rng.randomize()


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


## (시간 칸, 자원 id)만의 결정적 함수(PCG). 자원마다 따로 뽑는다(개정 11). 0.1 단위 값은 정수 단계에서 만들어 부동소수 오차가 없다.
static func merchant_rate(hour: int, res_id: String) -> float:
	var rng := RandomNumberGenerator.new()
	var s: int = hour * 0x1E3779B97F4A7C15 + 0x2545F4914F6CDD1D
	s ^= res_id.hash() * 0x1E3779B97F4A7C15  # 자원 id를 섞는다
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


## 모집 비용(정수 골드). 가능 조건은 gold(= floor(tenths / 10)) ≥ 비용, 차감은 비용 × 10.
static func gacha_cost(count: int) -> int:
	return int(GameData.config_num("gacha_cost_10" if count == 10 else "gacha_cost_1"))


## 모집(스펙 §3.6) count장 → [{id, grade}]. 장마다 등급(SSR rate_ssr, SR rate_sr, 나머지 R)을 정하고 그 등급 안에서 균등하게.
## 10연차는 SR 이상이 gacha_10_min_sr장보다 적으면 뒤에서부터 R을 SR(균등)로 바꾼다. rand = [0, 1) 난수 Callable(테스트는 주입).
## 확률은 주점 레벨로 오른다(개정 12, GameData.gacha_rates). 서버 rules.rollGacha와 같은 규칙(같은 난수열이면 같은 결과).
static func roll_gacha(count: int, rand: Callable, tavern_level := 1) -> Array:
	var pools := {"SSR": [], "SR": [], "R": []}
	for h in GameData.heroes():
		if pools.has(h.grade):
			pools[h.grade].append(h.id)
	var rates := GameData.gacha_rates(tavern_level)
	var ssr: float = rates.ssr
	var sr: float = rates.sr
	var out := []
	for i in count:
		var r: float = rand.call()
		out.append(_pick(pools, "SSR" if r < ssr else ("SR" if r < ssr + sr else "R"), rand))
	if count == 10:
		var need := int(GameData.config_num("gacha_10_min_sr")) - out.filter(func(x): return x.grade != "R").size()
		for i in range(out.size() - 1, -1, -1):
			if need <= 0:
				break
			if out[i].grade == "R":
				out[i] = _pick(pools, "SR", rand)
				need -= 1
	return out


static func _pick(pools: Dictionary, grade: String, rand: Callable) -> Dictionary:
	var pool: Array = pools[grade]
	return {"id": pool[mini(floori(rand.call() * pool.size()), pool.size() - 1)], "grade": grade}


# --- 상태 ---

func _ready() -> void:
	load_save(Time.get_unix_time_from_system())


func _process(delta: float) -> void:
	complete_due(time_now())
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
	for b in GameData.buildings():
		levels[b.id] = 1
	build = {}
	_build_poll_at = 0.0
	for r in GameData.resources():
		var id: String = r.id
		var b: String = r.building
		res[id] = 0
		last_collect[b] = now
		levels[b] = 1
	heroes = {}
	hero_levels = {}
	deploy = []
	for id in GameData.config_list("starter_heroes"):  # 시작 영웅 copies 1, 그 순서로 배치
		heroes[str(id)] = 1
		deploy.append(str(id))
	_pending_deploy = null
	_deploys_out = 0
	_dirty = false
	changed.emit()
	roster_changed.emit()


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
func current_rate(res_id: String, now: float) -> float:
	if net != null:
		var rates = merchant.get("rates")
		return float(rates.get(res_id, 1.0)) if rates is Dictionary else 1.0
	return merchant_rate(hour_index(now), res_id)


func seconds_to_next_rate(now: float) -> float:
	if net != null:
		return maxf(0.0, float(merchant.get("next_change", now)) - now)
	return (hour_index(now) + 1) * 3600.0 - now


## 그 자원을 현재 시세로 판다(amount < 0이면 전부, 아니면 보유로 자른 그 수량). 얻은 골드를 돌려준다. 온라인은 요청만 보내고 0.
func sell(res_id: String, now: float, amount := -1) -> int:
	if net != null:
		_sell_online(res_id, amount)
		return 0
	var n: int = res[res_id] if amount < 0 else mini(amount, res[res_id])
	if n <= 0:
		return 0
	var g := sell_value(res_id, n, current_rate(res_id, now))
	res[res_id] -= n
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


## 배치 슬롯 i → 영웅 id 또는 null(길이 slots). 보유하지 않았거나 표에 없거나 앞 슬롯과 겹치면 null. GameState.deploy가 쓴다.
func deploy_slots(slots: int) -> Array:
	var out := []
	for i in slots:
		var id = deploy[i] if i < deploy.size() else null
		var ok: bool = id is String and int(heroes.get(id, 0)) >= 1 and not GameData.hero(id).is_empty() and not out.has(id)
		out.append(id if ok else null)
	return out


## 모집 count장(1 또는 10). 골드가 모자라면 알림만. 오프라인은 바로 뽑아 저장하고 gacha_done, 온라인은 요청(응답에 gacha_done).
## 뽑았거나 요청을 보냈으면 true.
func gacha(count: int) -> bool:
	if not count in [1, 10]:
		return false
	if gold < gacha_cost(count):
		notice.emit(NO_GOLD_TEXT)
		return false
	if net != null:
		return _gacha_online(count)
	gold_tenths -= gacha_cost(count) * 10
	var results := []
	for r in roll_gacha(count, rng.randf, building_level(GameData.TAVERN)):
		var c := int(heroes.get(r.id, 0)) + 1
		results.append({"hero_id": r.id, "grade": r.grade, "new": c == 1, "copies": c})
		heroes[r.id] = c
	changed.emit()
	roster_changed.emit()
	save()
	gacha_done.emit(results)
	return true


## 배치 적용. 오프라인은 저장, 온라인은 /v1/deploy(멱등이라 Net 기본 재시도). 답이 올 때까지 보낸 배치를 쓴다.
func set_deploy(ids: Array) -> void:
	var d := ids.duplicate()
	if net == null:
		deploy = d
		roster_changed.emit()
		save()
		return
	if not net.up:
		notice.emit(WAIT_TEXT)
		return
	_pending_deploy = d
	_deploys_out += 1
	deploy = d
	roster_changed.emit()
	net.send("POST", "/v1/deploy", {"deploy": d}, _on_deployed, _on_deploy_failed)


func level_of(hero_id: String) -> int:
	return maxi(1, int(hero_levels.get(hero_id, 1)))


## count번 레벨업을 못 하는 이유(UI 문구). 되면 "".
func levelup_block(hero_id: String, count := 1) -> String:
	var h := GameData.hero(hero_id)
	if h.is_empty() or int(heroes.get(hero_id, 0)) < 1:
		return "보유하지 않은 영웅"
	if level_of(hero_id) + count > GameData.max_level(int(heroes[hero_id])):
		return "최대 레벨"
	var cost := GameData.levelup_cost(h.grade, level_of(hero_id), count)
	return "골드 부족" if gold < cost.gold else ""


## 지금 감당할 수 있는 레벨업 횟수(최대 cap, 최대 레벨까지). [×10] 버튼.
func levelup_affordable(hero_id: String, cap := 10) -> int:
	var n := 0
	while n < cap and levelup_block(hero_id, n + 1) == "":
		n += 1
	return n


## 레벨업 count번(스펙 §2.1). 안 되면 알림만. 오프라인은 골드(× 10 tenths)만 빼고(개정 12) 올려 저장한 뒤 leveled,
## 온라인은 /v1/hero/levelup(once — 다시 보내면 두 번 오를 수 있어 재전송하지 않는다. 응답에 leveled). 올렸거나 보냈으면 true.
## 능력치 반영은 배치 변경과 같다(roster_changed → main: 다음 리필, 방치 모드면 그 영웅만 곧바로).
func level_up(hero_id: String, count := 1) -> bool:
	var why := levelup_block(hero_id, count)
	if why != "":
		notice.emit(why)
		return false
	if net != null:
		return _levelup_online(hero_id, count)
	var cost := GameData.levelup_cost(GameData.hero(hero_id).grade, level_of(hero_id), count)
	gold_tenths -= int(cost.gold) * 10
	hero_levels[hero_id] = level_of(hero_id) + count
	changed.emit()
	roster_changed.emit()
	save()
	leveled.emit(hero_id, level_of(hero_id))
	return true


## 레벨업 응답을 기다리는 중(UI는 버튼을 끈다).
func levelup_waiting() -> bool:
	return _waiting.has("levelup")


## 개발용(main의 --heroes= / ?heroes=): 그 영웅들을 보유(없으면 copies 1)하고 그 순서로 배치한다. 저장 파일은 쓰지 않는다
## (save_path를 비운다). 모르는 id는 경고하고 건너뛴다. 받아들인 id 목록을 돌려준다.
func grant_dev_heroes(ids: Array) -> Array:
	save_path = ""
	var ok := []
	for raw in ids:
		var id := str(raw).strip_edges()
		if GameData.hero(id).is_empty():
			push_warning("--heroes: unknown hero '%s' skipped" % id)
		elif not ok.has(id):
			ok.append(id)
			heroes[id] = maxi(1, int(heroes.get(id, 0)))
	deploy = ok
	changed.emit()
	roster_changed.emit()
	return ok


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


# --- 건물 레벨업(개정 12 §2.2~2.5) — UI가 쓰는 API는 여기 한 곳 ---

## 업그레이드 못 하는 이유 코드(순수 함수, 서버 rules.upgradeBlock과 같은 순서·코드). 되면 "".
## levels: 건물 id → 레벨(없으면 1), build_id: 짓고 있는 건물(쉬면 ""), res: 쓸 수 있는 자원(자원 건물이면 자동 수집분 포함).
##   unknown → max_level → keep_cap(성채 제외: 목표 레벨 > 성채 레벨) → prereq(req1·req2 레벨 < 목표 − 1)
##   → in_progress(바로 이 건물을 짓는 중) / builder_busy(다른 건물을 짓는 중) → not_enough
static func upgrade_block_for(id: String, lv: Dictionary, build_id: String, have: Dictionary) -> String:
	var d := GameData.building_def(id)
	if d.is_empty():
		return "unknown"
	var level := maxi(1, int(lv.get(id, 1)))
	if level >= int(d.max_level):
		return "max_level"
	if id != GameData.KEEP and level + 1 > maxi(1, int(lv.get(GameData.KEEP, 1))):
		return "keep_cap"
	for c in GameData.BUILDING_REQ_COLS:
		if d[c] != "" and maxi(1, int(lv.get(d[c], 1))) < level:
			return "prereq"
	if build_id != "":
		return "in_progress" if build_id == id else "builder_busy"
	var cost := GameData.build_cost(id, level)
	for r in cost:
		if int(have.get(r, 0)) < int(cost[r]):
			return "not_enough"
	return ""


func building_level(id: String) -> int:
	return maxi(1, int(levels.get(id, 1)))


## 인구 = 민가 레벨로(GameData.population). 병사 배치 상한(병사는 다음 개정).
func population() -> int:
	return GameData.population(building_level(GameData.HOUSES))


## 지금 모집 확률 {ssr, sr}(주점 레벨). 모집 창 확률 줄.
func gacha_rates() -> Dictionary:
	return GameData.gacha_rates(building_level(GameData.TAVERN))


## 지금 업그레이드 못 하는 이유 코드(upgrade_block_for + "waiting": 온라인 응답 대기). 되면 "". now = 보정 시각(time_now) —
## 자원 건물은 시작할 때 자동 수집하므로 그만큼(pending)을 보유량에 더해 본다(서버와 같다). 문구는 BLOCK_TEXT[코드].
func upgrade_block(id: String, now: float) -> String:
	if _waiting.has("build"):
		return "waiting"
	var have := res.duplicate()
	var r := res_of(id)
	if r != "":
		have[r] = int(have.get(r, 0)) + pending(id, now)
	return upgrade_block_for(id, levels, str(build.get("id", "")), have)


## 다음 레벨 비용 {wood, stone, food}(최대 레벨이면 {}).
func upgrade_cost(id: String) -> Dictionary:
	var d := GameData.building_def(id)
	return GameData.build_cost(id, building_level(id)) if not d.is_empty() and building_level(id) < int(d.max_level) else {}


## 다음 레벨 건설 시간(초, 최대 레벨이면 0).
func upgrade_sec(id: String) -> int:
	var d := GameData.building_def(id)
	return GameData.build_sec(id, building_level(id)) if not d.is_empty() and building_level(id) < int(d.max_level) else 0


## 선행 조건 목록(건물 창 ✓/✗): [{id, need, have, ok}]. 성채가 아니면 성채 상한(성채 Lv 목표 필요)이 먼저, 그다음 req1·req2
## (목표 − 1 필요). 최대 레벨·모르는 건물이면 [].
func requirements(id: String) -> Array:
	var d := GameData.building_def(id)
	if d.is_empty() or building_level(id) >= int(d.max_level):
		return []
	var to := building_level(id) + 1
	var out := []
	if id != GameData.KEEP:
		out.append({"id": GameData.KEEP, "need": to, "have": building_level(GameData.KEEP), "ok": building_level(GameData.KEEP) >= to})
	for c in GameData.BUILDING_REQ_COLS:
		if d[c] != "":
			out.append({"id": d[c], "need": to - 1, "have": building_level(d[c]), "ok": building_level(d[c]) >= to - 1})
	return out


func is_building(id: String) -> bool:
	return str(build.get("id", "")) == id


## 건설 남은 초(쉬면 0).
func build_left(now: float) -> float:
	return maxf(0.0, float(build.finish) - now) if not build.is_empty() else 0.0


## 건설 진행 0..1(쉬면 0). 전체 시간 = 지금 레벨의 건설 시간.
func build_progress(now: float) -> float:
	if build.is_empty():
		return 0.0
	var total := float(GameData.build_sec(str(build.id), building_level(str(build.id))))
	return clampf(1.0 - build_left(now) / total, 0.0, 1.0) if total > 0.0 else 1.0


## 업그레이드 시작(스펙 §2.4·§2.5). 안 되면 알림(BLOCK_TEXT)만. 오프라인: 자원 건물이면 먼저 자동 수집(수집 규칙 그대로, 남은 초 유지)
## → 비용 즉시 차감 → 일꾼 {id, finish = now + 시간} → 저장 → build_started. 온라인: /v1/building/upgrade(once — 다시 보내면 두 번
## 지어질 수 있어 재전송하지 않는다. 실패하면 알림 + 상태 새로 받기. 응답에 build_started). 시작했거나 보냈으면 true.
func upgrade(id: String, now: float) -> bool:
	if _waiting.has("build"):
		return false  # 응답 전 재탭
	complete_due(now)
	var why := upgrade_block(id, now)
	if why != "":
		notice.emit(BLOCK_TEXT.get(why, BUILD_FAIL_TEXT))
		return false
	if net != null:
		return _upgrade_online(id)
	if res_of(id) != "":
		collect(id, now)
	var cost := upgrade_cost(id)
	for r in cost:
		res[r] = int(res.get(r, 0)) - int(cost[r])
	build = {"id": id, "finish": now + upgrade_sec(id)}
	changed.emit()
	save()
	build_started.emit(id, float(build.finish))
	return true


## 게으른 완료: 끝나는 시각(보정 시각)이 지났으면 오프라인은 레벨 +1 · 일꾼 비움 · 저장 · building_done. 온라인은 서버가 완료한다 —
## BUILD_POLL_SEC마다 한 번 /v1/player로 새 상태를 받는다(레벨이 오르면 apply_server가 building_done). 매 프레임 불러도 가볍다.
func complete_due(now: float) -> void:
	if build.is_empty() or now < float(build.finish):
		return
	if net != null:
		if net.up and now >= _build_poll_at:
			_build_poll_at = now + BUILD_POLL_SEC
			net.refresh()
		return
	var id := str(build.id)
	levels[id] = building_level(id) + 1
	build = {}
	changed.emit()
	save()
	building_done.emit(id, levels[id])


## 테스트 훅(입력·통합 체크): 진행 중 건설을 지금 끝낸다. 오프라인은 끝나는 시각을 지금으로 두고 완료, 온라인은
## POST /v1/test/build_now(ALLOW_TEST_HOOKS 서버만)의 응답을 반영한다(완료는 서버가, building_done은 apply_server가).
func finish_build_now() -> void:
	if build.is_empty():
		return
	if net != null:
		net.send("POST", "/v1/test/build_now", {}, apply_server)
		return
	build.finish = time_now()
	complete_due(time_now())


# --- 온라인 ---

## 서버 플레이어 응답 반영. 형이 틀리면 아무것도 안 바꾸고 false. heroes·deploy는 있으면 반영(형은 검사).
func apply_server(data: Dictionary) -> bool:
	var p = data.get("player")
	var m = data.get("merchant")
	if not (p is Dictionary and m is Dictionary and _num(p.get("gold_tenths")) and _num(p.get("stage")) and p.get("res") is Dictionary \
			and p.get("buildings") is Dictionary and _rates_ok(m.get("rates")) and _num(m.get("next_change")) \
			and (p.get("heroes") == null or p.heroes is Dictionary) and (p.get("deploy") == null or p.deploy is Array) \
			and (p.get("build") == null or p.build is Dictionary)):
		push_error("bad player response: %s" % str(data))
		return false
	var roster_before := [heroes.duplicate(), deploy.duplicate(), hero_levels.duplicate()]
	if p.get("heroes") is Dictionary:  # 개정 11: {id: {copies, level}}
		var h := {}
		var lv := {}
		for id in p.heroes:
			var v = p.heroes[id]
			if v is Dictionary and _num(v.get("copies")) and int(v.copies) >= 1:
				h[str(id)] = int(v.copies)
				lv[str(id)] = maxi(1, int(v.level)) if _num(v.get("level")) else 1
		heroes = h
		hero_levels = lv
	if p.get("deploy") is Array:
		deploy = p.deploy.map(func(x): return x if x is String else null)
	if _pending_deploy != null:
		deploy = _pending_deploy.duplicate()
	var r := {}
	var lc := {}
	var lv := {}
	for row in GameData.buildings():  # 개정 12: 모든 건물 {level}(자원 건물은 아래에서 last_collect와 함께)
		var v = p.buildings.get(row.id)
		lv[row.id] = maxi(1, int(v.level)) if v is Dictionary and _num(v.get("level")) else 1
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
	var levels_before := levels
	levels = lv
	var bd = p.get("build")  # 일꾼: {id, finish} 또는 null
	build = {"id": bd.id, "finish": float(bd.finish)} if bd is Dictionary and bd.get("id") is String and _num(bd.get("finish")) else {}
	server_gold_tenths = int(p.gold_tenths)
	server_stage = int(p.stage)
	if _num(p.get("kill_seq")):
		kill_seq = int(p.kill_seq)
	var rates := {}
	for k in m.rates:
		rates[str(k)] = float(m.rates[k])
	merchant = {"rates": rates, "next_change": float(m.next_change)}
	_recalc_gold()
	changed.emit()
	if [heroes, deploy, hero_levels] != roster_before:
		roster_changed.emit()
	if _synced:  # 서버가 완료한 건설(게으른 완료) — 첫 반영의 레벨 차이는 완료가 아니라 접속이다
		for id in levels:
			if int(levels[id]) > int(levels_before.get(id, 1)):
				building_done.emit(id, levels[id])
	_synced = true
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


## 자원별 시세 표: 모든 자원 id가 숫자 배율로 있어야 한다.
func _rates_ok(rates) -> bool:
	if not rates is Dictionary:
		return false
	for r in GameData.resources():
		if not _num(rates.get(r.id)):
			return false
	return true


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


func _sell_online(target: String, amount := -1) -> void:
	var key := "sell:" + target
	if _waiting.has(key):
		return
	if not net.up:
		notice.emit(WAIT_TEXT)
		return
	_waiting[key] = true
	var body := {"res": target}
	if amount >= 0 and target != "all":
		body["amount"] = amount
	net.send("POST", "/v1/sell", body, _on_sold.bind(key), _unwait.bind(key))


func _on_sold(data: Dictionary, key: String) -> void:
	_waiting.erase(key)
	apply_server(data)


func _unwait(key: String) -> void:
	_waiting.erase(key)


## 온라인 모집: 쌓인 처치를 먼저 보내(서버 골드를 표시 골드에 맞춤) 뒤 /v1/gacha. once — 실패해도 다시 보내지 않는다
## (서버가 반영했는데 답만 잃었으면 두 번 뽑힌다). 실패하면 알림, Net이 /v1/player로 상태를 새로 받는다(뽑힌 영웅은 거기 보인다).
func _gacha_online(count: int) -> bool:
	if _waiting.has("gacha"):
		return false
	if not net.up:
		notice.emit(WAIT_TEXT)
		return false
	_waiting["gacha"] = true
	net.flush_kills()
	net.send("POST", "/v1/gacha", {"count": count}, _on_gacha, _on_gacha_failed, true, true)
	return true


func _on_gacha(data: Dictionary) -> void:
	_waiting.erase("gacha")
	apply_server(data)
	var results := []
	if data.get("results") is Array:
		for r in data.results:
			if r is Dictionary and r.get("hero_id") is String and not GameData.hero(r.hero_id).is_empty():
				results.append({"hero_id": r.hero_id, "grade": GameData.hero(r.hero_id).grade, "new": r.get("new") == true,
					"copies": int(r.copies) if _num(r.get("copies")) else 1})
	gacha_done.emit(results)


func _on_gacha_failed() -> void:
	_waiting.erase("gacha")
	notice.emit(NO_GOLD_TEXT if net.last_error == "not_enough_gold" else GACHA_FAIL_TEXT)
	gacha_done.emit([])


## 온라인 레벨업: 쌓인 처치를 먼저 보내(서버 골드를 표시 골드에 맞춤) 뒤 once로 보낸다(모집과 같은 이유로 다시 보내지 않는다).
func _levelup_online(hero_id: String, count: int) -> bool:
	if _waiting.has("levelup"):
		return false
	if not net.up:
		notice.emit(WAIT_TEXT)
		return false
	_waiting["levelup"] = true
	net.flush_kills()
	net.send("POST", "/v1/hero/levelup", {"hero_id": hero_id, "count": count}, _on_levelup.bind(hero_id), _on_levelup_failed, true, true)
	changed.emit()  # UI가 응답 전 버튼을 끈다
	return true


func _on_levelup(data: Dictionary, hero_id: String) -> void:
	_waiting.erase("levelup")
	apply_server(data)
	leveled.emit(hero_id, level_of(hero_id))


## 거부(409 max_level·not_enough_gold, 404)나 응답 유실: 알림 + 상태를 새로 받는다(이미 반영됐으면 거기 보인다).
func _on_levelup_failed() -> void:
	_waiting.erase("levelup")
	var why := {"not_enough_gold": NO_GOLD_TEXT, "max_level": "최대 레벨입니다"}
	notice.emit(why.get(net.last_error, LEVELUP_FAIL_TEXT))
	net.refresh()
	changed.emit()


func _on_deployed(data: Dictionary) -> void:
	_deploy_answered()
	apply_server(data)


## 배치가 거부됐다(400 등): 서버 배치로 되돌린다.
func _on_deploy_failed() -> void:
	_deploy_answered()
	notice.emit(DEPLOY_FAIL_TEXT)
	net.refresh()


func _deploy_answered() -> void:
	_deploys_out -= 1
	if _deploys_out <= 0:
		_deploys_out = 0
		_pending_deploy = null


## 온라인 업그레이드: once로 보낸다(모집·레벨업과 같은 이유로 다시 보내지 않는다). 자원은 서버가 뺀다(처치 골드와 무관).
func _upgrade_online(id: String) -> bool:
	if not net.up:
		notice.emit(WAIT_TEXT)
		return false
	_waiting["build"] = true
	net.send("POST", "/v1/building/upgrade", {"building": id}, _on_upgraded, _on_upgrade_failed, true, true)
	changed.emit()  # UI가 응답 전 버튼을 끈다
	return true


func _on_upgraded(data: Dictionary) -> void:
	_waiting.erase("build")
	apply_server(data)
	if not build.is_empty():
		build_started.emit(str(build.id), float(build.finish))


## 거부(409 max_level·keep_cap·prereq·builder_busy·not_enough, 400)나 응답 유실: 알림 + 상태를 새로 받는다(이미 반영됐으면 거기 보인다).
func _on_upgrade_failed() -> void:
	_waiting.erase("build")
	notice.emit(BLOCK_TEXT.get(net.last_error, BUILD_FAIL_TEXT))
	net.refresh()
	changed.emit()


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
	var hs := {}
	for id in heroes:
		hs[id] = {"copies": heroes[id], "level": level_of(id)}
	f.store_string(JSON.stringify({"version": SAVE_VERSION, "gold_tenths": gold_tenths, "res": res, "last_collect": last_collect, "levels": levels,
		"build": null if build.is_empty() else build, "heroes": hs, "deploy": deploy}))
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
	roster_changed.emit()
	complete_due(now)  # 앱이 꺼져 있는 동안 끝난 건설


## 형 검사 후 반영. JSON 숫자는 float(혹시 int여도 받는다)이라 int로 되돌린다. 하나라도 틀리면 false(부분 반영 없음).
func _apply(data) -> bool:
	if not (data is Dictionary) or not _num(data.get("version")) or not int(data.version) in [1, 2, 3, SAVE_VERSION]:
		return false
	var v3: bool = int(data.version) >= 3  # v3 이상: heroes {id: {copies, level}}. 그 전은 {id: copies}이고 level 1
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
	# 건물(개정 12, v4): 자원 건물이 아닌 건물 레벨은 있으면 숫자여야 하고, 없으면(v3 이하·새 건물) 1. 일꾼은 null 또는 {표에 있는 id, finish}
	for row in GameData.buildings():
		var v = data.levels.get(row.id)
		if v != null and not _num(v):
			return false
		if not lv.has(row.id):
			lv[row.id] = maxi(1, int(v)) if v != null else 1
	var bd = data.get("build")
	var bld := {}
	if bd != null:
		if not (bd is Dictionary and bd.get("id") is String and not GameData.building_def(bd.id).is_empty() and _num(bd.get("finish"))):
			return false
		bld = {"id": bd.id, "finish": float(bd.finish)}
	# 영웅(개정 10): 없으면(v1, 영웅 전 v2) reset()의 시작 영웅 그대로. 있으면 둘 다 형이 맞아야 한다
	var hs = data.get("heroes")
	var ds = data.get("deploy")
	var h := heroes
	var hl := {}
	var d := deploy
	if hs != null or ds != null:
		if not (hs is Dictionary and ds is Array):
			return false
		h = {}
		for id in hs:
			var v = hs[id]
			var level := 1
			if v3:
				if not (v is Dictionary and _num(v.get("copies")) and _num(v.get("level"))):
					return false
				level = maxi(1, int(v.level))
				v = v.copies
			if not (id is String and _num(v)):
				return false
			if int(v) >= 1:
				h[id] = int(v)
				hl[id] = level
		d = []
		for x in ds:
			if not (x == null or x is String):
				return false
			d.append(x)
	gold_tenths = maxi(0, int(data.gold) * 10 if v1 else int(data.gold_tenths))
	res = r
	last_collect = lc
	levels = lv
	build = bld
	heroes = h
	hero_levels = hl
	deploy = d
	return true


static func _num(v) -> bool:
	return v is float or v is int
