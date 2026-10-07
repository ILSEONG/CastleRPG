extends Node
## PVP 상태(사용자 2026-10-07). 오토로드 Pvp. 규칙·수치는 pvp_rules.gd(서버 server/src/pvp.ts와 같다).
## 모드 둘: 결투(duel — 영웅 5 대 5, 내 영웅 조종, 상대 AI) · 총력전(total — 영웅 5 + 병사, 양쪽 AI). 모드마다 하루 5판·포인트·등급·방어팀.
## 상대는 미리 정해 둔다(view.modes[모드].next — 다른 플레이어의 방어팀, 없으면 내 힘에 맞춘 봇). 페이지에 상대를 보여 주고 [전투 시작]을 누르면
## 곧바로 그 상대와 싸운다(battle_started → main이 pvp_battle.gd를 연다).
##
## 기다림 없이(사용자 규칙 — 버튼이 "..."가 되지 않는다): 시작·방어팀·상점은 앱 값을 먼저 바꾸고 서버 확인은 뒤에서 받는다. 서버가 거절하면
## 되돌리고 짧은 알림(전투는 나간다). 결과도 앱이 먼저 계산해 보여 주고 서버 값이 오면 맞춘다.
## 온라인(econ.net != null, 내보낸 APK): 서버 /v1/pvp*가 진실. 오프라인(개발·테스트): 같은 모양의 값을 user://pvp.json으로 계산한다.

const GameData := preload("res://scripts/game_data.gd")
const PvpRules := preload("res://scripts/pvp_rules.gd")
const GuildWarScript := preload("res://scripts/guild_war.gd")

const SAVE_VERSION := 1
const ERROR_TEXT := {"no_plays": "오늘 도전 횟수를 다 썼습니다", "bad_heroes": "보유한 영웅 5명을 고르세요", "sold_out": "오늘(이번 주) 구매 한도를 채웠습니다",
	"not_enough_coins": "PVP 코인이 부족합니다", "bag_full": "보관함이 가득 찼습니다", "no_heroes": "조각을 받을 영웅이 없습니다", "conflict": "잠시 뒤 다시 시도하세요"}
const BOT_NICK_A := ["졸린", "용감한", "배고픈", "빠른", "느긋한", "씩씩한", "조용한", "화난", "행복한", "수상한", "귀여운", "우직한"]
const BOT_NICK_B := ["감자", "고양이", "기사", "궁수", "곰", "여우", "도토리", "망치", "방패", "늑대", "토끼", "마법사"]

signal changed
signal battle_started(run: Dictionary)  # {mode, opponent, me, soldiers, my_soldiers, time, gain, loss, online} — main이 pvp_battle.gd를 연다
signal battle_confirmed(id: String)  # 서버가 판을 열었다(결과를 보낼 수 있다)
signal battle_refused(text: String)  # 서버가 시작을 거절 — 전투 장면이 알림과 함께 나간다
signal result_ready(result: Dictionary)  # 서버(또는 오프라인)가 결과를 정했다 {win, delta, coins}

var view := {}  # 서버 pvp 응답과 같은 모양 {coins, next_reset, my_soldiers, shop: [...], modes: {duel, total}}. 비면 아직 모름
var save_path := "user://pvp.json"
var fixed_now := -1.0
var econ
var local := {}  # 오프라인 {modes: {m: {points, wins, losses, day, plays, defense: [team rows], soldiers, power, next}}, coins, shop: {day, week, bought}}
var battle := {}  # 진행 중인 판 {mode, id(서버 확인 전 ""), finished(보낼 결과, 확인 전이면 기다린다), gain, loss}

var _fetched_at := -INF
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	econ = get_node_or_null("/root/Economy")
	_rng.randomize()
	load_save()


func online() -> bool:
	return econ != null and econ.net != null


func now_t() -> float:
	if fixed_now >= 0.0:
		return fixed_now
	return econ.time_now() if econ != null else Time.get_unix_time_from_system()


