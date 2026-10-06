extends Node
## 길드전(공성전) 상태. 오토로드 GuildWar. 규칙·수치는 war_rules.gd(서버 server/src/guild_war.ts와 같다).
## 한 주(월요일 리셋)에 상대 길드 하나. 상대 성 = 상대 길드원마다 미리 고른 수비 영웅 4명이 네 성문에 나뉘어 지킨다(수비 AI, war_brain.gd).
## 공성 전투는 한 주에 1번: 길드원이 정한 시각(안 정하면 토요일 21:00)부터 BATTLE_SEC초 동안 열리고 그 사이 누구나 합류한다. 길드원마다 영웅 4명을
## 직접 조종하고 가상 길드원 분대는 AI가 진격한다. 점수 = 처치 1 · 성문 10 · 성채 최대 체력 3%마다 1.
## 주가 끝나면 상대 점수(가상 상대가 한 번 우리 성을 친 결과 — 우리 공성 시간이 끝나면 보인다)와 비교해 승리·패배 보상을 받는다.
##
## 온라인(econ.net != null, 내보낸 APK): 서버 /v1/guild/war*가 진실이다(war = 응답의 war). 전투는 enter → plan → battle_started →
## main이 war_battle.gd를 연다 → war_net.gd가 실시간 방(WebSocket)에 붙는다.
## 오프라인: 같은 모양의 war를 이 스크립트가 계산한다(상대·가상 점수는 seed로, 성 상태·오늘 전투·수비 영웅·보상은 user://guild_war.json).
## 테스트는 .new()로 만들어 save_path를 ""로 두고 now 인자·fixed_now를 쓴다.

const GameData := preload("res://scripts/game_data.gd")
const WarRules := preload("res://scripts/war_rules.gd")

const SAVE_VERSION := 1
const ENEMY_DAY_BASE := 45.0
const ENEMY_DAY_SPREAD := 0.25
const ENEMY_POWER_RANGE := [0.85, 1.15]
const VIRTUAL_POWER_RANGE := [0.8, 1.05]
const MIN_POWER := 250
const WAIT_TEXT := "응답 대기 중"
const ERROR_TEXT := {"battle_done": "이번 주 공성전은 끝났습니다", "conquered": "이번 주 상대 성채를 이미 함락했습니다",
	"not_yet": "아직 공성 시각이 아닙니다", "schedule_locked": "공성 시각이 이미 지났습니다", "schedule_past": "지금보다 뒤의 시각을 고르세요",
	"bad_heroes": "보유한 영웅 4명을 고르세요", "no_guild": "길드에 가입하세요", "nothing": "받을 보상이 없습니다", "not_host": "다른 길드원이 전투를 진행 중입니다"}

signal changed
signal battle_started(run: Dictionary)  # {plan, role, online} — main이 공성 전투 장면(war_battle.gd)을 연다

var war := {}  # 지금 길드전 화면 값(서버 warView와 같은 모양). 비면 아직 모름
var busy := false
var save_path := "user://guild_war.json"
var fixed_now := -1.0
var econ
var guild_node
var local := {}  # 오프라인 저장 {week, castle, battles {week: {id, started_at, closed}}, at(정한 공성 시각, 없으면 -1), defense [ids], claimed [weeks], last {week: {points, enemy_points}}}

var _fetch_cd := 0.0
var _fetched_at := -INF
var _enemy_cache := {}


func _ready() -> void:
	econ = get_node_or_null("/root/Economy")
	guild_node = get_node_or_null("/root/Guild")
	load_save()


func online() -> bool:
	return econ != null and econ.net != null


func now_t() -> float:
	if fixed_now >= 0.0:
		return fixed_now
	return econ.time_now() if econ != null else Time.get_unix_time_from_system()


## 리셋 날 → 주(KST 월요일 00:00에 바뀐다 — 서버 guild_war.ts weekOf, 미션과 같다).
static func week_of(day: int) -> int:
	return floori((day + 4) / 7.0)


static func week_start(week: int) -> int:
	return week * 7 - 4


