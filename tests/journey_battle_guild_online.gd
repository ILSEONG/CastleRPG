extends Node
## 온라인 통합 체크(길드·길드전, 2026-10-14 통합 테스트 — tests/guild_online.gd가 보는 가입·보스 한 판·창설 흐름은 되풀이하지 않고 나머지를 본다):
## 로컬 서버(메모리 PGlite, ALLOW_TEST_HOOKS=1, tutorial_new_players=0)에 게스트로 접속해 버튼이 부르는 같은 함수(Guild.attend·claim_box·donate·buy·
## start_boss, GuildWar.set_schedule·set_defense·enter·start_battle·claim)로 하나씩 해 보고, 동작마다 앱 값이 서버 GET /v1/guild·/v1/guild/war·/v1/player와 같은지 본다.
## 잠김(stage 10) → stage 11 → 추천 길드 가입 → 출석·출석 상자 → 기부 셋(골드·다이아·왕실) → 길드 상점 → 보스 두 판(더블 탭 한 판, 세 번째는 막힘) →
## 길드 회관 도움(건설 시간) → 탈퇴 → 창설 → 길드전: 공성 시각(길드장) · 수비 영웅 · 열리기 전 막힘 · /v1/test/war_now · 입장(1배속) · [전투 시작] ·
## 성문 3개 + 수비 2명 처치로 끝 → 점수(성문은 2개까지 10점씩) · 다음 주로 넘겨(/v1/test/war_last_week) 보상 받기.
## 실행: journey_battle_online.gd와 같다(포트 8803 예). 마지막 줄이 JOURNEY GUILD ONLINE PASSED(실패면 종료 코드 1).

const WarRules := preload("res://scripts/war_rules.gd")
const WarBattleScript := preload("res://scripts/war_battle.gd")
const GuildBossScript := preload("res://scripts/guild_boss.gd")
const SpeedButton := preload("res://scripts/speed_button.gd")
const Prefs := preload("res://scripts/prefs.gd")
const HEROES := ["arteon", "ignis", "selene", "valen", "kyle", "mira"]
const GOLD_SLACK := 300

var _main
var _panel
var _shots: Array = []
var _fails := 0
var _resp_done := false
var _resp = null
var _notes: Array = []
var _boss = null


func _ready() -> void:
	Fever.save_path = ""
	Guild.save_path = ""
	GuildWar.save_path = ""
	get_window().size = Vector2i(360, 640)
	var device := Net.arg_value("device")
	_check(Net.is_online() and device != "", "online mode with --api and --device", Net.api_base)
	if _fails > 0:
		return _finish()
	Net.device_path = device
	Net.auth_path = device.get_base_dir().path_join("auth.json")
	DirAccess.remove_absolute(device)
	Net.set_auth("guest")
	_main = preload("res://scenes/main.tscn").instantiate()
	add_child(_main)
	_check(await _wait_until(func(): return Net.ready_once and _main.camera != null, 30.0), "world built after connecting", "")
	if _fails > 0:
		return _finish()
	Economy.notice.connect(func(s): _notes.append(s))
	Guild.notice.connect(func(s): _notes.append(s))
	Guild.boss_done.connect(func(r): _boss = r)
	_check(await _wait_until(func(): return Net.up, 15.0), "connected", "")
	for id in HEROES:
		await _request("/v1/test/grant_hero", {"hero_id": id})
	await _frames(10)
	for c in _main.get_children():
		if c.get_script() != null and c.get_script().resource_path == "res://scripts/side_menu.gd":
			_panel = c.windows.guild
			c.pick("guild")
	await _guild()
	await _war()
	Prefs.set_value(SpeedButton.PREF_KEY, 1.0)
	_sheet()
	_finish()


# --- 길드 ---

