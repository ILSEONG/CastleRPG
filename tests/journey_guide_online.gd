extends Node
## 통합 테스트(2026-10-14) — 가이드 여정(온라인): 새 게스트로 로컬 서버(ALLOW_TEST_HOOKS=1, tutorial_new_players=1)에 접속해 가이드 80개 미션을 처음부터
## 하나씩 깬다. 미션마다 카드(제목·설명·보상·[바로가기])가 말이 되는지 보고 [바로가기]를 눌러 무엇이 열리는지 본 뒤, 버튼과 같은 함수로 목표를 채운다
## (실제 플레이로 오래 걸리는 처치·스테이지·FEVER 게이지는 테스트 훅/사건 수로 대신 — SIM 줄로 적는다). 카드 [보상 받기]로 받으면
## 보상이 곧바로 보이고(예측), 서버가 받아들이고(되돌림 없음), 앱 단계·보상 반영 상태 == 서버 GET /v1/player인지 본다.
## 가이드가 끝나면 반복 퀘스트를 한 바퀴(9개) 같은 방식으로 돈다.
## 실행: cd server && env -u DATABASE_URL PGLITE_DIR=memory ALLOW_TEST_HOOKS=1 PORT=8802 node src/main.ts &
##   xvfb-run -a godot --path . --resolution 720x1280 res://tests/journey_guide_online.tscn -- --api=http://127.0.0.1:8802 --device=/tmp/x/device.json --out=/tmp/jg.png
## 마지막 줄이 JOURNEY GUIDE ONLINE PASSED(실패면 종료 코드 1). INFO 줄 = 실패는 아니지만 보고할 것(보상 부족 등).

const EconomyScript := preload("res://scripts/economy.gd")
const GameData := preload("res://scripts/game_data.gd")
const MainScript := preload("res://scripts/main.gd")
const SpawnerScript := preload("res://scripts/spawner.gd")
const PlacementScript := preload("res://scripts/placement.gd")
const CardScript := preload("res://scripts/tutorial_card.gd")
const UiWindowScript := preload("res://scripts/ui_window.gd")

var _main
var _shots: Array = []
var _fails := 0
var _notes: Array = []
var _resp = null
var _resp_done := false
var _resp_err := ""
var _infos: Array = []
var _boss_run := {}


func _ready() -> void:
	Fever.save_path = ""
	Guild.save_path = ""
	Tutorial.save_path = ""
	Missions.save_path = ""
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
	Tutorial.go_online()
	add_child(preload("res://scenes/main.tscn").instantiate())
	if not await _world("world built after connecting (fresh guest)"):
		return _finish()
	Economy.notice.connect(func(s): _notes.append(s))
	Guild.boss_started.connect(func(r): _boss_run = r)
	_check(await _wait_until(func(): return not Tutorial.mission().is_empty(), 10.0) and Tutorial.active() and Tutorial.step == 0, "guide starts at mission 1", str(Economy.server_quest))
	var total: int = Tutorial.MISSIONS.size()
	_check(total == 80, "the guide has 80 missions", str(total))
	var guard := 0
	var upto := int(Net.arg_value("upto")) if Net.arg_value("upto") != "" else total  # 디버그: 이 미션까지만
	while Tutorial.active() and guard < total + 2 and Tutorial.step < upto:
		guard += 1
		if not await _mission(Tutorial.step):
			print("STOP the guide is stuck at mission %d (%s)" % [Tutorial.step + 1, Tutorial.mission().get("id", "?")])
			break
	_check(not Tutorial.active() and str(Economy.server_quest.get("tut_state", "")) == "done" and Tutorial.step == total, "the whole guide is done (client and server)",
		"step=%d state=%s server=%s" % [Tutorial.step, Tutorial.state, Economy.server_quest])
	if not Tutorial.active():
		await _repeats(9)
	for s in _infos:
		print("INFO " + s)
	await _snap()
	_sheet()
	_finish()


