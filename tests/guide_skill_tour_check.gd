extends Node
## 가이드 스킬 자동·수동 설명(2026-10-23, 사용자 "가이드에도 반영했어?" — 영웅 터치 조작 스레드의 [스킬 AUTO]·스킬 칸):
## 「골드 던전」 미션에서 첫 던전 전투가 시작되면 게임을 멈추고 [스킬 AUTO] 버튼 → 초상화 위 스킬 칸 순서로 짚는다.
## 성 화면 대기 중에는(버튼이 숨어 있어) 뜨지 않는다.
## 실행: xvfb-run -a godot --path . --resolution 720x1280 res://tests/guide_skill_tour_check.tscn  (마지막 줄 GUIDE SKILL TOUR PASSED)
##   -- --shot=<png 경로>: 설명 두 단계를 나란히 저장한다

const PreloaderScript := preload("res://scripts/preloader.gd")
const GuideTour := preload("res://scripts/guide_tour.gd")
const GameData := preload("res://scripts/game_data.gd")

var _fails := 0


func _ready() -> void:
	Economy.save_path = ""
	Fever.save_path = ""
	Guild.save_path = ""
	GuildWar.save_path = ""
	Party.save_path = ""
	await _frames(2)
	Tutorial.save_path = ""
	Economy.reset(Time.get_unix_time_from_system())
	Tutorial.begin(true)
	Tutorial.step = Tutorial.mission_index("dungeon_gold")
	Tutorial.tours_seen = {"dungeon": true, "dungeon_form": true}
	Tutorial.tours_on = true
	PreloaderScript.done = true
	add_child(preload("res://scenes/main.tscn").instantiate())
	await _frames(60)
	_check(not _tour_is("skill"), "castle idle: no skill tour (the button is hidden there)", _tour_id())
	for h in GameData.heroes():  # 그 미션쯤이면 모집으로 영웅이 늘어 있다(스타터 4명은 골드 던전 편성 인원보다 적다)
		if Economy.heroes.size() >= GameData.party_size("gold"):
			break
		Economy.heroes[str(h.id)] = 1
	_check(Economy.start_dungeon("gold", 1, Economy.default_party("gold")), "start gold dungeon 1 (offline)", Economy.dungeon_block("gold", 1, Economy.default_party("gold")))
	var t0 := Time.get_ticks_msec()
	while not _tour_is("skill") and Time.get_ticks_msec() - t0 < 10000:
		await get_tree().process_frame
	_check(_tour_is("skill") and get_tree().paused, "dungeon battle: the skill tour starts and pauses the battle", "tour=%s paused=%s" % [_tour_id(), get_tree().paused])
	if not _tour_is("skill"):
		return _finish()
	var shots: Array = []
	for i in 2:
		await _frames(6)
		var at: String = Tutorial.tour_node.steps[i].at
		_check(GuideTour.resolve(at, get_tree()) != null, "step %d points at %s on screen" % [i + 1, at], "no rect")
		shots.append(get_viewport().get_texture().get_image())
		Tutorial.tour_node.next()
	await _frames(6)
	_check(not _tour_is("skill") and not get_tree().paused and Tutorial.tours_seen.has("skill"), "after the last step the battle runs again; shown once", "paused=%s" % get_tree().paused)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			var w: int = shots[0].get_width() / 2
			var h: int = shots[0].get_height() / 2
			var out := Image.create(w * 2, h, false, Image.FORMAT_RGBA8)
			for i in 2:
				shots[i].convert(Image.FORMAT_RGBA8)
				shots[i].resize(w, h, Image.INTERPOLATE_LANCZOS)
				out.blit_rect(shots[i], Rect2i(0, 0, w, h), Vector2i(i * w, 0))
			out.save_png(a.substr(7))
	_finish()


func _tour_is(id: String) -> bool:
	return _tour_id() == id


func _tour_id() -> String:
	return str(Tutorial.tour_node.id) if Tutorial.tour_node != null and is_instance_valid(Tutorial.tour_node) else ""


func _finish() -> void:
	get_tree().paused = false
	print("GUIDE SKILL TOUR %s" % ("PASSED" if _fails == 0 else "FAILED %d" % _fails))
	get_tree().quit(0 if _fails == 0 else 1)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _check(ok: bool, what: String, detail: String) -> void:
	print(("PASS " if ok else "FAIL ") + what + ("" if ok else "  " + detail))
	if not ok:
		_fails += 1
