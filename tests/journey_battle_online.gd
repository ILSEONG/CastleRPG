extends Node
## 온라인 통합 체크(던전·PVP, 2026-10-14 통합 테스트): 로컬 서버(메모리 PGlite, ALLOW_TEST_HOOKS=1, tutorial_new_players=0)에 게스트로 접속해
## 버튼이 부르는 같은 코드(던전 창 open_form·deploy, 결과 화면 [다음 단계]·[다시]·[나가기]·자동, [포기], Pvp.set_defense·start·finish·buy)로
## 던전 셋(골드·장비·모집권)과 PVP 두 모드를 하나씩 해 보고, 동작마다 앱 값(곧바로 보인 값)이 서버 GET /v1/player·/v1/dungeon·/v1/pvp와 같은지 본다.
## 승리는 Economy.debug_win_on(시작하자마자 POST /v1/test/dungeon_age로 시작 시각을 당기고 최소 시간으로 끝냄), 패배는 장면의 _report(false)(제한 시간·전멸과 같은 길).
## 실행: cd server && env -u DATABASE_URL PGLITE_DIR=memory ALLOW_TEST_HOOKS=1 PORT=8803 node src/main.ts &
##   curl -XPOST localhost:8803/v1/test/config -H 'content-type: application/json' -d '{"key":"tutorial_new_players","value":"0"}'
##   xvfb-run -a godot --path . --resolution 720x1280 res://tests/journey_battle_online.tscn -- --api=http://127.0.0.1:8803 --device=/tmp/x/device.json --out=/tmp/battle.png
## 마지막 줄이 JOURNEY BATTLE ONLINE PASSED(실패면 종료 코드 1).

const GameData := preload("res://scripts/game_data.gd")
const PvpRules := preload("res://scripts/pvp_rules.gd")
const DungeonScript := preload("res://scripts/dungeon.gd")
const PvpBattleScript := preload("res://scripts/pvp_battle.gd")
const HEROES := ["arteon", "ignis", "selene", "valen", "kyle", "mira"]
const GOLD_SLACK := 300  # 성 전투 처치 골드(보낸 뒤 조금 더 쌓인다)

var _main
var _panel
var _shots: Array = []
var _fails := 0
var _resp_done := false
var _resp = null
var _notes: Array = []


func _ready() -> void:
	Fever.save_path = ""
	Guild.save_path = ""
	Pvp.save_path = ""
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
	_check(await _wait_until(func(): return Net.up, 15.0), "connected", "")
	_check(not Tutorial.active(), "tutorial is off for this account (tutorial_new_players=0)", "")
	for id in HEROES:
		await _request("/v1/test/grant_hero", {"hero_id": id})
	_check(HEROES.all(func(id): return int(Economy.heroes.get(id, 0)) >= 1), "6 heroes from the server", str(Economy.heroes.keys()))
	await _frames(20)
	for n in _main.find_children("*", "", true, false):
		if n.get_script() == preload("res://scripts/dungeon_panel.gd"):
			_panel = n
	_check(_panel != null, "dungeon sheet found", "")
	await _gold_dungeon()
	await _equip_dungeon()
	await _ticket_dungeon()
	await _dungeon_view_matches()
	await _pvp()
	_sheet()
	_finish()


# --- 던전 ---

