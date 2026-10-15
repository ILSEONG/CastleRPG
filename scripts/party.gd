extends Node
## 파티 퀘스트 상태(사용자 2026-10-15). 오토로드 Party. 수치는 party_rules.gd(서버 server/src/party.ts와 같다).
## 흐름: 퀘스트·난이도·출전(리치 = 영웅 1, 거미 여왕 = 병사 4)을 골라 [매칭 시작] → 대기(화면 위 띠, 어느 화면에서든 보인다 — party_overlay.gd)
## → 자리가 차면 [입장 수락] 창(모두 수락해야 시작, CONFIRM_SEC초) → 시작(battle_started → main이 party_battle.gd를 연다) → 결과(finish).
## [자동 수락]을 켜 두면 확인 창이 뜨는 즉시 수락한다(user://party.json에 저장).
## 기다림 없이(사용자 규칙): 매칭·취소·수락은 앱 값을 먼저 바꾸고 서버 확인은 뒤에서 받는다. 거절되면 되돌리고 짧은 알림.
## 온라인(Economy.net): 서버가 진실 — 대기·확인 중에는 POLL_SEC마다 GET /v1/party로 묻는다(서버는 묻지 않는 대기를 지운다).
## 오프라인(개발·테스트): 혼자 대기 → OFFLINE_WAIT초 뒤 AI 성주로 채운 확인 → 시작. 보상은 이 기기 보관함에.

const Lang := preload("res://scripts/lang.gd")
const GameData := preload("res://scripts/game_data.gd")
const PartyRules := preload("res://scripts/party_rules.gd")
const PvpRules := preload("res://scripts/pvp_rules.gd")

const POLL_SEC := 1.0
const OFFLINE_WAIT := 2.0
const SAVE_PATH := "user://party.json"
static var ERROR_TEXT := {"locked": "이전 난이도를 먼저 깨야 합니다", "bag_full": "보관함이 가득 찼습니다", "no_soldiers": "병사가 모자랍니다",
	"in_match": "이미 매칭된 파티가 있습니다", "bad_party": "출전을 다시 골라 주세요", "no_match": "파티가 흩어졌습니다", "conflict": "잠시 뒤 다시 시도하세요"}
static var FAIL_TEXT := "매칭을 시작하지 못했습니다"

signal changed
signal battle_started(run: Dictionary)  # 서버 live 상태 {match_id, run_id, quest, diff, seed, elapsed, time_limit, boss, seats, me, online}
signal result_ready(result: Dictionary)  # {win, rewards: {items}, no_reward}

var view := {}  # {quests: {lich|spider: {best, clears_left}}, queue: {state, …}}. 비면 아직 모름
var auto_accept := false
var picks := {}  # 퀘스트 → {diff, hero, soldiers: [{type, tier}]}(마지막 고른 값, 저장)
var save_path := SAVE_PATH
var econ
var started_match := ""  # battle_started를 보낸 매치(같은 매치로 두 번 열지 않는다)
var finishing := {}  # run_id → true(결과를 보내는 중)

var _poll := 0.0
var _busy := false  # 서버 요청 하나가 오가는 중(대기열 묻기는 겹쳐 보내지 않는다)
var _offline_t := 0.0
var _local := {}  # 오프라인 {quests: {q: {best, day, clears}}}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	econ = get_node_or_null("/root/Economy")
	_rng.randomize()
	load_save()
	if view.is_empty():
		view = {"quests": _local_quests(), "queue": {"state": "idle"}}
	if econ != null:
		add_child(preload("res://scripts/party_overlay.gd").new())  # 대기 띠·입장 수락 창(어느 화면에서든)


func online() -> bool:
	return econ != null and econ.net != null


func load_save() -> void:
	if save_path == "" or not FileAccess.file_exists(save_path):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if d is Dictionary:
		auto_accept = d.get("auto_accept", false) == true
		if d.get("picks") is Dictionary:
			picks = d.picks
		if d.get("local") is Dictionary:
			_local = d.local


func save() -> void:
	if save_path == "":
		return
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"auto_accept": auto_accept, "picks": picks, "local": _local}))


func set_auto_accept(on: bool) -> void:
	auto_accept = on
	save()
	changed.emit()
	if on and state() == "confirm" and not queue().get("accepted", false):
		accept(true)


func queue() -> Dictionary:
	var q = view.get("queue")
	return q if q is Dictionary else {"state": "idle"}


func state() -> String:
	return str(queue().get("state", "idle"))


func quest_view(q: String) -> Dictionary:
	var v = view.get("quests", {}).get(q)
	return v if v is Dictionary else {"best": 0, "clears_left": PartyRules.REWARD_CLEARS}


