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
const LOBBY_POLL_SEC := 2.0  # 파티 대기실(매칭 전)에서 묻는 간격
const INVITE_POLL_SEC := 8.0  # 받은 초대를 묻는 간격(앱이 켜져 있는 동안 — 서버는 이 요청으로 '접속 중'을 안다)
const OFFLINE_CODE := "TEST00"  # 오프라인 파티 코드(혼자 — 참가는 온라인에서만)
const OFFLINE_WAIT := 2.0
const SAVE_PATH := "user://party.json"
static var ERROR_TEXT := {"locked": Lang.t("party.error_text.locked"), "bag_full": Lang.t("party.error_text.bag_full"), "no_soldiers": Lang.t("party.error_text.no_soldiers"),
	"in_match": Lang.t("party.error_text.in_match"), "no_code": Lang.t("party.error_text.no_code"), "full": Lang.t("party.error_text.full"), "not_leader": Lang.t("party.error_text.not_leader"),
	"no_lobby": Lang.t("party.error_text.no_lobby"), "busy": Lang.t("party.error_text.busy"), "member_locked": Lang.t("party.error_text.member_locked"),
	"rate_limited": Lang.t("party.error_text.rate_limited"), "in_lobby": Lang.t("party.error_text.in_lobby"), "bad_party": Lang.t("party.error_text.bad_party"), "no_match": Lang.t("party.error_text.no_match"), "conflict": Lang.t("party.error_text.conflict"),
	"not_friend": Lang.t("party.error_text.not_friend"), "offline": Lang.t("party.error_text.offline"), "member": Lang.t("party.error_text.member")}
static var FAIL_TEXT := Lang.t("party.fail_text")

signal changed
signal battle_started(run: Dictionary)  # 서버 live 상태 {match_id, run_id, quest, diff, seed, elapsed, time_limit, boss, seats, me, online}
signal result_ready(result: Dictionary)  # {win, rewards: {items}, no_reward}
signal invites_changed  # 받은 파티 초대가 바뀌었다(party_overlay.gd가 수락·거절 창을 띄운다)

var view := {}  # {quests: {lich|spider: {best, clears_left}}, queue: {state, …}}. 비면 아직 모름
var auto_accept := false
var picks := {}  # 퀘스트 → {diff, hero, soldiers: [{type, tier}]}(마지막 고른 값, 저장)
var save_path := SAVE_PATH
var econ
var started_match := ""  # battle_started를 보낸 매치(같은 매치로 두 번 열지 않는다)
var finishing := {}  # run_id → true(결과를 보내는 중)

var invites := []  # 받은 초대 [{id, name, quest, diff, code, left, until}](서버 GET /v1/party/invites)
var _poll := 0.0
var _inv_poll := 1.0
var _inv_busy := false
var _gone := {}  # 수락·거절한 초대 id(서버 답이 오기 전 묻기 답에 다시 나오지 않게)
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
func queue_block(q: String, diff: int, hero: String, soldiers: Array, lobby_ok := false) -> String:
	if state() != "idle":
		return Lang.t("party.queue_block")
	if in_lobby() and not lobby_ok:
		return ERROR_TEXT.in_lobby
	if not unlocked(q, diff):
		return Lang.t("party.queue_block_2") % PartyRules.DIFF_NAMES[diff - 2]
	if econ != null and econ.bag_full():
		return Lang.t("party.queue_block_3")
	if q == "lich" and hero == "":
		return Lang.t("party.queue_block_4")
	if q == "spider" and (soldiers.size() != PartyRules.SOLDIERS_PER or not soldiers_ok(soldiers, owned_soldiers())):
		return Lang.t("party.queue_block_5") % PartyRules.SOLDIERS_PER
	return ""


# --- 매칭 ---

## [매칭 시작]: 곧바로 대기 띠가 보이고 서버 확인은 뒤에서(거절되면 되돌리고 알림).
func start_queue(q: String, diff: int, hero := "", soldiers := [], from_lobby := false) -> bool:
	if queue_block(q, diff, hero, soldiers, from_lobby) != "":
		return false
	_epoch += 1
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


# --- 파티 코드(사용자 2026-10-15 "파티코드 있어서 파티를 구성할수잇어") ---
## [파티 만들기] → 코드가 나오고, 다른 성주는 [코드로 참가]. 방장이 [매칭 시작]을 누르면 파티원이 함께 대기열에 들어가 같은 판에 앉는다
## (빈자리는 무작위 매칭 → BOT_WAIT_SEC 뒤 AI 성주). view.lobby = {code, quest, diff, leader, size, members: [{name, me, leader, hero?, soldiers?}]} 또는 null.
## 버튼은 앱 값을 먼저 바꾸고(코드는 서버가 정하니 "······"로) 서버가 거절하면 되돌린다. 빠른 두 번 탭은 _lobby_busy로 한 번만.

var _lobby_busy := false
var _epoch := 0  # 버튼(매칭·취소·수락·파티)을 누를 때마다 +1 — 그 전에 보낸 상태 묻기의 답은 버린다


func lobby() -> Dictionary:
	var l = view.get("lobby")
	return l if l is Dictionary else {}