func _gold_dungeon() -> void:
	print("--- gold dungeon")
	_panel.open()
	await _frames(10)
	var c: Dictionary = _panel.cards.gold
	_check(c.keys.text == "3 / 10" and c.reward.text == "보상 4,000 골드" and not c.go.disabled, "gold card: 3/10 keys, 4,000 gold at level 1", "%s | %s" % [c.keys.text, c.reward.text])
	await _snap()
	_panel.open_form("gold")
	await _frames(5)
	_check(_panel.party.size() == 6 and _panel.helper_box.visible == false, "gold form: 6 heroes, no helper row", str(_panel.party))
	# 1) 1단계 승리
	var g0 := Economy.gold
	Economy.debug_win_on = true
	_panel.deploy()
	var d = await _scene_result()
	_check(d != null and d.result.get("win", false) and int(d.result.rewards.get("gold_tenths", 0)) == GameData.gold_reward(1) * 10,
		"gold 1: win pays 4,000 gold", str(d.result if d != null else {}))
	if d == null:
		return
	_check(d.hud.gold_label != null and d.hud.gold_label.text == "+4,000 골드", "result shows +4,000 골드", d.hud.gold_label.text if d.hud.gold_label else "")
	var st := Economy.dungeon_state("gold")
	_check(st.keys == 2 and st.best_level == 1 and st.max_level == 2, "key used, best level 1 (level 2 opens)", str(st))
	_check(absi(Economy.gold - (g0 + 4000)) <= GOLD_SLACK, "gold +4,000 in the app", "%d → %d" % [g0, Economy.gold])
	await _compare_dungeon("gold", "after gold 1 win")
	_check(d.hud.next_button.visible and d.hud.again_button.visible and d.hud.exit_button.visible, "[다음 단계]·[다시]·[나가기] shown after a win", "")
	await _snap()
	# 2) [다음 단계] → 2단계 승리
	d.hud.next_button.pressed.emit()
	var d2 = await _scene_result(d)
	_check(d2 != null and int(d2.run.level) == 2 and d2.result.get("win", false) and int(d2.result.rewards.get("gold_tenths", 0)) == GameData.gold_reward(2) * 10,
		"[다음 단계] starts level 2 and wins %d gold" % GameData.gold_reward(2), str(d2.result if d2 != null else {}))
	if d2 == null:
		return
	_check(Economy.dungeon_state("gold").keys == 1 and Economy.dungeon_state("gold").best_level == 2, "keys 1, best level 2", str(Economy.dungeon_state("gold")))
	await _compare_dungeon("gold", "after [다음 단계]")
	# 3) [다시] → 2단계 패배(제한 시간·전멸과 같은 길) — 열쇠는 그대로
	Economy.debug_win_on = false
	d2.hud.again_button.pressed.emit()
	var d3 = await _scene_fight(d2)
	_check(d3 != null and int(d3.run.level) == 2, "[다시] restarts the same level", "")
	if d3 == null:
		return
	d3._report(false)
	_check(await _wait_until(func(): return d3.phase == d3.Phase.RESULT, 10.0) and not d3.result.get("win", true) and not d3.result.has("error"),
		"loss: the server closes the run as a loss", str(d3.result))
	_check(d3.hud.result_title.text == "패배" and not d3.hud.reward_box.visible and not d3.hud.next_button.visible and d3.hud.again_button.visible,
		"loss screen: 패배, no rewards, [다시] but no [다음 단계]", d3.hud.result_title.text)
	_check(Economy.dungeon_state("gold").keys == 1, "a loss uses no key", str(Economy.dungeon_state("gold")))
	await _compare_dungeon("gold", "after loss")
	await _snap()
	# 4) [다시] 두 번 → 한 판만, [포기] → 성으로(열쇠 그대로)
	var runs := [0]
	var count := func(r):
		if not r.is_empty():
			runs[0] += 1
	Economy.dungeon_started.connect(count)
	d3.hud.again_button.pressed.emit()
	d3.hud.again_button.pressed.emit()
	_check(d3.hud.again_button.disabled, "buttons lock while the next run starts", "")
	var d4 = await _scene_fight(d3)
	await _frames(30)
	Economy.dungeon_started.disconnect(count)
	_check(runs[0] == 1, "double tap on [다시] starts one run", str(runs[0]))
	if d4 == null:
		return
	d4.give_up()
	_check(await _wait_until(func(): return _main._dungeon == null and _main.is_inside_tree(), 10.0), "[포기] goes straight back to the castle", "")
	await _wait_until(func(): return Economy._waiting.keys().filter(func(k): return str(k).begins_with("finish:")).is_empty(), 10.0)
	_check(Economy.dungeon_state("gold").keys == 1, "give up uses no key", str(Economy.dungeon_state("gold")))
	await _compare_dungeon("gold", "after give up")
	# 5) 마지막 열쇠로 승리 → 자동 반복은 열쇠가 없어 멈추고, [다시]는 열쇠 없음 알림
	Economy.debug_win_on = true
	_panel.open()
	_panel.open_form("gold")
	_panel.deploy()
	var d5 = await _scene_result()
	if d5 == null:
		return
	_check(d5.result.get("win", false) and Economy.dungeon_state("gold").keys == 0, "last key: win, 0 keys left", str(Economy.dungeon_state("gold")))
	d5.auto_delay = 0.3
	_notes.clear()
	d5.hud.auto_repeat_box.button_pressed = true
	_check(Fever.dungeon_auto == "repeat" and not d5.hud.auto_next_box.button_pressed, "auto repeat on (the other box off)", Fever.dungeon_auto)
	_check(await _wait_until(func(): return d5.auto_halted, 5.0) and _notes.has(DungeonScript.STOP_KEYS), "auto repeat stops: no keys", str(_notes))
	d5.hud.auto_repeat_box.button_pressed = false
	_check(Fever.dungeon_auto == "", "auto off", Fever.dungeon_auto)
	_notes.clear()
	d5.hud.again_button.pressed.emit()
	await _frames(10)
	_check(_notes.has(Economy.DUNGEON_TEXT.no_key) and _main._dungeon == d5 and not d5.starting, "[다시] without keys: notice, stays on the result", str(_notes))
	await _compare_dungeon("gold", "after the last key")
	d5.hud.exit_button.pressed.emit()
	_check(await _wait_until(func(): return _main._dungeon == null and _main.is_inside_tree(), 10.0), "[나가기] goes back to the castle", "")
	_panel.open()
	await _frames(5)
	_check(_panel.cards.gold.go.disabled and _panel.cards.gold.reason.text == Economy.DUNGEON_TEXT.no_key and _panel.cards.gold.keys.text == "0 / 10",
		"gold card: 0/10, [도전] off with the no-key reason", _panel.cards.gold.reason.text)
	_notes.clear()
	_check(not Economy.start_dungeon("gold", 1, Economy.default_party("gold")) and _notes.has(Economy.DUNGEON_TEXT.no_key), "start without keys is refused in the app", str(_notes))
	_check(not Economy.start_dungeon("gold", 4, Economy.default_party("gold")), "level 4 is locked (best 2 → up to level 3)", "")
	_panel.close()


