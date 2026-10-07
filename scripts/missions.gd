extends Node
## 미션(2026-10-06): 일일·주간·반복. 오토로드 Missions. 창은 mission_panel.gd(오른쪽 아래 메뉴 [미션]).
## 일일 = 리셋 날짜(config daily_reset_utc_hour, 00:00 KST)마다, 주간 = 월요일 리셋마다 진행·받은 기록이 지워진다.
## 반복 = 받을 때마다 목표가 step만큼 커지고 끝없이 받는다(진행은 받은 뒤 남은 만큼부터 다시 센다).
## 튜토리얼 카드의 반복 퀘스트(Tutorial.REPEATS, 한 번에 하나)는 그대로 두고, 이 반복 미션은 여러 개가 함께 도는 별도 목록이다.
## 사건 수(처치·수집·판매·모집·레벨업·성장·던전·건물·연구·훈련·길드)는 여기서 센다(튜토리얼과 같다). 받은 기록은
## 온라인이면 서버(/v1/player의 missions — Economy.server_missions)가, 오프라인이면 이 파일 저장이 가진다. 온라인 보상은 POST /v1/mission/claim.
## 미션 표(DEFS)는 server/src/missions.ts와 같다(온라인은 GET /v1/missions가 준 표를 쓴다).
## 저장: user://missions.json {version, day, week, counts: {d: {kind: n}, w: {kind: n}, r: {id: n}}, claimed: {d, w, wd, r}}.

const GameData := preload("res://scripts/game_data.gd")
const EconomyScript := preload("res://scripts/economy.gd")  # 주머니 이름(pouch_name)

const SAVE_VERSION := 1
const TYPES := [["daily", "일일"], ["weekly", "주간"], ["repeat", "반복"]]
## server/src/missions.ts DEFS와 같은 표. kind: 여기서 세는 사건, daily_count = 오늘 받은 다른 일일 미션 수, daily_bonus = 이번 주 일일 보너스 받은 날 수.
const DEFS := [
	{"id": "d_kill", "type": "daily", "kind": "kill", "title": "몬스터 %d마리 처치", "target": 300, "reward": {"gold": 3000, "pouch_gold_10": 1}},
	{"id": "d_collect", "type": "daily", "kind": "collect", "title": "자원 %d번 수집", "target": 5, "reward": {"wood": 3000, "stone": 3000, "food": 3000, "pouch_res_10": 1}},
	{"id": "d_sell", "type": "daily", "kind": "sell", "title": "상인과 %d번 거래", "target": 2, "reward": {"gold": 2000}},
	{"id": "d_hero", "type": "daily", "kind": "hero_level", "title": "영웅 레벨업 %d회", "target": 5, "reward": {"gold": 3000}},
	{"id": "d_growth", "type": "daily", "kind": "growth", "title": "성장 강화 %d회", "target": 3, "reward": {"gold": 3000}},
	{"id": "d_gacha", "type": "daily", "kind": "gacha", "title": "영웅 %d회 모집", "target": 10, "reward": {"diamonds": 30}},
	{"id": "d_dungeon", "type": "daily", "kind": "dungeon_win", "title": "던전 %d번 클리어", "target": 2, "reward": {"diamonds": 30}},
	{"id": "d_guild", "type": "daily", "kind": "guild_attend", "title": "길드 출석", "target": 1, "reward": {"diamonds": 20}},
	{"id": "d_all", "type": "daily", "kind": "daily_count", "title": "일일 미션 %d개 완료", "target": 6, "reward": {"diamonds": 100, "tickets": 1, "pouch_gold_60": 1}},
	{"id": "w_bonus", "type": "weekly", "kind": "daily_bonus", "title": "일일 미션 보너스 %d일 받기", "target": 5, "reward": {"tickets": 5, "pouch_gold_360": 1, "pouch_res_360": 1}},
	{"id": "w_kill", "type": "weekly", "kind": "kill", "title": "몬스터 %d마리 처치", "target": 3000, "reward": {"gold": 30000, "pouch_gold_240": 1}},
	{"id": "w_dungeon", "type": "weekly", "kind": "dungeon_win", "title": "던전 %d번 클리어", "target": 10, "reward": {"diamonds": 150}},
	{"id": "w_gacha", "type": "weekly", "kind": "gacha", "title": "영웅 %d회 모집", "target": 50, "reward": {"diamonds": 150}},
	{"id": "w_hero", "type": "weekly", "kind": "hero_level", "title": "영웅 레벨업 %d회", "target": 30, "reward": {"gold": 30000}},
	{"id": "w_build", "type": "weekly", "kind": "build_up", "title": "건물 레벨업 %d번 완료", "target": 3, "reward": {"wood": 20000, "stone": 20000, "food": 20000, "pouch_res_240": 1}},
	{"id": "w_research", "type": "weekly", "kind": "research", "title": "연구 %d번 시작", "target": 2, "reward": {"gold": 20000}},
	{"id": "w_train", "type": "weekly", "kind": "train", "title": "병사 훈련 %d번", "target": 3, "reward": {"gold": 10000}},
	{"id": "w_boss", "type": "weekly", "kind": "guild_boss", "title": "길드 보스 %d번 도전", "target": 3, "reward": {"diamonds": 100}},
	{"id": "r_kill", "type": "repeat", "kind": "kill", "title": "몬스터 %d마리 처치", "target": 1000, "step": 500, "reward": {"gold": 5000, "pouch_gold_30": 1}},
	{"id": "r_stage", "type": "repeat", "kind": "stage", "title": "라운드 %d번 클리어", "target": 10, "step": 5, "reward": {"diamonds": 20}},
	{"id": "r_collect", "type": "repeat", "kind": "collect", "title": "자원 %d번 수집", "target": 20, "step": 10, "reward": {"wood": 5000, "stone": 5000, "food": 5000, "pouch_res_30": 1}},
	{"id": "r_sell", "type": "repeat", "kind": "sell", "title": "상인과 %d번 거래", "target": 10, "step": 5, "reward": {"gold": 5000}},
	{"id": "r_hero", "type": "repeat", "kind": "hero_level", "title": "영웅 레벨업 %d회", "target": 20, "step": 10, "reward": {"gold": 5000}},
	{"id": "r_growth", "type": "repeat", "kind": "growth", "title": "성장 강화 %d회", "target": 20, "step": 10, "reward": {"gold": 5000}},
	{"id": "r_gacha", "type": "repeat", "kind": "gacha", "title": "영웅 %d회 모집", "target": 30, "step": 10, "reward": {"tickets": 1}},
	{"id": "r_dungeon", "type": "repeat", "kind": "dungeon_win", "title": "던전 %d번 클리어", "target": 5, "step": 3, "reward": {"diamonds": 30}},
]
## 사건 → [바로가기] 대상(Tutorial.goto_requested 형식 — main이 처리한다). 없으면 버튼 없음.
const GOTO := {"kill": "stage", "stage": "stage", "collect": "look:lumber", "sell": "merchant", "hero_level": "tab:hero", "growth": "tab:growth",
	"gacha": "tab:recruit", "dungeon_win": "tab:dungeon", "guild_attend": "tab:guild", "guild_boss": "tab:guild", "build_up": "building:keep",
	"research": "building:lab", "train": "building:barracks"}
