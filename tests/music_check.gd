extends Node
## 헤드리스 배경음악 체크(2026-10-06): 실제 main 씬(오토로드 Music 포함)에서 테마 고르기·크로스페이드·켬/끔·곡 반복을 확인한다.
## 실행: ./tools/Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/music_check.tscn
## 타이틀(첫 로딩 전) → 방치 → FEVER → 스테이지 → 보스 라운드 → 던전 3종(main._enter_dungeon) → 나가면 성 곡 → 길드 보스·길드전 테마 → 끄기·켜기.

const PreloaderScript := preload("res://scripts/preloader.gd")
const GameData := preload("res://scripts/game_data.gd")
const MusicScript := preload("res://scripts/music.gd")
const SpawnerScript := preload("res://scripts/spawner.gd")

## 곡 길이(초) = dev/music/songs.py의 마디 × 박 × 60 / BPM
const LENGTHS := {"title": 45.71, "idle": 41.54, "fever": 25.6, "stage": 43.64, "boss": 40.0, "dungeon_gold": 48.0,
	"dungeon_equip": 41.74, "dungeon_ticket": 38.4, "dragon": 41.74, "guild_war": 34.29}

const PARTY := ["hans", "ella", "dorik", "nina"]
const GOLD_PARTY := ["hans", "ella", "dorik", "nina", "tia", "jack"]

var _fails := 0
var _main


func _ready() -> void:
	Economy.save_path = ""
	Fever.save_path = ""
	Fever.reset()
	Music.settings_path = ""
	Music.enabled = true
	Economy.reset(Time.get_unix_time_from_system())
	for id in GOLD_PARTY:  # 골드 던전은 6명
		Economy.heroes[id] = maxi(1, int(Economy.heroes.get(id, 0)))
	await _run()
	if _fails > 0:
		print("MUSIC FAILED %d" % _fails)
		get_tree().quit(1)
	else:
		print("MUSIC ALL PASSED")
		get_tree().quit(0)