func _equip_dungeon() -> void:
	print("--- equip dungeon")
	_panel.open()
	await _frames(5)
	var c: Dictionary = _panel.cards.equip
	_check(c.keys.text == "1 / 3" and c.reward.text.begins_with("장비 5개"), "equip card: 1/3 keys, 5 items", "%s | %s" % [c.keys.text, c.reward.text])
	_panel.open_form("equip")
	_check(_panel.party.size() == 4, "equip form: 4 heroes", str(_panel.party))
	var bag0: int = Economy.bag.size()
	Economy.debug_win_on = true
	_panel.deploy()
	var d = await _scene_result()
	if d == null:
		return
	var items: Array = d.result.rewards.get("items", [])
	_check(d.result.win and items.size() >= 5 and Economy.bag.size() == bag0 + items.size(), "equip 1: win drops %d items into the bag" % items.size(), str(d.result))
	_check(d.hud.reward_tiles.size() == items.size(), "result shows one tile per item", str(d.hud.reward_tiles.size()))
	_check(Economy.dungeon_state("equip").keys == 0 and Economy.dungeon_state("equip").best_level == 1 and Economy.dungeon_state("equip").extra_cost == 100000,
		"key used, best 1, extra run costs 100,000 gold", str(Economy.dungeon_state("equip")))
	await _compare_dungeon("equip", "after equip 1")
	await _compare_items("after equip 1")
	await _snap()
	d.hud.exit_button.pressed.emit()
	await _wait_until(func(): return _main._dungeon == null, 10.0)
	# 열쇠 없이 골드 추가 도전(100,000)
	await _request("/v1/test/grant_gold", {"amount": 150000})
	var g0 := Economy.gold
	_panel.open()
	await _frames(5)
	_check(c.cost.text == "/ 100,000" and not c.go.disabled, "card shows the extra-run gold cost and [도전] is on", c.cost.text)
	_panel.open_form("equip")
	_panel.step_level("equip", 1)
	_panel.deploy()
	var d2 = await _scene_result()
	if d2 == null:
		return
	_check(d2.result.win and str(d2.run.paid_with) == "gold" and int(d2.run.level) == 2, "equip 2 without a key: paid with gold, win", str(d2.run.get("paid_with")))
	var st := Economy.dungeon_state("equip")
	_check(st.extra_today == 1 and st.extra_cost == 300000 and st.best_level == 2, "extra run counted, next one costs 300,000", str(st))
	_check(absi(Economy.gold - (g0 - 100000)) <= GOLD_SLACK, "100,000 gold spent", "%d → %d" % [g0, Economy.gold])
	await _compare_dungeon("equip", "after the gold run")
	await _compare_items("after the gold run")
	d2.hud.exit_button.pressed.emit()
	await _wait_until(func(): return _main._dungeon == null, 10.0)
	_notes.clear()
	var gold_before := Economy.gold
	_check(not Economy.start_dungeon("equip", 1, Economy.default_party("equip")) and _notes.has(Economy.DUNGEON_TEXT.not_enough_gold) and Economy.gold == gold_before,
		"not enough gold for the next extra run: notice, nothing changes", str(_notes))
	_panel.close()