## 미션 i 하나: 카드 → [바로가기] → 목표 채우기 → [보상 받기] → 서버 비교. 깨지 못하면 false.
func _mission(i: int) -> bool:
	var m: Dictionary = Tutorial.mission()
	var id := str(m.id)
	var tag := "(g%02d %s)" % [i + 1, id]
	var card = _child(CardScript)
	await _frames(2)
	var reward: Dictionary = Tutorial.reward(i)
	var text_ok: bool = card.panel.visible and card.step_label.text == "가이드 %d/80" % (i + 1) and str(m.title) in card.title_label.text and card.desc_label.text.length() > 10 \
		and card.reward_label.text == "보상: " + Tutorial.reward_text(reward) and not reward.is_empty() and Tutorial.reward_text(reward) != ""
	_check(text_ok, tag + " card: step, title, description, reward", "%s | %s | %s | %s" % [card.step_label.text, card.title_label.text, card.desc_label.text, card.reward_label.text])
	if not Tutorial.complete():
		await _goto(m, tag, card)
		await _satisfy(m, tag)
	var done := await _wait_until(func(): return Tutorial.complete(), 20.0)
	_check(done, tag + " target reached (mission complete)", "kind=%s count=%d progress=%s" % [m.kind, Tutorial.count, Tutorial.progress_text()])
	if not done:
		return false
	await _close_all()
	await _settle()
	await _frames(3)
	var s0 := _state()
	card = _child(CardScript)
	await _wait_until(func(): return card.action_button.visible and card.action_button.text == "보상 받기", 3.0)  # Tutorial.check는 1초마다
	_check(card.action_button.visible and not card.action_button.disabled and card.action_button.text == "보상 받기", tag + " card shows [보상 받기]",
		"%s visible=%s title=%s complete=%s" % [card.action_button.text, card.action_button.visible, card.title_label.text, Tutorial.complete()])
	_notes.clear()
	card.action_button.pressed.emit()
	card.action_button.pressed.emit()  # 빠른 두 번 탭 = 한 번
	var s1 := _state()
	var bad := _added(s0, s1, reward, false)
	_check(bad.is_empty(), tag + " reward %s shows at once" % Tutorial.reward_text(reward), str(bad))
	var moved := await _wait_until(func(): return Tutorial.step == i + 1 and not Economy.quest_waiting(), 15.0)
	await _settle()
	_check(moved and not _notes.has(EconomyScript.ROLLBACK_TEXT) and not _notes.has(EconomyScript.QUEST_FAIL_DEFAULT), tag + " server accepted the claim (step %d → %d)" % [i + 1, i + 2],
		"step=%d notes=%s" % [Tutorial.step, _notes])
	if not moved:
		return false
	var p := await _server()
	var s2 := _state_of(p)
	bad = _added(s0, s2, reward, true)
	_check(bad.is_empty(), tag + " server paid the same reward", str(bad))
	await _diff(tag)
	if i % 10 == 9:
		await _snap()
	return true


## 카드 [바로가기]: 갈 곳이 있으면 눌러 무엇이 열리는지 본다(전투 시작·공성 연습은 누르지 않는다).
func _goto(m: Dictionary, tag: String, card) -> void:
	var g: String = Tutorial.goto_of(m)
	var shown: bool = card.action_button.visible
	_check(shown == (g != "") or (g == "stage"), tag + " [바로가기] shown only when there is somewhere to go (goto '%s')" % g, "visible=%s" % shown)
	if g == "" or g == "stage" or g == "siege_practice":
		if g == "stage":
			_check(card.action_button.text == "▶ 진행", tag + " battle mission button says ▶ 진행", card.action_button.text)
		return
	var placement = _child(PlacementScript)
	var before := _open_windows()
	card.action_button.pressed.emit()
	await _frames(12)
	var panel = _main._picker.building_panel
	var opened: bool = _open_windows().size() > before.size() or panel.visible or placement.is_active()
	if g.begins_with("look:"):
		opened = true  # 카메라만 옮긴다
	_check(opened, tag + " [바로가기] (%s) opens something" % g, "windows=%s panel=%s placement=%s" % [_open_windows(), panel.visible, placement.is_active()])
	if g.begins_with("building:") and not opened:
		return
	if g.begins_with("building:") and panel.visible:
		_check(panel.building_id == g.get_slice(":", 1), tag + " [바로가기] opened the right building window", panel.building_id)