## 그 주 공성 시각: 정한 값(saved ≥ 0), 없으면 토요일 21:00.
static func battle_at(week: int, saved: float) -> float:
	return saved if saved >= 0.0 else GameData.reset_at(week_start(week) + WarRules.DEFAULT_DAY) + WarRules.DEFAULT_HOUR * 3600.0


## 고른 (주 안 날 0~6, 시 0~23) → 시각(전투가 다음 주 리셋 전에 끝나야 한다). 못 쓰면 -1.
static func pick_at(week: int, day: int, hour: int) -> float:
	if day < 0 or day > 6 or hour < 0 or hour > 23:
		return -1.0
	var at := GameData.reset_at(week_start(week) + day) + hour * 3600.0
	return at if at + WarRules.BATTLE_SEC <= GameData.reset_at(week_start(week + 1)) else -1.0


static func day_in_week(day: int) -> int:
	return day - week_start(week_of(day))


# --- 내 영웅 ---

## 보유 영웅(전투력 높은 순) id.
func owned_heroes() -> Array:
	if econ == null:
		return []
	var ids: Array = econ.heroes.keys().filter(func(id): return not GameData.hero(str(id)).is_empty())
	ids.sort_custom(func(a, b): return hero_power(a) > hero_power(b))
	return ids


func hero_power(id: String) -> int:
	if econ == null:
		return 0
	return GameData.hero_power(GameData.hero(id), econ.level_of(id), econ.promotion_of(id))


## 전투에 쓰는 내 영웅 능력치(성장·연구·장비·길드 버프 포함, hero.refresh_stats와 같은 식). {id, hp, atk}
func hero_entry(id: String) -> Dictionary:
	var def := GameData.hero(id)
	var st := GameData.hero_stats(def, econ.level_of(id), econ.promotion_of(id))
	var ub: Dictionary = econ.upgrade_bonus()
	var rb: Dictionary = econ.research_bonus()
	var g: float = 1.0 + (guild_node.buff_pct() if guild_node != null else 0.0) / 100.0
	return {"id": id, "hp": roundf(st.hp * (1.0 + ub.hp_pct) * (1.0 + float(rb.get("hero_hp_pct", 0.0)) / 100.0) * g),
		"atk": snappedf(st.atk * (1.0 + ub.atk_pct) * (1.0 + float(rb.get("hero_atk_pct", 0.0)) / 100.0) * g, 0.1)}


## 기본 분대: 전투력 높은 4명.
func default_squad() -> Array:
	return owned_heroes().slice(0, WarRules.SQUAD)


func defense() -> Array:
	return war.get("defense", [])


# --- 막힘 ---

func enter_block(ids: Array) -> String:
	if guild_node == null or not guild_node.joined():
		return "길드에 가입하세요"
	if busy:
		return WAIT_TEXT
	if war.is_empty():
		return "길드전 정보를 불러오는 중입니다"
	if ids.size() != WarRules.SQUAD:
		return "출전 영웅 %d명을 고르세요" % WarRules.SQUAD
	if int(war.get("castle", {}).get("keep", {}).get("hp", 1)) <= 0:
		return "이번 주 상대 성채를 이미 함락했습니다"
	match str(war.get("battle", {}).get("state", "")):
		"done":
			return "이번 주 공성전은 끝났습니다"
		"waiting":
			return "공성 시각 %s에 열립니다" % at_text(float(war.get("schedule", {}).get("at", 0.0)))
	return ""


## 공성 시각 글: "토요일 21:00"
static func at_text(at: float) -> String:
	var day := GameData.reset_day(at)
	var hour := roundi((at - GameData.reset_at(day)) / 3600.0)
	return "%s요일 %d:00" % [WarRules.DAY_NAMES[day_in_week(day)], hour]