func _ticket_dungeon() -> void:
	print("--- ticket dungeon")
	_panel.open()
	await _frames(5)
	var c: Dictionary = _panel.cards.ticket
	_check(c.keys.text == "1 / 3" and c.reward.text.contains("다이아 모집권 10장"), "ticket card: 1/3 keys, 10 tickets", "%s | %s" % [c.keys.text, c.reward.text])
	var helpers: Array = Economy.helper_candidates()
	_check(helpers.size() == 3, "3 helper candidates from the server", str(helpers))
	_panel.open_form("ticket")
	await _frames(5)
	_check(_panel.party.size() == 4 and _panel.helper_id == str(helpers[0].key) and not _panel.party.has(_panel.helper_hero()), "ticket form: 4 heroes + first helper picked", str([_panel.party, _panel.helper_id]))
	await _snap()
	# 패배 먼저(열쇠 그대로, [다시]는 같은 도우미로)
	Economy.debug_win_on = false
	_panel.deploy()
	var d = await _scene_fight()
	if d == null:
		return
	_check(d.heroes.size() == 5 and d.heroes[4].helper, "ticket run: 4 heroes + the helper", str(d.heroes.size()))
	d._report(false)
	await _wait_until(func(): return d.phase == d.Phase.RESULT, 10.0)
	_check(not d.result.win and d.hud.again_button.visible and not d.hud.next_button.visible and not d.hud.auto_next_box.get_parent().visible,
		"ticket loss: [다시] only, no auto", str(d.result))
	_check(Economy.dungeon_state("ticket").keys == 1, "ticket loss uses no key", "")
	var t0 := Economy.dia_tickets
	Economy.debug_win_on = true
	d.hud.again_button.pressed.emit()
	var d2 = await _scene_result(d)
	if d2 == null:
		return
	_check(d2.result.win and int(d2.result.rewards.get("tickets", 0)) == GameData.ticket_reward(1), "ticket win: 10 tickets in the result", str(d2.result))
	_check(d2.hud.gold_label != null and d2.hud.gold_label.text == "다이아 모집권 +10", "result shows 다이아 모집권 +10", d2.hud.gold_label.text if d2.hud.gold_label else "(none)")
	_check(Economy.dia_tickets == t0 + 10, "tickets +10 in the app", "%d → %d" % [t0, Economy.dia_tickets])
	_check(not d2.hud.again_button.visible and not d2.hud.next_button.visible, "after a ticket win: only [나가기]", "")
	var used: Array = Economy.dungeon_state("ticket").helpers_used
	_check(used == [str(helpers[0].key)] and Economy.helper_by_key(str(helpers[0].key)).is_empty(), "the helper is used for today", str(used))
	await _compare_dungeon("ticket", "after ticket win")
	var p := await _player()
	_check(int(p.get("dia_tickets", -1)) == Economy.dia_tickets, "server tickets == app tickets", "%s vs %d" % [p.get("dia_tickets"), Economy.dia_tickets])
	await _snap()
	d2.hud.exit_button.pressed.emit()
	await _wait_until(func(): return _main._dungeon == null, 10.0)
	_panel.close()