func mode_view(mode: String) -> Dictionary:
	return view.get("modes", {}).get(mode, {})


func coins() -> int:
	return int(view.get("coins", 0))


func plays_left(mode: String) -> int:
	return int(mode_view(mode).get("plays_left", PvpRules.PLAYS))


func points(mode: String) -> int:
	return int(mode_view(mode).get("points", 0))


func opponent(mode: String) -> Dictionary:
	var o = mode_view(mode).get("next")
	return o if o is Dictionary else {}


## 방어팀 영웅 id(없으면 []).
func defense(mode: String) -> Array:
	return mode_view(mode).get("defense", [])


# --- 내 영웅 ---

## 보유 영웅(전투력 높은 순) id.
func owned_heroes() -> Array:
	if econ == null:
		return []
	var ids: Array = econ.heroes.keys().filter(func(id): return int(econ.heroes[id]) >= 1 and not GameData.hero(str(id)).is_empty())
	ids.sort_custom(func(a, b): return hero_power(a) > hero_power(b))
	return ids


func hero_power(id: String) -> int:
	if econ == null:
		return 0
	return GameData.hero_power(GameData.hero(id), econ.level_of(id), econ.promotion_of(id))


## 전투 능력치(성장·연구·장비·길드 버프 포함) {id, hp, atk} — 길드전과 같은 식.
func hero_entry(id: String) -> Dictionary:
	return GuildWar.hero_entry(id) if has_node("/root/GuildWar") else {"id": id, "hp": 0.0, "atk": 0.0}


## 기본 팀: 방어팀이 다 보유 중이면 그 팀, 아니면 전투력 높은 5명.
func default_team(mode: String) -> Array:
	var d := defense(mode)
	if d.size() == PvpRules.TEAM and d.all(func(id): return econ != null and int(econ.heroes.get(id, 0)) >= 1):
		return d.duplicate()
	return owned_heroes().slice(0, PvpRules.TEAM)


func my_soldiers() -> Dictionary:
	return PvpRules.pick_soldiers(econ.soldiers if econ != null else {})


func team_power(ids: Array) -> int:
	var n := 0
	for id in ids:
		n += hero_power(id)
	return n


# --- 막힘 ---

## [전투 시작]이 안 되는 이유(되면 "").
func start_block(mode: String, ids: Array) -> String:
	if view.is_empty():
		return "PVP 정보를 불러오는 중입니다"
	if plays_left(mode) <= 0:
		return ERROR_TEXT.no_plays
	if opponent(mode).is_empty():
		return "상대를 찾는 중입니다"
	if ids.size() != PvpRules.TEAM:
		return "영웅 %d명을 고르세요" % PvpRules.TEAM
	if not battle.is_empty() and not battle.get("done", false):
		return "진행 중인 전투가 있습니다"
	return ""


func buy_block(id: String) -> String:
	var it := shop_item(id)
	if it.is_empty():
		return "없는 상품입니다"
	if int(it.get("bought", 0)) >= int(it.limit):
		return ERROR_TEXT.sold_out
	if coins() < int(it.price):
		return ERROR_TEXT.not_enough_coins
	if it.give.has("equip") and econ != null and econ.bag.size() + int(it.give.equip) > int(GameData.config_num("equip_bag_cap")):
		return ERROR_TEXT.bag_full
	return ""


func shop_item(id: String) -> Dictionary:
	for it in view.get("shop", []):
		if str(it.id) == id:
			return it
	return {}


# --- 동작 ---

func fetch() -> void:
	_fetched_at = Time.get_ticks_msec() / 1000.0
	if online():
		if econ.net.up:
			econ.net.send("GET", "/v1/pvp", null, func(d): _take(d), Callable())
		return
	view = local_view(now_t())
	changed.emit()


func fetch_if_stale(sec := 20.0) -> void:
	if view.is_empty() or Time.get_ticks_msec() / 1000.0 - _fetched_at >= sec:
		fetch()


