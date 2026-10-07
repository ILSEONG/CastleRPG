extends Node
## 길드(오프라인 로컬). 오토로드 Guild. 흐름: 가입(추천 길드 가입·직접 창설) → 매일 출석·기부로 길드 경험치 → 길드 레벨 → 길드 버프
## (모든 영웅 공격력·체력 %, hero.refresh_stats가 곱한다 — 레벨 끝 없음) → 길드 보스 드래곤(길드원마다 하루 BOSS_TRIES번, 매 판 Lv 1에서 시작해
## 쓰러뜨릴 때마다 같은 판에서 레벨이 오른다. 판 점수 = 준 피해, 내 점수 = 오늘 판 점수 합, 길드 점수 = 길드원 점수 합) →
## 길드 코인으로 길드 상점. 다른 길드원은 가상 길드원이다: 길드 seed와 날짜로 정해지는 시각에 출석·기부·보스 공격을 한다(_simulate).
## 오프라인: 보상·비용은 Economy에 바로 반영하고 둘 다 저장한다. 온라인(econ.net != null, 내보낸 APK): 서버 길드(/v1/guild*)가 진실이다 —
## 실제 유저 + 가상 길드원(서버가 계산). 응답의 guild 값을 이 스크립트의 같은 필드(guild·me·coins·shop_*)에 옮겨 담아 창은 두 모드를 같은 코드로 그린다.
## 온라인 쓰기는 요청만 보내고(busy 동안 막힘 "응답 대기 중") 응답이 오면 Economy.apply_server + 길드 값을 반영한다.
## 날짜는 던전과 같은 일일 리셋(GameData.reset_day, 00:00 KST). 주간 상점은 reset_day / 7.
## 저장: user://guild.json(Economy 저장과 따로). 길드 코인은 탈퇴해도 남고, 오늘 기여도·출석 상자는 길드를 옮기면 새로 센다.
## 테스트는 .new()로 만들어 econ·gs를 넣고 save_path를 ""로 둔다(트리에 안 넣으면 _ready 안 돎). 시각은 인자 now.

const GameData := preload("res://scripts/game_data.gd")

const SAVE_VERSION := 1
const UNLOCK_ROUND := 11  # GameState.stage가 이 이상(= 1-10 클리어)이면 열린다. 한 번 열리면 저장한다
const FULL_LEVEL := 6  # 길드 레벨은 끝이 없다(2026-10-06). 인원(나 포함)은 이 레벨부터 MEMBERS_MAX(최대 20명 유지)
const MEMBERS_BASE := 15
const MEMBERS_MAX := 20
const MAX_MEMBERS := MEMBERS_MAX
const BUFF_PER_LEVEL := 1.0  # 길드 레벨당 영웅 공격력·체력 +%
const CREATE_GOLD := 500000
const SIM_DAYS_MAX := 7  # 앱을 오래 껐다 켜도 가상 길드원 활동은 최근 이 날수만 센다
const LOG_MAX := 30
const MY_NAME := "나"
const ROLES := ["길드장", "부길드장", "정예", "길드원"]

const ATTEND_REWARD := {"gold": 3000, "coins": 30}
const ATTEND_EXP := 10
## 출석 인원 상자: [오늘 출석 인원(나 포함), 보상]
const ATTEND_BOXES := [[5, {"coins": 20, "gold": 5000}], [10, {"coins": 40, "diamonds": 20}], [15, {"coins": 60, "diamonds": 30}],
	[20, {"coins": 100, "diamonds": 50}]]
const DONATIONS := {
	"gold": {"name": "골드 기부", "gold": 10000, "diamonds": 0, "exp": 20, "coins": 20, "daily": 3},
	"dia": {"name": "다이아 기부", "gold": 0, "diamonds": 50, "exp": 60, "coins": 60, "daily": 1},
	"royal": {"name": "왕실 기부", "gold": 0, "diamonds": 200, "exp": 250, "coins": 250, "daily": 1},
}
const DONATION_ORDER := ["gold", "dia", "royal"]

const BOSS_TRIES := 2
const BOSS_FIGHT_SEC := 40.0  # 2026-10-07 20 → 40초. 실제 전투 시간(초) — 이 동안 배치 영웅이 드래곤에 준 피해가 내 피해
const BOSS_DMG_CAP := 3.0  # 받는 피해 상한 = 시작 때 배치 영웅 초당 피해 합 × 전투 초 × 이것(서버 guild.ts와 같다, 조작 방지)
const BOSS_HP_BASE := 1000.0  # 드래곤 Lv n 최대 HP = BASE × GROWTH^(n−1) — 매 판 Lv 1부터(서버 guild.ts와 같다)
const BOSS_HP_GROWTH := 1.22
const BOSS_NAMES := ["드래곤"]
## 판 등급: [등급, 도달한 드래곤 레벨 이상, 코인, 골드]
## 판 등급(2026-10-07 B-~SSS+ 15단계, 서버 guild.ts BOSS_GRADES와 같다): [등급, 도달 레벨 이상, 코인, 골드]
const BOSS_GRADES := [
	["SSS+", 45, 300, 80000],
	["SSS", 41, 250, 65000],
	["SSS-", 37, 215, 50000],
	["SS+", 34, 190, 40000],
	["SS", 31, 165, 35000],
	["SS-", 28, 145, 30000],
	["S+", 25, 125, 26000],
	["S", 22, 110, 22000],
	["S-", 19, 95, 19000],
	["A+", 16, 80, 16000],
	["A", 13, 65, 13000],
	["A-", 10, 55, 11000],
	["B+", 7, 45, 9000],
	["B", 4, 35, 7000],
	["B-", 1, 25, 5000],
]