func _guild() -> void:
	print("--- guild")
	await _request("/v1/test/stage", {"stage": 10})
	Guild.fetch()
	_check(await _wait_until(func(): return not Guild.remote.is_empty(), 10.0) and not Guild.is_unlocked(), "stage 10: guild locked", str(Guild.remote.get("unlocked")))
	_check(Guild.join_block() != "", "join is blocked while locked", Guild.join_block())
	await _request("/v1/test/stage", {"stage": 11})
	Guild.fetch()
	_check(await _wait_until(func(): return Guild.is_unlocked(), 10.0), "stage 11 unlocks the guild", "")
	var recs: Array = Guild.recommendations()
	Guild.join(recs[0])
	Guild.join(recs[1])  # 더블 탭: 응답 전 두 번째는 막힌다
	_check(await _wait_until(func(): return Guild.joined() and not Guild.busy, 10.0) and str(Guild.guild.get("id", "")) == str(recs[0].id), "join the first recommended guild (second tap ignored)", str(Guild.guild.get("name")))
	await _compare_guild("after join")
	# 출석
	var g0 := Economy.gold
	Guild.attend()
	Guild.attend()
	_check(bool(Guild.me.attended) and Guild.coins == 30 and absi(Economy.gold - (g0 + 3000)) <= GOLD_SLACK, "attend: +3,000 gold, +30 coins at once (double tap once)", "coins %d gold %d→%d" % [Guild.coins, g0, Economy.gold])
	_check(await _wait_until(func(): return Guild._pending == 0, 10.0) and Guild.coins == 30 and not _notes.has("오늘은 이미 출석했습니다"), "server agrees on attendance", str(_notes))
	await _compare_guild("after attend")
	_check(Guild.attend_block() == "오늘은 이미 출석했습니다", "attend again: already attended", Guild.attend_block())
	# 출석 상자: 열린 것은 받고, 잠긴 것은 못 받는다
	var att := Guild.attend_count()
	for i in Guild.ATTEND_BOXES.size():
		var need: int = Guild.ATTEND_BOXES[i][0]
		var st := Guild.box_state(i)
		_check(st == ("ready" if att >= need else "locked"), "box %d (%d attendees, have %d): %s" % [i, need, att, st], st)
		if st == "ready":
			var c0 := Guild.coins
			var d0 := Economy.diamonds
			_check(Guild.claim_box(i) and Guild.box_state(i) == "claimed", "claim box %d" % i, "")
			var rw: Dictionary = Guild.ATTEND_BOXES[i][1]
			_check(Guild.coins == c0 + int(rw.coins) and Economy.diamonds == d0 + int(rw.get("diamonds", 0)), "box %d pays %s at once" % [i, rw], "")
			await _wait_until(func(): return Guild._pending == 0, 10.0)
			_check(not Guild.claim_box(i), "box %d can't be claimed twice" % i, "")
		else:
			_check(not Guild.claim_box(i), "locked box %d can't be claimed" % i, "")
	await _compare_guild("after boxes")
	# 기부 셋
	await _request("/v1/test/grant_gold", {"amount": 40000})
	await _request("/v1/test/grant_diamonds", {"amount": 250})
	for kind in Guild.DONATION_ORDER:
		var d: Dictionary = Guild.DONATIONS[kind]
		var c0 := Guild.coins
		var dia0 := Economy.diamonds
		var gold0 := Economy.gold
		_check(Guild.donate(kind), "%s donation sent" % kind, Guild.donate_block(kind))
		_check(Guild.coins == c0 + int(d.coins) and Economy.diamonds == dia0 - int(d.diamonds) and absi(Economy.gold - (gold0 - int(d.gold))) <= GOLD_SLACK
			and Guild.donations_left(kind) == int(d.daily) - 1, "%s: cost and +%d coins at once" % [kind, int(d.coins)], "coins %d dia %d gold %d" % [Guild.coins, Economy.diamonds, Economy.gold])
		await _wait_until(func(): return Guild._pending == 0, 10.0)
		_check(Guild.coins == c0 + int(d.coins) and Guild.donations_left(kind) == int(d.daily) - 1 and not _notes.has(Guild.ERROR_TEXT.get("donated", "-")), "%s: server agrees" % kind, str(Guild.me.donations))
		await _compare_guild("after %s donation" % kind)
	_check(Guild.donate_block("dia") == "오늘 기부 횟수를 다 썼습니다" and not Guild.donate("dia"), "dia donation: daily limit", Guild.donate_block("dia"))
	_check(Guild.donate_block("gold") == "골드가 부족합니다" or Economy.gold >= 10000, "gold donation needs 10,000 gold", Guild.donate_block("gold"))
	_panel.tab = "home"
	_panel._rebuild()
	await _snap()
	# 상점
	print("coins before shop: %d" % Guild.coins)
	var items0 := Economy.bag.size()
	for id in ["dia", "gold", "equip"]:
		var it: Dictionary = Guild.shop_item(id)
		var c0 := Guild.coins
		var dia0 := Economy.diamonds
		var gold0 := Economy.gold
		var left := Guild.shop_left(id)
		if c0 < int(it.price):
			_check(Guild.buy_block(id) == "길드 코인이 부족합니다", "%s: not enough coins" % id, Guild.buy_block(id))
			continue
		Guild.buy(id)
		_check(Guild.coins == c0 - int(it.price) and Guild.shop_left(id) == left - 1, "buy %s: −%d coins at once" % [id, int(it.price)], str(Guild.coins))
		await _wait_until(func(): return Guild._pending == 0, 10.0)
		var ok := true
		if id == "dia":
			ok = Economy.diamonds == dia0 + 50
		elif id == "gold":
			ok = absi(Economy.gold - (gold0 + 30000)) <= GOLD_SLACK
		else:
			ok = Economy.bag.size() == items0 + 1
		_check(ok, "%s reward arrives from the server" % id, "dia %d gold %d bag %d" % [Economy.diamonds, Economy.gold, Economy.bag.size()])
		await _compare_guild("after buying %s" % id)
	await _compare_items("after the guild shop")
	var c1 := Guild.coins
	Guild.buy("ssr")
	_check(Guild.coins == c1, "ssr (600 coins): refused without a change", str(Guild.coins))
	_panel.tab = "shop"
	_panel._rebuild()
	await _snap()
	# 보스 두 판(x2 배속 — 서버는 실제 경과 ≥ 40 ÷ 2 − 2초를 본다)
	Prefs.set_value(SpeedButton.PREF_KEY, 2.0)
	_check(Guild.team_dps() > 0.0 and Guild.boss_block() == "", "boss can start (deployed heroes)", Guild.boss_block())
	_panel.tab = "boss"
	_panel._rebuild()
	for n in 2:
		_boss = null
		var c0 := Guild.coins
		_panel._start_fight()
		_panel._start_fight()
		_check(int(Guild.me.boss_tries) == n + 1, "boss %d: one try used at once (double tap once)" % (n + 1), str(Guild.me.boss_tries))
		if not await _wait_until(func(): return _main._dungeon != null and _main._dungeon.get_script() == GuildBossScript, 10.0):
			_check(false, "boss fight opens", str(_notes))
			return
		var fight = _main._dungeon
		await _frames(5)
		_check(is_equal_approx(Engine.time_scale, 2.0), "boss fight runs at x2", str(Engine.time_scale))
		_check(await _wait_until(func(): return fight.phase == fight.Phase.RESULT, 60.0) and _boss != null and not _boss.has("error"), "boss %d: server result" % (n + 1), str(_boss))
		if _boss == null or _boss.has("error"):
			return
		var g = Guild.boss_grade(float(_boss.dmg))
		_check(str(_boss.grade) == str(g[0]) and int(_boss.coins) == int(g[2]) and Guild.coins == c0 + int(g[2]), "boss %d: grade %s, +%d coins (app table == server)" % [n + 1, _boss.grade, int(_boss.coins)], str(_boss))
		await _compare_guild("after boss %d" % (n + 1))
		await _snap()
		fight.leave()
		await _wait_until(func(): return _main._dungeon == null, 10.0)
		await _frames(10)
	_check(Guild.boss_block() == "오늘 도전 횟수를 다 썼습니다" and not Guild.start_boss(), "third boss try: no tries left", Guild.boss_block())
	Prefs.set_value(SpeedButton.PREF_KEY, 1.0)
	# 길드 회관 도움: 길드에 들어 있으면 건설 시간이 줄어든다 — 앱이 곧바로 보인 끝 시각 == 서버 끝 시각
	await _request("/v1/test/levels", {"levels": {"keep": 11, "guild_hall": 3, "lumber": 10}, "res": {"wood": 50000000, "stone": 50000000, "food": 50000000}})
	await _frames(30)  # 성채 단계가 바뀌면 main이 월드를 다시 만든다 — 새 main·길드 창을 다시 잡는다
	for c in get_children():
		if "_picker" in c and not c.is_queued_for_deletion():
			_main = c
	await _wait_until(func(): return is_instance_valid(_main) and _main.camera != null, 30.0)
	for c in _main.get_children():
		if c.get_script() != null and c.get_script().resource_path == "res://scripts/side_menu.gd":
			_panel = c.windows.guild
			c.pick("guild")
	await _frames(10)
	if Economy.building_level("guild_hall") >= 1:
		Economy.upgrade("lumber", Economy.time_now())
		var fin0 := float(Economy.build_job("lumber").get("finish", 0.0))
		_check(await _wait_until(func(): return not Economy._waiting.has("build"), 10.0), "lumber upgrade answered", "")
		var fin1 := float(Economy.build_job("lumber").get("finish", 0.0))
		_check(Economy.is_building("lumber") or Economy.building_level("lumber") == 4, "lumber upgrade started", str(_notes.slice(-3)))
		_check(fin0 > 0.0 and absf(fin0 - fin1) < 2.0, "guild hall help: predicted finish == server finish", "app %.0f vs server %.0f (Δ %.0f s)" % [fin0, fin1, fin0 - fin1])
	else:
		_check(false, "guild hall level set", str(Economy.building_level("guild_hall")))
	# 탈퇴 → 창설
	Guild.leave()
	_check(await _wait_until(func(): return not Guild.joined() and not Guild.busy, 10.0), "leave", "")
	await _compare_guild("after leave")
	await _request("/v1/test/grant_gold", {"amount": Guild.CREATE_GOLD})
	var gc := Economy.gold
	Guild.create("공성%d" % (randi() % 100000), 2)  # 이름은 서버 전체에서 하나 — 다시 돌려도 겹치지 않게
	_check(await _wait_until(func(): return Guild.joined() and not Guild.busy, 10.0) and bool(Guild.guild.get("mine", false)), "create a guild", str(Guild.guild.get("name")))
	_check(absi(Economy.gold - (gc - Guild.CREATE_GOLD)) <= GOLD_SLACK, "500,000 gold spent", "%d → %d" % [gc, Economy.gold])
	await _compare_guild("after create")