func _satisfy(m: Dictionary, tag: String) -> void:
	var kind := str(m.kind)
	var now := Economy.time_now()
	match kind:
		"open":
			if str(m.arg) == "keep":
				_main._picker.building_panel.open_building("keep")
			elif str(m.arg) == "exchange" and Tutorial.count < 1:
				_main._tutorial_ui.side_menu.pick("exchange")
			await _frames(5)
		"build":
			var id := str(m.arg)
			var placement = _child(PlacementScript)
			if not placement.is_active() and not Economy.is_placed(id):
				placement.start(id)
				await _frames(3)
			var why := Economy.upgrade_block(id, Economy.time_now())
			if why == "not_enough":
				_info("%s the previous reward does not cover building %s (cost %s, have %s)" % [tag, id, GameData.build_cost(id, 1), Economy.res])
				await _request("/v1/test/levels", {"res": _plus(GameData.build_cost(id, 1))})
			if placement.is_active():
				placement.confirm()
			elif not Economy.is_building(id) and Economy.unbuilt.has(id):
				Economy.upgrade(id, Economy.time_now())
			await _settle()
			_check(Economy.is_building(id) or not Economy.unbuilt.has(id), tag + " %s lot started" % id, str(_notes.slice(-2)))
			await _wait_until(func(): return not Economy.unbuilt.has(id), 12.0)
		"level":
			var id := str(m.arg[0])
			while Economy.shown_level(id) < int(m.arg[1]):
				var why := Economy.upgrade_block(id, Economy.time_now())
				if why == "not_enough":
					_info("%s the previous reward does not cover %s Lv %d→%d (cost %s, have %s)" % [tag, id, Economy.building_level(id), Economy.building_level(id) + 1, Economy.upgrade_cost(id), Economy.res])
					await _request("/v1/test/levels", {"res": _plus(Economy.upgrade_cost(id))})
				elif why != "":
					_check(false, tag + " %s can be upgraded" % id, why)
					return
				Economy.upgrade(id, Economy.time_now())
				await _settle()
				await _request("/v1/test/build_now", {})
				await _settle()
		"kill":
			_sim(tag, "kills %d via /v1/test/events + Tutorial.note" % int(m.arg))
			await _request("/v1/test/events", {"events": {"kill": int(m.arg)}})
			Tutorial.note("kill", int(m.arg))
		"collect":
			await _request("/v1/test/age", {"minutes": 3})
			Economy.collect("lumber", Economy.time_now())
		"sell":
			var r := "wood" if int(Economy.res.get("wood", 0)) > 0 else ("stone" if int(Economy.res.get("stone", 0)) > 0 else "food")
			Economy.sell(r, Economy.time_now(), mini(50, int(Economy.res.get(r, 0))))
		"attend":
			var ev = _main._tutorial_ui.side_menu.windows.get("event")
			if ev != null:
				if not ev.is_open():
					_main._tutorial_ui.side_menu.pick("event")
				await _wait_until(func(): return ev.can_claim(), 10.0)
				ev.claim()
		"pouch":
			for pid in Economy.pouches.keys():
				if Economy.pouch_count(pid) > 0:
					Economy.open_pouch(pid, 1, GameState.stage)
					break
		"stage":
			_sim(tag, "stage → %d via /v1/test/stage" % (int(m.arg) + 1))
			await _request("/v1/test/stage", {"stage": int(m.arg) + 1})
			GameState.stage = Economy.server_stage  # 스테이지 경계에서 앱이 서버 값으로 맞추는 것과 같다
			Tutorial.note_stage(Economy.server_stage)
		"auto_on":
			var n = _target_node("hud:auto")
			_check(n != null, tag + " the [연속 진행] checkbox is registered", "")
			if n is BaseButton and n.toggle_mode:
				n.button_pressed = true
			elif n != null:
				n.pressed.emit()
		"speed_on":
			var n = _target_node("hud:speed")
			_check(n != null, tag + " the speed button is registered", "")
			var k := 0
			while n != null and not Tutorial._speed_on() and k < 3:
				n.pressed.emit()
				k += 1
				await _frames(2)
		"hero_level":
			var h := str(GameData.config_list("starter_heroes")[0])
			await _gold_for(tag, func(): return Economy.levelup_block(h, 1))
			Economy.level_up(h, 1)
		"hero_lv":
			var need := int(m.arg[0])
			var lv := int(m.arg[1])
			var ids: Array = Economy.heroes.keys()
			ids.sort_custom(func(a, b): return Economy.level_of(a) > Economy.level_of(b))
			for h in ids.slice(0, need):
				var guard := 0
				while Economy.level_of(h) < lv and guard < 40:
					guard += 1
					var n := lv - Economy.level_of(h)
					await _gold_for(tag, func(): return Economy.levelup_block(h, n))
					if Economy.levelup_block(h, n) != "":
						_check(false, tag + " %s can level to %d" % [h, lv], Economy.levelup_block(h, n))
						break
					Economy.level_up(h, n)
					await _settle()
		"mission_claim":
			await _settle()
			Missions.fetch()
			await _frames(30)
			var claimed := false
			for mm in Missions.list("daily"):
				if Missions.can_claim(mm):
					claimed = Missions.claim(str(mm.id))
					break
			_check(claimed, tag + " a daily mission is claimable (the card says 영웅 레벨업 5회 is done)", str(Missions.list("daily").map(func(x): return [x.id, Missions.progress(x)])))
		"growth":
			await _gold_for(tag, func(): return "not_enough" if Economy.gold < GameData.upgrade_cost("atk", int(Economy.upgrades.get("atk", 0))) else "")
			Economy.growth_up("atk", 1)
		"growth_lv":
			var sid := str(m.arg[0])
			var n := int(m.arg[1]) - int(Economy.upgrades.get(sid, 0))
			if n > 0:
				var cost := 0
				for l in range(int(Economy.upgrades.get(sid, 0)), int(m.arg[1])):
					cost += GameData.upgrade_cost(sid, l)
				await _gold_for(tag, func(): return "not_enough" if Economy.gold < cost else "")
				Economy.growth_up(sid, n)
		"gacha":
			Economy.gacha(10, GameData.GACHA_TICKET)
		"deploy_new":
			var starters: Array = GameData.config_list("starter_heroes").map(func(x): return str(x))
			var fresh := ""
			for h in Economy.heroes:
				if not str(h) in starters:
					fresh = str(h)
					break
			_check(fresh != "", tag + " a newly recruited hero exists", str(Economy.heroes.keys()))
			if fresh != "":
				var d: Array = Economy.deploy.duplicate()
				d[0] = fresh
				Economy.set_deploy(d)
		"auto_deploy":
			var hp = _main._tutorial_ui.tabs.windows.get("hero")
			if not hp.is_open():
				_main._tutorial_ui.tabs.press("hero")
				await _frames(5)
			hp.auto_deploy()
			hp.apply()
		"shop_free":
			Economy.buy_shop("d_free")
		"train":
			if Economy.train_block("barracks", 1) == "not_enough":
				_info("%s the previous reward does not cover training 1 infantry" % tag)
			Economy.start_training("barracks", 1)
		"soldier_deploy":
			await _wait_until(func(): return Economy.training("barracks").ready or Economy.training("barracks").count == 0, 15.0)
			if Economy.training("barracks").ready:
				Economy.collect_training("barracks")
				await _settle()
			Economy.set_soldier_deploy(Economy.auto_deploy())
		"dungeon":
			await _dungeon(str(m.arg), tag)
		"equip":
			var done := false
			for it in Economy.items():
				for h in Economy.deploy:
					if not done and h is String and Economy.equip_block(h, str(it.slot), int(it.id)) == "":
						done = Economy.equip(h, str(it.slot), int(it.id))
			_check(done, tag + " an item from the dungeon can be equipped", str(Economy.items().size()))
		"research":
			if Economy.research_block(Tutorial.RESEARCH_ID) in ["not_enough_resources", "not_enough_gold"]:
				_info("%s the previous reward does not cover research %s (%s)" % [tag, Tutorial.RESEARCH_ID, Economy.research_block(Tutorial.RESEARCH_ID)])
				await _request("/v1/test/levels", {"res": _plus(Economy.research_cost(Tutorial.RESEARCH_ID))})
				await _request("/v1/test/grant_gold", {"amount": maxi(1, int(Economy.research_cost(Tutorial.RESEARCH_ID).get("gold", 0)))})
			Economy.start_research(Tutorial.RESEARCH_ID)
		"guild":
			var gname := "가이드%d" % (randi() % 10000)  # 같은 서버에 여러 번 돌려도 이름이 겹치지 않게
			if Guild.create_block(gname) == "골드가 부족합니다":
				await _request("/v1/test/grant_gold", {"amount": Guild.CREATE_GOLD})
			_check(Guild.create(gname, 0), tag + " create a guild", Guild.create_block(gname))
			await _wait_until(func(): return Guild.joined(), 10.0)
		"guild_attend":
			Guild.attend()
			await _wait_until(func(): return Guild.me.get("attended", false) == true, 10.0)
			if Guild.donate_block("gold") != "":
				await _request("/v1/test/grant_gold", {"amount": 1000000})
			Guild.donate("gold")
			await _wait_until(func(): return not Dictionary(Guild.me.get("donations", {})).is_empty(), 10.0)
		"promote":
			var h := str(Economy.deploy[0])
			await _request("/v1/test/shards", {"hero_id": h, "shards": 500})
			await _request("/v1/test/grant_gold", {"amount": 5000000})
			_check(Economy.promote_block(h) == "" and Economy.promote(h), tag + " promote %s" % h, Economy.promote_block(h))
		"guild_boss":
			_boss_run = {}
			_check(Guild.start_boss(), tag + " start the guild boss", Guild.boss_block())
			await _wait_until(func(): return not _boss_run.is_empty(), 10.0)
			_check(not Tutorial.complete(), tag + " only starting the fight does not complete the mission (the server counts finished fights)", "")
			# 전투 장면이 끝나 스스로 결과를 보낼 때까지(서버는 BOSS_FIGHT_SEC / 최대 배속보다 이른 결과를 받지 않는다)
			if not await _wait_until(func(): return Tutorial.complete(), 60.0) and not _boss_run.is_empty():
				Guild.finish_boss(str(_boss_run.get("run_id", "")), 1.0)
				await _wait_until(func(): return Tutorial.complete(), 10.0)
			await _leave_scene()
		"siege_try":
			_sim(tag, "practice siege not played (scene) — Tutorial.note(\"siege_try\")")
			Tutorial.note("siege_try")
		"pvp":
			Pvp.fetch()
			await _wait_until(func(): return not Pvp.opponent("duel").is_empty(), 10.0)
			var team: Array = Pvp.default_team("duel")
			_check(Pvp.start("duel", team), tag + " start a PVP duel", Pvp.start_block("duel", team))
			await _wait_until(func(): return str(Pvp.battle.get("id", "")) != "", 10.0)
			await _frames(30)
			Pvp.finish(false, 10.0)
			await _frames(30)
			await _leave_scene()
		"fever":
			_sim(tag, "FEVER gauge filled directly")
			Fever.gauge = Fever.kills_needed()
			_check(Fever.start(), tag + " FEVER starts", "")
		_:
			_check(false, tag + " no handler for kind " + kind, "")
	await _settle()


