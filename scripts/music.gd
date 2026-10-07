extends Node
## 배경음악(2026-10-06). 오토로드 Music. 장면(테마)마다 다른 곡이 끊김 없이 반복되고, 테마가 바뀌면 FADE_SEC 동안 크로스페이드한다.
## 곡은 모두 이 저장소에서 새로 작곡한 것(dev/music/songs.py → assets/audio/music/*.ogg, 출처·라이선스는 docs/music.md).
## 테마는 스스로 고른다(CHECK_SEC마다):
##   override(main.gd가 던전·길드 보스·길드전 장면을 붙일 때 넣고 뗄 때 비운다)가 있으면 그것,
##   첫 로딩이 끝나기 전(로그인·로딩 화면)이면 "title",
##   아니면 성 월드: 방치 = FEVER 중 "fever", 아니면 "idle" / 스테이지·카운트다운·결과 = 보스 라운드(라운드 25) "boss", 아니면 "stage".
## 켬/끔: enabled(앱 로컬 user://settings.json의 music, 기본 켬), 크기: volume(같은 파일 music_volume 0..1, 기본 1)
## — 오른쪽 아래 메뉴 [설정] 창(settings_panel.gd)에서 바꾼다. 같은 파일의 다른 기기 설정(화면 흔들림 등)은 prefs에 담아 함께 쓴다(prefs.gd).
## 히트스톱(Engine.time_scale)에 흔들리지 않게 페이드는 실제 시간으로 잰다.

const PreloaderScript := preload("res://scripts/preloader.gd")
const GameData := preload("res://scripts/game_data.gd")

const TRACKS := {
	"title": "res://assets/audio/music/title.ogg",  # 성의 서막
	"idle": "res://assets/audio/music/idle.ogg",  # 성 아래 마을
	"fever": "res://assets/audio/music/fever.ogg",  # 피버 타임
	"stage": "res://assets/audio/music/stage.ogg",  # 성벽 방어전
	"boss": "res://assets/audio/music/boss.ogg",  # 성문 앞의 거인
	"dungeon_gold": "res://assets/audio/music/dungeon_gold.ogg",  # 고블린 들판
	"dungeon_equip": "res://assets/audio/music/dungeon_equip.ogg",  # 망자의 성채
	"dungeon_ticket": "res://assets/audio/music/dungeon_ticket.ogg",  # 돌의 사원
	"dragon": "res://assets/audio/music/dragon.ogg",  # 화염의 비룡
	"guild_war": "res://assets/audio/music/guild_war.ogg",  # 공성전
}
const BUS := "Music"
const VOLUME_DB := -4.0  # 곡 자체는 RMS −17 dBFS로 맞춰 두었다
const FADE_SEC := 1.2
const CHECK_SEC := 0.25
const SILENT_DB := -60.0

var enabled := true
var volume := 1.0  # 0..1(설정 창 슬라이더). 버스 크기 = VOLUME_DB + linear_to_db(volume)
var override := ""  # 던전·길드 장면 테마(main.gd). 비면 성 월드·타이틀에서 고른다
var theme := ""  # 지금 테마(꺼져 있어도 고른 값)
var settings_path := "user://settings.json"  # ""이면 저장하지 않는다(테스트)
var prefs := {}  # 파일의 나머지 키(prefs.gd가 읽고 쓴다)

var _players: Array[AudioStreamPlayer] = []
var _cur := -1  # 지금 곡을 트는 플레이어(0·1), 없으면 −1
var _fade := {}  # 플레이어 i → {from: 0..1, to: 0..1, t0: 초}
var _check := 0.0
var _streams := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if AudioServer.get_bus_index(BUS) < 0:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, BUS)
		AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = BUS
		p.volume_db = SILENT_DB
		add_child(p)
		_players.append(p)
	load_settings()
	_apply_volume()