# --- 길드전 ---

func _war() -> void:
	print("--- guild war")
	GuildWar.fetch()
	_check(await _wait_until(func(): return not GuildWar.war.is_empty(), 10.0), "war view arrives", "")
	var w: Dictionary = GuildWar.war
	var squad: Array = GuildWar.default_squad()
	_check(w.battle.state == "waiting" and w.schedule.can_change and w.schedule.leader, "this week's siege waits; the guild master can set the time", str(w.schedule))
	_check(GuildWar.enter_block(squad).begins_with("공성 시각"), "enter before the time: blocked", GuildWar.enter_block(squad))
	_panel.tab = "war"
	_panel._rebuild()
	await _snap()
	# 공성 시각
	_check(GuildWar.schedule_block(0, 0) == GuildWar.ERROR_TEXT.schedule_past, "a past time is refused", GuildWar.schedule_block(0, 0))
	var at := GuildWar.pick_at(int(w.week), 6, 20)
	_check(GuildWar.set_schedule(6, 20) and is_equal_approx(float(GuildWar.war.schedule.at), at), "set sunday 20:00: shows at once", GuildWar.at_text(float(GuildWar.war.schedule.at)))
	_check(not GuildWar.set_schedule(6, 21), "second tap while waiting is ignored", "")
	await _wait_until(func(): return not GuildWar.busy, 10.0)
	var sv = await _http_get("/v1/guild/war")
	_check(is_equal_approx(float(sv.war.schedule.at), at) and is_equal_approx(float(GuildWar.war.schedule.at), at) and sv.war.schedule.set, "server keeps sunday 20:00", str(sv.war.schedule))
	# 수비 영웅
	var def_ids: Array = squad.duplicate()
	GuildWar.set_defense(def_ids)
	_check(GuildWar.defense() == def_ids, "defense heroes show at once", str(GuildWar.defense()))
	await _wait_until(func(): return not GuildWar.busy, 10.0)
	sv = await _http_get("/v1/guild/war")
	_check(sv.war.defense == def_ids and GuildWar.defense() == def_ids, "server keeps the defense heroes", str(sv.war.defense))
	var mine_row: Array = sv.war.members.filter(func(m): return m.mine)
	_check(mine_row.size() == 1 and mine_row[0].defense == def_ids, "my member row lists the defense", str(mine_row))
	GuildWar.set_defense(def_ids.slice(0, 3))
	_check(_notes.has("수비 영웅 %d명을 고르세요" % WarRules.SQUAD), "3 heroes: refused", "")
	# 지금 열기 → 입장(배속 x2로 둬도 길드전은 1배)
	_request_war_sync("/v1/test/war_now")
	await _wait_until(func(): return GuildWar.war.get("battle", {}).get("state", "") == "live", 10.0)
	_check(GuildWar.war.battle.state == "live" and GuildWar.enter_block(squad) == "", "war_now: the siege is live, enter is allowed", str(GuildWar.war.battle))
	Prefs.set_value(SpeedButton.PREF_KEY, 2.0)
	GuildWar.enter(squad)
	_check(not GuildWar.enter(squad), "double tap on enter: one request", "")
	if not await _wait_until(func(): return _main._dungeon != null and _main._dungeon.get_script() == WarBattleScript and _main._dungeon.is_inside_tree(), 15.0):
		_check(false, "siege scene opens", str(_notes))
		return
	var b = _main._dungeon
	await _frames(20)
	_check(is_equal_approx(Engine.time_scale, 1.0) and b.find_children("*", "CanvasLayer", false, false).all(func(n): return n.get_script() != SpeedButton),
		"guild war runs at x1 (no speed button) even with x2 picked", str(Engine.time_scale))
	_check(b.deploying and b.can_start and b.gates.size() == 4, "deploy phase, [전투 시작] allowed", str([b.deploying, b.can_start]))
	await _snap()
	b.request_start()
	_check(await _wait_until(func(): return not b.deploying, 10.0), "[전투 시작] → fight begins", "")
	await _wait_until(func(): return not GuildWar.busy, 5.0)
	sv = await _http_get("/v1/guild/war")
	_check(not bool(sv.war.battle.deploying) and bool(sv.war.battle.me_in), "server: battle started, I'm in the roster", str(sv.war.battle))
	await get_tree().create_timer(6.0).timeout  # 서버 피해 상한(시작 뒤 초 × 초당 공격력 × 10) 안에 들게
	# 성문 3개 + 수비 2명 처치 → 점수 = 2 + 성문 2개(10점씩)
	for i in 3:
		b.gates[i].take_damage(b.gates[i].hp + 1.0)
	var killed := 0
	for u in b._def:
		if killed < 2 and u.is_alive():
			u.take_damage(u.hp + 1.0)
			killed += 1
	await _frames(10)
	var expect: int = b.kills * WarRules.PTS_KILL + WarRules.MAX_GATES_SCORED * WarRules.PTS_GATE + b.keep_points_now()  # 처치 수는 실제 전투 몫도 더해진다
	_check(b.gates_broken_now() == 3 and b.kills >= 2 and b.points_now() == expect, "3 gates + %d kills = %d points in the app (only 2 gates score)" % [b.kills, expect], "pts %d kills %d gates %d" % [b.points_now(), b.kills, b.gates_broken_now()])
	b._finish()
	_check(int(b.result.points) == expect, "result screen points == %d" % expect, str(b.result.get("points")))
	await _snap()
	_check(await _wait_until(func(): return GuildWar.war.get("battle", {}).get("state", "") == "done" or _refetch_war(), 15.0), "server closes the battle", str(GuildWar.war.get("battle")))
	sv = await _http_get("/v1/guild/war")
	_check(int(sv.war.points) == expect and int(GuildWar.war.points) == expect, "server points == app points (%d)" % expect, "server %s app %s" % [sv.war.points, GuildWar.war.points])
	_check(GuildWar.enter_block(squad) == GuildWar.ERROR_TEXT.battle_done, "one siege a week", GuildWar.enter_block(squad))
	b.leave()
	await _wait_until(func(): return _main._dungeon == null, 10.0)
	Prefs.set_value(SpeedButton.PREF_KEY, 1.0)
	# 보상: 이번 주를 지난 주로 넘기고 받는다
	_request_war_sync("/v1/test/war_last_week")
	await _wait_until(func(): return GuildWar.war.get("claim") is Dictionary, 10.0)
	var cl = GuildWar.war.get("claim")
	_check(cl is Dictionary and int(cl.points) == expect, "last week's reward is claimable (points %d)" % expect, str(cl))
	if cl is Dictionary:
		var dia0 := Economy.diamonds
		var c0 := Guild.coins
		_panel._rebuild()
		await _snap()
		GuildWar.claim()
		GuildWar.claim()
		_check(not (GuildWar.war.get("claim") is Dictionary), "claim card goes away at once", "")
		await _wait_until(func(): return not GuildWar.busy, 10.0)
		await _frames(30)
		_check(Economy.diamonds == dia0 + int(cl.reward.diamonds), "diamonds +%d" % int(cl.reward.diamonds), "%d → %d" % [dia0, Economy.diamonds])
		_panel.visible = false  # 창의 주기 새로 받기(REFETCH)가 아니라 보상 응답이 코인을 맞추는지 본다
		await _wait_until(func(): return Guild.coins == c0 + int(cl.reward.coins), 2.0)
		_panel.visible = true
		_check(Guild.coins == c0 + int(cl.reward.coins), "guild coins +%d in the app" % int(cl.reward.coins), "%d → %d" % [c0, Guild.coins])
		await _compare_guild("after war claim")
		var again = await _http_post("/v1/guild/war/claim", {})
		_check(again == null and Net.last_error == "nothing", "claiming twice: nothing", str(again))
	_panel._rebuild()
	await _snap()