func _dungeon(type: String, tag: String) -> void:
	await _settle()
	var party: Array = Economy.default_party(type)
	var helper := ""
	if type == "ticket":
		await _request_get_dungeons()
		var hs: Array = Economy.helper_candidates()
		helper = str(hs[0].get("key", hs[0].get("hero_id", ""))) if not hs.is_empty() else ""
		party = Economy.default_party("gold").filter(func(x): return x != helper).slice(0, GameData.party_size(type))  # 도우미와 겹치지 않게(main._dev_dungeon과 같다)
	var keys := int(Economy.dungeon_state(type).keys)
	_check(keys >= 1, tag + " the previous reward gave a %s key (%d)" % [type, keys], "")
	var started := []
	var cb := func(r): started.append(r)
	Economy.dungeon_started.connect(cb)
	_check(Economy.start_dungeon(type, 1, party, helper), tag + " start %s dungeon 1" % type, Economy.dungeon_block(type, 1, party, helper if type == "ticket" else null))
	await _wait_until(func(): return not started.is_empty(), 10.0)
	Economy.dungeon_started.disconnect(cb)
	await _frames(20)
	Economy.debug_win()
	await _wait_until(func(): return int(Economy.dungeon_state(type).best_level) >= 1, 15.0)
	await _frames(20)
	await _leave_scene()


