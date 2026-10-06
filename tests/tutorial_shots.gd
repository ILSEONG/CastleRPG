extends Node
## 튜토리얼 스냅샷(개발용): 실제 main 씬에서 새 게임 튜토리얼을 진행하며 화면을 찍어 한 장으로 붙인다 —
## 시작(성채만 + 공터 + 미션 카드 + 잠긴 탭) → 공터 건설 창 → 건설 중 → 보상 받기 → 모집권 모집 → 건물을 다 지은 성.
## 화면이 필요하다(헤드리스 불가). 실행: xvfb-run -a godot --path . --resolution 720x1280 res://tests/tutorial_shots.tscn -- --out=/tmp/tutorial.png
## 저장 파일은 건드리지 않는다(Economy·Fever·Guild·Tutorial save_path = "").

var _main
var _shots: Array = []


func _ready() -> void:
	Economy.save_path = ""
	Fever.save_path = ""
	Guild.save_path = ""
	await _frames(2)  # Tutorial._start(테스트 장면이라 건너뜀, save_path = "")
	Tutorial.save_path = ""
	Economy.reset(Time.get_unix_time_from_system())
	Tutorial.begin(true)
	_main = preload("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await _frames(90)
	await _snap()  # 1. 시작
	var bp = _find("res://scripts/building_panel.gd")
	Tutorial.goto_current()  # 성채 창 → 미션 1 완료
	await _frames(30)
	bp.close()
	await _snap()  # 2. 보상 받기
	Tutorial.claim()
	Tutorial.goto_current()  # 벌목장 공터 창
	await _frames(30)
	await _snap()  # 3. 공터 건설 창
	bp.upgrade_button.pressed.emit()
	bp.close()
	await _frames(30)
	await _snap()  # 4. 건설 중(비계)
	Economy.finish_build_now()
	await _frames(20)
	await _snap()  # 5. 다 지음
	Tutorial.claim()
	for id in ["quarry", "farm"]:
		Economy.unbuilt.erase(id)
	Economy.changed.emit()
	Tutorial.check()
	Tutorial.claim()
	Tutorial.claim()
	Tutorial.count = 12
	Tutorial.changed.emit()
	await _frames(10)
	await _snap()  # 6. 처치 미션 진행
	Economy.unbuilt.erase("tavern")
	Tutorial.step = Tutorial.mission_index("gacha")
	Economy.grant({"tickets": 10})
	Tutorial.changed.emit()
	Tutorial.goto_current()
	await _frames(30)
	await _snap()  # 7. 모집권 모집 창
	var rp = _find("res://scripts/recruit_panel.gd")
	rp.ten_button.pressed.emit()  # 모집권이 10장이면 [10회]가 모집권 버튼
	await _frames(30)
	await _snap()  # 8. 결과
	rp.close()
	Economy.unbuilt.clear()
	Economy.changed.emit()
	Tutorial.step = Tutorial.mission_index("keep_2")
	Tutorial.changed.emit()
	await _frames(30)
	await _snap()  # 9. 다 지은 성
	Tutorial.state = "done"
	Tutorial.repeats_on = true
	Tutorial.check()
	Tutorial.changed.emit()
	await _frames(10)
	await _snap()  # 10. 반복 퀘스트
	var out := "/tmp/tutorial.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	var w: int = _shots[0].get_width() / 2
	var h: int = _shots[0].get_height() / 2
	var cols := 5
	var sheet := Image.create(w * cols, h * 2, false, Image.FORMAT_RGB8)
	for i in _shots.size():
		var img: Image = _shots[i]
		img.convert(Image.FORMAT_RGB8)
		img.resize(w, h, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(img, Rect2i(0, 0, w, h), Vector2i((i % cols) * w, (i / cols) * h))
	sheet.save_png(out)
	print("saved ", out, " shots=", _shots.size())
	get_tree().quit()


func _snap() -> void:
	await _frames(8)
	_shots.append(get_viewport().get_texture().get_image())


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _find(path: String) -> Node:
	for n in _main.get_children():
		if n.get_script() != null and n.get_script().resource_path == path:
			return n
	return null
