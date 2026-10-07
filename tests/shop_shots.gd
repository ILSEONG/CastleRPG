extends Node
## 상점 화면 스냅샷(개발용): 실제 main 씬에서 하단 [상점]과 오른쪽 아래 메뉴([길드])를 찍어 한 장으로 붙인다.
## 화면이 필요하다. 실행: xvfb-run -a godot --path . --resolution 720x1280 res://tests/shop_shots.tscn -- --out=/tmp/shop.png [--more]
## --more: PVP 상점·가방·출석 이벤트도 찍는다(3열로 한 줄 더).
## 저장 파일은 건드리지 않는다(오프라인, save_path = "").

var _main
var _shots: Array = []


func _ready() -> void:
	Economy.save_path = ""
	Fever.save_path = ""
	Guild.save_path = ""
	Tutorial.save_path = ""
	Economy.reset(Time.get_unix_time_from_system())
	Tutorial.state = "skipped"
	_main = preload("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await _frames(90)
	Economy.diamonds = 500
	Economy.gold = 20000
	Economy.changed.emit()
	var side = _find("res://scripts/side_menu.gd")
	side.set_open(true)
	await _frames(20)
	await _snap()
	side.set_open(false)
	GameState.stage = 60  # 성장 패스: 1-10·1-25·2-25(50) 단계까지 깬 상태
	var tabs = _find("res://scripts/tab_bar.gd")
	tabs.press("shop")
	var shop = tabs.windows.shop
	await _snap()
	shop._pick("pass")
	await _snap()
	shop.buttons["growth:0:free"].pressed.emit()
	await _frames(4)
	shop._pick("daily")
	shop.buttons["buy:d_free"].pressed.emit()
	await _frames(4)
	await _snap()
	shop._pick("weekly")
	await _snap()
	shop._pick("diamond")
	await _snap()
	if "--more" in OS.get_cmdline_user_args():  # PVP 상점·가방·출석 이벤트(그린 상점 그림이 쓰이는 다른 창)
		shop._pick("pvp")
		await _snap()
		shop.visible = false
		Economy.pouches = {"gold_60": 2, "res_60": 1, "gold_360": 1, "res_360": 3}
		Economy.changed.emit()
		side.pick("bag")
		await _snap()
		side.windows.bag.visible = false
		side.pick("event")
		var ev = side.windows.event  # 오프라인이라 서버 표 대신 출석 1~2주차 보상(server/src/attendance.ts REWARDS 앞 14개)을 넣어 그린다
		ev.data = {"n": 3, "can_claim": true, "rewards": [{"gold": 10000, "pouch_gold_30": 1}, {"tickets": 5}, {"wood": 5000, "stone": 5000, "food": 5000, "pouch_res_30": 1},
			{"diamonds": 100}, {"keys_equip": 2}, {"gold": 30000, "pouch_gold_60": 1}, {"equip": {"grade": "SR"}, "tickets": 5}, {"gold": 20000, "pouch_gold_60": 1},
			{"tickets": 5}, {"keys_gold": 3}, {"diamonds": 150}, {"wood": 10000, "stone": 10000, "food": 10000, "pouch_res_60": 1}, {"keys_ticket": 2},
			{"hero": "luna", "tickets": 10}]}
		ev._rebuild()
		await _snap()
	var out := "/tmp/shop.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	var w: int = _shots[0].get_width() / 2
	var h: int = _shots[0].get_height() / 2
	var sheet := Image.create(w * 3, h * ((_shots.size() + 2) / 3), false, Image.FORMAT_RGB8)
	for i in _shots.size():
		var img: Image = _shots[i]
		img.convert(Image.FORMAT_RGB8)
		img.resize(w, h, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(img, Rect2i(0, 0, w, h), Vector2i((i % 3) * w, (i / 3) * h))
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
	for c in _main.get_children():
		if c.get_script() != null and c.get_script().resource_path == path:
			return c
	return null
