extends Node
## 자유 건설 체크(사용자 2026-10-13): 실제 main 씬에서 [건설] 버튼(배속 버튼 아래, [메뉴] 높이) → 건물 목록 → 자리 고르기 → 짓기·옮기기.
## 자리를 안 잡은 공터는 성 안에 안 보이고, 고른 자리에 짓고, 끌어서 옮기면 2 m 격자에 붙고, 길 위면 빨강(버튼 꺼짐)·빈 곳이면 초록,
## 다 지으면 그 자리에 건물·이름표·탭 판정체가 있고 길 막기(Balance.plots)도 따라오는지, 지은 건물 옮기기도 되는지 본다.
## 실행: godot --headless --path . res://tests/build_check.tscn
## 화면: xvfb-run -a godot --path . --resolution 720x1280 res://tests/build_check.tscn -- --out=/tmp/build  (→ _before/_list/_ok/_bad/_after/_moved.png)

const Balance := preload("res://scripts/balance.gd")
const PreloaderScript := preload("res://scripts/preloader.gd")

var _fails := 0
var _main
var _out := ""


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	Economy.save_path = ""
	Fever.save_path = ""
	Fever.reset()
	Tutorial.save_path = ""
	Engine.time_scale = 1.0
	Economy.reset(Time.get_unix_time_from_system())
	for h in preload("res://scripts/game_data.gd").heroes().slice(0, 5):
		Economy.heroes[h.id] = 1
	Economy.start_unbuilt(["keep", "gate", "houses", "tavern"])  # 새 게임처럼 대부분 공터 + 몇 채는 기본 자리
	for r in ["wood", "stone", "food"]:
		Economy.res[r] = 1_000_000
	await _run()
	if _fails > 0:
		print("BUILD FAILED %d" % _fails)
		get_tree().quit(1)
	else:
		print("BUILD ALL PASSED")
		get_tree().quit(0)


