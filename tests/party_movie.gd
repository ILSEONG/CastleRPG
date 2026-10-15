extends Node
## 파티 퀘스트 시연 영상(개발용, 오프라인 — AI 성주와 함께): [파티] 탭 → [매칭 시작] → AI 성주가 빈자리를 채움 → [입장 수락] → 전투 끝까지.
## 보스가 스킬을 쓸 때마다 아래에 자막을 단다. 화면이 필요하다(--write-movie와 함께):
##   xvfb-run -a godot --path . --resolution 720x1280 --write-movie /tmp/lich.avi --fixed-fps 30 res://tests/party_movie.tscn -- --quest=lich
## --quest=lich|spider, --tier=3(병사 티어), --speed=1.5(전투 배속 — 영상 길이). 저장 파일은 건드리지 않는다.

const GameData := preload("res://scripts/game_data.gd")
const BattleScript := preload("res://scripts/party_battle.gd")
const FONT := preload("res://assets/fonts/Pretendard-SemiBold.otf")

const SKILL_TEXT := {
	"bolt": "영혼 화살: 성주들의 영웅에게 유도 화살 3발",
	"ring": "죽음의 고리: 빨간 원이 터지기 전에 밖으로 피하세요",
	"raise": "망자 소환: 해골 병사 4마리가 일어납니다",
	"curse": "저주의 늪: 독 장판 + 받는 피해 20% 증가",
	"harvest": "영혼 수확: 리치 무적! 12초 안에 수정 3개를 모두 깨세요",
	"web": "거미줄: 2명을 3초 묶고 느리게 합니다",
	"lunge": "도약: 가장 많이 모인 곳으로 뛰어들어 독을 뿌립니다",
	"brood": "알 낳기: 8초 안에 못 깨면 거미 부하 4마리가 부화합니다",
	"acid": "산성 비: 원 6개가 예고된 뒤 떨어집니다",
}

var _main
var _quest := "lich"
var _speed := 1.5
var _tier := 3
var _caption: Label
var _cap_left := 0.0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--quest="):
			_quest = a.substr(8)
		elif a.begins_with("--tier="):
			_tier = int(a.substr(7))
		elif a.begins_with("--speed="):
			_speed = float(a.substr(8))
	Economy.save_path = ""
	Fever.save_path = ""
	Guild.save_path = ""
	Tutorial.save_path = ""
	Party.save_path = ""
	Party.auto_accept = false
	Economy.reset(Time.get_unix_time_from_system())
	Tutorial.state = "skipped"
	for h in GameData.heroes():
		Economy.heroes[str(h.id)] = 1
		Economy.hero_levels[str(h.id)] = 25
	Economy.soldiers = {"infantry:%d" % _tier: 8, "archer:%d" % _tier: 8}
	_main = preload("res://scenes/main.tscn").instantiate()
	add_child(_main)
	var layer := CanvasLayer.new()
	layer.layer = 40
	_caption = Label.new()
	_caption.add_theme_font_override("font", FONT)
	_caption.add_theme_font_size_override("font_size", 32)
	_caption.add_theme_color_override("font_color", Color(1.0, 0.95, 0.75))
	_caption.add_theme_color_override("font_outline_color", Color(0.1, 0.08, 0.05))
	_caption.add_theme_constant_override("outline_size", 10)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption.position = Vector2(20, 990)
	_caption.size = Vector2(680, 110)
	layer.add_child(_caption)
	add_child(layer)
	await _wait(2.0)
	var tabs = _find("res://scripts/tab_bar.gd")
	tabs.press("dungeon")
	var panel = tabs.windows.dungeon
	panel.set_section("party")
	_say("던전 → [파티] 탭: %s" % ("리치의 무덤 (성주 4명 · 영웅 1명씩)" if _quest == "lich" else "거미 여왕의 둥지 (성주 3명 · 병사 4마리씩)"))
	await _wait(2.5)
	panel.party_tab._start(_quest)
	_say("[매칭 시작] — 시험 중이라 AI 성주가 바로 빈자리를 채웁니다")
	while Party.state() != "confirm":
		await get_tree().process_frame
	_say("모두 [입장 수락]을 눌러야 시작합니다")
	await _wait(2.5)
	Party.accept(true)
	var b = null
	while b == null:
		await get_tree().process_frame
		b = _battle()
	_say("")
	var seen := {}
	while not b.done:
		if b.phase == b.Phase.FIGHT:
			Engine.time_scale = _speed
		if is_instance_valid(b.boss):
			for k in b.boss.casts:
				if int(b.boss.casts[k]) > int(seen.get(k, 0)):
					seen[k] = int(b.boss.casts[k])
					if SKILL_TEXT.has(k):
						_say(SKILL_TEXT[k], 3.5)
		if _cap_left > 0.0:
			_cap_left -= get_process_delta_time() / maxf(Engine.time_scale, 0.01)
			if _cap_left <= 0.0:
				_say("")
		await get_tree().process_frame
	Engine.time_scale = 1.0
	_say("승리! 보상: %s" % ("반지" if _quest == "lich" else "목걸이") if b.result.get("win", false) else "")
	await _wait(4.5)
	print("MOVIE %s win %s clock %.1f casts %s" % [_quest, b.result.get("win"), b.clock, seen])
	get_tree().quit()


func _say(t: String, sec := 0.0) -> void:
	_caption.text = t
	_cap_left = sec


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout


func _battle():
	for c in get_children():
		if c.get_script() == BattleScript and not c.is_queued_for_deletion():
			return c
	return null


func _find(path: String) -> Node:
	for c in _main.get_children():
		if c.get_script() != null and c.get_script().resource_path == path:
			return c
	return null