## 길드 상점. give 키: gold·diamonds·equip(장비 상자 — 장비 던전 최고 단계 드롭 1개)·shards(보유 영웅 무작위 조각)·ssr_shards(보유 SSR 무작위 조각). period: day | week
const SHOP := [
	{"id": "dia", "name": "다이아 50", "give": {"diamonds": 50}, "price": 150, "limit": 2, "period": "day"},
	{"id": "gold", "name": "골드 30,000", "give": {"gold": 30000}, "price": 60, "limit": 3, "period": "day"},
	{"id": "equip", "name": "장비 상자", "give": {"equip": 1}, "price": 50, "limit": 3, "period": "day"},
	{"id": "shards", "name": "영웅 조각 상자", "give": {"shards": 3}, "price": 200, "limit": 5, "period": "week"},
	{"id": "ssr", "name": "SSR 조각", "give": {"ssr_shards": 1}, "price": 600, "limit": 2, "period": "week"},
]

const NAME_A := ["새벽", "은빛", "붉은", "강철", "푸른", "황금", "서리", "폭풍", "달빛", "불꽃", "검은", "하얀", "용맹한", "고요한", "별빛", "천둥"]
const NAME_B := ["방패단", "기사단", "수호대", "검술회", "원정대", "늑대단", "망루", "용병단", "결사대", "깃발단", "성채", "사냥단"]
const NICK_A := ["졸린", "용감한", "배고픈", "빠른", "느긋한", "씩씩한", "조용한", "화난", "행복한", "수상한", "귀여운", "우직한", "새침한", "엉뚱한"]
const NICK_B := ["감자", "고양이", "기사", "궁수", "곰", "여우", "도토리", "망치", "방패", "늑대", "토끼", "수염", "마법사", "호박"]
const NOTICES := ["매일 출석과 기부 부탁드려요!", "보스는 하루 두 번 꼭 쳐 주세요", "즐겁게 함께 성장해요", "초보 환영, 질문은 언제든지",
	"주말엔 왕실 기부 이벤트!", "출석 20명 달성 목표!"]
const EMBLEMS := 8  # 문장 모양·색 수(guild_panel이 그린다)

signal changed  # 길드 상태(가입·출석·기부·보스·상점·가상 길드원 활동)가 바뀌었다
signal buff_changed  # 길드 버프(공격력·체력 %)가 바뀌었다 — 영웅 능력치를 다시 읽는다
signal notice(text: String)  # 짧은 알림(레벨업)
signal boss_started(run: Dictionary)  # 보스 전투 시작 {run_id, sec, level, hp, max} — main이 드래곤 전투 장면을 연다
signal acted(kind: String)  # 미션(Missions)이 세는 행동: guild_attend(출석 성공 — 온라인은 응답이 왔을 때)
signal boss_done(result: Dictionary)  # 보스 전투 결과 {dmg, grade, coins, gold, level(도달), killed, total(오늘 내 점수)} 또는 {error}. 온라인은 응답이 왔을 때

var save_path := "user://guild.json"  # ""이면 저장하지 않는다
var econ = null  # Economy(오토로드 또는 테스트가 넣은 것)
var gs = null  # GameState
var unlocked := false
var coins := 0
var guild := {}  # 가입한 길드. 없으면 {}
var me := {}  # 오늘 내 활동 {day, attended, boxes[], donations{}, boss_tries, boss_best, boss_total, contrib}
var shop_day := {}  # {day, bought{}}
var shop_week := {}  # {week, bought{}}
var recommend_n := 0  # 추천 목록 새로고침 횟수(오늘)
var rng := RandomNumberGenerator.new()
var fixed_now := -1.0  # 테스트: 0 이상이면 now_t()가 이 값

var _sim_cd := 0.0
var _last_buff := -1.0
var busy := false  # 온라인: 응답 대기 중
var remote := {}  # 온라인: 마지막 서버 길드 값(GET /v1/guild·쓰기 응답의 guild)
var _boss_run := {}  # 오프라인: 진행 중인 보스 전투(start_boss → finish_boss)
var _last_op := ""  # 온라인: 마지막으로 보낸 쓰기(실패 처리)
var _fetched := false  # 온라인: 접속 뒤 한 번 받았다(길드 버프)

const WAIT_TEXT := "응답 대기 중"
## 서버 409 코드 → 문구
const ERROR_TEXT := {
	"locked": "1-10 라운드를 클리어하면 열립니다", "in_guild": "이미 길드에 가입했습니다", "full": "길드 인원이 가득 찼습니다",
	"name_taken": "이미 있는 길드 이름입니다", "not_enough_gold": "골드가 부족합니다", "not_enough_diamonds": "다이아가 부족합니다",
	"attended": "오늘은 이미 출석했습니다", "claimed": "이미 받은 상자입니다", "donated": "오늘 기부 횟수를 다 썼습니다",
	"no_tries": "오늘 도전 횟수를 다 썼습니다", "no_heroes": "배치된 영웅이 없습니다", "nothing": "받을 보상이 없습니다",
	"sold_out": "구매 한도에 도달했습니다", "not_enough_coins": "길드 코인이 부족합니다", "no_guild": "길드에 가입하세요",
	"no_such_guild": "길드를 찾을 수 없습니다", "bad_name": "길드 이름은 2~8글자입니다",
	"no_run": "보스 전투 기록을 찾지 못했습니다", "too_early": "보스 전투가 아직 끝나지 않았습니다", "bag_full": "장비 보관함이 가득 찼습니다",
}