func schedule_block(day: int, hour: int) -> String:
	if guild_node == null or not guild_node.joined():
		return "길드에 가입하세요"
	if busy:
		return WAIT_TEXT
	if war.is_empty():
		return "길드전 정보를 불러오는 중입니다"
	if not war.get("schedule", {}).get("can_change", false):
		return ERROR_TEXT.schedule_locked
	var at := pick_at(int(war.week), day, hour)
	if at < 0.0:
		return "이번 주 안의 시각을 고르세요"
	if at <= now_t():
		return ERROR_TEXT.schedule_past
	return ""


# --- 동작 ---

## 화면 값 새로 받기(온라인 GET, 오프라인 계산).
func fetch() -> void:
	_fetched_at = Time.get_ticks_msec() / 1000.0
	if online():
		if not econ.net.up:
			return
		econ.net.send("GET", "/v1/guild/war", null, func(d): _take(d), Callable())
		return
	war = local_view(now_t())
	changed.emit()


## 창이 열릴 때: 마지막으로 받은 지 sec초가 지났으면 다시 받는다.
func fetch_if_stale(sec := 20.0) -> void:
	if Time.get_ticks_msec() / 1000.0 - _fetched_at >= sec:
		fetch()


func set_defense(ids: Array) -> void:
	if ids.size() != WarRules.SQUAD:
		_notice("수비 영웅 %d명을 고르세요" % WarRules.SQUAD)
		return
	if online():
		_post("defense", {"heroes": ids.map(func(id): return hero_entry(id))}, func(_d): _notice("수비 영웅을 저장했습니다"))
		return
	local.defense = ids.duplicate()
	save()
	fetch()
	_notice("수비 영웅을 저장했습니다")


## 이번 주 공성 시각을 정한다(길드원 누구나, 그 시각이 오기 전까지). day 0 = 월요일.
func set_schedule(day: int, hour: int) -> bool:
	var why := schedule_block(day, hour)
	if why != "":
		_notice(why)
		return false
	if online():
		_post("schedule", {"day": day, "hour": hour}, func(_d): _notice("이번 주 공성 시각: %s" % at_text(pick_at(int(war.week), day, hour))))
		return true
	local.at = pick_at(int(war.week), day, hour)
	save()
	fetch()
	_notice("이번 주 공성 시각: %s" % at_text(float(local.at)))
	return true


## 이번 주 공성 전투에 들어간다(공성 시각 ~ +BATTLE_SEC, 없으면 연다). 성공하면 battle_started.
func enter(ids: Array) -> bool:
	var why := enter_block(ids)
	if why != "":
		_notice(why)
		return false
	var entries: Array = ids.map(func(id): return hero_entry(id))
	if online():
		econ.net.flush_kills()
		_post("enter", {"heroes": entries}, func(d):
			var plan: Dictionary = d.get("plan", {})
			if not plan.is_empty():
				battle_started.emit({"plan": plan, "role": "puppet", "online": true}))
		return true
	var plan := local_enter(entries, now_t())
	if plan.is_empty():
		return false
	battle_started.emit.call_deferred({"plan": plan, "role": "solo", "online": false})
	return true


## 실시간 방에 붙지 못한 방장 기기가 결과를 직접 보낸다(온라인), 또는 오프라인 저장.
func finish(result: Dictionary, final := true) -> void:
	if online():
		econ.net.send("POST", "/v1/guild/war/finish", {"battle_id": result.get("battle_id", ""), "state": result}, func(d): _take(d), Callable(), true, true)
		return
	local_save_state(result, final, now_t())


func claim() -> void:
	if online():
		_post("claim", {}, func(d):
			var r: Dictionary = d.get("result", {})
			_notice(_claim_text(r)))
		return
	var cl = war.get("claim")
	if not (cl is Dictionary):
		_notice(ERROR_TEXT.nothing)
		return
	local.claimed.append(int(cl.week))
	if guild_node != null:
		guild_node._grant(cl.reward)
		guild_node.save()
		guild_node.changed.emit()
	save()
	fetch()
	_notice(_claim_text(cl))


static func _claim_text(r: Dictionary) -> String:
	var rw: Dictionary = r.get("reward", {})
	return "길드전 %s 보상: 길드 코인 +%d · 다이아 +%d" % ["승리" if r.get("win", false) else "참여", int(rw.get("coins", 0)), int(rw.get("diamonds", 0))]