const FAIL_TEXT := {"claimed": "이미 받은 보상입니다", "not_done": "아직 완료하지 않았습니다", "too_soon": "잠시 뒤 다시 받아 주세요",
	"stale": "진행을 새로 받았습니다. 다시 눌러 주세요"}
const FAIL_DEFAULT := "보상을 받지 못했습니다"
const WAIT_TEXT := "연결 대기 중"

signal changed  # 진행·받은 기록·응답 대기가 바뀌었다(창·메뉴 빨간 점이 다시 그린다)

var save_path := "user://missions.json"  # ""이면 저장하지 않는다
var econ = null  # Economy
var gs = null  # GameState
var guild = null  # Guild
var net = null  # Net(온라인일 때만)
var defs: Array = DEFS  # 온라인: GET /v1/missions가 준 표
var day := -1  # 지금 리셋 날짜 번호
var week := -1
var counts := {"d": {}, "w": {}, "r": {}}  # d·w: 사건 → 오늘·이번 주 센 수, r: 반복 미션 id → 마지막으로 받은 뒤 센 수
var claimed := {"d": [], "w": [], "wd": 0, "r": {}}  # 오프라인 받은 기록(온라인은 Economy.server_missions)
var pending := {}  # 온라인: 보냈고 응답을 기다리는 받기(예측 키 → 미션 id) — 보상·받은 기록은 이미 곧바로 반영했다
var waiting: String:  # 응답을 기다리는 미션 id(없으면 "")
	get:
		return "" if pending.is_empty() else str(pending.values()[0])

var _dirty := false
var _save_cd := 0.0
var _fetched := false