func _ready() -> void:
	econ = get_node_or_null("/root/Economy")
	gs = get_node_or_null("/root/GameState")
	load_save()
	if gs != null:
		gs.stage_cleared.connect(func(_s): check_unlock())
	if econ != null:
		notice.connect(func(t): econ.notice.emit(t))  # HUD 알림
	check_unlock()


func _process(delta: float) -> void:
	_sim_cd -= delta
	if _sim_cd <= 0.0:
		_sim_cd = 5.0
		if online():
			if not _fetched and econ.net.up:
				_fetched = true
				fetch()
		elif not guild.is_empty():
			tick(now_t())


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		save()


func now_t() -> float:
	if fixed_now >= 0.0:
		return fixed_now
	return econ.time_now() if econ != null else Time.get_unix_time_from_system()


## 두 모드 모두 열린다(온라인은 서버 길드).
func available() -> bool:
	return true


func online() -> bool:
	return econ != null and econ.net != null


func is_unlocked() -> bool:
	if econ != null and econ.get("admin") == true:  # 슈퍼관리자: 라운드 1-10 전에도 열린다(서버도 허락)
		return true
	if online():
		return remote.get("unlocked", false) == true or (gs != null and int(gs.stage) >= UNLOCK_ROUND)
	return unlocked or (gs != null and int(gs.stage) >= UNLOCK_ROUND)


func check_unlock() -> void:
	if online():
		return
	if not unlocked and is_unlocked():
		unlocked = true
		save()
		changed.emit()


func joined() -> bool:
	return not guild.is_empty()


# --- 레벨·버프 ---

## 레벨 L → L+1에 드는 길드 경험치.
static func exp_need(level: int) -> int:
	return roundi(150.0 * pow(float(level), 1.3))


## 길드 레벨 → 인원(나 포함): 1~5레벨 15명, 6레벨부터 20명. 가상 길드원은 남는 자리만 채운다(실제 유저 우선).
static func capacity(level: int) -> int:
	return MEMBERS_MAX if level >= FULL_LEVEL else MEMBERS_BASE


static func buff_of(level: int) -> float:
	return BUFF_PER_LEVEL * maxi(level, 0)


## 지금 길드 버프(영웅 공격력·체력 %). 길드가 없거나 온라인이면 0.
func buff_pct() -> float:
	return buff_of(int(guild.level)) if joined() and available() else 0.0


func _add_exp(n: int, quiet := false) -> void:
	if not joined():
		return
	guild.exp = int(guild.exp) + n
	var up := false
	while int(guild.exp) >= exp_need(int(guild.level)):
		guild.exp = int(guild.exp) - exp_need(int(guild.level))
		guild.level = int(guild.level) + 1
		up = true
	if up:
		if not quiet:
			notice.emit("길드 레벨 업! Lv %d · 영웅 공격력·체력 +%d%%" % [int(guild.level), roundi(buff_pct())])
		_emit_buff()


func _emit_buff() -> void:
	var b := buff_pct()
	if b != _last_buff:
		_last_buff = b
		buff_changed.emit()


# --- 보스 ---

static func boss_max(level: int) -> float:
	return roundf(BOSS_HP_BASE * pow(BOSS_HP_GROWTH, maxi(level, 1) - 1))


static func boss_name(level: int) -> String:
	return BOSS_NAMES[(maxi(level, 1) - 1) % BOSS_NAMES.size()]


## 한 판 피해 → 도달한 드래곤 레벨(Lv 1부터 쓰러뜨린 만큼, 서버 bossOf와 같다).
static func boss_reach(dmg: float) -> int:
	var lv := 1
	var left := maxf(0.0, dmg)
	while left >= boss_max(lv) and lv < 10000:
		left -= boss_max(lv)
		lv += 1
	return lv


## 판 등급(도달 레벨로): [등급, 레벨 이상, 코인, 골드]
static func boss_grade(dmg: float) -> Array:
	var lv := boss_reach(dmg)
	for g in BOSS_GRADES:
		if lv >= int(g[1]):
			return g
	return BOSS_GRADES[-1]


## 오늘 길드 드래곤 점수(길드원 오늘 점수의 합, 나 포함).
func boss_score() -> float:
	if not joined():
		return 0.0
	if online():
		return float(guild.get("boss", {}).get("score", 0))
	var n := float(me.get("boss_total", 0.0))
	for m in members_now():
		n += float(m.get("dmg", 0.0))
	return n