## 방어팀 저장: 화면은 곧바로 바뀌고 서버 확인은 뒤에서(거절되면 되돌리고 알림).
func set_defense(mode: String, ids: Array) -> bool:
	if ids.size() != PvpRules.TEAM:
		_notice("방어 영웅 %d명을 고르세요" % PvpRules.TEAM)
		return false
	var mv := mode_view(mode)
	var before = mv.duplicate(true)
	mv.defense = ids.duplicate()
	mv.power = team_power(ids)
	if mode == "total":
		mv.soldiers = my_soldiers()
	changed.emit()
	_notice("방어팀을 저장했습니다")
	if online():
		econ.net.send("POST", "/v1/pvp/defense", {"mode": mode, "heroes": ids.map(func(id): return hero_entry(id))}, func(d): _take(d), func():
			view.modes[mode] = before
			changed.emit()
			_notice(ERROR_TEXT.get(econ.net.last_error, "방어팀을 저장하지 못했습니다")), true, true)
		return true
	var lm: Dictionary = local.modes[mode]
	lm.defense = ids.map(func(id): return _team_row(id))
	lm.soldiers = mv.get("soldiers", {})
	lm.power = mv.power
	save()
	return true


## [전투 시작]: 판 하나를 쓰고 보여 준 상대와 곧바로 싸운다. 서버 확인은 뒤에서(battle_confirmed) — 거절되면 battle_refused.
func start(mode: String, ids: Array) -> bool:
	var why := start_block(mode, ids)
	if why != "":
		_notice(why)
		return false
	var mv := mode_view(mode)
	var opp: Dictionary = opponent(mode).duplicate(true)
	var me_pts := int(mv.get("points", 0))
	var loss := PvpRules.loss_of(me_pts)
	var gain := PvpRules.win_gain(me_pts, int(opp.get("points", 0)))
	var before := view.duplicate(true)
	# 앱 값 먼저: 판 −1, 패배로 먼저 적기(서버와 같다), 방어팀이 없으면 이 팀
	mv.plays_left = maxi(0, int(mv.get("plays_left", PvpRules.PLAYS)) - 1)
	mv.points = me_pts - loss
	mv.tier = PvpRules.tier_of(int(mv.points))
	mv.losses = int(mv.get("losses", 0)) + 1
	view.coins = coins() + PvpRules.COINS_LOSS
	if defense(mode).is_empty():
		mv.defense = ids.duplicate()
	var entries: Array = ids.map(func(id): return hero_entry(id))
	var soldiers := my_soldiers() if mode == "total" else {}
	battle = {"mode": mode, "id": "", "gain": gain, "loss": loss, "done": false, "pending": null}
	changed.emit()
	var run := {"mode": mode, "opponent": opp, "me": ids.duplicate(), "my_soldiers": soldiers, "time": float(PvpRules.BATTLE_SEC[mode]),
		"gain": gain, "loss": loss, "online": online()}
	if online():
		econ.net.flush_kills()
		econ.net.send("POST", "/v1/pvp/start", {"mode": mode, "heroes": entries}, func(d):
			_take(d)
			var b = d.get("battle")
			if b is Dictionary and battle.get("mode", "") == mode and str(battle.get("id", "")) == "":
				battle.id = str(b.id)
				battle.gain = int(b.get("gain", gain))
				battle.loss = int(b.get("loss", loss))
				battle_confirmed.emit(battle.id)
				if battle.pending != null:  # 시작 확인보다 결과가 먼저 났다: 서버 시계는 지금부터라 너무 이른 승리로 거절되지 않게 기다렸다 보낸다
					var w: bool = battle.pending
					var bid := str(battle.id)
					var wait := (PvpRules.MIN_WIN_SEC / 1.5 + 0.6) if w else 0.0
					if wait <= 0.0:
						_send_finish(w)
					else:
						(Engine.get_main_loop() as SceneTree).create_timer(wait, true, false, true).timeout.connect(func(): _send_finish(w, bid)), func():
			var t: String = ERROR_TEXT.get(econ.net.last_error, "전투를 시작하지 못했습니다")
			view = before
			battle = {}
			changed.emit()
			battle_refused.emit(t)
			fetch(), true, true)
	else:
		battle.id = local_start(mode, ids, now_t())
	battle_started.emit.call_deferred(run)
	return true