func _request_get_dungeons() -> void:
	_resp_done = false
	Net.send("GET", "/v1/dungeon", null, func(d):
		if Economy.has_method("apply_dungeons"):
			Economy.apply_dungeons(d)
		_resp_done = true, func(): _resp_done = true)
	await _wait_until(func(): return _resp_done, 10.0)


## 던전·PVP·보스 장면에서 성으로 돌아온다.
func _leave_scene() -> void:
	if _main._dungeon != null:
		_main.leave_dungeon()
	await _frames(10)


## 반복 퀘스트 n개: 카드 → 목표 → [보상 받기] → 서버 비교(서버는 quest_repeat_min_sec 간격만 받는다).
func _repeats(n: int) -> void:
	for k in n:
		var q: Dictionary = Tutorial.mission()
		var tag := "(rep%d %s)" % [Tutorial.rep_n + 1, str(q.get("kind", "?"))]
		var card = _child(CardScript)
		await _frames(2)
		var reward: Dictionary = Tutorial.repeat_reward(q)
		_check(Tutorial.repeating() and card.panel.visible and card.step_label.text == "반복 퀘스트 %d" % (Tutorial.rep_n + 1) and str(q.title) in card.title_label.text
			and card.reward_label.text == "보상: " + Tutorial.reward_text(reward) and not reward.is_empty(), tag + " card", "%s | %s | %s" % [card.step_label.text, card.title_label.text, card.reward_label.text])
		# 2026-10-14: 카드는 서버가 센 진행을 보인다(앱이 따로 세던 기준이 어긋나 「1-2 클리어」가 ✓인데 받아지지 않았다)
		var sr: Dictionary = Economy.server_quest.get("rep", {})
		_check(not sr.is_empty() and int(sr.have) < int(sr.need) and not Tutorial.complete()
			and (str(q.kind) != "stage" or int(q.arg) == int(sr.from) + 1)
			and (int(sr.need) <= 1 or str(q.kind) == "stage" or Tutorial.progress_text() == "%d/%d" % [int(sr.have), int(sr.need)]),
			tag + " card shows the server's progress and isn't done yet", "rep=%s progress=%s q=%s" % [sr, Tutorial.progress_text(), q])
		await _repeat_satisfy(q, tag)
		var done := await _wait_until(func(): return Tutorial.complete(), 20.0)
		_check(done, tag + " target reached", "count=%d progress=%s q=%s" % [Tutorial.count, Tutorial.progress_text(), q])
		if not done:
			return
		await _close_all()
		await _settle()
		var wait := float(GameData.config_num("quest_repeat_min_sec")) + 1.0
		await get_tree().create_timer(wait).timeout  # 서버 간격(지난 받기 이후)
		var s0 := _state()
		var rn := Tutorial.rep_n
		card = _child(CardScript)
		_notes.clear()
		card.action_button.pressed.emit()
		var bad := _added(s0, _state(), reward, false)
		_check(bad.is_empty(), tag + " reward shows at once", str(bad))
		var moved := await _wait_until(func(): return Tutorial.rep_n == rn + 1 and not Economy.quest_waiting(), 15.0)
		await _settle()
		_check(moved and not _notes.has(EconomyScript.ROLLBACK_TEXT), tag + " server accepted", "rep_n=%d notes=%s" % [Tutorial.rep_n, _notes])
		if not moved:
			return
		var p := await _server()
		bad = _added(s0, _state_of(p), reward, true)
		_check(bad.is_empty(), tag + " server paid the same reward", str(bad))
		await _diff(tag)


