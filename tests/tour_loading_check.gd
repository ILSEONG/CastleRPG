extends Node
## 첫 포커스 설명은 로딩 화면이 걷힌 뒤에(사용자 2026-10-18 "이게 게임 로딩창일때부터 떠" — 「성 화면 둘러보기」 1/12가 로딩 화면 위에 떴다).
## 새 게임(가이드 1번)으로 main을 띄우고 첫 로딩 화면(preloader.gd)을 실제로 돌린다. 로딩 화면이 있는 동안 설명이 뜨면 실패,
## 로딩 화면이 걷힌 뒤 설명이 뜨면 통과.
## 실행: xvfb-run -a godot --path . --resolution 720x1280 res://tests/tour_loading_check.tscn  (마지막 줄 TOUR LOADING PASSED)

const PreloaderScript := preload("res://scripts/preloader.gd")

var _fails := 0


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
	Tutorial.tours_on = true  # 실제 게임처럼 포커스 설명을 띄운다
	PreloaderScript.done = false  # 첫 실행처럼 로딩 화면을 띄운다
	add_child(preload("res://scenes/main.tscn").instantiate())
	var loading_seen := false
	var over_loading := 0
	var after := -1.0
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 60000:
		await get_tree().process_frame
		var loading := get_tree().get_first_node_in_group(PreloaderScript.GROUP) != null
		loading_seen = loading_seen or loading
		var tour := Tutorial.tour_node != null and is_instance_valid(Tutorial.tour_node)
		if tour and loading:
			over_loading += 1
		if tour and not loading:
			after = (Time.get_ticks_msec() - t0) / 1000.0
			break
	_check(loading_seen, "the first loading screen showed", "")
	_check(over_loading == 0, "no guide tour over the loading screen", "%d frames with the tour on top" % over_loading)
	_check(after > 0.0 and str(Tutorial.tour_node.id) == "intro", "the first tour (성 화면 둘러보기) starts once the loading screen is gone", "after=%.1f s" % after)
	for i in 30:  # 화면 기록(--write-movie)에 설명이 뜬 성 화면이 남게
		await get_tree().process_frame
	print("TOUR LOADING %s" % ("PASSED" if _fails == 0 else "FAILED %d" % _fails))
	get_tree().quit(0 if _fails == 0 else 1)


func _check(ok: bool, what: String, detail: String) -> void:
	print(("PASS " if ok else "FAIL ") + what + ("" if ok else "  " + detail))
	if not ok:
		_fails += 1
