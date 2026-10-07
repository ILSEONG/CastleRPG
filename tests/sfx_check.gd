extends Node
## 효과음 체크(2026-10-07): 실제 main 씬에서 성 전투를 돌려 평타·타격·처치·스킬 소리가 나는지, 너무 잦지 않은지(초당 상한),
## 버튼 소리, 화면 밖 소리 끔, 효과음 끄기, 보상·승패 신호 소리를 본다. 기기 설정 파일은 건드리지 않는다.
## 실행: godot --headless --path . res://tests/sfx_check.tscn

const Sfx := preload("res://scripts/sfx.gd")
const PreloaderScript := preload("res://scripts/preloader.gd")
const TMP := "user://sfx_check.json"
const BATTLE_SEC := 25.0
const MAX_PER_SEC := 25.0  # 전투 소리 전체 상한(초당) — 이보다 많으면 시끄럽다

var _fails := 0
var _main


func _ready() -> void:
	Economy.save_path = ""
	Fever.save_path = ""
	Fever.reset()
	Music.settings_path = TMP
	Music.prefs = {}
	Economy.reset(Time.get_unix_time_from_system())
	SoundFx.set_enabled(true)
	SoundFx.set_volume(1.0, false)
	await _run()
	if FileAccess.file_exists(TMP):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	if _fails > 0:
		print("SFX FAILED %d" % _fails)
		get_tree().quit(1)
	else:
		print("SFX ALL PASSED")
		get_tree().quit(0)


func _run() -> void:
	PreloaderScript.done = true
	_main = preload("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await _frames(5)
	_check(Sfx.current == SoundFx, "autoload SoundFx is the static current", "")
	_check(AudioServer.get_bus_index(Sfx.BUS) >= 0, "Sfx bus exists", "")

	# 버튼: 트리에 들어온 버튼을 누르면 click
	SoundFx.played.clear()
	var b := Button.new()
	add_child(b)
	await _frames(1)
	b.pressed.emit()
	_check(SoundFx.played.has("click"), "a new button plays click when pressed", str(SoundFx.played))
	b.queue_free()

	# 화면 밖 월드 소리는 내지 않는다
	SoundFx.played.clear()
	Sfx.at("crit", Vector3(5000, 0, 5000))
	_check(not SoundFx.played.has("crit"), "off-screen world sound is skipped", str(SoundFx.played))

	# 전투: 성 스테이지
	SoundFx.played.clear()
	GameState.start_stage()
	var t0 := Time.get_ticks_msec()
	while (Time.get_ticks_msec() - t0) / 1000.0 < BATTLE_SEC:
		await _frames(10)
	var counts := {}
	for id in SoundFx.played:
		counts[id] = int(counts.get(id, 0)) + 1
	print("  battle sounds (last 64): ", counts)
	var all: int = SoundFx.debug_total
	print("  total sounds in %.0f s: %d (%.1f/s)" % [BATTLE_SEC, all, all / BATTLE_SEC])
	_check(counts.has("hit") or counts.has("crit"), "hits make a sound", str(counts))
	_check(counts.has("swing") or counts.has("arrow") or counts.has("bolt") or counts.has("throw"), "attacks make a sound", str(counts))
	_check(SoundFx.debug_ids.has("death"), "kills make a sound", str(SoundFx.debug_ids.keys()))
	_check(SoundFx.debug_ids.keys().any(func(k): return String(k).begins_with("sk_")), "skills make a sound", str(SoundFx.debug_ids.keys()))
	_check(all / BATTLE_SEC <= MAX_PER_SEC, "not more than %d sounds per second" % MAX_PER_SEC, "%.1f/s" % (all / BATTLE_SEC))

	# 보상·승패 신호
	SoundFx.played.clear()
	Economy.leveled.emit("arteon", 2)
	await _frames(1)
	GameState.stage_failed.emit(GameState.stage)
	await _frames(1)
	_check(SoundFx.played.has("level_up") and SoundFx.played.has("defeat"), "level up and defeat play their jingles", str(SoundFx.played))

	# 끄면 아무 소리도 없다(그리고 기기 설정에 남는다)
	SoundFx.set_enabled(false)
	SoundFx.played.clear()
	Sfx.play("reward")
	_check(SoundFx.played.is_empty() and Music.prefs.get("sfx", true) == false, "sound off: nothing plays and the setting is saved", str(SoundFx.played))
	SoundFx.set_enabled(true)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _check(ok: bool, what: String, detail: String) -> void:
	if ok:
		print("  ok   ", what)
	else:
		_fails += 1
		print("  FAIL ", what, "  ", detail)