func _ready() -> void:
	econ = get_node_or_null("/root/Economy")
	gs = get_node_or_null("/root/GameState")
	guild = get_node_or_null("/root/Guild")
	var n = get_node_or_null("/root/Net")
	if n != null and n.is_online():
		net = n
	if not OS.get_cmdline_user_args().is_empty():
		save_path = ""  # 개발 플래그 실행·체크 장면: 실제 저장을 건드리지 않는다
	_connect()
	load_save()
	roll()


func _connect() -> void:
	if econ != null:
		econ.collected.connect(func(_b, _r, _a): note("collect"))
		econ.sold.connect(func(_g): note("sell"))
		econ.killed.connect(func(_k): note("kill"))
		econ.gacha_done.connect(func(results): if results.size() > 0: note("gacha", results.size()))
		econ.building_done.connect(func(_id, _lv): note("build_up"))
		econ.dungeon_finished.connect(func(r): if r.get("win", false) and not r.get("repeated", false): note("dungeon_win"))
		econ.acted.connect(func(kind, n): note(kind, n))
		econ.changed.connect(_on_econ_changed)
	if gs != null:
		gs.stage_cleared.connect(func(_s): note("stage"))
	if guild != null:
		guild.acted.connect(func(kind): note(kind))
		guild.boss_done.connect(func(r): if not r.has("error"): note("guild_boss"))


func _process(delta: float) -> void:
	_save_cd -= delta
	if _save_cd <= 0.0:
		_save_cd = 2.0
		roll()
		if _dirty:
			save()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		save()


func _on_econ_changed() -> void:
	if net != null and not _fetched and net.up:
		fetch()


## 온라인: 서버 미션 표를 받는다(한 번). 진행(받은 기록)은 /v1/player 응답마다 Economy.server_missions로 온다.
func fetch() -> void:
	if net == null or not net.up:
		return
	_fetched = true
	net.send("GET", "/v1/missions", null, func(d):
		if d.get("defs") is Array and not d.defs.is_empty():
			defs = d.defs
		if d.get("missions") is Dictionary:
			econ.server_missions = d.missions
		changed.emit(), func(): _fetched = false)


func now_t() -> float:
	return econ.time_now() if econ != null else Time.get_unix_time_from_system()


static func day_of(t: float, hour: int) -> int:
	return floori((t - hour * 3600.0) / 86400.0)


static func week_of(d: int) -> int:
	return floori((d + 4) / 7.0)


func _hour() -> int:
	return int(GameData.config_num("daily_reset_utc_hour"))


## 다음 일일·주간 리셋 시각(유닉스 초, 보정 시각).
func next_day_at() -> float:
	return (day + 1) * 86400.0 + _hour() * 3600.0


func next_week_at() -> float:
	return ((week + 1) * 7 - 4) * 86400.0 + _hour() * 3600.0


## 날·주가 바뀌었으면 그 진행·받은 기록을 비운다.
func roll() -> void:
	var d := day_of(now_t(), _hour())
	if d == day:
		return
	var w := week_of(d)
	counts.d = {}
	claimed.d = []
	if w != week:
		counts.w = {}
		claimed.w = []
		claimed.wd = 0
	day = d
	week = w
	_dirty = true
	changed.emit()


## 사건 알림: 오늘·이번 주 그 사건 수, 그 사건을 세는 반복 미션 수에 더한다.
func note(kind: String, n := 1) -> void:
	if n <= 0:
		return
	roll()
	counts.d[kind] = int(counts.d.get(kind, 0)) + n
	counts.w[kind] = int(counts.w.get(kind, 0)) + n
	for m in defs:
		if m.type == "repeat" and m.kind == kind:
			counts.r[m.id] = int(counts.r.get(m.id, 0)) + n
	_dirty = true
	changed.emit()


## 받은 기록 {d, w, wd, r}: 온라인은 서버 값(서버의 날·주가 지난 것이면 그만큼 비운 값), 오프라인은 저장.
func record() -> Dictionary:
	if net == null:
		return claimed
	var s: Dictionary = econ.server_missions if econ != null else {}
	var same_day := int(s.get("day", -1)) == day
	var same_week := int(s.get("week", -1)) == week
	return {"d": s.get("d", []) if same_day else [], "w": s.get("w", []) if same_week else [], "wd": int(s.get("wd", 0)) if same_week else 0,
		"r": s.get("r", {}) if s.get("r") is Dictionary else {}}


func list(type: String) -> Array:
	return defs.filter(func(m): return m.type == type)


func find(id: String) -> Dictionary:
	for m in defs:
		if m.id == id:
			return m
	return {}


## 반복 미션 받은 횟수.
func times(id: String) -> int:
	return int(record().r.get(id, 0))