func _post(op: String, body: Dictionary, done: Callable) -> void:
	if not econ.net.up:
		_notice("연결 대기 중")
		return
	busy = true
	changed.emit()
	econ.net.send("POST", "/v1/guild/war/" + op, body, func(d):
		busy = false
		if d.get("player") is Dictionary:  # 보상(claim)만 플레이어 값을 같이 준다
			econ.apply_server(d)
		_take(d)
		done.call(d), func():
		busy = false
		_notice(ERROR_TEXT.get(econ.net.last_error, "길드전 요청을 처리하지 못했습니다"))
		fetch()
		changed.emit(), true, true)


func _take(d) -> void:
	if d is Dictionary and d.get("war") is Dictionary:
		war = d.war
		changed.emit()


func _notice(t: String) -> void:
	if econ != null:
		econ.notice.emit(t)


func _process(delta: float) -> void:
	_fetch_cd -= delta
	if _fetch_cd <= 0.0:
		_fetch_cd = 60.0
		if not online() and guild_node != null and guild_node.joined() and not war.is_empty():
			war = local_view(now_t())  # 시각이 지나면 공성 상태·상대 점수가 바뀐다


# --- 오프라인 계산(서버 guild_war.ts·war_routes.ts와 같은 식) ---

static func _rng(parts: Array) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash(parts)
	return r


## 목표 전투력에 가장 가까운 (레벨, 승급).
static func fit_hero(def: Dictionary, target: float) -> Dictionary:
	var best := {"level": 1, "promotion": 0}
	var best_d := INF
	for p in 4:
		for l in range(1, GameData.max_level(p) + 1):
			var d := absf(GameData.hero_power(def, l, p, {}) - target)
			if d < best_d - 1e-9:
				best_d = d
				best = {"level": l, "promotion": p}
	return best


## 무작위 영웅 4명(근접 ≥ 1, 원거리 ≥ 1), 전투력에 맞춘 레벨. [{hero, level, promotion, hp, atk}]
static func random_squad(r: RandomNumberGenerator, power: float) -> Array:
	var pool: Array = GameData.heroes().duplicate()
	var picks := []
	var take := func(list: Array):
		var left := list.filter(func(h): return not picks.has(h))
		if not left.is_empty():
			picks.append(left[r.randi_range(0, left.size() - 1)])
	take.call(pool.filter(func(h): return h.role == "melee"))
	take.call(pool.filter(func(h): return h.role != "melee"))
	while picks.size() < WarRules.SQUAD and picks.size() < pool.size():
		take.call(pool)
	var per := maxf(MIN_POWER, power) / WarRules.SQUAD
	var out := []
	for d in picks:
		var f := fit_hero(d, per)
		var s := GameData.hero_stats(d, f.level, f.promotion, {})
		out.append({"hero": d.id, "level": f.level, "promotion": f.promotion, "hp": roundf(s.hp), "atk": snappedf(s.atk, 0.1)})
	return out


## 상대 길드(seed·인원·평균 전투력으로 정해진다). {name, emblem, power, members [{name, power}], defenders [...]}
static func enemy_guild(seed_n: int, n: int, avg: float) -> Dictionary:
	var r := _rng([seed_n, 31])
	var members := []
	var defs := []
	var total := 0
	for m in n:
		var power := roundi(maxf(MIN_POWER, avg) * r.randf_range(ENEMY_POWER_RANGE[0], ENEMY_POWER_RANGE[1]))
		var nr := _rng([seed_n, 500 + m])
		var name_s: String = GuildScriptNames.nick(nr)
		members.append({"name": name_s, "power": power})
		total += power
		var sq := random_squad(r, power)
		for i in sq.size():
			var h: Dictionary = sq[i]
			h.merge({"uid": 1 + m * WarRules.SQUAD + i, "owner": "d:%d" % m, "name": name_s, "squad": m, "lane": WarRules.lane_of(m)})
			defs.append(h)
	var gr := _rng([seed_n, 3])
	return {"seed": seed_n, "name": GuildScriptNames.guild(gr), "emblem": _rng([seed_n, 4]).randi_range(0, 7), "power": total, "members": members, "defenders": defs}