func _repeat_satisfy(q: Dictionary, tag: String) -> void:
	var n := int(q.get("arg", 1))
	match str(q.kind):
		"kill":
			_sim(tag, "kills via events")
			await _request("/v1/test/events", {"events": {"kill": n}})
			Tutorial.note("kill", n)
		"collect":
			for i in n:
				await _request("/v1/test/age", {"minutes": 2})
				Economy.collect("lumber", Economy.time_now())
				await _settle()
		"stage":
			_sim(tag, "stage via hook")
			await _request("/v1/test/stage", {"stage": maxi(Economy.server_stage, int(q.arg) + 1) + 2})
			GameState.stage = Economy.server_stage
			Tutorial.note_stage(Economy.server_stage)
		"growth_up":
			await _request("/v1/test/grant_gold", {"amount": 10000000})
			for i in n:
				Economy.growth_up("hp", 1)
				await _settle()
		"sell":
			Economy.sell("wood", Economy.time_now(), 10)
		"hero_up":
			await _request("/v1/test/grant_gold", {"amount": 50000000})
			var h = Economy.deploy[0]
			for i in n:
				Economy.level_up(h, 1)
				await _settle()
		"gacha":
			await _request("/v1/test/grant_gold", {"amount": 50000000})
			Economy.gacha(10, GameData.GACHA_GOLD)
		"dungeon_win":
			await _dungeon("gold", tag)
		"build_up":
			await _request("/v1/test/levels", {"res": {"wood": 90000000, "stone": 90000000, "food": 90000000}})
			Economy.upgrade("houses", Economy.time_now())
			await _settle()
			await _request("/v1/test/build_now", {})
	await _settle()


# --- 상태 비교 ---