func best(q: String) -> int:
	return int(quest_view(q).get("best", 0))


func clears_left(q: String) -> int:
	return int(quest_view(q).get("clears_left", PartyRules.REWARD_CLEARS))


func unlocked(q: String, diff: int) -> bool:
	return diff <= best(q) + 1


# --- 출전 고르기 ---

## 보유 영웅(전투력 높은 순).
func owned_heroes() -> Array:
	return Pvp.owned_heroes() if has_node("/root/Pvp") else []


## 리치 출전 영웅: 저장한 값(보유 중이면), 아니면 전투력 1위.
func pick_hero() -> String:
	var h := str(picks.get("lich", {}).get("hero", ""))
	if h != "" and econ != null and int(econ.heroes.get(h, 0)) >= 1:
		return h
	var all := owned_heroes()
	return str(all[0]) if not all.is_empty() else ""


## 보유 병사 "병종:티어" → 수(0 초과).
func owned_soldiers() -> Dictionary:
	if econ == null:
		return {}
	var out := {}
	var src: Dictionary = econ.soldiers
	for k in src:
		if int(src[k]) > 0:
			out[k] = int(src[k])
	return out


## 거미 여왕 출전 병사 4마리 [{type, tier}]: 저장한 값(보유 수가 맞으면), 아니면 높은 티어부터.
func pick_soldiers() -> Array:
	var own := owned_soldiers()
	var saved = picks.get("spider", {}).get("soldiers")
	if saved is Array and saved.size() == PartyRules.SOLDIERS_PER and soldiers_ok(saved, own):
		return saved.duplicate(true)
	var keys: Array = own.keys()
	keys.sort_custom(func(a, b): return int(str(a).get_slice(":", 1)) > int(str(b).get_slice(":", 1)) or (int(str(a).get_slice(":", 1)) == int(str(b).get_slice(":", 1)) and str(a) < str(b)))
	var out := []
	for k in keys:
		for i in int(own[k]):
			if out.size() >= PartyRules.SOLDIERS_PER:
				break
			out.append({"type": str(k).get_slice(":", 0), "tier": int(str(k).get_slice(":", 1))})
	return out


static func soldiers_ok(list: Array, own: Dictionary) -> bool:
	var need := {}
	for s in list:
		var k := "%s:%d" % [str(s.get("type", "")), int(s.get("tier", 0))]
		need[k] = int(need.get(k, 0)) + 1
	for k in need:
		if int(own.get(k, 0)) < int(need[k]):
			return false
	return true


func remember(q: String, diff: int, hero := "", soldiers := []) -> void:
	var p: Dictionary = picks.get(q, {})
	p.diff = diff
	if hero != "":
		p.hero = hero
	if not soldiers.is_empty():
		p.soldiers = soldiers.duplicate(true)
	picks[q] = p
	save()


func last_diff(q: String) -> int:
	return clampi(int(picks.get(q, {}).get("diff", 1)), 1, PartyRules.DIFFS)


## [매칭 시작]이 안 되는 까닭("" = 된다).
func queue_block(q: String, diff: int, hero: String, soldiers: Array) -> String:
	if state() != "idle":
		return "이미 매칭 중입니다"
	if not unlocked(q, diff):
		return "%s 난이도를 먼저 깨야 합니다" % PartyRules.DIFF_NAMES[diff - 2]
	if econ != null and econ.bag_full():
		return "보관함이 가득 찼습니다"
	if q == "lich" and hero == "":
		return "출전할 영웅이 없습니다"
	if q == "spider" and (soldiers.size() != PartyRules.SOLDIERS_PER or not soldiers_ok(soldiers, owned_soldiers())):
		return "병사 %d마리가 필요합니다(훈련한 병사만 출전합니다)" % PartyRules.SOLDIERS_PER
	return ""


# --- 매칭 ---

## [매칭 시작]: 곧바로 대기 띠가 보이고 서버 확인은 뒤에서(거절되면 되돌리고 알림).
func start_queue(q: String, diff: int, hero := "", soldiers := []) -> bool:
	if queue_block(q, diff, hero, soldiers) != "":
		return false
	remember(q, diff, hero, soldiers)
	view.queue = {"state": "queued", "quest": q, "diff": diff, "waited": 0, "bot_in": int(PartyRules.BOT_WAIT_SEC), "since": _now()}
	changed.emit()
	if not online():
		_offline_t = OFFLINE_WAIT
		return true
	var body := {"quest": q, "diff": diff}
	if q == "lich":
		body.hero = GuildWar.hero_entry(hero) if has_node("/root/GuildWar") else {"id": hero, "hp": 0, "atk": 0}
	else:
		body.soldiers = soldiers
	_busy = true
	econ.net.send("POST", "/v1/party/queue", body, func(d): _busy = false; _take(d), func():
		_busy = false
		view.queue = {"state": "idle"}
		_notice(ERROR_TEXT.get(econ.net.last_error, FAIL_TEXT))
		changed.emit(), true, true)
	return true