func _refetch_war() -> bool:
	GuildWar.fetch_if_stale(2.0)
	return false


func _request_war_sync(path: String) -> void:
	Net.send("POST", path, {}, func(d): GuildWar._take(d), Callable())


# --- 비교 ---

func _compare_guild(what: String) -> void:
	await _wait_until(func(): return Guild._pending == 0 and not Guild.busy, 10.0)
	var gv = await _http_get("/v1/guild")
	var s: Dictionary = gv.get("guild", {}) if gv is Dictionary else {}
	var p := await _player()
	var sm: Dictionary = s.get("me", {}) if s.get("me") is Dictionary else {}
	var ok: bool = int(s.get("coins", -1)) == Guild.coins and (s.get("guild") is Dictionary) == Guild.joined()
	if not sm.is_empty():
		ok = ok and bool(sm.get("attended", false)) == bool(Guild.me.get("attended", false)) and int(sm.get("boss_tries", 0)) == int(Guild.me.get("boss_tries", 0))
		ok = ok and (sm.get("boxes", []) as Array).map(func(x): return int(x)) == Guild.me.get("boxes", [])
		for k in Guild.DONATION_ORDER:
			ok = ok and int(sm.get("donations", {}).get(k, 0)) == int(Guild.me.get("donations", {}).get(k, 0))
		for k in ["dia", "gold", "equip", "shards", "ssr"]:
			ok = ok and int(Guild.shop_left(k)) == int(Guild.shop_item(k).limit) - int((sm.get("shop_day", {}) if Guild.shop_item(k).period == "day" else sm.get("shop_week", {})).get("bought", {}).get(k, 0))
	var eco_ok: bool = int(p.get("diamonds", -1)) == Economy.diamonds and absi(int(p.get("gold", 0)) - Economy.gold) <= GOLD_SLACK
	_check(ok and eco_ok, "guild app == server (%s)" % what, "server coins %s me %s | app coins %d me %s | dia %s/%d gold %s/%d" % [s.get("coins"), sm, Guild.coins, Guild.me, p.get("diamonds"), Economy.diamonds, p.get("gold"), Economy.gold])