## 내 배치 영웅의 초당 피해 합(성장·연구·길드 버프·공격속도 반영).
func team_dps() -> float:
	if online():
		return float(remote.get("dps", 0))
	if econ == null:
		return 0.0
	var slots: int = gs.hero_count() if gs != null else 5
	var ub: Dictionary = econ.upgrade_bonus()
	var rb: Dictionary = econ.research_bonus()
	var out := 0.0
	for id in econ.deploy_slots(slots):
		if id == null:
			continue
		var def := GameData.hero(id)
		var st := GameData.hero_stats(def, econ.level_of(id), econ.promotion_of(id))
		var atk: float = st.atk * (1.0 + ub.atk_pct) * (1.0 + float(rb.get("hero_atk_pct", 0.0)) / 100.0) * (1.0 + buff_pct() / 100.0)
		out += atk * (1.0 + ub.aspd_pct) / maxf(0.1, float(def.atk_interval))
	return out


## 배치 영웅 전투력 합(길드원 목록의 내 전투력).
func my_power() -> int:
	if online():
		return int(remote.get("power", 0))
	if econ == null:
		return 0
	var slots: int = gs.hero_count() if gs != null else 5
	var p := 0
	for id in econ.deploy_slots(slots):
		if id != null:
			p += GameData.hero_power(GameData.hero(id), econ.level_of(id), econ.promotion_of(id))
	return p


func boss_block() -> String:
	if not joined():
		return "길드에 가입하세요"
	if busy:
		return WAIT_TEXT
	_roll_day(now_t())
	if int(me.boss_tries) >= BOSS_TRIES:
		return "오늘 도전 횟수를 다 썼습니다"
	if team_dps() <= 0.0:
		return "배치된 영웅이 없습니다"
	return ""


## 보스 도전 시작(실제 전투): 도전 1회를 쓰고 boss_started(run {run_id, sec, level(1), hp, max})를 낸다 — main이 드래곤 전투 장면(guild_boss.gd)을 연다.
## 온라인은 서버(/v1/guild/boss/start)가 횟수를 쓰고 run을 준다. 못 하면 false(이유는 boss_block).
func start_boss(now := -1.0) -> bool:
	if now < 0.0:
		now = now_t()
	if boss_block() != "":
		return false
	if online():
		econ.net.flush_kills()
		_post("boss/start", {}, func(d): boss_started.emit(d.get("result", {})))
		return true
	tick(now)
	me.boss_tries = int(me.boss_tries) + 1
	_boss_run = {"run_id": "local-%d" % int(now * 1000.0), "sec": BOSS_FIGHT_SEC, "level": 1, "hp": boss_max(1), "max": boss_max(1),
		"cap": roundf(team_dps() * BOSS_FIGHT_SEC * BOSS_DMG_CAP)}
	save()
	changed.emit()
	boss_started.emit.call_deferred(_boss_run.duplicate())
	return true


## 보스 전투 끝: 영웅이 드래곤에 준 피해 dmg(= 판 점수)를 낸다. 결과는 boss_done({dmg, grade, coins, gold, level, killed, total}) — 실패면 {error}.
## 피해 상한 = 시작 때 초당 피해 × 초 × BOSS_DMG_CAP(서버와 같다).
func finish_boss(run_id: String, dmg: float, now := -1.0) -> void:
	if now < 0.0:
		now = now_t()
	dmg = maxf(0.0, roundf(dmg))
	if online():
		_post("boss/finish", {"run_id": run_id, "dmg": int(dmg)}, func(d): boss_done.emit(d.get("result", {})))
		if not busy:  # 연결이 없어 보내지 못했다
			boss_done.emit({"error": "offline"})
		return
	if _boss_run.is_empty() or str(_boss_run.run_id) != run_id or not joined():
		boss_done.emit({"error": "no_run"})
		return
	dmg = minf(dmg, float(_boss_run.cap))
	_boss_run = {}
	tick(now)
	var lv := boss_reach(dmg)
	var g := boss_grade(dmg)
	me.boss_best = maxf(float(me.boss_best), dmg)
	me.boss_total = float(me.boss_total) + dmg
	me.contrib = int(me.contrib) + 10
	_grant({"coins": int(g[2]), "gold": int(g[3])})
	_log("%s님이 %s Lv %d까지 · %s점" % [MY_NAME, boss_name(lv), lv, _commas(int(dmg))], now)
	save()
	changed.emit()
	boss_done.emit({"dmg": dmg, "grade": g[0], "coins": int(g[2]), "gold": int(g[3]), "level": lv, "killed": lv - 1, "total": float(me.boss_total)})


# --- 하루 ---

func _roll_day(now: float) -> void:
	if online():
		return  # 서버가 날짜를 넘긴 값을 준다
	var d := GameData.reset_day(now)
	if me.is_empty() or int(me.get("day", -1)) != d:
		me = {"day": d, "attended": false, "boxes": [], "donations": {}, "boss_tries": 0, "boss_best": 0.0, "boss_total": 0.0, "contrib": 0}
		recommend_n = 0
	if shop_day.is_empty() or int(shop_day.get("day", -1)) != d:
		shop_day = {"day": d, "bought": {}}
	var w := floori(d / 7.0)
	if shop_week.is_empty() or int(shop_week.get("week", -1)) != w:
		shop_week = {"week": w, "bought": {}}
	if joined() and int(guild.get("today", -1)) != d:
		guild.today = d
		for m in guild.members:
			m.att = false
			m.contrib = 0
			m.dmg = 0.0


## 다음 리셋까지 남은 초.
func reset_in(now := -1.0) -> float:
	if now < 0.0:
		now = now_t()
	if online() and remote.has("next_reset"):
		return maxf(0.0, float(remote.next_reset) - now)
	return GameData.next_reset(now) - now


