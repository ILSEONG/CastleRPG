extends Node
## 던전 보스 평타가 끝나기 전에 끊기는지(2026-10-06): 장비(데스나이트)·모집권(바위 골렘) 던전 1단계를 실제로 돌리며 보스 AnimationPlayer를 프레임마다 본다.
## 공격 모션이 90% 전에 다른 모션으로 바뀌거나 처음부터 다시 돌면 "끊김". 기절은 일부러 끊으므로 뺀다. 끊김 0이면 종료 코드 0.
## env -u DATABASE_URL godot --headless --fixed-fps 30 res://tests/boss_swing_check.tscn -- --type=equip|ticket
const GameData := preload("res://scripts/game_data.gd")
const ATK := ["Attack", "Shoot", "Throw", "Spell"]
var _main

func _is_atk(n: String) -> bool:
	for k in ATK:
		if n.contains(k):
			return true
	return false

func _ready() -> void:
	var type := "equip"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--type="):
			type = a.substr(7)
	Economy.save_path = ""
	Fever.save_path = ""
	Fever.reset()
	Economy.reset(Time.get_unix_time_from_system())
	_main = preload("res://scenes/main.tscn").instantiate()
	add_child(_main)
	for i in 60:
		await get_tree().process_frame
	var helper := ""
	if type == "ticket":
		helper = str(Economy.dungeon_state(type).helpers[0].key)
	print("block ", Economy.dungeon_block(type, 1, Economy.default_party(type), helper if type == "ticket" else null))
	print("start ", Economy.start_dungeon(type, 1, Economy.default_party(type), helper))
	var prev := {}
	var cuts := 0
	var swings := 0
	for f in 30 * 60:
		await get_tree().process_frame
		var d = _main._dungeon
		if d == null or d.boss == null or not is_instance_valid(d.boss):
			continue
		var b = d.boss
		var mdl = b._model
		var ap: AnimationPlayer = mdl._anim
		var cur := String(ap.current_animation)
		var pos := ap.current_animation_position if cur != "" else 0.0
		if prev.has("cur"):
			var pc: String = prev.cur
			if _is_atk(pc):
				var ln := ap.get_animation(pc).length
				if (cur != pc or pos < prev.pos) and prev.pos < ln * 0.9 and not b.is_stunned():
					cuts += 1
					print("CUT f=%d %s at %.2f/%.2f -> %s  tele=%s swing=%.2f" % [f, pc, prev.pos, ln, cur, str(b.is_telegraphing()) if b.has_method("is_telegraphing") else "-", b._swing_left], " stun=", b.is_stunned(), " root=", b._root_t, " knock=", b._knock_t, " tgt=", is_instance_valid(b._target_hero) and b._target_hero.is_alive())
			if _is_atk(cur) and (cur != pc or pos < prev.pos):
				swings += 1
		prev = {"cur": cur, "pos": pos}
		if not b.is_alive():
			break
	print("swings=%d cuts=%d" % [swings, cuts])
	get_tree().quit(0 if cuts == 0 and swings >= 5 else 1)