## [취소](대기 중) — 확인 중이면 거절과 같다.
func cancel() -> void:
	var was := state()
	if was == "idle" or was == "live":
		return
	view.queue = {"state": "idle"}
	changed.emit()
	if online():
		econ.net.send("POST", "/v1/party/cancel", {}, func(d): _take(d), Callable(), true, true)


## [입장 수락]·[거절].
func accept(yes: bool) -> void:
	var q := queue()
	if str(q.get("state", "")) != "confirm" or (yes and q.get("accepted", false)):
		return
	if not yes:
		view.queue = {"state": "idle"}
		changed.emit()
	else:
		q.accepted = true
		for s in q.get("seats", []):
			if s.get("me", false):
				s.accepted = true
		changed.emit()
	if not online():
		if yes:
			_offline_live()
		return
	econ.net.send("POST", "/v1/party/accept", {"match_id": str(q.get("match_id", "")), "accept": yes}, func(d): _take(d), func():
		if econ.net.last_error == "no_match":
			view.queue = {"state": "idle"}
			_notice(ERROR_TEXT.no_match)
			changed.emit(), true, true)


func fetch() -> void:
	if not online() or _busy or not econ.net.up:
		return
	_busy = true
	econ.net.send("GET", "/v1/party", null, func(d): _busy = false; _take(d), func(): _busy = false, true, true)


func _take(d) -> void:
	if not (d is Dictionary and d.get("party") is Dictionary):
		return
	var p: Dictionary = d.party
	var q = p.get("queue")
	if q is Dictionary and str(q.get("state", "")) == "live" and finishing.size() > 0:
		p.queue = {"state": "idle"}  # 결과를 보내는 중인 판(서버가 놓아주기 전 응답) — 다시 열지 않는다
		q = p.queue
	view = p
	if q is Dictionary:
		q.since = _now() - float(q.get("waited", 0))
	changed.emit()
	_after_state()


## 상태가 바뀐 뒤: 확인 창 + 자동 수락, 시작이면 전투 장면.
func _after_state() -> void:
	var q := queue()
	match str(q.get("state", "")):
		"confirm":
			if auto_accept and not q.get("accepted", false):
				accept(true)
		"live":
			var id := str(q.get("match_id", ""))
			if id != "" and id != started_match and q.get("result") == null:
				started_match = id
				var run := q.duplicate(true)
				run.online = online()
				_last_run = run
				battle_started.emit(run)


func _process(delta: float) -> void:
	var st := state()
	if st == "queued" or st == "confirm":
		if not online():
			_offline_t -= delta
			if st == "queued" and _offline_t <= 0.0:
				_offline_confirm()
			return
		_poll -= delta
		if _poll <= 0.0:
			_poll = POLL_SEC
			fetch()


## 판 결과(방장이든 아니든 각자 보낸다 — 서버는 방장이 방에서 알린 결과를 쓴다). 결과는 result_ready.
func finish(run_id: String, win: bool, elapsed: float) -> void:
	if finishing.has(run_id):
		return
	finishing[run_id] = true
	view.queue = {"state": "idle"}
	changed.emit()
	if not online():
		finishing.erase(run_id)
		result_ready.emit(_offline_finish(win, elapsed))
		return
	econ.net.send("POST", "/v1/party/finish", {"run_id": run_id, "win": win, "elapsed": snappedf(elapsed, 0.01)}, func(d):
		finishing.erase(run_id)
		if d is Dictionary:
			econ.apply_server(d)
			_take(d)
			var r = d.get("result")
			result_ready.emit(r if r is Dictionary else {"win": false, "rewards": {}}), func():
		finishing.erase(run_id)
		result_ready.emit({"win": false, "rewards": {}, "error": econ.net.last_error}), true, false)


# --- 오프라인(개발·테스트) ---

func _local_quests() -> Dictionary:
	var out := {}
	var day := int(GameData.reset_day(_now())) if econ != null else 0
	for q in PartyRules.QUESTS:
		var l: Dictionary = _local.get("quests", {}).get(q, {})
		var used := int(l.get("clears", 0)) if int(l.get("day", -1)) == day else 0
		out[q] = {"best": int(l.get("best", 0)), "clears_left": maxi(0, PartyRules.REWARD_CLEARS - used)}
	return out