func in_lobby() -> bool:
	return not lobby().is_empty()


func lobby_leader() -> bool:
	return lobby().get("leader", false) == true


func _pick_body(q: String, hero: String, soldiers: Array) -> Dictionary:
	var body := {}
	if q == "lich":
		body.hero = GuildWar.hero_entry(hero) if has_node("/root/GuildWar") else {"id": hero, "hp": 0, "atk": 0}
	else:
		body.soldiers = soldiers
	return body


## [파티 만들기]: 내가 방장인 파티(그 퀘스트). 막히면 이유("" = 됨).
func create_lobby(q: String, diff: int, hero := "", soldiers := []) -> String:
	var why := queue_block(q, diff, hero, soldiers, true)
	if why != "" or _lobby_busy:
		return why
	remember(q, diff, hero, soldiers)
	_epoch += 1
	var before = view.get("lobby")
	var me := _my_seat(q, picks.get(q, {}))
	me.leader = true
	view.lobby = {"code": "" if online() else OFFLINE_CODE, "quest": q, "diff": diff, "leader": true, "size": int(PartyRules.SEATS[q]), "members": [me]}
	changed.emit()
	if not online():
		return ""
	var body := _pick_body(q, hero, soldiers)
	body.quest = q
	body.diff = diff
	_lobby_busy = true
	econ.net.send("POST", "/v1/party/lobby/create", body, func(d): _lobby_busy = false; _take(d), func():
		_lobby_busy = false
		view.lobby = before
		_notice(ERROR_TEXT.get(econ.net.last_error, FAIL_TEXT))
		changed.emit(), true, true)
	return ""


## [코드로 참가]: 결과는 done(ok, 글). 같은 파티 코드로 다시 보내면 내 출전만 바꾼다.
func join_lobby(code: String, done := Callable()) -> void:
	code = code.strip_edges().to_upper().replace(" ", "").replace("-", "")
	if code.length() < 4:
		if done.is_valid():
			done.call(false, ERROR_TEXT.no_code)
		return
	if not online():
		if done.is_valid():
			done.call(false, Lang.t("party.join_lobby"))
		return
	if _lobby_busy or state() != "idle":
		if done.is_valid():
			done.call(false, ERROR_TEXT.in_match if state() != "idle" else "")
		return
	_lobby_busy = true
	_epoch += 1
	# 퀘스트는 코드가 정한다 — 두 퀘스트 출전을 모두 보내고 서버가 맞는 쪽을 쓴다
	var body := {"code": code, "hero": _pick_body("lich", pick_hero(), []).hero, "soldiers": pick_soldiers()}
	econ.net.send("POST", "/v1/party/lobby/join", body, func(d):
		_lobby_busy = false
		_take(d)
		if done.is_valid():
			done.call(true, ""), func():
		_lobby_busy = false
		if done.is_valid():
			done.call(false, ERROR_TEXT.get(econ.net.last_error, FAIL_TEXT)), true, true)


## 파티에서 내 출전(영웅·병사)을 바꿨다 — 서버 파티 자리에도 알린다.
func update_lobby_pick(hero := "", soldiers := []) -> void:
	var l := lobby()
	if l.is_empty() or str(l.get("code", "")) == "" or not online() or state() != "idle":
		return
	var q := str(l.get("quest", "lich"))
	remember(q, int(l.get("diff", 1)), hero, soldiers)
	var body := _pick_body(q, hero, soldiers)
	body.code = str(l.code)
	econ.net.send("POST", "/v1/party/lobby/join", body, func(d): _take(d), Callable(), true, false)


## [파티 나가기].
func leave_lobby() -> void:
	if not in_lobby():
		return
	if state() == "queued":
		cancel()
	view.lobby = null
	_epoch += 1
	changed.emit()
	if online():
		econ.net.send("POST", "/v1/party/lobby/leave", {}, func(d): _take(d), Callable(), true, true)


## 방장 [매칭 시작]: 파티원 모두 함께 대기. 막히면 이유("" = 됨).
func start_lobby(diff: int) -> String:
	var l := lobby()
	if l.is_empty() or not lobby_leader():
		return ERROR_TEXT.not_leader
	var q := str(l.get("quest", "lich"))
	if not unlocked(q, diff):
		return Lang.t("party.queue_block_2") % PartyRules.DIFF_NAMES[diff - 2]
	if state() != "idle":
		return ""
	_epoch += 1
	l.diff = diff
	if not online():
		var me: Dictionary = l.members[0]
		return "" if start_queue(q, diff, str(me.get("hero", {}).get("hero", "")), Party.pick_soldiers() if q == "spider" else [], true) else Lang.t("party.queue_block_4")
	view.queue = {"state": "queued", "quest": q, "diff": diff, "waited": 0, "bot_in": int(PartyRules.BOT_WAIT_SEC), "since": _now()}
	changed.emit()
	econ.net.send("POST", "/v1/party/lobby/start", {"diff": diff}, func(d): _take(d), func():
		view.queue = {"state": "idle"}
		_notice(ERROR_TEXT.get(econ.net.last_error, FAIL_TEXT))
		changed.emit(), true, true)
	return ""