func target(m: Dictionary) -> int:
	return int(m.target) + int(m.get("step", 0)) * times(m.id) if m.type == "repeat" else int(m.target)


func title(m: Dictionary) -> String:
	var t := str(m.title)
	return t % target(m) if "%d" in t else t


func progress(m: Dictionary) -> int:
	var rec := record()
	match str(m.kind):
		"daily_count":
			var n := 0
			for id in rec.d:
				if find(str(id)).get("kind", "") != "daily_count":
					n += 1
			return n
		"daily_bonus":
			return int(rec.wd)
	var sc = _server_counts()
	if sc != null:  # 온라인: 서버가 센 진행(보상 받기도 이것으로 판정한다) + 아직 안 보낸 처치
		var unsent := _unsent_kills() if m.kind == "kill" else 0
		if m.type == "repeat":
			return int(sc.get("r", {}).get(m.id, 0)) + unsent
		return int(sc.get("d" if m.type == "daily" else "w", {}).get(m.kind, 0)) + unsent
	if m.type == "repeat":
		return int(counts.r.get(m.id, 0))
	return int(counts["d" if m.type == "daily" else "w"].get(m.kind, 0))


## 온라인 서버 진행 {d, w, r}(그날·그 주 것일 때만), 없으면 null.
func _server_counts():
	if net == null or econ == null:
		return null
	var s: Dictionary = econ.server_missions
	var c = s.get("c")
	if not c is Dictionary or int(s.get("day", -1)) != day:
		return null
	return c


## 아직 서버에 보내지 않은(또는 응답 전) 처치 수.
func _unsent_kills() -> int:
	var n := 0
	for part in [econ.kills_pending, econ.kills_sent]:
		for st in part:
			for k in part[st]:
				n += int(part[st][k])
	return n


func is_claimed(m: Dictionary) -> bool:
	var rec := record()
	if m.type == "daily":
		return str(m.id) in rec.d
	if m.type == "weekly":
		return str(m.id) in rec.w
	return false


func can_claim(m: Dictionary) -> bool:
	return not is_claimed(m) and progress(m) >= target(m)


## 받을 수 있는 미션 수(전체 또는 한 종류) — 메뉴·탭 빨간 점.
func ready_count(type := "") -> int:
	var n := 0
	for m in defs:
		if (type == "" or m.type == type) and can_claim(m):
			n += 1
	return n


func goto_of(m: Dictionary) -> String:
	return GOTO.get(str(m.kind), "")


## 보상 받기. 온라인도 곧바로 보상과 받은 기록을 반영하고(Economy.predict_reward) 서버에 보낸다(once) — 응답이 오면 서버 값으로,
## 거절되면 되돌리고 알린다. 응답을 기다리지 않으니 여러 개를 연달아 받을 수 있다(서버는 보낸 순서대로 확인한다). 보냈거나 받았으면 true.
func claim(id: String) -> bool:
	var m := find(id)
	if m.is_empty() or not can_claim(m):
		return false
	if net != null:
		if not net.up:
			econ.notice.emit(WAIT_TEXT)
			return false
		var body := {"id": id}
		if m.type == "repeat":
			body.n = times(id)
		var need := target(m)
		var key := "mission:%s:%d" % [id, times(id)]
		pending[key] = id
		econ.predict_reward(key, m.reward, _mark_claimed.bind(m))
		if m.type == "repeat":
			counts.r[id] = maxi(0, int(counts.r.get(id, 0)) - need)
			save()
		econ.granted.emit(m.reward)
		_reward_notice(m.reward)
		net.flush_kills()
		net.send("POST", "/v1/mission/claim", body, _on_claimed.bind(key), _on_claim_failed.bind(key, m, need), true, true)
		changed.emit()
		return true
	var need := target(m)
	if m.type == "daily":
		claimed.d.append(id)
		if m.kind == "daily_count":
			claimed.wd = int(claimed.wd) + 1
	elif m.type == "weekly":
		claimed.w.append(id)
	else:
		claimed.r[id] = times(id) + 1
		counts.r[id] = maxi(0, int(counts.r.get(id, 0)) - need)
	econ.grant(m.reward)
	_reward_notice(m.reward)
	save()
	changed.emit()
	return true