func _compare_items(what: String) -> void:
	var p := await _player()
	var sid: Array = p.get("items", []).map(func(it): return int(it.id))
	var aid: Array = Economy.bag.map(func(it): return int(it.id))
	sid.sort()
	aid.sort()
	_check(sid == aid, "bag app == server (%s)" % what, "%s vs %s" % [sid, aid])


func _player() -> Dictionary:
	Net.flush_kills()
	await _frames(10)
	var d = await _http_get("/v1/player")
	return d.get("player", {}) if d is Dictionary else {}


func _http_get(path: String):
	_resp_done = false
	_resp = {}
	Net.send("GET", path, null, func(d):
		_resp = d
		_resp_done = true, func(): _resp_done = true)
	await _wait_until(func(): return _resp_done, 10.0)
	return _resp


func _http_post(path: String, body):
	_resp_done = false
	_resp = null
	Net.send("POST", path, body, func(d):
		_resp = d
		_resp_done = true, func(): _resp_done = true, true, true)
	await _wait_until(func(): return _resp_done, 10.0)
	return _resp


func _finish() -> void:
	if _fails > 0:
		print("JOURNEY GUILD ONLINE FAILED %d" % _fails)
		get_tree().quit(1)
	else:
		print("JOURNEY GUILD ONLINE PASSED")
		get_tree().quit(0)