## 전투가 끝났다(전투 장면): 앱이 먼저 결과를 계산해 화면에 보이고 서버(오프라인)에 보낸다. 반환 = 화면용 결과 {win, delta, coins}.
func finish(win: bool, elapsed: float) -> Dictionary:
	if battle.is_empty() or battle.get("done", false):
		return {}
	battle.done = true
	var ok := win and elapsed >= PvpRules.MIN_WIN_SEC
	var res := {"win": ok, "delta": int(battle.gain) if ok else -int(battle.loss), "coins": PvpRules.COINS_WIN if ok else PvpRules.COINS_LOSS}
	if ok:
		var mv := mode_view(str(battle.mode))
		mv.points = int(mv.get("points", 0)) + int(battle.loss) + int(battle.gain)
		mv.tier = PvpRules.tier_of(int(mv.points))
		mv.wins = int(mv.get("wins", 0)) + 1
		mv.losses = maxi(0, int(mv.get("losses", 0)) - 1)
		view.coins = coins() + PvpRules.COINS_WIN - PvpRules.COINS_LOSS
		changed.emit()
	if online():
		if str(battle.id) == "":
			battle.pending = ok  # 시작 확인이 오면 보낸다
		else:
			_send_finish(ok)
	else:
		local_finish(str(battle.mode), str(battle.id), ok)
		result_ready.emit.call_deferred(res)
	return res


func _send_finish(win: bool, bid: String = "") -> void:
	econ.net.send("POST", "/v1/pvp/finish", {"battle_id": bid if bid != "" else str(battle.id), "win": win}, func(d):
		_take(d)
		var r = d.get("result")
		if r is Dictionary:
			if win and not r.get("win", false):
				_notice("전투 결과를 확인하지 못해 패배로 기록되었습니다")
			result_ready.emit(r), func(): fetch(), true, true)


## 상점 구매: 코인·구매 수는 곧바로, 보상은 서버 응답과 함께(거절되면 되돌리고 알림).
func buy(id: String) -> String:
	var why := buy_block(id)
	if why != "":
		_notice(why)
		return why
	var it := shop_item(id)
	var before := view.duplicate(true)
	it.bought = int(it.get("bought", 0)) + 1
	view.coins = coins() - int(it.price)
	changed.emit()
	if online():
		econ.net.send("POST", "/v1/pvp/buy", {"id": id}, func(d):
			econ.apply_server(d)
			_take(d)
			_notice("%s 구매 완료" % PvpRules.SHOP_NAMES.get(id, id)), func():
			view = before
			changed.emit()
			_notice(ERROR_TEXT.get(econ.net.last_error, "구매하지 못했습니다")), true, true)
		return ""
	local_buy(id, now_t())
	_notice("%s 구매 완료" % PvpRules.SHOP_NAMES.get(id, id))
	return ""


func _take(d) -> void:
	if d is Dictionary and d.get("pvp") is Dictionary:
		view = d.pvp
		changed.emit()


func _notice(t: String) -> void:
	if econ != null:
		econ.notice.emit(t)


# --- 오프라인(서버 pvp.ts·pvp_routes.ts와 같은 식, 상대는 늘 봇) ---

func load_save() -> void:
	local = {}
	if save_path != "" and FileAccess.file_exists(save_path):
		var d = JSON.parse_string(FileAccess.get_file_as_string(save_path))
		if d is Dictionary and int(d.get("version", 0)) == SAVE_VERSION:
			local = d
	if not local.has("modes"):
		local = {"version": SAVE_VERSION, "modes": {}, "coins": 0, "shop": {}}
	for m in PvpRules.MODES:
		if not local.modes.has(m):
			local.modes[m] = {"points": 0, "wins": 0, "losses": 0, "day": 0, "plays": 0, "defense": [], "soldiers": {}, "power": 0, "next": null}