func _state() -> Dictionary:
	var keys := {}
	for t in GameData.DUNGEON_TYPES:
		keys[t] = int(Economy.dungeon_state(t).keys)
	return {"wood": int(Economy.res.get("wood", 0)), "stone": int(Economy.res.get("stone", 0)), "food": int(Economy.res.get("food", 0)),
		"gold_tenths": Economy.gold_tenths, "diamonds": Economy.diamonds, "tickets": Economy.dia_tickets, "keys": keys}


func _state_of(p: Dictionary) -> Dictionary:
	var keys := {}
	for t in GameData.DUNGEON_TYPES:
		keys[t] = int(p.dungeons.get(t, {}).get("keys", 0)) if p.get("dungeons") is Dictionary else 0
	return {"wood": int(p.res.wood), "stone": int(p.res.stone), "food": int(p.res.food), "gold_tenths": int(p.gold_tenths), "diamonds": int(p.diamonds),
		"tickets": int(p.dia_tickets), "keys": keys}


## s1 == s0 + reward 인가(keys = 열쇠도 본다 — 열쇠는 응답 때 반영). 다른 것 목록.
func _added(s0: Dictionary, s1: Dictionary, r: Dictionary, keys: bool) -> Array:
	var bad := []
	for k in ["wood", "stone", "food"]:
		if s1[k] != s0[k] + int(r.get(k, 0)):
			bad.append("%s %d+%d≠%d" % [k, s0[k], int(r.get(k, 0)), s1[k]])
	if s1.gold_tenths != s0.gold_tenths + int(r.get("gold", 0)) * 10:
		bad.append("gold_tenths %d+%d≠%d" % [s0.gold_tenths, int(r.get("gold", 0)) * 10, s1.gold_tenths])
	if s1.diamonds != s0.diamonds + int(r.get("diamonds", 0)):
		bad.append("diamonds %d+%d≠%d" % [s0.diamonds, int(r.get("diamonds", 0)), s1.diamonds])
	if s1.tickets != s0.tickets + int(r.get("tickets", 0)):
		bad.append("tickets %d+%d≠%d" % [s0.tickets, int(r.get("tickets", 0)), s1.tickets])
	if keys:
		for t in GameData.DUNGEON_TYPES:
			if s1.keys[t] != s0.keys[t] + int(r.get("keys_" + t, 0)):
				bad.append("keys_%s %d+%d≠%d" % [t, s0.keys[t], int(r.get("keys_" + t, 0)), s1.keys[t]])
	return bad


func _diff(tag: String) -> void:
	await _settle()
	var p := await _server()
	if p.is_empty():
		_check(false, tag + " client == server", "no reply")
		return
	var bad := []
	var a := _state()
	var b := _state_of(p)
	for k in a:
		if a[k] != b[k]:
			bad.append("%s %s/%s" % [k, a[k], b[k]])
	if int(p.quest.tut_step) != Tutorial.step and Tutorial.active():
		bad.append("tut_step %d/%d" % [Tutorial.step, int(p.quest.tut_step)])
	if int(p.quest.rep_n) != Tutorial.rep_n:
		bad.append("rep_n %d/%d" % [Tutorial.rep_n, int(p.quest.rep_n)])
	for h in p.heroes:
		if Economy.level_of(h) != int(p.heroes[h].level) or int(Economy.heroes.get(h, 0)) != int(p.heroes[h].copies):
			bad.append("hero %s" % h)
	for u in p.upgrades:
		if int(Economy.upgrades.get(u, 0)) != int(p.upgrades[u]):
			bad.append("upgrade %s %s/%s" % [u, Economy.upgrades.get(u, 0), p.upgrades[u]])
	for k in GameData.building_keys():
		if int(Economy.levels.get(k, 1)) != int(p.buildings.get(k, {}).get("level", 1)):
			bad.append("level %s" % k)
	if p.unbuilt.size() != Economy.unbuilt.size():
		bad.append("unbuilt %s/%s" % [Economy.unbuilt.keys(), p.unbuilt])
	_check(bad.is_empty(), tag + " client == server", str(bad))


# --- 도구 ---

func _sim(tag: String, what: String) -> void:
	print("SIM %s %s" % [tag, what])


func _info(s: String) -> void:
	_infos.append(s)
	print("INFO " + s)


