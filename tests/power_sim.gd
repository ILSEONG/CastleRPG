extends Node
## 영웅 실제 화력 측정(개발용, 헤드리스): 아레나에서 영웅 혼자, 움직이지도 때리지도 않는 허수아비를 SEC초 동안 친다.
## single = HP 무한 허수아비 1마리, group = HP GROUP_HP 허수아비 6마리(쓰러지면 0.5초 뒤 같은 자리에 다시).
## 실행: godot --headless --fixed-fps 30 --path . res://tests/power_sim.tscn -- --level=50 --promo=5 --sec=60 [--only=ignis,rian]

const GameData := preload("res://scripts/game_data.gd")
const HeroScript := preload("res://scripts/hero.gd")
const MonsterScript := preload("res://scripts/monster.gd")

const GROUP_HP := 2500.0
const DIST := 6.0

var _dummies: Array = []  # [monster, 자리]
var _dealt := 0.0


func _ready() -> void:
	Economy.save_path = ""
	Fever.save_path = ""
	GameData._config.fx_shake = "0"
	var level := int(_arg("level", "50"))
	var promo := int(_arg("promo", "5"))
	var sec := float(_arg("sec", "60"))
	var only := _arg("only", "")
	var mode := _arg("mode", "dps")
	for def in GameData.heroes():
		if only != "" and not str(def.id) in only.split(","):
			continue
		if mode == "tank":
			print("TANK %s %s %s %s survive=%.1f" % [def.id, def.name, def.grade, def.role, await _tank(def, level, promo, float(_arg("atk", "50")))])
			continue
		if mode == "team":
			var r := await _team(def, level, promo, sec, float(_arg("atk", "30")))
			print("TEAM %s %s %s %s dmg=%.1f alive=%.1f" % [def.id, def.name, def.grade, def.role, r.x, r.y])
			continue
		var s := await _run(def, level, promo, sec, 1)
		var g := await _run(def, level, promo, sec, 6)
		print("SIM %s %s %s %s single=%.1f group=%.1f" % [def.id, def.name, def.grade, def.role, s / sec, g / sec])
	get_tree().quit()


func _run(def: Dictionary, level: int, promo: int, sec: float, n: int) -> float:
	_dealt = 0.0
	_dummies.clear()
	var h = HeroScript.new()
	h.setup(0, def, null, null, promo, level)
	h.free_pos = Vector3.ZERO
	add_child(h)
	var center := Vector3(DIST, 0, 0)
	for i in n:
		var p := center if n == 1 else center + Vector3(cos(TAU * i / n), 0, sin(TAU * i / n)) * 1.4
		_dummies.append([_spawn(p, 1e12 if n == 1 else GROUP_HP), p])
	var t := 0.0
	var dt := 1.0 / 30.0
	while t < sec:
		await get_tree().process_frame
		t += dt
		for d in _dummies:
			var m = d[0]
			if m != null and not m.is_alive():
				_dealt += m.hp_max
				d[0] = null
				d.append(t + 0.5)
			elif m == null and t >= d[2]:
				d[0] = _spawn(d[1], GROUP_HP)
				d.resize(2)
	for d in _dummies:
		if d[0] != null and d[0].is_alive():
			_dealt += d[0].hp_max - d[0].hp
	for c in get_children():
		c.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	return _dealt


## 탱커: 영웅 혼자 공격하는 grunt 6마리(공격력 atk, 간격 1초, 안 죽음)에 둘러싸여 버틴 초(최대 300).
func _tank(def: Dictionary, level: int, promo: int, atk: float) -> float:
	var h = HeroScript.new()
	h.setup(0, def, null, null, promo, level)
	h.free_pos = Vector3.ZERO
	add_child(h)
	for i in 6:
		_spawn(Vector3(cos(TAU * i / 6), 0, sin(TAU * i / 6)) * 3.0, 1e12, atk, 2.5)
	var t := 0.0
	while t < 300.0 and h.is_alive():
		await get_tree().process_frame
		t += 1.0 / 30.0
	await _clear()
	return t


## 팀: 시험 영웅 + 같은 동료 3명(TEAM_MATE, 같은 레벨·승급) vs 공격하는 grunt 8마리(HP 무한, 공격력 atk).
## x = sec초 동안 팀 전체가 준 피해, y = 네 명이 살아 있던 시간 합(초).
const TEAM_MATE := "dorik"
func _team(def: Dictionary, level: int, promo: int, sec: float, atk: float) -> Vector2:
	var hs := []
	for i in 4:
		var h = HeroScript.new()
		h.setup(i, def if i == 0 else GameData.hero(TEAM_MATE), null, null, promo, level)
		h.free_pos = Vector3(-1.5 + i, 0, 0)
		add_child(h)
		h.global_position = h.free_pos
		hs.append(h)
	var ms := []
	for i in 8:
		ms.append(_spawn(Vector3(8.0 + (i % 2) * 1.5, 0, -3.0 + (i / 2) * 2.0), 1e12, atk, 2.5))
	var t := 0.0
	var alive := 0.0
	while t < sec:
		await get_tree().process_frame
		t += 1.0 / 30.0
		for h in hs:
			if h.is_alive():
				alive += 1.0 / 30.0
	var dmg := 0.0
	for m in ms:
		dmg += m.hp_max - m.hp
	await _clear()
	return Vector2(dmg / sec, alive)


func _clear() -> void:
	for c in get_children():
		c.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _spawn(p: Vector3, hp: float, atk := 0.0, speed := 0.0):
	var row := GameData.monster("grunt").duplicate()
	row.kind = "grunt"
	row.hp = hp
	row.atk = atk
	row.speed = speed
	var m = MonsterScript.new()
	m.setup_arena(row)
	m.position = p
	add_child(m)
	return m


func _arg(k: String, d: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % k):
			return a.substr(k.length() + 3)
	return d