func _dungeon_view_matches() -> void:
	var dv = await _http_get("/v1/dungeon")
	for t in GameData.DUNGEON_TYPES:
		var s: Dictionary = dv.get("dungeons", {}).get(t, {})
		var a := Economy.dungeon_state(t)
		_check(int(s.get("keys", -1)) == a.keys and int(s.get("best_level", -1)) == a.best_level and int(s.get("extra_today", -1)) == a.extra_today
			and int(s.get("key_cap", -1)) == a.key_cap and absf(float(s.get("next_reset", 0)) - a.next_reset) < 1.0
			and (t != "equip" or int(s.get("extra_cost", -1)) == a.extra_cost), "GET /v1/dungeon %s == app" % t, "%s vs %s" % [s, a])


# --- PVP ---

func _pvp() -> void:
	print("--- pvp")
	_panel.open()
	_panel.set_section("pvp")
	var pv = _panel.pvp
	_check(await _wait_until(func(): return not Pvp.view.is_empty(), 10.0) and pv.visible, "PVP tab opens and the server view arrives", "")
	for m in PvpRules.MODES:
		_check(Pvp.plays_left(m) == 5 and Pvp.points(m) == 0 and not Pvp.opponent(m).is_empty() and str(Pvp.mode_view(m).tier.id) == "bronze",
			"%s: 5 plays, 0 points, bronze, an opponent is ready" % m, str(Pvp.mode_view(m)))
	_check(Pvp.coins() == 0, "0 PVP coins", str(Pvp.coins()))
	await _snap()
	# 방어팀(결투): 화면 [방어팀 설정] → 영웅 5 → [확인]
	pv.open_mode("duel")
	await _frames(3)
	pv.buttons["방어팀 설정"].pressed.emit()
	var ids: Array = Pvp.owned_heroes().slice(1, 6)
	pv.pick = ids.duplicate()
	pv._confirm_pick()
	_check(Pvp.defense("duel") == ids, "defense team shows at once", str(Pvp.defense("duel")))
	var predicted := int(Pvp.mode_view("duel").get("power", 0))
	await get_tree().create_timer(1.5).timeout  # 저장 응답
	var srv = await _http_get("/v1/pvp")
	var sm: Dictionary = srv.pvp.modes.duel
	_check(sm.defense == ids and Pvp.defense("duel") == ids, "server keeps the duel defense team", str(sm.defense))
	_check(predicted == int(sm.power), "predicted defense power == server power", "app %d vs server %d" % [predicted, int(sm.power)])
	await _snap()
	# 결투 승리
	var opp: Dictionary = Pvp.opponent("duel")
	var gain := PvpRules.win_gain(0, int(opp.points))
	var team: Array = pv.team.get("duel", [])
	_check(team.size() == 5, "duel team of 5", str(team))
	pv.buttons["start"].pressed.emit()
	_check(Pvp.plays_left("duel") == 4 and Pvp.coins() == PvpRules.COINS_LOSS, "start: play used, loss coins first (instant)", str(Pvp.mode_view("duel")))
	var b = await _pvp_scene()
	if b == null:
		return
	_check(await _wait_until(func(): return str(Pvp.battle.get("id", "")) != "", 10.0), "server confirms the battle", str(Pvp.battle))
	await _wait_until(func(): return b.phase == b.Phase.FIGHT and b.clock >= PvpRules.MIN_WIN_SEC + 0.2, 30.0)
	var got := [null]
	Pvp.result_ready.connect(func(r): got[0] = r, CONNECT_ONE_SHOT)
	b._end(true, "test")
	_check(Pvp.points("duel") == gain and Pvp.coins() == PvpRules.COINS_WIN, "win shows +%d points, 30 coins at once" % gain, str([Pvp.points("duel"), Pvp.coins()]))
	_check(await _wait_until(func(): return got[0] != null, 10.0) and got[0].win and int(got[0].delta) == gain, "server accepts the win", str(got[0]))
	await _compare_pvp("after duel win")
	await _snap()
	b.leave()
	await _wait_until(func(): return _main._dungeon == null, 10.0)
	# 결투 패배(포기) × 4 → 판 다 씀
	for i in 4:
		var pts := Pvp.points("duel")
		_panel.open()
		_panel.set_section("pvp")
		pv.open_mode("duel")
		pv.buttons["start"].pressed.emit()
		var bb = await _pvp_scene()
		if bb == null:
			return
		await _wait_until(func(): return str(Pvp.battle.get("id", "")) != "", 10.0)
		var lost := [null]
		Pvp.result_ready.connect(func(r): lost[0] = r, CONNECT_ONE_SHOT)
		bb.forfeit()
		await _wait_until(func(): return lost[0] != null and _main._dungeon == null, 10.0)
		_check(lost[0] != null and not lost[0].win and Pvp.points("duel") == pts - PvpRules.loss_of(pts), "duel forfeit %d: loss −%d" % [i + 1, PvpRules.loss_of(pts)], str(lost[0]))
	_check(Pvp.plays_left("duel") == 0, "5 duel plays used", str(Pvp.plays_left("duel")))
	await _compare_pvp("after 5 duel plays")
	_notes.clear()
	_check(not Pvp.start("duel", team) and _notes.has(Pvp.ERROR_TEXT.no_plays), "6th duel: no plays left notice", str(_notes))
	# 총력전: 방어팀 없이 시작하면 그 팀이 방어팀, 승리
	_panel.open()
	_panel.set_section("pvp")
	pv.open_mode("total")
	await _frames(3)
	var tteam: Array = pv.team.total
	pv.buttons["start"].pressed.emit()
	_check(Pvp.defense("total") == tteam, "total without a defense team: this team becomes the defense", str(Pvp.defense("total")))
	var tb = await _pvp_scene()
	if tb == null:
		return
	_check(tb.mode == "total", "total battle scene", tb.mode)
	await _wait_until(func(): return str(Pvp.battle.get("id", "")) != "", 10.0)
	await _wait_until(func(): return tb.phase == tb.Phase.FIGHT and tb.clock >= PvpRules.MIN_WIN_SEC + 0.2, 30.0)
	var tg := [null]
	Pvp.result_ready.connect(func(r): tg[0] = r, CONNECT_ONE_SHOT)
	await _snap()
	tb._end(true, "test")
	_check(await _wait_until(func(): return tg[0] != null, 10.0) and tg[0].win, "total win accepted", str(tg[0]))
	await _compare_pvp("after total win")
	var ts = await _http_get("/v1/pvp")
	_check(ts.pvp.modes.total.defense == tteam, "server: total defense = the first team", str(ts.pvp.modes.total.defense))
	tb.leave()
	await _wait_until(func(): return _main._dungeon == null, 10.0)
	# 상점: 코인 = 30 + 10×4 + 30 = 100 → 골드 30,000(60) 구매, 다이아(150) 부족
	_check(Pvp.coins() == 100, "coins 100 (2 wins + 4 losses)", str(Pvp.coins()))
	var g0 := Economy.gold
	_check(Pvp.buy("gold") == "" and Pvp.coins() == 40 and int(Pvp.shop_item("gold").bought) == 1, "buy gold: −60 coins at once", str(Pvp.coins()))
	_check(await _wait_until(func(): return absi(Economy.gold - (g0 + 30000)) <= GOLD_SLACK, 10.0), "+30,000 gold after the server answers", "%d → %d" % [g0, Economy.gold])
	await _compare_pvp("after shop buy")
	var p := await _player()
	_check(absi(int(p.gold) - Economy.gold) <= GOLD_SLACK, "server gold == app gold after the buy", "%d vs %d" % [int(p.gold), Economy.gold])
	_notes.clear()
	_check(Pvp.buy("dia") == Pvp.ERROR_TEXT.not_enough_coins and Pvp.coins() == 40, "dia (150): not enough coins, nothing changes", str(_notes))
	# 등급: 서버 포인트를 바꿔 등급 경계마다 앱 등급 == 서버 등급
	for pts in [199, 200, 500, 900, 1400, 2000, 2700]:
		await _request_pvp("/v1/test/pvp_points", {"mode": "duel", "points": pts})
		var tv: Dictionary = Pvp.mode_view("duel")
		_check(str(tv.tier.id) == str(PvpRules.tier_of(pts).id) and int(tv.points) == pts, "tier at %d points: %s" % [pts, tv.tier.id], str(tv.tier))
	pv.open_mode("duel")
	await _frames(5)
	_check(pv._p.tier.text.begins_with("챌린저"), "page shows the challenger tier", pv._p.tier.text)
	await _snap()
	var shop = get_tree().get_first_node_in_group("shop_panel")
	if shop != null:
		pv.open_shop()
		await _frames(10)
		await _snap()
		shop.close()
	_panel.close()