# --- 출석 ---

func attend_block() -> String:
	if not joined():
		return "길드에 가입하세요"
	if busy:
		return WAIT_TEXT
	_roll_day(now_t())
	return "오늘은 이미 출석했습니다" if me.attended else ""


func attend(now := -1.0) -> bool:
	if now < 0.0:
		now = now_t()
	if attend_block() != "":
		return false
	if online():
		_post("attend", {}, func(_d):
			notice.emit("출석 완료! 골드 +%s · 길드 코인 +%d" % [_commas(ATTEND_REWARD.gold), ATTEND_REWARD.coins])
			acted.emit("guild_attend"))
		return true
	me.attended = true
	me.contrib = int(me.contrib) + ATTEND_EXP
	_grant(ATTEND_REWARD)
	_add_exp(ATTEND_EXP)
	_log("%s님이 출석했습니다" % MY_NAME, now)
	save()
	changed.emit()
	acted.emit("guild_attend")
	return true


## 오늘 출석 인원(나 포함, 지금 길드에 있는 사람).
func attend_count() -> int:
	if not joined():
		return 0
	if online():
		return int(guild.get("attend_count", 0))
	var n := 1 if me.attended else 0
	var now := now_t()
	for m in guild.members:
		if float(m.join_t) <= now and m.att:
			n += 1
	return n


## 출석 상자 i: "claimed" | "ready" | "locked"
func box_state(i: int) -> String:
	if not joined():
		return "locked"
	_roll_day(now_t())
	if me.boxes.has(i):
		return "claimed"
	return "ready" if me.attended and attend_count() >= int(ATTEND_BOXES[i][0]) else "locked"


func claim_box(i: int) -> bool:
	if i < 0 or i >= ATTEND_BOXES.size() or box_state(i) != "ready" or busy:
		return false
	if online():
		_post("box", {"index": i})
		return true
	me.boxes.append(i)
	_grant(ATTEND_BOXES[i][1])
	save()
	changed.emit()
	return true


# --- 기부 ---

func donations_left(kind: String) -> int:
	_roll_day(now_t())
	return int(DONATIONS[kind].daily) - int(me.donations.get(kind, 0))


func donate_block(kind: String) -> String:
	if not joined():
		return "길드에 가입하세요"
	if not DONATIONS.has(kind):
		return "알 수 없는 기부"
	if busy:
		return WAIT_TEXT
	if donations_left(kind) <= 0:
		return "오늘 기부 횟수를 다 썼습니다"
	var d: Dictionary = DONATIONS[kind]
	if econ != null and int(econ.gold) < int(d.gold):
		return "골드가 부족합니다"
	if econ != null and int(econ.diamonds) < int(d.diamonds):
		return "다이아가 부족합니다"
	return ""


func donate(kind: String, now := -1.0) -> bool:
	if now < 0.0:
		now = now_t()
	if donate_block(kind) != "":
		return false
	var d: Dictionary = DONATIONS[kind]
	if online():
		if int(d.gold) > 0:
			econ.net.flush_kills()  # 골드는 서버 값으로 판정한다
		_post("donate", {"kind": kind})
		return true
	_pay(int(d.gold), int(d.diamonds))
	me.donations[kind] = int(me.donations.get(kind, 0)) + 1
	me.contrib = int(me.contrib) + int(d.exp)
	_grant({"coins": int(d.coins)})
	_add_exp(int(d.exp))
	_log("%s님이 %s를 했습니다" % [MY_NAME, d.name], now)
	save()
	changed.emit()
	return true


# --- 상점 ---

func shop_item(id: String) -> Dictionary:
	for it in SHOP:
		if it.id == id:
			return it
	return {}


func shop_left(id: String) -> int:
	var it := shop_item(id)
	if it.is_empty():
		return 0
	_roll_day(now_t())
	var bought: Dictionary = (shop_day if it.period == "day" else shop_week).bought
	return int(it.limit) - int(bought.get(id, 0))


func buy_block(id: String) -> String:
	var it := shop_item(id)
	if it.is_empty():
		return "알 수 없는 상품"
	if busy:
		return WAIT_TEXT
	if shop_left(id) <= 0:
		return "구매 한도에 도달했습니다"
	if coins < int(it.price):
		return "길드 코인이 부족합니다"
	if (it.give.has("shards") and _owned("").is_empty()) or (it.give.has("ssr_shards") and _owned("SSR").is_empty()):
		return "조각을 받을 영웅이 없습니다"
	if it.give.has("equip") and econ != null and econ.bag.size() + int(it.give.equip) > int(GameData.config_num("equip_bag_cap")):
		return "장비 보관함이 가득 찼습니다"
	return ""


## 구매. 반환 받은 것 설명(알림용, 못 사면 "").
func buy(id: String) -> String:
	if buy_block(id) != "":
		return ""
	var it := shop_item(id)
	if online():
		_post("buy", {"id": id}, func(d):
			var parts := []
			for hid in d.get("result", {}).get("shards", {}):
				parts.append("%s 조각 +%d" % [GameData.hero(hid).get("name", hid), int(d.result.shards[hid])])
			for x in d.get("result", {}).get("items", []):
				parts.append(item_text(x))
			notice.emit(" · ".join(parts) if not parts.is_empty() else "%s 구매 완료" % it.name))
		return ""
	coins -= int(it.price)
	var bought: Dictionary = (shop_day if it.period == "day" else shop_week).bought
	bought[id] = int(bought.get(id, 0)) + 1
	var text := _grant(it.give)
	save()
	changed.emit()
	return text


