extends Node
## 헤드리스 스킬 수동 체크(사용자 2026-10-23): 실제 main 씬 스테이지에서
##  (1) [스킬 AUTO]를 끄면 쿨이 찬 액티브가 저절로 나가지 않고 칸에서 기다린다(준비됨),
##  (2) 그 칸을 실제로 누르면(마우스) 영웅이 곧바로 쓰고, 고른 영웅은 풀리지 않는다, 쿨이 도는 칸을 누르면 아무 일 없다,
##  (3) 다시 켜면 저절로 나간다, (4) 스킬 칸 누르는 곳이 넉넉하다(5명이면 칸마다 55×65 px 안팎, 예전 지름 24 px).
## 실행: godot --headless --path . res://tests/skill_manual_check.tscn

const HeroStrip := preload("res://scripts/hero_strip.gd")
const SkillAuto := preload("res://scripts/skill_auto_button.gd")
const SpawnerScript := preload("res://scripts/spawner.gd")
const MonsterScript := preload("res://scripts/monster.gd")
const HeroSkills := preload("res://scripts/hero_skills.gd")

class ErrorCounter extends Logger:
	var count := 0
	func _log_error(_fn: String, _file: String, _line: int, _code: String, _why: String, _notify: bool, error_type: int, _bt: Array[ScriptBacktrace]) -> void:
		if error_type != ERROR_TYPE_WARNING:
			count += 1

var _fails := 0
var _errors := ErrorCounter.new()
var _main
var _strip


func _ready() -> void:
	OS.add_logger(_errors)
	Economy.save_path = ""
	Fever.save_path = ""
	Fever.reset()
	Economy.reset(Time.get_unix_time_from_system())
	for h in preload("res://scripts/game_data.gd").heroes().slice(0, 5):
		Economy.heroes[h.id] = 1
	get_window().size = Vector2i(360, 640)
	var was_auto := SkillAuto.is_auto()
	_main = preload("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await _frames(5)
	for c in _main.get_children():
		if c.get_script() == SpawnerScript:
			c.set_process(false)
	for m in get_tree().get_nodes_in_group("monsters"):
		m.queue_free()
	GameState.start_stage()
	await _frames(30)
	_strip = _main._strip
	await _run()
	SkillAuto.set_auto(was_auto)
	_fails += _errors.count
	if _errors.count > 0:
		print("SKILL SCRIPT ERRORS %d" % _errors.count)
	print("SKILL FAILED %d" % _fails if _fails > 0 else "SKILL ALL PASSED")
	get_tree().quit(1 if _fails > 0 else 0)


func _run() -> void:
	_check(_strip.visible and _strip.cells.size() >= 2, "strip shows the heroes (%d)" % _strip.cells.size())
	# 누를 수 있는 액티브(쿨 스킬)를 가진 영웅
	var h = null
	var k := ""
	var slot_i := -1
	for c in _strip.cells:
		var slots: Array = c.hero.active_slots()
		for i in slots.size():
			if not slots[i].locked and String(slots[i].kind) in HeroSkills.ACTIVE:
				h = c.hero
				k = slots[i].kind
				slot_i = i
				break
		if h != null:
			break
	_check(h != null, "found a hero with an unlocked active (%s %s)" % [h.def.id if h else "-", k])
	if h == null:
		return
	var btn: Button = _slot_button(h, slot_i)
	_check(btn != null and btn.mouse_filter == Control.MOUSE_FILTER_STOP, "skill slot is a tappable button")
	_check(btn.size.x >= 50.0 and btn.size.y >= 56.0, "skill slot tap area is large (%s, was a 24 px circle)" % btn.size)
	var auto_btn = null
	for c in _main.get_children():
		if c.get_script() == SkillAuto:
			auto_btn = c
	_check(auto_btn != null and auto_btn.button.visible, "[스킬 AUTO] button shows over the portrait row")
	if auto_btn != null:
		_check(auto_btn.button.get_global_rect().end.y <= _strip.row.global_position.y, "[스킬 AUTO] sits above the portraits")
	# (1) 수동: 적을 붙여 두고 쿨을 채워도 저절로 안 나간다
	SkillAuto.set_auto(false)
	var m = MonsterScript.new()
	m.setup("grunt", 0, 1, h.castle, 50.0)
	_main.add_child(m)
	m.global_position = h.global_position + Vector3(1.0, 0.0, 1.0) * 0.8
	m.global_position.y = 0.0
	m.set_process(false)
	h._skx._cd[k] = 0.05
	await _frames(60)
	_check(h._skx.cd_left(k) <= 0.0 and float(h.active_slots()[slot_i].left) <= 0.0, "manual: a ready skill waits in its slot (cd %.2f)" % h._skx.cd_left(k))
	# (2) 칸을 실제로 누르면 쓴다 — 고른 영웅은 그대로
	_main._picker._select(h)
	await _click(btn.get_global_rect().get_center())
	_check(_main._picker.selected == h, "tapping a skill slot keeps the hero selected")
	var cast := false
	for i in 90:
		if h._skx.cd_left(k) > 1.0:
			cast = true
			break
		await _frames(1)
	_check(cast, "manual: tapping the slot casts the skill (cd now %.1f)" % h._skx.cd_left(k))
	var cd_after: float = h._skx.cd_left(k)
	_check(not HeroStrip.tap_slot(h, slot_i), "tapping a cooling slot does nothing")
	await _frames(2)
	_check(not h._skill_req.has(k) and h._skx.cd_left(k) <= cd_after, "cooling slot tap leaves no pending cast")
	# 빠른 연타: 준비된 칸을 두 번 눌러도 한 번
	h._skx._cd[k] = 0.0
	_check(HeroStrip.tap_slot(h, slot_i) and not HeroStrip.tap_slot(h, slot_i), "double tap on a ready slot asks once")
	await _frames(60)
	# (3) 자동으로 되돌리면 저절로 나간다
	SkillAuto.set_auto(true)
	h._skx._cd[k] = 0.05
	var auto_cast := false
	for i in 120:
		await _frames(1)
		if h._skx.cd_left(k) > 1.0:
			auto_cast = true
			break
	_check(auto_cast, "auto: the skill fires on its own again")
	# 수동인데 쓸 수 없으면(적 없음) 잠시 뒤 취소된다
	SkillAuto.set_auto(false)
	m.queue_free()
	for mm in get_tree().get_nodes_in_group("monsters"):
		mm.queue_free()
	await _frames(3)
	h._skx._cd[k] = 0.0
	HeroStrip.tap_slot(h, slot_i)
	await get_tree().create_timer(h.SKILL_REQ_SEC + 0.5).timeout
	_check(not h._skill_req.has(k) and h._skx.cd_left(k) <= 0.0, "manual: a tap with no enemy near expires and keeps the skill ready")
	SkillAuto.set_auto(true)


func _slot_button(h, i: int) -> Button:
	for c in _strip.cells:
		if c.hero == h:
			return c.cell.find_child("Skill%d" % i, true, false) as Button
	return null


func _click(pos: Vector2) -> void:
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = pos
		ev.global_position = pos
		get_viewport().push_input(ev, true)
	await _frames(3)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
		await get_tree().process_frame


func _check(cond: bool, what: String, detail := "") -> void:
	if cond:
		print("SKILL PASS: " + what)
	else:
		_fails += 1
		print("SKILL FAIL: %s (%s)" % [what, detail])