func _pvp_scene():
	if not await _wait_until(func(): return _main._dungeon != null and _main._dungeon.get_script() == PvpBattleScript, 10.0):
		_check(false, "PVP battle scene opens", "")
		return null
	return _main._dungeon


func _compare_pvp(what: String) -> void:
	var s = await _http_get("/v1/pvp")
	var v: Dictionary = s.get("pvp", {})
	var ok: bool = int(v.get("coins", -1)) == Pvp.coins()
	for m in PvpRules.MODES:
		var a: Dictionary = Pvp.mode_view(m)
		var b: Dictionary = v.get("modes", {}).get(m, {})
		ok = ok and int(a.points) == int(b.points) and int(a.plays_left) == int(b.plays_left) and int(a.wins) == int(b.wins) and int(a.losses) == int(b.losses)
	var bought_ok := true
	for it in v.get("shop", []):
		bought_ok = bought_ok and int(Pvp.shop_item(str(it.id)).get("bought", -1)) == int(it.bought)
	_check(ok and bought_ok, "pvp app == server (%s)" % what, "%s vs %s" % [str(Pvp.view.get("modes")), str(v.get("modes"))])


func _request_pvp(path: String, body) -> void:
	_resp_done = false
	Net.send("POST", path, body, func(d):
		Pvp._take(d)
		_resp_done = true, func(): _resp_done = true)
	await _wait_until(func(): return _resp_done, 10.0)


