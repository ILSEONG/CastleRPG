extends Node
## 헤드리스 파티 퀘스트 체크(오프라인): 던전 시트 [파티] 탭 → [매칭 시작] → AI 성주 확인 창 → [입장 수락] → 리치·거미 여왕 전투를 끝까지 돌리고
## 스킬이 다 나왔는지, 결과·보상(반지·목걸이)·하루 보상 수·다음 난이도 열림을 본다. 그다음 방장·꼭두각시 두 장면을 한 트리에 띄워
## 스냅샷만으로 꼭두각시가 방장을 따라가는지(졸개 생성·체력·끝) 본다.
## 실행: godot --headless --path . res://tests/party_check.tscn [-- --diff=N --quest=lich|spider --runs=K]  (time_scale 8)

const GameData := preload("res://scripts/game_data.gd")
const PartyRules := preload("res://scripts/party_rules.gd")
const BattleScript := preload("res://scripts/party_battle.gd")

class ErrorCounter extends Logger:
	var count := 0
	func _log_error(_fn: String, _file: String, _line: int, _code: String, _why: String, _notify: bool, error_type: int, _bt: Array[ScriptBacktrace]) -> void:
		if error_type != ERROR_TYPE_WARNING:
			count += 1

var _fails := 0
var _errors := ErrorCounter.new()
var _main
var _args := {}


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails += 1


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _ready() -> void:
	OS.add_logger(_errors)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			_args[a.substr(2).get_slice("=", 0)] = a.get_slice("=", 1)
	Economy.save_path = ""
	Fever.save_path = ""
	Fever.reset()
	GameData._config.fx_shake = "0"
	Economy.reset(Time.get_unix_time_from_system())
	Party.save_path = ""
	Party.picks = {}
	Party._local = {}
	Party.auto_accept = false
	Party.view = {"quests": Party._local_quests(), "queue": {"state": "idle"}}
	for h in GameData.heroes():
		Economy.heroes[str(h.id)] = 1
	var lv := int(_args.get("level", "60"))
	for h in GameData.heroes():
		Economy.hero_levels[str(h.id)] = lv
	Economy.soldiers = {"infantry:%s" % _args.get("tier", "5"): 8, "archer:%s" % _args.get("tier", "5"): 8}
	if _args.has("quest"):
		await _sim(str(_args.quest), int(_args.get("diff", "1")), int(_args.get("runs", "3")))
	else:
		_main = preload("res://scenes/main.tscn").instantiate()
		add_child(_main)
		await _frames(5)
		await _run()
		await _mirror()
	if _errors.count > 0:
		print("PARTY SCRIPT ERRORS %d" % _errors.count)
	_fails += _errors.count
	if _fails > 0:
		print("PARTY FAILED %d" % _fails)
		get_tree().quit(1)
	else:
		print("PARTY ALL PASSED")
		get_tree().quit(0)


func _battle():
	for c in get_children():
		if c.get_script() == BattleScript and not c.is_queued_for_deletion():
			return c
	return null