func save() -> void:
	if save_path == "":
		return
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(local))


func _team_row(id: String) -> Dictionary:
	var e := hero_entry(id)
	return {"hero": id, "level": econ.level_of(id), "promotion": econ.promotion_of(id), "hp": e.hp, "atk": e.atk}


func _week(day: int) -> int:
	return GuildWarScript.week_of(day)


func _shop_today(now: float) -> Dictionary:
	var day := GameData.reset_day(now)
	var s: Dictionary = local.get("shop", {})
	var bought := {}
	for it in PvpRules.SHOP:
		var keep: bool = int(s.get("day", -1)) == day if it.period == "day" else int(s.get("week", -1)) == _week(day)
		if keep and int(s.get("bought", {}).get(it.id, 0)) > 0:
			bought[it.id] = int(s.bought[it.id])
	return {"day": day, "week": _week(day), "bought": bought}


## 봇 방어팀(서버 botTeam과 같은 모양): 기준 팀(방어팀, 없으면 전투력 높은 5명)의 영웅마다 같은 등급(되면 같은 역할)의 다른 영웅을
## 그 전투력 × BOT_POWER에 맞춘다 — 전투력 식의 등급 배율 때문에 등급이 섞이면 같은 전투력이라도 봇이 훨씬 세다.
func make_bot(mode: String, base: Array, pts: int) -> Dictionary:
	var pool: Array = GameData.heroes().duplicate()
	pool.sort_custom(func(a, b): return str(a.id) < str(b.id))
	var picks := []
	var take := func(list: Array) -> bool:
		var left := list.filter(func(h): return not picks.has(h))
		if left.is_empty():
			return false
		picks.append(left[_rng.randi_range(0, left.size() - 1)])
		return true
	var scale := _rng.randf_range(PvpRules.BOT_POWER[0], PvpRules.BOT_POWER[1])
	var targets := []
	for i in PvpRules.TEAM:
		if picks.size() >= pool.size():
			break
		if i < base.size():
			var b: Dictionary = base[i]
			if not take.call(pool.filter(func(h): return h.grade == b.grade and h.role == b.role)):
				if not take.call(pool.filter(func(h): return h.grade == b.grade)):
					take.call(pool)
			targets.append(maxf(PvpRules.MIN_POWER / float(PvpRules.TEAM), float(b.power)) * scale)
		else:
			take.call(pool)
			targets.append(PvpRules.MIN_POWER / float(PvpRules.TEAM) * scale)
	var heroes := []
	var total := 0
	for i in picks.size():
		var d: Dictionary = picks[i]
		var f := GuildWarScript.fit_hero(d, targets[i])
		var s := GameData.hero_stats(d, int(f.level), int(f.promotion), {})
		heroes.append({"hero": d.id, "level": f.level, "promotion": f.promotion, "hp": roundf(s.hp), "atk": snappedf(s.atk, 0.1)})
		total += GameData.power_of(d, s.hp, s.atk)
	var soldiers := {}
	if mode == "total":
		var ids: Array = GameData.soldiers().map(func(x): return str(x.id))
		var mine := my_soldiers()
		for k in mine:
			var key := "%s:%s" % [ids[_rng.randi_range(0, ids.size() - 1)], str(k).get_slice(":", 1)]
			soldiers[key] = int(soldiers.get(key, 0)) + int(mine[k])
	var name: String = BOT_NICK_A[_rng.randi_range(0, BOT_NICK_A.size() - 1)] + BOT_NICK_B[_rng.randi_range(0, BOT_NICK_B.size() - 1)]
	return {"kind": "bot", "name": name, "points": maxi(0, pts + _rng.randi_range(-30, 30)), "tier": {}, "power": total, "heroes": heroes, "soldiers": soldiers}