func _run() -> void:
	# 곡 파일: 모두 OGG, 반복, 길이가 악보와 같다
	for t in MusicScript.TRACKS:
		var s = load(MusicScript.TRACKS[t])
		_check(s is AudioStreamOggVorbis, "track %s loads as OGG" % t, str(s))
		if s is AudioStreamOggVorbis:
			_check(s.loop, "track %s loops" % t, "")
			_check(absf(s.get_length() - LENGTHS[t]) < 0.05, "track %s length matches the score" % t, "%.2f vs %.2f" % [s.get_length(), LENGTHS[t]])
	_check(AudioServer.get_bus_index(MusicScript.BUS) >= 0, "Music bus exists", "")

	PreloaderScript.done = false
	await _wait(0.4)
	_check(Music.theme == "title" and Music.playing_track().ends_with("title.ogg"), "before the first loading finishes: title theme plays", Music.theme + " " + Music.playing_track())

	_main = preload("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await _frames(5)
	for c in _main.get_children():
		if c.get_script() == SpawnerScript:
			c.set_process(false)
	PreloaderScript.done = true
	GameState.mode = GameState.Mode.IDLE
	await _wait(0.4)
	_check(Music.theme == "idle", "idle screen: idle theme", Music.theme)
	await _wait(MusicScript.FADE_SEC + 0.3)
	var on := Music._players.filter(func(p): return p.playing)
	_check(on.size() == 1 and on[0].stream.resource_path.ends_with("idle.ogg") and on[0].volume_db > -0.5,
		"after the crossfade only the idle track plays, at full volume", str(on.map(func(p): return [p.stream.resource_path, p.volume_db])))

	Fever.left = 30.0
	await _wait(0.4)
	_check(Music.theme == "fever", "FEVER on the idle screen: fever theme", Music.theme)
	await _wait(0.3)
	on = Music._players.filter(func(p): return p.playing)
	_check(on.size() == 2, "mid-crossfade both tracks sound", str(on.size()))
	Fever.left = 0.0

	GameState.stage = 3
	GameState.mode = GameState.Mode.STAGE
	await _wait(0.4)
	_check(Music.theme == "stage", "round fight: stage theme", Music.theme)
	GameState.mode = GameState.Mode.COUNTDOWN
	await _wait(0.4)
	_check(Music.theme == "stage", "countdown keeps the stage theme", Music.theme)
	GameState.stage = GameData.rounds_per_stage()
	GameState.mode = GameState.Mode.STAGE
	await _wait(0.4)
	_check(Music.theme == "boss", "boss round (round %d): boss theme" % GameData.rounds_per_stage(), Music.theme)
	GameState.stage = 1
	GameState.mode = GameState.Mode.IDLE

	for type in ["gold", "equip", "ticket"]:
		var helper := ""
		if type == "ticket":
			helper = str(Economy.dungeon_state(type).helpers[0].key)
		var party: Array = GOLD_PARTY if type == "gold" else PARTY
		var started: bool = Economy.start_dungeon(type, 1, party, helper)
		if not started:
			print("dungeon %s did not start: %s" % [type, Economy.dungeon_block(type, 1, party, helper if type == "ticket" else null)])
		await _wait_until(func(): return _main._dungeon != null and _main._dungeon.is_inside_tree(), 3.0)
		await _wait(0.4)
		_check(Music.theme == "dungeon_" + type and Music.playing_track().ends_with("dungeon_%s.ogg" % type),
			"%s dungeon: its own theme" % type, Music.theme + " " + Music.playing_track())
		_main.leave_dungeon()
		await _wait(0.4)
		_check(Music.theme == "idle", "leaving the %s dungeon returns to the castle theme" % type, Music.theme)

	_check(MusicScript.dungeon_theme("gold") == "dungeon_gold" and MusicScript.dungeon_theme("nope") == "dungeon_gold", "dungeon_theme maps types", "")
	Music.override = "dragon"
	await _wait(0.4)
	_check(Music.playing_track().ends_with("dragon.ogg"), "guild dragon boss theme", Music.playing_track())
	Music.override = "guild_war"
	await _wait(0.4)
	_check(Music.playing_track().ends_with("guild_war.ogg"), "guild war theme", Music.playing_track())
	Music.override = ""

	Music.set_enabled(false)
	await _wait(MusicScript.FADE_SEC + 0.3)
	_check(Music._players.all(func(p): return not p.playing), "music off: everything fades out and stops", "")
	Fever.left = 30.0
	await _wait(0.4)
	_check(Music._players.all(func(p): return not p.playing) and Music.theme == "fever", "while off, theme changes stay silent", Music.theme)
	Fever.left = 0.0
	await _wait(0.4)
	Music.set_enabled(true)
	await _wait(0.4)
	_check(Music.playing_track().ends_with("idle.ogg"), "music back on: the current theme plays again", Music.playing_track())
	# 빠르게 왔다 갔다: 줄이던 같은 곡으로 돌아오면 그 플레이어를 다시 키운다(곡이 셋 이상 겹치지 않는다)
	Fever.left = 30.0
	await _wait(0.4)
	Fever.left = 0.0
	await _wait(0.4)
	on = Music._players.filter(func(p): return p.playing)
	_check(on.size() <= 2 and Music.playing_track().ends_with("idle.ogg"), "quick back-and-forth keeps at most two players", str(on.size()))


func _wait(sec: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < sec * 1000.0:
		await get_tree().process_frame


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _wait_until(cond: Callable, timeout: float) -> void:
	var t0 := Time.get_ticks_msec()
	while not cond.call() and Time.get_ticks_msec() - t0 < timeout * 1000.0:
		await get_tree().process_frame


func _check(ok: bool, what: String, detail: String) -> void:
	if ok:
		print("MUSIC PASS: " + what)
	else:
		_fails += 1
		print("MUSIC FAIL: %s (%s)" % [what, detail])
