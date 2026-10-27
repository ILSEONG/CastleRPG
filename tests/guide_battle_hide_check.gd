extends Node
## 스테이지를 미는 동안 가이드를 숨긴다(사용자 2026-10-18 "스테이지 밀때는 가이드 안보이게해줘").
## 새 게임으로 main을 띄운다. 대기에서는 카드·화살표가 보이고, 스테이지·결과·카운트다운 동안은 카드·화살표(버튼·건물 이름표)·
## 포커스 설명이 하나도 안 보여야 한다. 그동안 미션은 계속 세고(1-1 클리어 → ✓), 방치로 돌아오면 카드가 바로 다시 보이고
## 「스테이지 1-2」의 포커스 설명(스테이지 정보)도 그때 뜬다.
## 실행: xvfb-run -a godot --path . --resolution 720x1280 res://tests/guide_battle_hide_check.tscn  (마지막 줄 GUIDE BATTLE HIDE PASSED)
##   -- --shot=<png 경로>: 첫 전투 2초 뒤 화면을 저장한다(전·후 비교용)

const PreloaderScript := preload("res://scripts/preloader.gd")
const GuideTour := preload("res://scripts/guide_tour.gd")

var _fails := 0
var _card: Node
var _shown := {}  # 모드 → 카드·화살표·설명이 보인 프레임 수
var _frames := {}  # 모드 → 지나간 프레임 수


func _ready() -> void:
	Economy.save_path = ""
	Fever.save_path = ""
	Guild.save_path = ""
	GuildWar.save_path = ""
	Party.save_path = ""
	await get_tree().process_frame
	await get_tree().process_frame
	Tutorial.save_path = ""
	Economy.reset(Time.get_unix_time_from_system())
	Tutorial.begin(true)
	Tutorial.tours_seen = {}
	Tutorial.tours_on = false  # 두 번째 전투가 시작되면 켠다
	PreloaderScript.done = true
	add_child(preload("res://scenes/main.tscn").instantiate())
	for i in 30:
		await get_tree().process_frame
	_card = GuideTour.find_script_node(get_tree().root, "res://scripts/tutorial_card.gd")
	# 1) 「스테이지 1-1 클리어」: 전투 중에도 미션을 센다
	_set_mission("stage_1_1")
	GameState.auto_continue = true  # 클리어 뒤 결과 → 카운트다운 → 다음 스테이지까지 본다
	for i in 10:
		await get_tree().process_frame
	_check(GameState.mode == GameState.Mode.IDLE and _card.panel.visible, "idle: the guide card shows", "mode=%d visible=%s" % [GameState.mode, _card.panel.visible])
	_check(_card._target_id != 0, "idle: the guide arrow points at [▶ 진행]", "no arrow")
	GameState.start_stage()
	await _watch(2.0)
	_shot()
	_check(not Tutorial.complete(), "the mission is not done before the clear", "")
	GameState.on_all_monsters_dead()  # 1-1 클리어 → 결과
	_check(Tutorial.complete(), "the mission still counts while the guide is hidden (1-1 cleared → ✓)", "step=%d" % Tutorial.step)
	# 연속 진행이어도 가이드 보상이 준비됐으면 결과 뒤 다음 라운드로 넘어가지 않고 대기(사용자 2026-10-25 "라운드 끝에 멈춤")
	var counted := false
	var t0 := Time.get_ticks_msec()
	while GameState.mode != GameState.Mode.IDLE and Time.get_ticks_msec() - t0 < 10000:
		await _watch(0.0)
		counted = counted or GameState.mode == GameState.Mode.COUNTDOWN
	_check(GameState.mode == GameState.Mode.IDLE and not counted and GameState.auto_continue,
		"with 연속 진행 on and a guide reward ready, the round ends in idle (no countdown to the next round)", "mode=%d countdown=%s" % [GameState.mode, counted])
	var back := -1.0
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 3000:
		await get_tree().process_frame
		if _card.panel.visible:
			back = (Time.get_ticks_msec() - t0) / 1000.0
			break
	_check(back >= 0.0 and back < 0.1, "idle again: the card comes back at once", "after %.2f s" % back)
	_check(_card.title_label.text.begins_with("✓") and _card.action_button.visible, "idle again: the card shows ✓ and [보상 받기]", _card.title_label.text)

	# 2) 「스테이지 1-2 클리어」(포커스 설명 「스테이지 정보」, 초반 단순화 2026-10-23): 전투 중엔 설명이 안 뜨고 방치로 오면 뜬다
	_set_mission("stage_1_2")
	for i in 10:
		await get_tree().process_frame
	_check(_card.panel.visible and _card._target_id != 0, "idle: the card and the [▶ 진행] arrow show", "visible=%s" % _card.panel.visible)
	GameState.start_stage()
	Tutorial.tours_on = true  # 전투 중엔 「성 화면 둘러보기」가 떠선 안 된다
	await _watch(1.0)
	var hold: Callable = GameState.auto_hold
	GameState.auto_hold = Callable()  # 카운트다운 동안 숨김을 보려고 이번만 멈춤을 끈다(멈춤은 1)에서 봤다)
	GameState.on_all_monsters_dead()
	await _cycle()
	GameState.auto_hold = hold
	for m in [GameState.Mode.STAGE, GameState.Mode.RESULT, GameState.Mode.COUNTDOWN]:
		var name: String = GameState.Mode.keys()[m]
		_check(int(_frames.get(m, 0)) > 0, "%s ran" % name, "")
		_check(int(_shown.get(m, 0)) == 0, "%s: no guide card, arrow or tour" % name, "%d of %d frames showed one" % [int(_shown.get(m, 0)), int(_frames.get(m, 0))])
	GameState.stop_stage()
	var tour := ""
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 3000:
		await get_tree().process_frame
		if Tutorial.tour_node != null and is_instance_valid(Tutorial.tour_node):
			tour = str(Tutorial.tour_node.id)
			break
	_check(_card.panel.visible and tour == "stage_info", "idle again: the card shows and the focus tour (스테이지 정보) starts", "visible=%s tour=%s" % [_card.panel.visible, tour])
	for i in 30:  # 화면 기록(--write-movie)에 설명이 뜬 성 화면이 남게
		await get_tree().process_frame
	print("GUIDE BATTLE HIDE %s" % ("PASSED" if _fails == 0 else "FAILED %d" % _fails))
	get_tree().quit(0 if _fails == 0 else 1)