func _process(delta: float) -> void:
	_check -= delta
	if _check <= 0.0:
		_check = CHECK_SEC
		set_theme(pick_theme())
	var now := _now()
	for i in _fade.keys():
		var f: Dictionary = _fade[i]
		var k := clampf((now - float(f.t0)) / FADE_SEC, 0.0, 1.0)
		var a := lerpf(float(f.from), float(f.to), k)
		_players[i].volume_db = linear_to_db(maxf(a, 0.001))
		if k >= 1.0:
			_fade.erase(i)
			if a <= 0.0:
				_players[i].stop()


## 지금 장면에 맞는 테마(위 규칙).
func pick_theme() -> String:
	if override != "":
		return override
	if not PreloaderScript.done:
		return "title"
	if GameState.mode == GameState.Mode.IDLE:
		return "fever" if Fever.active() else "idle"
	return "boss" if GameData.is_boss_round(GameState.stage) else "stage"


## 던전 run.type(gold·equip·ticket) → 테마.
static func dungeon_theme(type: String) -> String:
	var t := "dungeon_" + type
	return t if TRACKS.has(t) else "dungeon_gold"


func set_theme(t: String) -> void:
	if t == theme:
		return
	theme = t
	if enabled:
		_switch(t)


func set_enabled(on: bool) -> void:
	if on == enabled:
		return
	enabled = on
	save_settings()
	if on:
		_switch(theme)
	else:
		_switch("")


func toggle() -> void:
	set_enabled(not enabled)


## 크기(0..1)를 바로 바꾼다. save = false면 저장하지 않는다(슬라이더를 끄는 동안 — 손을 떼면 저장).
func set_volume(v: float, save := true) -> void:
	volume = clampf(v, 0.0, 1.0)
	_apply_volume()
	if save:
		save_settings()


func _apply_volume() -> void:
	var bus := AudioServer.get_bus_index(BUS)
	if bus < 0:
		return
	AudioServer.set_bus_volume_db(bus, VOLUME_DB + linear_to_db(maxf(volume, 0.001)))
	AudioServer.set_bus_mute(bus, volume <= 0.0)


## 지금 곡을 줄이고(멈추고) t 곡을 처음부터 키운다. t = ""이면 끄기만.
func _switch(t: String) -> void:
	var old := _cur
	if old >= 0:
		_fade_to(old, 0.0)
	_cur = -1
	if t == "" or not TRACKS.has(t):
		return
	var s := _stream(t)
	if s == null:
		return
	var i := 1 - old if old >= 0 else (1 if _players[0].playing and not _players[1].playing else 0)
	_cur = i
	var p := _players[i]
	if p.playing and p.stream == s:  # 방금 줄이던 같은 곡으로 돌아왔다: 그 자리에서 다시 키운다
		_fade_to(i, 1.0)
		return
	p.stream = s
	p.volume_db = SILENT_DB
	p.play()
	_fade[i] = {"from": 0.0, "to": 1.0, "t0": _now()}


func _fade_to(i: int, to: float) -> void:
	var from := db_to_linear(_players[i].volume_db) if _players[i].playing else 0.0
	_fade[i] = {"from": from, "to": to, "t0": _now()}


func _stream(t: String) -> AudioStream:
	if not _streams.has(t):
		var s = load(TRACKS[t]) if ResourceLoader.exists(TRACKS[t]) else null
		if s is AudioStreamOggVorbis:
			s.loop = true
		_streams[t] = s
	return _streams[t]


## 지금 소리 나는 곡(테스트·디버그): 키워지는 플레이어의 곡 경로, 없으면 "".
func playing_track() -> String:
	if _cur < 0 or not _players[_cur].playing or _players[_cur].stream == null:
		return ""
	return _players[_cur].stream.resource_path


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func load_settings() -> void:
	if settings_path == "" or not FileAccess.file_exists(settings_path):
		return
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(settings_path)) == OK and json.data is Dictionary:
		prefs = json.data.duplicate()
		prefs.erase("music")
		prefs.erase("music_volume")
		enabled = bool(json.data.get("music", true))
		volume = clampf(float(json.data.get("music_volume", 1.0)), 0.0, 1.0)


func save_settings() -> void:
	if settings_path == "":
		return
	var data := prefs.duplicate()
	data["music"] = enabled
	data["music_volume"] = volume
	var f := FileAccess.open(settings_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data))