## AI 성주로 채운 확인 창(내 자리 = 0).
func _offline_confirm() -> void:
	var q := queue()
	var quest := str(q.get("quest", "lich"))
	var p: Dictionary = picks.get(quest, {})
	var seats := [_my_seat(quest, p)]
	var names := ["로엔", "베릭", "실라", "카엘"]
	for i in range(1, int(PartyRules.SEATS[quest])):
		var s := {"name": names[i] + " 성주", "bot": true, "me": false, "accepted": true}
		if quest == "lich":
			var all: Array = GameData.heroes()
			var def: Dictionary = all[_rng.randi() % all.size()]
			var mine: Dictionary = seats[0].hero
			s.hero = {"hero": def.id, "level": int(mine.level), "promotion": int(mine.promotion), "hp": float(mine.hp), "atk": float(mine.atk)}
		else:
			s.soldiers = seats[0].soldiers.duplicate(true)
		seats.append(s)
	view.queue = {"state": "confirm", "match_id": "local-%d" % _rng.randi(), "quest": quest, "diff": int(q.get("diff", 1)), "left": int(PartyRules.CONFIRM_SEC),
		"seats": seats, "accepted": false, "since": _now()}
	changed.emit()
	_after_state()


func _my_seat(quest: String, p: Dictionary) -> Dictionary:
	var s := {"name": "나", "bot": false, "me": true, "accepted": false}
	if quest == "lich":
		var id := str(p.get("hero", pick_hero()))
		var e: Dictionary = GuildWar.hero_entry(id) if has_node("/root/GuildWar") and econ != null else {"hp": 500.0, "atk": 40.0}
		s.hero = {"hero": id, "level": econ.level_of(id) if econ != null else 1, "promotion": econ.promotion_of(id) if econ != null else 0,
			"hp": float(e.get("hp", 500.0)), "atk": float(e.get("atk", 40.0))}
	else:
		var out := []
		for x in p.get("soldiers", pick_soldiers()):
			var st := GameData.soldier_stats(str(x.type), int(x.tier))
			out.append({"type": str(x.type), "tier": int(x.tier), "hp": float(st.get("hp", 100.0)), "atk": float(st.get("atk", 10.0))})
		s.soldiers = out
	return s


func _offline_live() -> void:
	var q := queue()
	var quest := str(q.get("quest", "lich"))
	var diff := int(q.get("diff", 1))
	view.queue = {"state": "live", "match_id": q.get("match_id", "local"), "run_id": "local-run-%d" % _rng.randi(), "quest": quest, "diff": diff, "seed": _rng.randi(),
		"elapsed": 0.0, "time_limit": PartyRules.TIME_LIMIT[quest], "boss": PartyRules.boss_stats(quest, diff), "seats": q.get("seats", []), "me": 0, "result": null}
	changed.emit()
	_after_state()


func _offline_finish(win: bool, elapsed: float) -> Dictionary:
	var quest := str(_last_run.get("quest", "lich"))
	var diff := int(_last_run.get("diff", 1))
	var ok := win and elapsed >= PartyRules.MIN_CLEAR_SEC
	var res := {"win": ok, "rewards": {}}
	var day := int(GameData.reset_day(_now()))
	var qs: Dictionary = _local.get("quests", {})
	var l: Dictionary = qs.get(quest, {"best": 0, "day": day, "clears": 0})
	if int(l.get("day", -1)) != day:
		l.day = day
		l.clears = 0
	if ok:
		l.best = maxi(int(l.get("best", 0)), diff)
		if int(l.clears) < PartyRules.REWARD_CLEARS and econ != null:
			l.clears = int(l.clears) + 1
			var item := GameData.roll_item(PartyRules.ACCESSORY[quest], null, _grade(diff), _rng.randf)
			res.rewards = {"items": [econ.add_local_item(item)]}
		else:
			res.no_reward = true
	qs[quest] = l
	_local.quests = qs
	save()
	view.quests = _local_quests()
	changed.emit()
	return res


var _last_run := {}  # 마지막으로 연 판(오프라인 결과에 쓴다)


func _grade(diff: int) -> String:
	var odds := PartyRules.drop_odds(diff)
	var pick := _rng.randf() * 100.0
	var out := "N"
	for g in odds:
		out = g
		pick -= float(odds[g])
		if pick < 0.0:
			break
	return out


func _now() -> float:
	return econ.time_now() if econ != null else Time.get_unix_time_from_system()


func _notice(text: String) -> void:
	if econ != null:
		econ.notice.emit(text)