func _owned(grade: String) -> Array:
	var out := []
	if econ == null:
		return out
	for id in econ.heroes:
		if grade == "" or str(GameData.hero(id).get("grade", "")) == grade:
			out.append(id)
	out.sort()
	return out


# --- 보상·비용(오프라인 Economy에 바로) ---

## 보상 반영. 반환 "골드 +3,000 · 길드 코인 +30" 같은 설명.
func _grant(give: Dictionary) -> String:
	var parts := []
	for k in give:
		var n := int(give[k])
		match k:
			"coins":
				coins += n
				parts.append("길드 코인 +%d" % n)
			"gold":
				if econ != null:
					econ.add_gold_tenths(n * 10)
				parts.append("골드 +%s" % _commas(n))
			"diamonds":
				if econ != null:
					econ.diamonds += n
				parts.append("다이아 +%d" % n)
			"food":
				if econ != null:
					econ.res["food"] = int(econ.res.get("food", 0)) + n
				parts.append("식량 +%d" % n)
			"equip":  # 장비 상자: 장비 던전 최고 단계(없으면 1)의 드롭(서버 grant와 같다)
				if econ != null:
					var lv := maxi(1, int(econ.dungeons.get("equip", {}).get("best_level", 0)))
					for it in GameData.roll_drops(lv, n, rng.randf):
						it.id = econ.next_item_id
						econ.next_item_id += 1
						econ.bag.append(it)
						parts.append(item_text(it))
					econ._reindex_items()
					econ.items_changed.emit()
			"shards", "ssr_shards":
				var pool := _owned("SSR" if k == "ssr_shards" else "")
				for i in n:
					if pool.is_empty():
						break
					var id: String = pool[rng.randi_range(0, pool.size() - 1)]
					econ.hero_shards[id] = int(econ.hero_shards.get(id, 0)) + 1
					parts.append("%s 조각 +1" % GameData.hero(id).get("name", id))
	if econ != null and give.keys().any(func(k): return k != "coins"):
		econ.changed.emit()
		if give.has("shards") or give.has("ssr_shards"):
			econ.roster_changed.emit()
		econ.save()
	return " · ".join(parts)


## 장비 한 줄 설명: "SR 무기 Lv 3"
static func item_text(it: Dictionary) -> String:
	var slot_names := {"weapon": "무기", "hat": "모자", "top": "상의", "bottom": "하의", "shoes": "신발", "pauldron": "견장", "gloves": "장갑"}
	return "%s %s 획득" % [str(it.get("grade", "")), slot_names.get(str(it.get("slot", "")), "장비")]


func _pay(gold_n: int, dia_n: int) -> void:
	if econ == null:
		return
	if gold_n > 0:
		econ.add_gold_tenths(-gold_n * 10)
	econ.diamonds -= dia_n
	econ.changed.emit()
	econ.save()


# --- 가입·창설·탈퇴 ---

## 오늘의 추천 길드 5개(새로고침하면 바뀐다). [{seed, name, emblem, level, count, notice, power}]
func recommendations(now := -1.0) -> Array:
	if online():
		return remote.get("recommendations", [])
	if now < 0.0:
		now = now_t()
	_roll_day(now)
	var out := []
	var r := RandomNumberGenerator.new()
	for i in 5:
		r.seed = hash([GameData.reset_day(now), recommend_n, i])
		var s := r.randi()
		var lv := r.randi_range(2, 14)
		out.append({"seed": s, "name": _guild_name(r), "emblem": r.randi_range(0, EMBLEMS - 1), "level": lv,
			"count": mini(r.randi_range(14, 28), capacity(lv) - 1), "notice": NOTICES[r.randi_range(0, NOTICES.size() - 1)], "power": 300 + lv * 120 + r.randi_range(0, 400)})
	return out


func refresh_recommendations() -> void:
	if online():
		fetch()
		return
	recommend_n += 1
	changed.emit()


func join_block() -> String:
	if busy:
		return WAIT_TEXT
	if not is_unlocked():
		return "1-10 라운드를 클리어하면 열립니다"
	if joined():
		return "이미 길드에 가입했습니다"
	return ""


func join(rec: Dictionary, now := -1.0) -> bool:
	if now < 0.0:
		now = now_t()
	if join_block() != "":
		return false
	if online():
		_post("join", {"guild_id": str(rec.get("id", ""))})
		return true
	var r := RandomNumberGenerator.new()
	r.seed = int(rec.seed)
	var members := []
	for i in int(rec.count) - 1:
		members.append(_member(r, i, int(rec.level), -1.0))
	members[0].role = ROLES[0]
	if members.size() > 2:
		members[1].role = ROLES[1]
	_set_guild(rec.name, int(rec.emblem), int(rec.level), r.randi_range(0, exp_need(int(rec.level)) / 2), int(rec.seed), false, str(rec.notice), members, now)
	guild.sim_t = GameData.reset_at(GameData.reset_day(now))  # 오늘 이미 한 길드원 활동은 보이게
	_log("%s님이 길드에 가입했습니다" % MY_NAME, now)
	tick(now, true)
	save()
	changed.emit()
	_emit_buff()
	return true