func _run() -> void:
	PreloaderScript.done = true
	_main = preload("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await _frames(5)
	Tutorial.state = "done"
	Economy.changed.emit()
	await _frames(5)
	var btn = _find("res://scripts/build_button.gd")
	var list = _find("res://scripts/build_list_panel.gd")
	var pl = _find("res://scripts/placement.gd")
	var scenery = _find("res://scripts/buildings.gd")
	var speed = _find("res://scripts/speed_button.gd")
	var menu = _find("res://scripts/side_menu.gd")
	_check(btn != null and list != null and pl != null, "build button, list and placement exist", "")
	if btn == null or list == null or pl == null:
		return
	var br: Rect2 = btn.button.get_global_rect()
	var tr: Rect2 = menu.toggle.get_global_rect()
	var sr: Rect2 = speed.button.get_global_rect()
	_check(absf(br.end.y - tr.end.y) < 1.0 and br.position.x <= 20.0, "[건설] bottom-left at the [메뉴] height", "%s vs %s" % [br, tr])
	_check(sr.end.y <= br.position.y and not sr.intersects(br), "x1.5 sits right above [건설]", "%s vs %s" % [sr, br])
	_check(scenery.hidden.has("lumber") and not scenery.lots.lumber.mi.visible and scenery.lots.lumber.body == null, "unplaced lot is not shown in the castle", "")
	_check(not scenery.hidden.has("houses") and scenery.lots.houses.mi.visible, "built buildings stay at their default spot", "")
	_check(btn._dot, "red dot: something can be built", "")
	await _shot("_before")

	btn.button.pressed.emit()
	await _frames(1)
	_check(list.is_open() and list.tray.scale.x < 0.5, "tray starts unfolding to the right", str(list.tray.scale))
	await get_tree().create_timer(0.7).timeout
	var tray: Rect2 = list.tray.get_global_rect()
	_check(list.is_open() and is_equal_approx(list.tray.scale.x, 1.0) and tray.position.x >= br.end.x and absf(tray.end.y - br.end.y) < 1.0, "tray unfolds from [건설] to the right", "%s vs %s" % [tray, br])
	_check(list.rows.lumber.action_label.text == "건설" and list.rows.lumber.why == "", "lumber can be built", list.rows.lumber.action_label.text)
	_check(list.rows.houses.action_label.text == "이동", "built building offers [이동]", list.rows.houses.action_label.text)
	_check(not list.rows.has("keep"), "keep is not in the list", "")
	var chat = _find("res://scripts/chat_bar.gd")
	_check(chat == null or not chat.visible, "mini chat hidden while the tray is open", "")
	await _shot("_list")
	btn.button.pressed.emit()
	await get_tree().create_timer(0.4).timeout
	_check(not list.visible and (chat == null or chat.visible), "pressing [건설] again folds it; chat back", "")
	btn.button.pressed.emit()
	await get_tree().create_timer(0.5).timeout

	list.rows.lumber.button.pressed.emit()
	await get_tree().create_timer(0.6).timeout
	_check(not list.visible and pl.is_active() and pl.building_id == "lumber" and not pl.moving, "[건설] starts placing the lumber mill", "")
	_check(pl.ok and Economy.place_block("lumber", pl.cell) == "" and pl._ghost.visible, "starts on a free spot (green)", str(pl.cell))
	_check(pl._plate_mat.albedo_color == pl.OK_COLOR and not pl.confirm_button.disabled, "green plate, [건설] enabled", "")
	_check(pl._floor.visible and pl._floor.mesh != null and pl._floor.mesh.get_surface_count() == 1, "floor tiles show where you can build", "")
	var half := Economy.interior_half_tiles()
	var others: Dictionary = Economy.placed_cells("lumber")
	_check(Balance.rect_block(Rect2i(0, 5, 1, 1), half, others) == "road" and Balance.rect_block(Rect2i(5, 5, 1, 1), half, others) == ""
		and Balance.rect_block(Rect2i(half - 1, 5, 1, 1), half, others) == "out", "tile rules: road red, free floor green, wall lane red", "")
	await _frames(20)
	await _shot("_ok")

	# 끌기: 건물을 잡아 길 위로 → 빨강
	var cam: Camera3D = _main.camera
	var grab := cam.unproject_position(pl._center())
	var road := Vector3(0.0, 0, 13.0)  # 남북 길(x = 0) 위
	await _drag(grab, cam.unproject_position(road))
	_check(Economy.place_block("lumber", pl.cell) == "road" and not pl.ok and pl.confirm_button.disabled, "dragging onto the road: red, [건설] off", "%s %s" % [pl.cell, Economy.place_block("lumber", pl.cell)])
	_check(pl._plate_mat.albedo_color == pl.BAD_COLOR and pl.hint_label.text == Balance.PLACE_TEXT.road, "red plate + reason", pl.hint_label.text)
	_check(Vector2(pl._center().x, pl._center().z).distance_to(Vector2(road.x, road.z)) <= Balance.TILE + 0.01, "ghost follows the finger on the 2 m grid", str(pl._center()))
	await _frames(10)
	await _shot("_bad")

	# 탭: 성 왼쪽 아래 빈 곳(-8, 5) 가운데를 누르면 거기로
	var target := Vector2i(-8, 5)
	var tc := Vector3((target.x + 1.5) * Balance.TILE, 0, (target.y + 1.5) * Balance.TILE)
	await _tap(cam.unproject_position(tc))
	_check(pl.cell == target and pl.ok, "tapping an empty spot moves the ghost there (green)", str(pl.cell))
	pl.confirm_button.pressed.emit()
	await _frames(5)
	_check(not pl._floor.visible, "floor tiles hide after building", "")
	_check(not pl.is_active() and Economy.layout.get("lumber") == target and str(Economy.build.get("id", "")) == "lumber", "[건설] places it and starts building", "%s %s" % [Economy.layout, Economy.build])
	_check(scenery.lots.lumber.mi.visible and scenery.lots.lumber.lot == true and scenery.lots.lumber.cell == target, "construction lot shows at the chosen spot", "")
	Economy.build.finish = Economy.time_now() - 1.0
	Economy.complete_due(Economy.time_now())
	await _frames(10)
	_check(Economy.is_built("lumber") and scenery.lots.lumber.lot == false, "lumber mill finished", "")
	var c := Balance.center_of("lumber")
	_check(c.is_equal_approx(tc) and scenery.lots.lumber.mi.position.is_equal_approx(tc) and scenery.tag_anchors.lumber.x == tc.x, "mesh, name tag and plot at the chosen spot", "%s vs %s" % [c, tc])
	_check(Balance.plots().any(func(p): return p.id == "lumber" and p.cell == target) and not Balance.plots().any(func(p): return p.id == "farm"),
		"path blocking follows (built + placed only)", str(Balance.plots()))
	await _frames(20)
	await _shot("_after")

	# 옮기기: 민가를 (2, -8)로(보병 막사 기본 자리 — 아직 안 지었다)
	list.open()
	await get_tree().create_timer(0.5).timeout
	list.rows.houses.button.pressed.emit()
	await get_tree().create_timer(0.6).timeout  # 카메라가 그 건물로 옮겨 간 뒤
	_check(pl.is_active() and pl.moving and pl.cell == Economy.building_cell("houses") and not pl.ok, "[이동] starts at the current spot ([여기로 이동] off)", "")
	_check(not scenery.lots.houses.mi.visible, "the building being moved is hidden at its old spot", "")
	pl.rig.pan_to(Vector3.ZERO, 0.05)
	await get_tree().create_timer(0.3).timeout
	var dest := Vector2i(2, -8)
	await _tap(cam.unproject_position(Vector3((dest.x + 1.5) * Balance.TILE, 0, (dest.y + 1.5) * Balance.TILE)))
	_check(pl.cell == dest and pl.ok, "tap picks the new spot", str(pl.cell))
	var wood: int = Economy.res.wood
	pl.confirm_button.pressed.emit()
	await _frames(5)
	_check(Economy.layout.get("houses") == dest and Economy.res.wood == wood and scenery.lots.houses.mi.visible and scenery.lots.houses.cell == dest, "moved for free", str(Economy.layout))
	await _frames(20)
	await _shot("_moved")

	# 취소: 옛 자리 그대로
	pl.start("houses")
	await _frames(3)
	pl.cancel()
	_check(not pl.is_active() and scenery.lots.houses.mi.visible and Economy.layout.houses == dest, "cancel keeps the building where it was", "")
	await _copies(list, pl, btn)


## 새 건물·n번째 채(2026-10-13): 성채 Lv 5면 벌목장 2는 지을 수 있고 금광(4)도 열림, 대장간(8)·벌목장 3(10)은 잠김.
func _copies(list, pl, btn) -> void:
	Economy.levels["keep"] = 5
	Economy.build = {}
	Economy.changed.emit()
	list.open()
	await get_tree().create_timer(1.0).timeout
	_check(list.rows.has("lumber#2") and list.rows.has("forge") and list.rows.has("goldmine"), "copies and new buildings have cards", str(list.rows.keys()))
	_check(list.rows["lumber#2"].why == "" and list.rows.goldmine.why == "", "unlocked copy / new type can be built", list.rows["lumber#2"].why)
	_check(list.rows.forge.why.contains("성채 Lv 8") and list.rows["lumber#3"].why.contains("성채 Lv"), "locked cards say the keep level", list.rows.forge.why)
	_check(list.rows.forge.card.modulate.a < 0.9 and list.rows["lumber#2"].card.modulate.a > 0.99, "locked cards stay dimmed after the unfold", "%s %s" % [list.rows.forge.card.modulate, list.rows["lumber#2"].card.modulate])
	var order: Array = []
	for c in list._list.get_children():
		order.append(c)
	_check(order.find(list.rows["lumber#2"].card) < order.find(list.rows.forge.card) and order.find(list.rows.goldmine.card) < order.find(list.rows.houses.card), "buildable first, built next, locked last", "")
	await _shot("_tray_copies")
	_check(list.rows["lumber#2"].tag.visible and list.rows.goldmine.tag.visible and not list.rows.forge.tag.visible and not list.rows.houses.tag.visible, "NEW tag only on newly opened lots you can build", "")
	list._scroll.ensure_control_visible(list.rows["lumber#2"].card)
	await _frames(5)
	await _shot("_tray_new")
	list._scroll.ensure_control_visible(list.rows.watchtower.card)
	await _frames(5)
	await _shot("_tray_types")
	list._scroll.scroll_horizontal = 100000
	await _frames(5)
	await _shot("_tray_locked")
	list.rows["lumber#2"].card.pressed.emit()
	await get_tree().create_timer(0.6).timeout
	_check(pl.is_active() and pl.building_id == "lumber#2" and pl.ok, "[건설] on lumber #2 starts placing it (green)", str(pl.cell))
	pl.confirm_button.pressed.emit()
	await _frames(5)
	_check(Economy.layout.has("lumber#2") and str(Economy.build.get("id", "")) == "lumber#2", "lumber #2 placed by its own key", str(Economy.layout))


func _drag(from: Vector2, to: Vector2) -> void:
	_mouse(from, true)
	await _frames(2)
	for k in range(1, 9):
		var m := InputEventMouseMotion.new()
		m.position = get_viewport().get_final_transform() * from.lerp(to, k / 8.0)  # 창 좌표(push_input이 뷰포트 좌표로 되돌린다)
		m.global_position = m.position
		m.button_mask = MOUSE_BUTTON_MASK_LEFT
		get_viewport().push_input(m)
		await _frames(1)
	_mouse(to, false)
	await _frames(3)


func _tap(at: Vector2) -> void:
	_mouse(at, true)
	await _frames(2)
	_mouse(at, false)
	await _frames(3)


func _mouse(at: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = get_viewport().get_final_transform() * at  # 창 좌표
	e.global_position = e.position
	get_viewport().push_input(e)


func _shot(suffix: String) -> void:
	if _out == "":
		return
	await _frames(5)
	get_viewport().get_texture().get_image().save_png(_out + suffix + ".png")
	print("saved ", _out + suffix + ".png")


func _find(path: String) -> Node:
	for c in _main.get_children():
		if c.get_script() != null and c.get_script().resource_path == path:
			return c
	return null


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _check(ok: bool, what: String, detail: String) -> void:
	if ok:
		print("  ok   ", what)
	else:
		_fails += 1
		print("  FAIL ", what, "  ", detail)