## 봇의 기준 팀 [{grade, role, power}]: 방어팀, 없으면 전투력 높은 5명.
func _base_team(lm: Dictionary) -> Array:
	var out := []
	if not lm.defense.is_empty():
		for h in lm.defense:
			var d := GameData.hero(str(h.hero))
			if not d.is_empty():
				out.append({"grade": d.grade, "role": d.role, "power": GameData.power_of(d, float(h.hp), float(h.atk))})
		return out
	for id in owned_heroes().slice(0, PvpRules.TEAM):
		var d := GameData.hero(str(id))
		out.append({"grade": d.grade, "role": d.role, "power": hero_power(str(id))})
	return out


func local_view(now: float) -> Dictionary:
	var day := GameData.reset_day(now)
	var modes := {}
	for m in PvpRules.MODES:
		var lm: Dictionary = local.modes[m]
		if lm.get("next") == null:
			lm.next = make_bot(m, _base_team(lm), int(lm.points))
			save()
		var nx: Dictionary = lm.next.duplicate(true)
		nx.tier = PvpRules.tier_of(int(nx.points))
		var used: int = int(lm.plays) if int(lm.day) == day else 0
		modes[m] = {"points": int(lm.points), "tier": PvpRules.tier_of(int(lm.points)), "wins": int(lm.wins), "losses": int(lm.losses),
			"plays_left": maxi(0, PvpRules.PLAYS - used), "plays": PvpRules.PLAYS, "defense": lm.defense.map(func(h): return h.hero),
			"soldiers": lm.get("soldiers", {}), "power": int(lm.power), "next": nx, "time": PvpRules.BATTLE_SEC[m]}
	var shop := _shop_today(now)
	var items := []
	for it in PvpRules.SHOP:
		var row: Dictionary = it.duplicate(true)
		row.bought = int(shop.bought.get(it.id, 0))
		items.append(row)
	return {"coins": int(local.coins), "next_reset": GameData.next_reset(now), "my_soldiers": my_soldiers(), "shop": items, "modes": modes}


func local_start(mode: String, ids: Array, now: float) -> String:
	var lm: Dictionary = local.modes[mode]
	var day := GameData.reset_day(now)
	var used: int = int(lm.plays) if int(lm.day) == day else 0
	lm.day = day
	lm.plays = used + 1
	lm.points = int(lm.points) - PvpRules.loss_of(int(lm.points))
	lm.losses = int(lm.losses) + 1
	if lm.defense.is_empty():
		lm.defense = ids.map(func(id): return _team_row(id))
		lm.power = team_power(ids)
		lm.soldiers = my_soldiers() if mode == "total" else {}
	lm.next = make_bot(mode, _base_team(lm), int(lm.points))
	local.coins = int(local.coins) + PvpRules.COINS_LOSS
	save()
	var mv := mode_view(mode)
	mv.next = lm.next.duplicate(true)
	mv.next.tier = PvpRules.tier_of(int(mv.next.points))
	return "local-%d" % Time.get_ticks_msec()


func local_finish(mode: String, _id: String, win: bool) -> void:
	if not win:
		return
	var lm: Dictionary = local.modes[mode]
	lm.points = int(lm.points) + int(battle.loss) + int(battle.gain)
	lm.wins = int(lm.wins) + 1
	lm.losses = maxi(0, int(lm.losses) - 1)
	local.coins = int(local.coins) + PvpRules.COINS_WIN - PvpRules.COINS_LOSS
	save()


func local_buy(id: String, now: float) -> void:
	var it := {}
	for s in PvpRules.SHOP:
		if s.id == id:
			it = s
	var shop := _shop_today(now)
	shop.bought[id] = int(shop.bought.get(id, 0)) + 1
	local.shop = shop
	local.coins = int(local.coins) - int(it.price)
	save()
	if econ == null:
		return
	for k in it.give:
		var n := int(it.give[k])
		match k:
			"gold":
				econ.gold += n
			"diamonds":
				econ.diamonds += n
			"tickets":
				econ.dia_tickets += n
	econ.changed.emit()
	if econ.has_method("save"):
		econ.save()