# --- 던전 도우미 ---

## 던전 장면이 열리고(이전 장면 prev가 아니면) 결과 화면까지 기다린다.
func _scene_result(prev = null):
	var d = await _scene_fight(prev)
	if d == null:
		return null
	if not await _wait_until(func(): return d.phase == d.Phase.RESULT, 30.0):
		_check(false, "dungeon result arrives", "phase %d" % d.phase)
		return null
	await _frames(5)
	return d


func _scene_fight(prev = null):
	var prev_id: int = prev.get_instance_id() if is_instance_valid(prev) else 0  # 지난 장면은 곧 지워진다 — 람다가 노드를 붙잡지 않게 id로
	prev = null
	var ok: bool = await _wait_until(func(): return _main._dungeon != null and is_instance_valid(_main._dungeon) and _main._dungeon.get_instance_id() != prev_id and is_instance_valid(_main._dungeon) and _main._dungeon.get_script() == DungeonScript and _main._dungeon.is_inside_tree(), 15.0)
	if not ok:
		_check(false, "dungeon scene opens", str(_notes))
		return null
	await _frames(3)
	return _main._dungeon


func _compare_dungeon(type: String, what: String) -> void:
	var p := await _player()
	var s: Dictionary = p.get("dungeons", {}).get(type, {})
	var a := Economy.dungeon_state(type)
	_check(int(s.get("keys", -1)) == a.keys and int(s.get("best_level", -1)) == a.best_level and int(s.get("extra_today", -1)) == a.extra_today
		and absi(int(p.get("gold", 0)) - Economy.gold) <= GOLD_SLACK, "%s dungeon app == server (%s)" % [type, what],
		"server %s gold %s vs app %s gold %d" % [s, p.get("gold"), a, Economy.gold])


func _compare_items(what: String) -> void:
	var p := await _player()
	var sid: Array = p.get("items", []).map(func(it): return int(it.id))
	var aid: Array = Economy.bag.map(func(it): return int(it.id))
	sid.sort()
	aid.sort()
	_check(sid == aid, "bag app == server (%s, %d items)" % [what, aid.size()], "%s vs %s" % [sid, aid])


# --- 공통 ---

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


func _finish() -> void:
	Economy.debug_win_on = false
	if _fails > 0:
		print("JOURNEY BATTLE ONLINE FAILED %d" % _fails)
		get_tree().quit(1)
	else:
		print("JOURNEY BATTLE ONLINE PASSED")
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
	var out := "/tmp/journey_battle_online.png"
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