static func castle_max(defs: Array) -> Dictionary:
	var lane := [0.0, 0.0, 0.0, 0.0]
	var all := 0.0
	for d in defs:
		lane[int(d.lane)] += float(d.hp)
		all += float(d.hp)
	return {"gates": lane.map(func(h): return WarRules.gate_hp_max(h)), "keep": WarRules.keep_hp_max(all)}


static func fresh_castle(defs: Array) -> Dictionary:
	var mx := castle_max(defs)
	return {"gates": mx.gates.duplicate(), "keep": mx.keep, "dead": {}}


static func kills_in(c: Dictionary) -> int:
	return c.dead.values().filter(func(v): return float(v) <= 0.0).size()


static func gates_down(c: Dictionary) -> int:
	return c.gates.filter(func(g): return float(g) <= 0.0).size()


static func castle_points(c: Dictionary, keep_max: float) -> int:
	return WarRules.points(kills_in(c), gates_down(c), WarRules.keep_points(float(c.keep), keep_max))


## 결과를 성 상태에 합친다(줄어든 값만).
static func merge_castle(c: Dictionary, r: Dictionary, defs: Array) -> Dictionary:
	var out := {"gates": c.gates.duplicate(), "keep": float(c.keep), "dead": c.dead.duplicate()}
	var gs = r.get("gates")
	if gs is Array:
		for i in mini(4, gs.size()):
			if float(gs[i]) >= 0.0:
				out.gates[i] = minf(float(out.gates[i]), roundf(float(gs[i])))
	if r.has("keep") and float(r.keep) >= 0.0:
		out.keep = minf(out.keep, roundf(float(r.keep)))
	var ds = r.get("defenders")
	if ds is Dictionary:
		var known := {}
		for d in defs:
			known[str(int(d.uid))] = true
		for k in ds:
			var x := float(ds[k])
			if not known.has(str(k)) or x < 0.0 or x > 1.0:
				continue
			var nv := snappedf(minf(float(out.dead.get(str(k), 1.0)), x), 0.001)
			if nv < 1.0:
				out.dead[str(k)] = nv
	return out


static func castle_cap(members: int) -> int:
	return members * WarRules.SQUAD * WarRules.PTS_KILL + 4 * WarRules.PTS_GATE + WarRules.KEEP_MAX_PTS


## 가상 상대가 그 주 한 번의 공성으로 우리 성을 친 점수.
static func enemy_points(seed_n: int, week: int, ratio: float, cap: int) -> int:
	var r := _rng([seed_n, week, 900])
	var v := roundi(ENEMY_DAY_BASE * clampf(ratio, 0.2, 2.5) * r.randf_range(1.0 - ENEMY_DAY_SPREAD, 1.0 + ENEMY_DAY_SPREAD))
	return maxi(0, mini(v, cap))


## 우리 길드원 {key, name, power, real}: 나 + 가상 길드원.
func our_members() -> Array:
	var out := [{"key": "me", "name": "나", "power": guild_node.my_power() if guild_node != null else 0, "real": true}]
	if guild_node != null:
		var ms: Array = guild_node.members_now()
		for i in ms.size():
			out.append({"key": "v:%d" % i, "name": str(ms[i].name), "power": int(ms[i].get("power", MIN_POWER)), "real": false})
	return out