## [취소](대기 중) — 확인 중이면 거절과 같다.
func cancel() -> void:
	var was := state()
	if was == "idle" or was == "live":
		return
	view.queue = {"state": "idle"}
	_epoch += 1
	changed.emit()
	if online():
		econ.net.send("POST", "/v1/party/cancel", {}, func(d): _take(d), Callable(), true, true)


## [입장 수락]·[거절].
func accept(yes: bool) -> void:
	var q := queue()
	if str(q.get("state", "")) != "confirm" or (yes and q.get("accepted", false)):
		return
	_epoch += 1
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
	var e := _epoch
	econ.net.send("GET", "/v1/party", null, func(d):
		_busy = false
		if e == _epoch:  # 그사이 버튼을 눌렀으면 옛 상태로 되돌리지 않는다(그 버튼의 답이 새 상태를 준다)
			_take(d), func(): _busy = false, true, true)


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
	if online():
		_inv_poll -= delta
		if _inv_poll <= 0.0:
			_inv_poll = INVITE_POLL_SEC
			fetch_invites()
	var st := state()
	if in_lobby() and st == "idle" and online():  # 파티 대기실: 파티원·방장의 매칭 시작을 묻는다(서버는 안 묻는 파티원을 뺀다)
		_poll -= delta
		if _poll <= 0.0:
			_poll = LOBBY_POLL_SEC
			fetch()
		return
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


# --- 초대(사용자 2026-10-15 "그냥 초대도되고"): 파티 안 [초대] → 접속 중인 친구·길드원을 골라 부른다. 받은 사람은 수락·거절 창(party_overlay.gd).
#     수락 = 초대에 든 코드로 참가(join_lobby). 서버가 친구·길드원·접속 중·도배를 검사한다.

func fetch_invites() -> void:
	if not online() or _inv_busy or not econ.net.up:
		return
	_inv_busy = true
	econ.net.send("GET", "/v1/party/invites", null, func(d):
		_inv_busy = false
		_take_invites(d), func(): _inv_busy = false, true, false)


func _take_invites(d) -> void:
	if not (d is Dictionary and d.get("invites") is Array):
		return
	var out := []
	for i in d.invites:
		if i is Dictionary and not _gone.has(str(i.get("id", ""))):
			var x: Dictionary = i.duplicate()
			x.until = _now() + float(i.get("left", 0))
			out.append(x)
	var ids := func(list: Array) -> Array: return list.map(func(i): return str(i.get("id", "")))
	if ids.call(out) != ids.call(invites):
		invites = out
		invites_changed.emit()


## 초대할 수 있는 사람(친구·길드원, 접속 중 먼저). done(people: Array 또는 null = 실패).
func invitable(done: Callable) -> void:
	if not online():
		done.call(null)
		return
	econ.net.send("GET", "/v1/party/invitable", null, func(d):
		done.call(d.get("people", []) if d is Dictionary else null), func(): done.call(null), true, false)


## [초대]: done(ok, 글). 버튼은 부르는 쪽이 먼저 '초대함'으로 바꾸고 실패면 되돌린다.
func invite(to_id: String, done := Callable()) -> void:
	if not online() or not in_lobby():
		if done.is_valid():
			done.call(false, ERROR_TEXT.no_lobby if online() else Lang.t("party.invite"))
		return
	econ.net.send("POST", "/v1/party/invite", {"to": to_id}, func(_d):
		if done.is_valid():
			done.call(true, ""), func():
		if done.is_valid():
			done.call(false, ERROR_TEXT.get(econ.net.last_error, FAIL_TEXT)), true, true)


## 받은 초대 [수락]: 창은 바로 닫고(앱 값 먼저), 코드로 참가한다. 실패면 알림.
func accept_invite(inv: Dictionary) -> void:
	var id := str(inv.get("id", ""))
	if _gone.has(id):
		return
	_gone[id] = true
	invites = invites.filter(func(i): return str(i.get("id", "")) != id)
	invites_changed.emit()
	join_lobby(str(inv.get("code", "")), func(ok, text):
		if not ok and text != "":
			_notice(text))


## 받은 초대 [거절].
func decline_invite(inv: Dictionary) -> void:
	var id := str(inv.get("id", ""))
	if _gone.has(id):
		return
	_gone[id] = true
	invites = invites.filter(func(i): return str(i.get("id", "")) != id)
	invites_changed.emit()
	if online():
		econ.net.send("POST", "/v1/party/invite/decline", {"id": id}, func(_d): pass, Callable(), true, false)


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
	var names := [Lang.t("party.offline_confirm"), Lang.t("party.offline_confirm_2"), Lang.t("party.offline_confirm_3"), Lang.t("party.offline_confirm_4")]
	for i in range(1, int(PartyRules.SEATS[quest])):
		var s := {"name": names[i] + Lang.t("party.offline_confirm_5"), "bot": true, "me": false, "accepted": true}
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
	var s := {"name": Lang.t("party.my_seat.name"), "bot": false, "me": true, "accepted": false}
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