func _check(ok: bool, what: String, detail: String) -> void:
	print(("PASS " if ok else "FAIL ") + what + ("" if ok else "  " + detail))
	if not ok:
		_fails += 1


func _request(path: String, body) -> void:
	_resp_done = false
	Net.send("POST", path, body, func(d):
		Economy.apply_server(d)
		_resp_done = true, func(): _resp_done = true)
	await _wait_until(func(): return _resp_done, 10.0)


func _sheet() -> void:
	var out := "/tmp/journey_guild_online.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	if _shots.is_empty() or _shots[0] == null:
		return
	var w: int = _shots[0].get_width() / 2
	var h: int = _shots[0].get_height() / 2
	var cols := 6
	var rows := ceili(_shots.size() / float(cols))
	var sheet := Image.create(w * cols, h * rows, false, Image.FORMAT_RGB8)
	for i in _shots.size():
		var img: Image = _shots[i]
		img.convert(Image.FORMAT_RGB8)
		img.save_png(out.get_basename() + "_%d.png" % (i + 1))
		img.resize(w, h, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(img, Rect2i(0, 0, w, h), Vector2i(w * (i % cols), h * (i / cols)))
	sheet.save_png(out)


func _snap() -> void:
	await _frames(8)
	_shots.append(get_viewport().get_texture().get_image())


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _wait_until(cond: Callable, timeout_sec: float) -> bool:
	var end := Time.get_ticks_msec() + int(timeout_sec * 1000.0)
	while not cond.call():
		if Time.get_ticks_msec() > end:
			return false
		await get_tree().process_frame
	return true
