extends Node
## 헤드리스 PVP 체크(오프라인): 던전 시트 PVP 탭 → 모드 페이지 → 결투·총력전을 끝까지 돌리고 결과·점수·코인·판 수와 상점 구매를 확인한다.
## 실행: godot --headless --path . res://tests/pvp_check.tscn   (time_scale 8로 빨리 돌린다)

const GameData := preload("res://scripts/game_data.gd")
const PvpRules := preload("res://scripts/pvp_rules.gd")

class ErrorCounter extends Logger:
	var count := 0
	func _log_error(_fn: String, _file: String, _line: int, _code: String, _why: String, _notify: bool, error_type: int, _bt: Array[ScriptBacktrace]) -> void:
		if error_type != ERROR_TYPE_WARNING:
			count += 1

var _fails := 0
var _errors := ErrorCounter.new()
var _main
var _ended := {}


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails += 1


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _ready() -> void:
	OS.add_logger(_errors)
	Economy.save_path = ""
	Fever.save_path = ""
	Fever.reset()
	GameData._config.fx_shake = "0"
	Economy.reset(Time.get_unix_time_from_system())
	Pvp.save_path = ""
	Pvp.load_save()
	for h in GameData.heroes():
		Economy.heroes[str(h.id)] = 1
	Economy.soldiers = {"infantry:2": 8, "archer:1": 10, "cavalry:3": 6}
	_main = preload("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await _frames(5)
	await _run()
	if _errors.count > 0:
		print("PVP SCRIPT ERRORS %d" % _errors.count)
	_fails += _errors.count
	if _fails > 0:
		print("PVP FAILED %d" % _fails)
		get_tree().quit(1)
	else:
		print("PVP ALL PASSED")
		get_tree().quit(0)


func _run() -> void:
	Pvp.fetch()
	_check(not Pvp.view.is_empty(), "offline view built")
	_check(Pvp.plays_left("duel") == PvpRules.PLAYS and Pvp.plays_left("total") == PvpRules.PLAYS, "5 plays each mode")
	_check(Pvp.opponent("duel").get("heroes", []).size() == 5, "duel opponent has 5 heroes")
	_check(PvpRules.soldier_count(Pvp.my_soldiers()) == PvpRules.SOLDIER_CAP, "soldiers capped at 20")
	# 던전 시트 PVP 탭
	var panel = null
	for c in _main.get_children():
		if c.get_script() == preload("res://scripts/dungeon_panel.gd"):
			panel = c
	_check(panel != null, "dungeon panel found")
	if panel != null:
		panel.open()
		await _frames(2)
		panel.set_section("pvp")
		await _frames(2)
		_check(panel.pvp.visible, "PVP tab shows the PVP view")
		panel.pvp.open_mode("duel")
		await _frames(2)
		panel.pvp.open_mode("total")
		await _frames(2)
		panel.pvp.show_home()
		panel.close()
		await _frames(2)
	Pvp.result_ready.connect(func(r): _ended = r)
	Engine.time_scale = 8.0
	for m in ["duel", "total"]:
		var pts := Pvp.points(m)
		var coins := Pvp.coins()
		var team := Pvp.default_team(m)
		_ended = {}
		_check(Pvp.start(m, team), "%s start accepted" % m)
		_check(Pvp.plays_left(m) == PvpRules.PLAYS - 1, "%s play used instantly" % m)
		var t := 0.0
		while _ended.is_empty() and t < 200.0:
			await get_tree().create_timer(0.5, true, false, true).timeout
			t += 0.5
		_check(not _ended.is_empty(), "%s battle ended (%.0f s real)" % [m, t])
		if not _ended.is_empty():
			var exp_pts := pts - PvpRules.loss_of(pts) + (int(Pvp.battle.loss) + int(Pvp.battle.gain) if _ended.win else 0)
			_check(Pvp.points(m) == exp_pts, "%s points %d → %d (%s)" % [m, pts, Pvp.points(m), "win" if _ended.win else "loss"])
			_check(Pvp.coins() == coins + (PvpRules.COINS_WIN if _ended.win else PvpRules.COINS_LOSS), "%s coins +%d" % [m, Pvp.coins() - coins])
			_check(Pvp.defense(m).size() == 5, "%s first team became defense" % m)
		_main.leave_dungeon()
		await _frames(3)
		Pvp.fetch()
	Engine.time_scale = 1.0
	# 상점
	Pvp.local.coins = 1000
	Pvp.fetch()
	var gold := Economy.gold
	_check(Pvp.buy("gold") == "", "buy gold allowed")
	await _frames(2)
	_check(Pvp.coins() == 1000 - 60, "coins deducted 60")
	_check(Economy.gold > gold, "gold granted")
	for i in 2:
		Pvp.buy("gold")
	await _frames(2)
	_check(Pvp.buy_block("gold") != "", "daily limit 3 reached")