func create_block(name_text: String) -> String:
	var b := join_block()
	if b != "":
		return b
	var n := name_text.strip_edges()
	if n.length() < 2 or n.length() > 8:
		return "길드 이름은 2~8글자입니다"
	if econ != null and int(econ.gold) < CREATE_GOLD:
		return "골드가 부족합니다"
	return ""


## 직접 창설: 혼자 시작하고, 가입 신청한 가상 길드원이 몇 시간마다 한 명씩 들어온다(길드 인원 capacity까지 — 6레벨부터 더 들어온다).
func create(name_text: String, emblem: int, now := -1.0) -> bool:
	if now < 0.0:
		now = now_t()
	if create_block(name_text) != "":
		return false
	if online():
		econ.net.flush_kills()
		_post("create", {"name": name_text.strip_edges(), "emblem": clampi(emblem, 0, EMBLEMS - 1)})
		return true
	_pay(CREATE_GOLD, 0)
	var r := RandomNumberGenerator.new()
	r.seed = hash([name_text, now])
	var members := []
	var t := now
	for i in MEMBERS_MAX - 1:
		t += r.randf_range(0.5, 3.0) * 3600.0 if i > 0 else 600.0
		members.append(_member(r, i, 1, t))
	_set_guild(name_text.strip_edges(), clampi(emblem, 0, EMBLEMS - 1), 1, 0, r.randi(), true, "함께 성장할 길드원을 모집합니다!", members, now)
	guild.sim_t = now
	_log("%s님이 길드를 창설했습니다" % MY_NAME, now)
	save()
	changed.emit()
	_emit_buff()
	return true


func leave() -> bool:
	if not joined() or busy:
		return false
	if online():
		_post("leave")
		return true
	guild = {}
	me.contrib = 0
	me.boxes = []
	save()
	changed.emit()
	_emit_buff()
	return true


func _set_guild(gname: String, emblem: int, level: int, exp_n: int, s: int, mine: bool, note: String, members: Array, now: float) -> void:
	guild = {"name": gname, "emblem": emblem, "level": level, "exp": exp_n, "seed": s, "mine": mine, "notice": note, "members": members,
		"boss": {}, "sim_t": now, "today": GameData.reset_day(now), "log": [], "joined_t": now}


## 가상 길드원 하나. join_t < 0 = 처음부터 있음.
func _member(r: RandomNumberGenerator, i: int, glv: int, join_t: float) -> Dictionary:
	var name_s: String = NICK_A[r.randi_range(0, NICK_A.size() - 1)] + NICK_B[r.randi_range(0, NICK_B.size() - 1)]
	if r.randf() < 0.4:
		name_s += str(r.randi_range(1, 99))
	var role: String = ROLES[2] if i < 4 else ROLES[3]
	return {"name": name_s, "role": role, "power": 200 + glv * 90 + r.randi_range(0, 900), "att_p": r.randf_range(0.55, 0.97), "join_t": join_t,
		"last": 0.0, "att": false, "contrib": 0, "dmg": 0.0, "hero": r.randi_range(0, 35)}


func _guild_name(r: RandomNumberGenerator) -> String:
	return NAME_A[r.randi_range(0, NAME_A.size() - 1)] + " " + NAME_B[r.randi_range(0, NAME_B.size() - 1)]


## 지금 길드에 있는 길드원(가입 시각이 지난 가상 길드원), 기여도 순은 쓰는 쪽이.
func members_now(now := -1.0) -> Array:
	if not joined():
		return []
	if online():
		return guild.get("members", [])
	if now < 0.0:
		now = now_t()
	return guild.members.slice(0, capacity(int(guild.level)) - 1).filter(func(m): return float(m.join_t) <= now)


# --- 가상 길드원 활동 ---

## sim_t부터 now까지 길드원 활동(출석·기부·보스)을 시간 순으로 반영한다. 하루에 한 번씩, 그날 seed로 정한 시각에.
func tick(now: float, quiet := false) -> void:
	if not joined() or online():
		return
	_roll_day(now)
	var from := maxf(float(guild.sim_t), now - SIM_DAYS_MAX * 86400.0)
	if now <= from:
		return
	var events := []
	for d in range(GameData.reset_day(from), GameData.reset_day(now) + 1):
		var day0 := GameData.reset_at(d)
		for i in mini(guild.members.size(), capacity(int(guild.level)) - 1):  # 자리 밖(아직 못 들어온) 길드원은 활동하지 않는다
			var m: Dictionary = guild.members[i]
			var r := RandomNumberGenerator.new()
			r.seed = hash([int(guild.seed), i, d])
			if r.randf() >= float(m.att_p):
				continue
			var t := day0 + r.randf_range(0.3, 23.5) * 3600.0
			if t <= from or t > now or float(m.join_t) > t:
				continue
			var roll := r.randf()
			var kind := "royal" if roll < 0.04 else ("dia" if roll < 0.2 else ("gold" if roll < 0.85 else ""))
			var hits := r.randi_range(1, BOSS_TRIES)
			var dmg := 0.0  # 그날 드래곤 점수(판마다 Lv 1부터 — 전투력 × 2.8~4.2, 서버 virtualDay와 같은 식)
			for h in hits:
				dmg += roundf(float(m.power) * r.randf_range(2.8, 4.2))
			events.append({"t": t, "i": i, "day": d, "kind": kind, "hits": hits, "dmg": dmg})
	events.sort_custom(func(a, b): return a.t < b.t)
	for e in events:
		var m: Dictionary = guild.members[e.i]
		var today := int(e.day) == GameData.reset_day(now)
		var exp_n := ATTEND_EXP + (int(DONATIONS[e.kind].exp) if e.kind != "" else 0)
		_add_exp(exp_n, quiet)
		m.last = e.t
		if today:
			m.att = true
			m.contrib = int(m.contrib) + exp_n + 10 * int(e.hits)
			m.dmg = float(m.dmg) + float(e.dmg)
			if e.kind != "":
				_log("%s님이 %s를 했습니다" % [m.name, DONATIONS[e.kind].name], e.t)
			else:
				_log("%s님이 출석했습니다" % m.name, e.t)
	guild.sim_t = now
	if not events.is_empty():
		save()
		changed.emit()