func _week_row(week: int) -> Dictionary:
	if int(local.get("week", -999)) != week or not (local.get("castle") is Dictionary):
		var ms := our_members()
		var avg := 0.0
		for m in ms:
			avg += float(m.power)
		avg /= maxf(1.0, ms.size())
		if int(local.get("week", -999)) >= 0 and local.get("castle") is Dictionary:
			var lw: Dictionary = local.get("last", {})
			lw[str(int(local.week))] = {"points": castle_points(local.castle, float(castle_max(enemy_of().defenders).keep)), "enemy_points": int(local.get("enemy_full", 0))}
			local.last = lw
		local.week = week
		local.seed = hash([int(guild_node.guild.get("seed", 0)) if guild_node != null else 0, week, 77])
		local.power = roundi(avg)
		local.members = guild_node.capacity(int(guild_node.guild.get("level", 1))) if guild_node != null else 15
		local.battles = {}
		local.at = -1.0
		local.castle = fresh_castle(enemy_of().defenders)
		save()
	return local


func enemy_of() -> Dictionary:
	var key := [int(local.seed), int(local.members), int(local.power)]
	if _enemy_cache.get("key") != key:
		_enemy_cache = {"key": key, "enemy": enemy_guild(int(local.seed), int(local.members), float(local.power))}
	return _enemy_cache.enemy


func local_view(now: float) -> Dictionary:
	if guild_node == null or not guild_node.joined():
		return {}
	var day := GameData.reset_day(now)
	var week := week_of(day)
	_week_row(week)
	var enemy := enemy_of()
	var mx := castle_max(enemy.defenders)
	var ms := our_members()
	var total := 0.0
	for m in ms:
		total += float(m.power)
	var ep := enemy_points(int(local.seed), week, float(enemy.power) / maxf(1.0, total), castle_cap(ms.size()))
	local.enemy_full = ep
	var at := battle_at(week, float(local.get("at", -1.0)))
	var ends := at + WarRules.BATTLE_SEC
	var ep_now := ep if now >= ends else 0
	var c: Dictionary = local.castle
	var b = local.battles.get(str(week))
	var state := "done" if (b is Dictionary and b.closed) or now >= ends else ("waiting" if now < at else "live")
	var gates := []
	for i in 4:
		gates.append({"hp": c.gates[i], "max": mx.gates[i]})
	var members := []
	for m in ms:
		members.append({"name": m.name, "power": m.power, "real": m.real, "mine": m.key == "me", "defense": local.defense if m.key == "me" else []})
	return {"week": week, "day": day_in_week(day), "week_ends": GameData.reset_at(week_start(week + 1)),
		"enemy": {"name": enemy.name, "emblem": enemy.emblem, "power": enemy.power, "members": enemy.members.size()},
		"points": castle_points(c, float(mx.keep)), "enemy_points": ep_now, "enemy_days": [ep] if now >= ends else [],
		"schedule": {"at": at, "ends_at": ends, "by": "나" if float(local.get("at", -1.0)) >= 0.0 else "", "set": float(local.get("at", -1.0)) >= 0.0, "can_change": now < at},
		"castle": {"gates": gates, "keep": {"hp": c.keep, "max": mx.keep}, "kills": kills_in(c), "defenders": enemy.defenders.size()},
		"battle": {"state": state, "me_in": b is Dictionary, "started_at": at, "ends_at": ends},
		"defense": local.defense, "members": members, "claim": _local_claim(week)}


func _local_claim(week: int):
	var lw = local.get("last", {}).get(str(week - 1))
	if not (lw is Dictionary) or local.claimed.has(week - 1):
		return null
	var win: bool = int(lw.points) > int(lw.enemy_points)
	return {"week": week - 1, "win": win, "points": int(lw.points), "enemy_points": int(lw.enemy_points),
		"reward": WarRules.REWARD_WIN if win else WarRules.REWARD_LOSE}