func _run() -> void:
	var panel = null
	for c in _main.get_children():
		if c.get_script() == preload("res://scripts/dungeon_panel.gd"):
			panel = c
	_check(panel != null, "dungeon panel found")
	panel.open()
	await _frames(2)
	panel.set_section("party")
	await _frames(2)
	var view = panel.party_tab
	_check(view.visible, "[파티] tab shows the party view")
	_check(view.buttons["diff:lich:2"].text.contains("잠김"), "normal is locked before easy is cleared")
	# 리치: 매칭 → 확인 창 → 수락 → 전투
	for quest in ["lich", "spider"]:
		view.buttons["start:" + quest].pressed.emit()
		view.buttons["start:" + quest].pressed.emit()  # 빠른 두 번 탭
		await _frames(2)
		_check(Party.state() == "queued", "%s: queued at once" % quest)
		_check(view.buttons["start:" + quest].disabled, "%s: start button off while matching" % quest)
		var overlay = Party.get_child(0)
		_check(overlay.bar.visible, "%s: matching bar shows" % quest)
		await get_tree().create_timer(PartyRules.CONFIRM_SEC * 0.0 + 2.5).timeout
		_check(Party.state() == "confirm", "%s: AI lords filled the party (confirm)" % quest)
		_check(overlay.dim.visible and Party.queue().seats.size() == PartyRules.SEATS[quest], "%s: accept window with %d seats" % [quest, PartyRules.SEATS[quest]])
		overlay.accept_button.pressed.emit()
		overlay.accept_button.pressed.emit()
		await _frames(4)
		var b = _battle()
		_check(b != null and b.quest == quest, "%s: battle scene opened" % quest)
		if b == null:
			return
		_check(b.boss != null and b.boss.is_alive(), "%s: boss up" % quest)
		_check(b.player_units().size() == (4 if quest == "lich" else 12), "%s: party units %d" % [quest, b.player_units().size()])
		if quest == "spider":  # 성주마다 병사 옷 색이 다르고, 한 성주의 4마리는 같다
			var by_seat := {}
			for s in b.soldiers:
				by_seat[s.owner_seat] = by_seat.get(s.owner_seat, []) + [s.outfit]
			var ok := by_seat.size() == 3
			for k in by_seat:
				ok = ok and by_seat[k].all(func(c): return c == PartyRules.SEAT_COLORS[k] and c.a > 0.0)
			_check(ok, "spider: each lord's 4 soldiers wear that seat's outfit color")
		Engine.time_scale = 8.0
		var t := 0.0
		while not b.done and t < 260.0:
			await get_tree().process_frame
			t += get_process_delta_time()
		Engine.time_scale = 1.0
		print("  %s: done %s win %s clock %.1f boss %.0f%% casts %s" % [quest, b.done, b.result.get("win"), b.clock, b.boss_hp_ratio() * 100.0, b.boss.casts if is_instance_valid(b.boss) else "-"])
		_check(b.done, "%s: battle ended" % quest)
		var casts: Dictionary = b.boss.casts if is_instance_valid(b.boss) else {}
		var want := ["bolt", "ring", "raise", "curse", "harvest"] if quest == "lich" else ["web", "lunge", "brood", "acid"]
		for k in want:
			if b.clock > 45.0:  # 아주 강한 파티는 스킬을 다 보기 전에 끝낸다
				_check(int(casts.get(k, 0)) > 0, "%s: skill %s used (%d)" % [quest, k, int(casts.get(k, 0))])
		await _frames(3)
		_check(not b.result.get("pending", false), "%s: result came back" % quest)
		if b.result.get("win", false):
			var items: Array = b.result.get("rewards", {}).get("items", [])
			_check(items.size() == 1 and items[0].slot == PartyRules.ACCESSORY[quest], "%s: one %s reward" % [quest, PartyRules.ACCESSORY[quest]])
			_check(Party.best(quest) == 1 and Party.clears_left(quest) == PartyRules.REWARD_CLEARS - 1, "%s: easy cleared, %d rewards left" % [quest, Party.clears_left(quest)])
		b.hud.result_layer.visible = true
		b.leave()
		await _frames(4)
		_check(_battle() == null, "%s: back to the castle" % quest)
	# 자동 수락
	Party.set_auto_accept(true)
	view.buttons["start:lich"].pressed.emit()
	await get_tree().create_timer(2.6).timeout
	await _frames(4)
	_check(_battle() != null, "auto accept: battle opens without tapping")
	var b2 = _battle()
	if b2 != null:
		b2.hud._on_leave()
		await get_tree().create_timer(0.5, true, false, true).timeout  # 실제 0.5초(배속 무관)
		b2.hud._on_leave()
		await _frames(4)
		_check(_battle() == null and Party.state() == "idle", "forfeit leaves and frees the queue")
	Party.set_auto_accept(false)