## block()이 골드 부족이면 그만큼 골드를 준다(가이드 보상만으로 모자란 골드 미션 — INFO). 처치 골드가 꺼져 있다.
func _gold_for(tag: String, block: Callable) -> void:
	var why: String = block.call()
	if why in ["not_enough", "not_enough_gold", "골드 부족"] or why == EconomyScript.NO_GOLD_TEXT:
		_info("%s gold from rewards alone is short (kills give gold in real play): gold %d" % [tag, Economy.gold])
		await _request("/v1/test/grant_gold", {"amount": 20000000})
		await _settle()


func _plus(cost: Dictionary) -> Dictionary:
	var out := {}
	for r in ["wood", "stone", "food"]:
		out[r] = int(Economy.res.get(r, 0)) + int(cost.get(r, 0))
	return out


func _target_node(key: String):
	var t = Tutorial.ui_targets.get(key)
	return t.node if t != null and is_instance_valid(t.node) else null


func _open_windows() -> Array:
	return get_tree().get_nodes_in_group(UiWindowScript.GROUP).filter(func(w): return w.is_open())


func _close_all() -> void:
	var placement = _child(PlacementScript)
	if placement != null and placement.is_active():
		placement.cancel()
	for w in _open_windows():
		w.close()
	if _main._picker.building_panel.visible:
		_main._picker.building_panel.close()
	await _frames(5)


func _settle() -> void:
	await _wait_until(func(): return Economy._hold == 0 and Economy._waiting.is_empty() and Economy._predicts.is_empty() and not Economy.quest_waiting(), 15.0)
	await _frames(3)


func _server() -> Dictionary:
	_resp = null
	_resp_done = false
	Net.send("GET", "/v1/player", null, func(d): _resp = d; _resp_done = true, func(): _resp_done = true)
	await _wait_until(func(): return _resp_done, 15.0)
	return _resp.player if _resp is Dictionary and _resp.get("player") is Dictionary else {}


func _request(path: String, body) -> void:
	_resp_done = false
	Net.send("POST", path, body, func(d):
		if d.has("player"):
			Economy.apply_server(d)
		_resp_done = true, func(): _resp_done = true)
	await _wait_until(func(): return _resp_done, 15.0)
	await _frames(3)
	await _refind()


func _refind() -> void:
	if not is_instance_valid(_main) or _main.is_queued_for_deletion() or (_main.get_parent() == null and _main._dungeon == null):
		await _world("world rebuilt")


func _world(what: String) -> bool:
	var ok := await _wait_until(func():
		var m = _current_main()
		return Net.ready_once and m != null and m.camera != null and m._picker != null, 30.0)
	_check(ok, what, "ready=%s up=%s" % [Net.ready_once, Net.up])
	if not ok:
		return false
	_main = _current_main()
	await _frames(3)
	GameData._config.fx_shake = "0"
	for c in _main.get_children():
		if c.get_script() == SpawnerScript:
			c.set_process(false)  # 처치 골드가 보상·골드 비교를 흔들지 않게(처치 미션은 사건 수로)
	for m in get_tree().get_nodes_in_group("monsters"):
		m.queue_free()
	return true


func _current_main():
	for c in get_children():
		if c.get_script() == MainScript and not c.is_queued_for_deletion():
			return c
	return _main if is_instance_valid(_main) and not _main.is_queued_for_deletion() else null


func _child(script):
	if is_instance_valid(_main) and _main.get_parent() == null and _main._dungeon == null:
		_main = _current_main()
	for c in _main.get_children():
		if c.get_script() == script:
			return c
	return null


func _finish() -> void:
	if _fails > 0:
		print("JOURNEY GUIDE ONLINE FAILED %d" % _fails)
		get_tree().quit(1)
	else:
		print("JOURNEY GUIDE ONLINE PASSED")
		get_tree().quit(0)


func _check(ok: bool, what: String, detail: String) -> void:
	print(("PASS " if ok else "FAIL ") + what + ("" if ok else "  " + detail))
	if not ok:
		_fails += 1


func _sheet() -> void:
	var out := "/tmp/journey_guide_online.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	if _shots.is_empty() or _shots[0] == null:
		return
	var w: int = _shots[0].get_width() / 2
	var h: int = _shots[0].get_height() / 2
	var sheet := Image.create(w * _shots.size(), h, false, Image.FORMAT_RGB8)
	for i in _shots.size():
		var img: Image = _shots[i]
		img.convert(Image.FORMAT_RGB8)
		img.save_png(out.get_basename() + "_%d.png" % (i + 1))
		img.resize(w, h, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(img, Rect2i(0, 0, w, h), Vector2i(w * i, 0))
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
