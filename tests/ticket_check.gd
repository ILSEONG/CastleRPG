extends Node
## 모집권 던전 확인(2026-10-06, 오토로드가 필요해 run_tests 밖): 오프라인 새 게임에서 던전 탭 카드 셋·모집권 편성(도우미 줄) 화면을 찍고,
## 실제 모집권 던전 1단계를 시작해 영웅 5(마지막 = 도우미, 장비 없음)·바위 골렘을 확인한 뒤 전투 장면을 찍는다. 골렘을 쓰러뜨리면 조각 2가 나오고
## 그것까지 쓰러뜨려야 승리 → 결과 화면(다이아 모집권 +1)을 찍는다. 결과는 마지막 줄 "TICKET ok" / "TICKET FAIL …".
## 헤드리스: godot --headless --path . res://tests/ticket_check.tscn
## 스크린샷: xvfb-run -a -s "-screen 0 720x1280x24" godot --path . --rendering-driver opengl3 --resolution 720x1280 res://tests/ticket_check.tscn -- --out=DIR

const GameData := preload("res://scripts/game_data.gd")

var _main
var _out := ""
var _fails: Array = []


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	if _out != "":
		DirAccess.make_dir_recursive_absolute(_out)
	Economy.save_path = ""
	Fever.save_path = ""
	Fever.reset()
	Economy.reset(Time.get_unix_time_from_system())
	for id in ["arteon", "ignis", "selene", "valen", "kyle", "mira"]:
		Economy.heroes[id] = 1
	Economy.dia_tickets = 0
	_main = preload("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await _frames(90)
	var panel = _main.find_children("*", "", true, false).filter(func(n): return n.get_script() == preload("res://scripts/dungeon_panel.gd"))[0]
	panel.open()
	await _frames(30)
	var sc: ScrollContainer = panel.find_children("*", "ScrollContainer", true, false)[0]
	sc.scroll_vertical = 10000  # 모집권 카드(맨 아래)가 보이게
	await _frames(30)
	_check(panel.cards.has("ticket") and panel.cards.ticket.reward.text.contains("다이아 모집권 10장"), "ticket card: %s" % panel.cards.ticket.reward.text)
	await _shot("1_cards")
	panel.open_form("ticket")
	await _frames(20)
	var hs: Array = Economy.helper_candidates()
	_check(hs.size() == 3 and panel.helper_id == hs[0].hero_id and panel.helper_cards.size() == 3 and panel.party.size() == 4 and not panel.party.has(panel.helper_id),
		"form: 4 heroes + helper %s of %s" % [panel.helper_id, hs])
	panel.pick_helper(hs[1].hero_id)
	await _frames(10)
	await _shot("2_form")
	var helper: String = panel.helper_id
	panel.deploy()
	await _frames(40)
	var d = _main._dungeon
	_check(d != null and d.heroes.size() == 5 and d.heroes[4].helper and d.heroes[4].def.id == helper, "scene: 4 heroes + helper %s" % helper)
	var golem = d.boss
	_check(golem != null and golem.kind == "rock_golem" and d.enemies_left() == 3, "rock golem + 2 pieces waiting")
	for i in 150:
		await get_tree().process_frame
	await _shot("3_fight")
	golem.take_damage(golem.hp)
	await _frames(2)
	var pieces: Array = get_tree().get_nodes_in_group("monsters").filter(func(m): return m.kind == "golemite")
	_check(pieces.size() == 2 and d.enemies_left() == 2 and d.phase == d.Phase.FIGHT, "the golem splits into 2 pieces")
	await _frames(30)
	await _shot("4_split")
	d.run.started_at = float(d.run.started_at) - 30.0
	Economy.current_run.started_at = float(Economy.current_run.started_at) - 30.0
	d.clock = maxf(d.clock, 21.0)
	for m in pieces:
		m.take_damage(m.hp)
	for i in 240:
		await get_tree().process_frame
		if d.phase == d.Phase.RESULT:
			break
	_check(d.result.get("win", false) and d.result.rewards == {"tickets": 10} and Economy.dia_tickets == 10
		and Economy.dungeon_state("ticket").helpers_used == [helper], "win: +10 tickets, helper used: %s" % [d.result])
	await _frames(20)
	await _shot("5_result")
	print("TICKET ok" if _fails.is_empty() else "TICKET FAIL %s" % [_fails])
	get_tree().quit(0 if _fails.is_empty() else 1)


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails.append(what)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(name: String) -> void:
	if _out == "" or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))