## 온라인 받은 기록(Economy.server_missions)에 이 받기를 더한다 — 서버 응답 위에도 응답이 올 때까지 다시 얹힌다(복사해서 바꾼다).
func _mark_claimed(m: Dictionary) -> void:
	var s: Dictionary = econ.server_missions.duplicate(true)
	if int(s.get("day", -1)) != day:
		s.day = day
		s.d = []
	if int(s.get("week", -1)) != week:
		s.week = week
		s.w = []
		s.wd = 0
	if not s.get("d") is Array:
		s.d = []
	if not s.get("w") is Array:
		s.w = []
	if not s.get("r") is Dictionary:
		s.r = {}
	if m.type == "daily":
		s.d.append(str(m.id))
		if m.kind == "daily_count":
			s.wd = int(s.get("wd", 0)) + 1
	elif m.type == "weekly":
		s.w.append(str(m.id))
	else:
		var done := int(s.r.get(str(m.id), 0))
		s.r[str(m.id)] = done + 1
		if s.get("c") is Dictionary and s.c.get("r") is Dictionary:  # 서버 진행에서도 이번 목표만큼 쓴다(응답 전 다시 받을 수 있어 보이지 않게)
			var need := int(m.target) + int(m.get("step", 0)) * done
			s.c.r[str(m.id)] = maxi(0, int(s.c.r.get(str(m.id), 0)) - need)
	econ.server_missions = s


func _on_claimed(data: Dictionary, key: String) -> void:
	pending.erase(key)
	econ.settle(key)
	econ.apply_server(data)
	changed.emit()


## 서버가 거절했거나 응답을 잃었다: 보상·받은 기록을 되돌리고(반복 미션은 센 수도) 알린 뒤 상태를 새로 받는다.
func _on_claim_failed(key: String, m: Dictionary, need: int) -> void:
	pending.erase(key)
	econ.unpredict(key)
	if m.type == "repeat":
		counts.r[m.id] = int(counts.r.get(m.id, 0)) + need
		save()
	econ.notice.emit(FAIL_TEXT.get(net.last_error, FAIL_DEFAULT))
	net.refresh()
	changed.emit()


func _reward_notice(r: Dictionary) -> void:
	if econ != null:
		econ.notice.emit("미션 보상: " + reward_text(r))


static func reward_text(r: Dictionary) -> String:
	var parts: Array = []
	if r.has("gold"):
		parts.append("골드 %s" % _commas(int(r.gold)))
	if r.has("diamonds"):
		parts.append("다이아 %s" % _commas(int(r.diamonds)))
	if r.has("wood") and int(r.get("wood", 0)) == int(r.get("stone", -1)) and int(r.wood) == int(r.get("food", -1)):
		parts.append("목재·석재·식량 각 %s" % _commas(int(r.wood)))
	else:
		for k in [["wood", "목재"], ["stone", "석재"], ["food", "식량"]]:
			if r.has(k[0]):
				parts.append("%s %s" % [k[1], _commas(int(r[k[0]]))])
	for k in [["keys_gold", "골드 던전 입장권"], ["keys_equip", "장비 던전 입장권"], ["keys_ticket", "모집권 던전 입장권"]]:
		if r.has(k[0]):
			parts.append("%s %d" % [k[1], int(r[k[0]])])
	if r.has("tickets"):
		parts.append("다이아 모집권 %d장" % int(r.tickets))
	var pz := EconomyScript.pouches_in(r)
	for id in EconomyScript.pouch_ids():
		if pz.has(id):
			parts.append(EconomyScript.pouch_name(id) + ("" if int(pz[id]) == 1 else " %d개" % int(pz[id])))
	return " + ".join(parts)


static func _commas(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


func save() -> void:
	_dirty = false
	if save_path == "":
		return
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"version": SAVE_VERSION, "day": day, "week": week, "counts": counts, "claimed": claimed}))


func load_save() -> bool:
	if save_path == "" or not FileAccess.file_exists(save_path):
		return false
	var d = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if not d is Dictionary or int(d.get("version", 0)) != SAVE_VERSION:
		return false
	day = int(d.get("day", -1))
	week = int(d.get("week", -1))
	var c = d.get("counts")
	if c is Dictionary:
		for k in ["d", "w", "r"]:
			if c.get(k) is Dictionary:
				counts[k] = _ints(c[k])
	var cl = d.get("claimed")
	if cl is Dictionary:
		claimed.d = cl.get("d", []) if cl.get("d") is Array else []
		claimed.w = cl.get("w", []) if cl.get("w") is Array else []
		claimed.wd = int(cl.get("wd", 0))
		claimed.r = _ints(cl.get("r", {})) if cl.get("r") is Dictionary else {}
	return true


static func _ints(src: Dictionary) -> Dictionary:
	var out := {}
	for k in src:
		out[str(k)] = int(src[k])
	return out