## 클리어 뒤 결과(2초) → 카운트다운(3초) → 다음 스테이지 1초까지 지켜본다.
func _cycle() -> void:
	var t0 := Time.get_ticks_msec()
	while GameState.mode != GameState.Mode.STAGE and Time.get_ticks_msec() - t0 < 15000:
		await _watch(0.0)
	await _watch(1.0)


func _shot() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			get_viewport().get_texture().get_image().save_png(a.substr(7))


func _set_mission(id: String) -> void:
	Tutorial.step = _index(id)
	Tutorial.count = 0
	Tutorial.changed.emit()


## sec초 동안(0이면 한 프레임) 모드마다 카드·버튼 화살표·포커스 설명이 보인 프레임을 센다.
func _watch(sec: float) -> void:
	var t0 := Time.get_ticks_msec()
	while true:
		await get_tree().process_frame
		var m := GameState.mode
		_frames[m] = int(_frames.get(m, 0)) + 1
		var tour := Tutorial.tour_node != null and is_instance_valid(Tutorial.tour_node)
		if _card.panel.visible or _card._target_id != 0 or tour:
			_shown[m] = int(_shown.get(m, 0)) + 1
		if Time.get_ticks_msec() - t0 >= sec * 1000.0:
			return


func _index(id: String) -> int:
	for i in Tutorial.MISSIONS.size():
		if str(Tutorial.MISSIONS[i].id) == id:
			return i
	return -1


func _check(ok: bool, what: String, detail: String) -> void:
	print(("PASS " if ok else "FAIL ") + what + ("" if ok else "  " + detail))
	if not ok:
		_fails += 1