func _log(text: String, t: float) -> void:
	if not joined():
		return
	guild.log.append({"t": t, "text": text})
	guild.log.sort_custom(func(a, b): return float(a.t) < float(b.t))
	while guild.log.size() > LOG_MAX:
		guild.log.pop_front()


static func _commas(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


# --- 온라인(서버 길드) ---

## GET /v1/guild(창을 열 때·새로고침·접속 직후).
func fetch() -> void:
	if not online() or not econ.net.up:
		return
	econ.net.send("GET", "/v1/guild", null, func(d): _take(d.get("guild")), Callable())


func _post(op: String, body := {}, done := Callable()) -> void:
	if not econ.net.up:
		notice.emit("연결 대기 중")
		return
	busy = true
	_last_op = op
	changed.emit()
	econ.net.send("POST", "/v1/guild/" + op, body, _on_post.bind(done), _on_post_failed, true, true)


func _on_post(d: Dictionary, done: Callable) -> void:
	busy = false
	econ.apply_server(d)
	_take(d.get("guild"))
	if done.is_valid():
		done.call(d)


## 거부(409 코드 → 문구)·응답 유실: 알림 + 길드 값을 새로 받는다.
func _on_post_failed() -> void:
	busy = false
	notice.emit(ERROR_TEXT.get(econ.net.last_error, "길드 요청을 처리하지 못했습니다"))
	if _last_op == "boss/finish":
		boss_done.emit({"error": econ.net.last_error})
	elif _last_op == "boss/start":
		boss_started.emit({})
	fetch()
	changed.emit()


## 서버 길드 값 → 이 스크립트의 필드(창이 두 모드를 같은 코드로 그린다).
func _take(v) -> void:
	if not (v is Dictionary):
		return
	remote = v
	coins = int(v.get("coins", 0))
	var m = v.get("me")
	if m is Dictionary:
		me = m
		me.boxes = (me.get("boxes", []) as Array).map(func(x): return int(x))
		shop_day = me.get("shop_day", {"bought": {}})
		shop_week = me.get("shop_week", {"bought": {}})
	var g = v.get("guild")
	if g is Dictionary:
		guild = g
		for x in guild.members:
			x.join_t = -1.0
	else:
		guild = {}
	changed.emit()
	_emit_buff()


# --- 저장 ---

func save() -> void:
	if save_path == "" or online():
		return
	var tmp := save_path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("guild save failed: %s" % error_string(FileAccess.get_open_error()))
		return
	f.store_string(JSON.stringify({"version": SAVE_VERSION, "unlocked": unlocked, "coins": coins, "guild": guild, "me": me, "shop_day": shop_day,
		"shop_week": shop_week, "recommend_n": recommend_n}))
	f.close()
	DirAccess.rename_absolute(tmp, save_path)


## 없거나 깨진 파일은 빈 상태로 시작한다(길드 없음).
func load_save() -> void:
	unlocked = false
	coins = 0
	guild = {}
	me = {}
	shop_day = {}
	shop_week = {}
	recommend_n = 0
	if save_path == "" or not FileAccess.file_exists(save_path):
		return
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(save_path)) != OK or not (json.data is Dictionary):
		push_warning("guild save is corrupt; starting empty")
		return
	var d: Dictionary = json.data
	unlocked = d.get("unlocked", false) == true
	coins = maxi(0, int(d.get("coins", 0)))
	recommend_n = maxi(0, int(d.get("recommend_n", 0)))
	if d.get("me") is Dictionary and d.me.has("day"):
		me = d.me
		if not (me.get("boxes") is Array) or not (me.get("donations") is Dictionary):
			me = {}
		else:
			me.boxes = me.boxes.map(func(x): return int(x))
	if d.get("shop_day") is Dictionary and d.shop_day.get("bought") is Dictionary:
		shop_day = d.shop_day
	if d.get("shop_week") is Dictionary and d.shop_week.get("bought") is Dictionary:
		shop_week = d.shop_week
	var g = d.get("guild")
	if g is Dictionary and g.get("members") is Array and g.has("name") and g.has("level"):
		guild = g
		for k in ["level", "exp", "seed", "emblem", "today"]:
			guild[k] = int(guild.get(k, 0))
		guild.level = maxi(1, int(guild.level))
		guild.boss = {}
		if not (guild.get("log") is Array):
			guild.log = []
	_last_buff = buff_pct()