## 방장 장면과 꼭두각시 장면: 꼭두각시는 스냅샷만 받는다.
func _mirror() -> void:
	for quest in ["lich", "spider"]:
		var run := {"quest": quest, "diff": 1, "seed": 7, "time_limit": 180.0, "boss": PartyRules.boss_stats(quest, 1), "me": 0, "run_id": "local-run",
			"seats": _seats(quest), "online": false}
		var host = BattleScript.new()
		host.run = run.duplicate(true)
		get_tree().root.add_child(host)
		var pup = BattleScript.new()
		var r2 := run.duplicate(true)
		r2.me = 1
		pup.run = r2
		get_tree().root.add_child(pup)
		pup.set_role("puppet")
		pup.hud.visible = false
		Engine.time_scale = 4.0
		var t := 0.0
		var most := 0
		var gap := 0.0
		while t < 60.0:
			await get_tree().process_frame
			t += get_process_delta_time()
			if host.snapshot_due():
				var s: Dictionary = JSON.parse_string(JSON.stringify(host.snapshot()))  # 실제 전송처럼 JSON을 거친다
				pup.apply_snapshot(s)
				most = maxi(most, pup.monsters.size())
				gap = 0.0
				for u in host.player_units():
					var p = pup.units_by_uid.get(u.uid)
					if p != null:
						gap = maxf(gap, Vector2(p.global_position.x - u.global_position.x, p.global_position.z - u.global_position.z).length())
		Engine.time_scale = 1.0
		var hm: int = host.monsters.values().filter(func(m): return is_instance_valid(m) and m.is_alive()).size()
		var pm: int = pup.monsters.values().filter(func(m): return is_instance_valid(m) and m.is_alive()).size()
		print("  mirror %s: host monsters %d puppet %d (max %d) unit gap %.2f m boss %.2f / %.2f" % [quest, hm, pm, most, gap, host.boss_hp_ratio(), pup.boss_hp_ratio()])
		_check(absi(hm - pm) <= 3, "%s mirror: puppet has the host's monsters" % quest)
		_check(gap < 2.5, "%s mirror: puppet units follow the host (%.2f m)" % [quest, gap])
		_check(absf(host.boss_hp_ratio() - pup.boss_hp_ratio()) < 0.08, "%s mirror: boss HP follows" % quest)
		_check(pup.phase == pup.Phase.FIGHT, "%s mirror: puppet left the intro" % quest)
		host.queue_free()
		pup.queue_free()
		await _frames(3)


func _seats(quest: String) -> Array:
	var out := []
	var ids: Array = GameData.heroes().map(func(h): return str(h.id))
	for i in PartyRules.SEATS[quest]:
		var s := {"name": "성주%d" % i, "bot": i > 0, "me": i == 0, "accepted": true}
		if quest == "lich":
			var id: String = ids[i * 3 % ids.size()]
			var e: Dictionary = GuildWar.hero_entry(id)
			s.hero = {"hero": id, "level": Economy.level_of(id), "promotion": 0, "hp": e.hp, "atk": e.atk}
		else:
			var so := []
			for k in 4:
				var type := "infantry" if k < 2 else "archer"
				var st := GameData.soldier_stats(type, int(_args.get("tier", "5")))
				so.append({"type": type, "tier": int(_args.get("tier", "5")), "hp": st.hp, "atk": st.atk})
			s.soldiers = so
		out.append(s)
	return out


## 밸런스 시뮬: 장면 하나로 runs판 돌려 승률·걸린 시간을 찍는다.
func _sim(quest: String, diff: int, runs: int) -> void:
	await _frames(2)
	var wins := 0
	var times := []
	for r in runs:
		var run := {"quest": quest, "diff": diff, "seed": 100 + r, "time_limit": PartyRules.TIME_LIMIT[quest], "boss": PartyRules.boss_stats(quest, diff),
			"me": 0, "run_id": "local-run", "seats": _seats(quest), "online": false}
		var b = BattleScript.new()
		b.run = run
		get_tree().root.add_child(b)
		Engine.time_scale = 8.0
		var t := 0.0
		while not b.done and t < 400.0:
			await get_tree().process_frame
			t += get_process_delta_time()
		Engine.time_scale = 1.0
		var win: bool = b.result.get("win", false)
		wins += 1 if win else 0
		times.append(snappedf(b.clock, 0.1))
		print("  sim %s diff %d run %d: win %s clock %.1f boss %.0f%% alive %d casts %s" % [quest, diff, r, win, b.clock, b.boss_hp_ratio() * 100.0, b.player_units().size(), b.boss.casts if is_instance_valid(b.boss) else "-"])
		b.queue_free()
		await _frames(3)
	print("SIM %s diff %d: %d/%d wins, clocks %s" % [quest, diff, wins, runs, times])