## 오프라인 전투 열기·다시 들어가기. 반환 plan(서버 enter와 같은 모양).
func local_enter(entries: Array, now: float) -> Dictionary:
	var day := GameData.reset_day(now)
	var week := week_of(day)
	_week_row(week)
	var at := battle_at(week, float(local.get("at", -1.0)))
	var b = local.battles.get(str(week))
	if now < at:
		_notice(ERROR_TEXT.not_yet)
		return {}
	if (b is Dictionary and b.closed) or now >= at + WarRules.BATTLE_SEC:
		_notice(ERROR_TEXT.battle_done)
		return {}
	if not (b is Dictionary):
		b = {"id": "local-%d" % week, "started_at": at, "closed": false}
		local.battles[str(week)] = b
		save()
	var enemy := enemy_of()
	var mx := castle_max(enemy.defenders)
	var c: Dictionary = local.castle
	var defs := []
	for d in enemy.defenders:
		var ratio := float(c.dead.get(str(int(d.uid)), 1.0))
		if ratio > 0.0:
			var x: Dictionary = d.duplicate()
			x.ratio = ratio
			defs.append(x)
	var roster := []
	var vi := 0
	for m in our_members():
		if m.real:
			continue
		var r := _rng([int(local.seed), day, vi])
		var pw := float(m.power) * r.randf_range(VIRTUAL_POWER_RANGE[0], VIRTUAL_POWER_RANGE[1])
		roster.append({"owner": m.key, "name": m.name, "squad": roster.size(), "lane": roster.size() % 4, "ai": true, "heroes": random_squad(r, pw)})
		vi += 1
	var mine := []
	for e in entries:
		mine.append({"hero": e.id, "level": econ.level_of(e.id), "promotion": econ.promotion_of(e.id), "hp": e.hp, "atk": e.atk})
	roster.append({"owner": "me", "name": "나", "squad": roster.size(), "lane": roster.size() % 4, "ai": false, "heroes": mine})
	var gates := []
	for i in 4:
		gates.append({"hp": c.gates[i], "max": mx.gates[i]})
	fetch()
	return {"battle_id": b.id, "my_id": "me", "enemy_name": enemy.name, "duration": WarRules.BATTLE_SEC, "clock": maxf(0.0, now - float(b.started_at)),
		"gates": gates, "keep": {"hp": c.keep, "max": mx.keep}, "defenders": defs, "attackers": roster, "live": ""}


func local_save_state(result: Dictionary, final: bool, now: float) -> void:
	var day := GameData.reset_day(now)
	_week_row(week_of(day))
	local.castle = merge_castle(local.castle, result, enemy_of().defenders)
	for k in local.battles:
		if str(local.battles[k].id) == str(result.get("battle_id", "")) and (final or float(local.castle.keep) <= 0.0):
			local.battles[k].closed = true
	save()
	fetch()


# --- 저장 ---

func save() -> void:
	if save_path == "" or online():
		return
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"version": SAVE_VERSION, "local": local}))
	f.close()


func load_save() -> void:
	local = {"defense": [], "claimed": [], "battles": {}, "last": {}}
	if save_path == "" or not FileAccess.file_exists(save_path):
		return
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(save_path)) != OK or not (json.data is Dictionary) or not (json.data.get("local") is Dictionary):
		return
	var d: Dictionary = json.data.local
	for k in local:
		if typeof(d.get(k)) == typeof(local[k]):
			local[k] = d[k]
	for k in ["week", "seed", "power", "members", "enemy_full"]:
		if d.has(k):
			local[k] = int(d[k])
	local.at = float(d.get("at", -1.0))
	if d.get("castle") is Dictionary and d.castle.get("gates") is Array and d.castle.get("dead") is Dictionary:
		local.castle = d.castle
	local.claimed = local.claimed.map(func(x): return int(x))


## 이름 만들기(guild.gd 단어 목록을 쓴다).
class GuildScriptNames:
	const G := preload("res://scripts/guild.gd")

	static func nick(r: RandomNumberGenerator) -> String:
		var s: String = G.NICK_A[r.randi_range(0, G.NICK_A.size() - 1)] + G.NICK_B[r.randi_range(0, G.NICK_B.size() - 1)]
		if r.randf() < 0.4:
			s += str(r.randi_range(1, 99))
		return s

	static func guild(r: RandomNumberGenerator) -> String:
		return G.NAME_A[r.randi_range(0, G.NAME_A.size() - 1)] + " " + G.NAME_B[r.randi_range(0, G.NAME_B.size() - 1)]
