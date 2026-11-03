extends Node
## 오늘 완료 작업 검증 영상(개발용, 오프라인, 2026-11-03): 항목마다 실제 main 씬을 띄워 화면을 직접 누르며 보여 준다. 자막 + 누른 자리 표시.
## 화면이 필요하다(--write-movie와 함께):
##   xvfb-run -a godot --path . --resolution 720x1280 --write-movie /tmp/x.avi --fixed-fps 30 res://tests/verify_movie.tscn -- --item=tray
## --item=double|range|power|party|settings|tray|pvp|stats|tap|gacha|overlap. 저장 파일은 건드리지 않는다(Prefs는 바꾼 뒤 되돌린다).

const GameData := preload("res://scripts/game_data.gd")
const Formation := preload("res://scripts/formation.gd")
const FONT := preload("res://assets/fonts/Pretendard-SemiBold.otf")
const PartyBattle := preload("res://scripts/party_battle.gd")
const PvpBattle := preload("res://scripts/pvp_battle.gd")
const UiKit := preload("res://scripts/ui_kit.gd")
const Prefs := preload("res://scripts/prefs.gd")

var _main
var _item := "tray"
var _cap_box: PanelContainer
var _caption: Label
var _taps: Array = []  # [pos, age]
var _tap_layer: Control
var _note: Label  # 화면 가운데 정보 상자(표·숫자)
var _note_box: PanelContainer
var _focus := Vector3.INF  # _cast_for: 이 근처 영웅만 스킬을 쓰게(화면 안)


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--item="):
			_item = a.substr(7)
	get_tree().create_timer(300.0, true, false, true).timeout.connect(func(): print("MOVIE timeout"); get_tree().quit())
	Economy.save_path = ""
	Fever.save_path = ""
	Guild.save_path = ""
	Tutorial.save_path = ""
	Pvp.save_path = ""
	Party.save_path = ""
	Party.auto_accept = false
	Economy.reset(Time.get_unix_time_from_system())
	Tutorial.state = "skipped"
	Economy.diamonds = 50000
	Economy.gold = 5000000
	if has_method("_setup_" + _item):
		call("_setup_" + _item)
	_main = preload("res://scenes/main.tscn").instantiate()
	add_child(_main)
	_build_overlay()
	Economy.changed.emit()
	Economy.roster_changed.emit()
	await _wait(5.0)  # 불러오기 화면이 걷힐 때까지
	match _item:
		"double":
			await _run_double()
		"range":
			await _run_range()
		"power":
			await _run_power()
		"party":
			await _run_party()
		"settings":
			await _run_settings()
		"tray":
			await _run_tray()
		"pvp":
			await _run_pvp()
		"stats":
			await _run_stats()
		"tap":
			await _run_tap()
		"gacha":
			await _run_gacha()
		"overlap":
			await _run_overlap()
	print("MOVIE %s done" % _item)
	get_tree().quit()


# ---------------------------------------------------------------- 공통

func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 40
	add_child(layer)
	_tap_layer = Control.new()
	_tap_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tap_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tap_layer.draw.connect(_draw_taps)
	layer.add_child(_tap_layer)
	_cap_box = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.06, 0.04, 0.78)
	sb.set_corner_radius_all(14)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	_cap_box.add_theme_stylebox_override("panel", sb)
	_cap_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cap_box.position = Vector2(20, 1000)
	_cap_box.size = Vector2(680, 0)
	_caption = Label.new()
	_caption.add_theme_font_override("font", FONT)
	_caption.add_theme_font_size_override("font_size", 28)
	_caption.add_theme_color_override("font_color", Color(1.0, 0.95, 0.75))
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption.custom_minimum_size = Vector2(648, 0)
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cap_box.add_child(_caption)
	layer.add_child(_cap_box)
	_cap_box.visible = false
	_note_box = _cap_box.duplicate()
	_note = _note_box.get_child(0)
	_note.add_theme_font_size_override("font_size", 24)
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_note_box.position = Vector2(40, 300)
	_note_box.size = Vector2(640, 0)
	_note_box.visible = false
	layer.add_child(_note_box)


func _process(delta: float) -> void:
	var real := delta / maxf(Engine.time_scale, 0.01)
	for t in _taps:
		t[1] += real
	_taps = _taps.filter(func(t): return t[1] < 0.7)
	if _tap_layer != null:
		_tap_layer.queue_redraw()


func _draw_taps() -> void:
	for t in _taps:
		var k: float = t[1] / 0.7
		_tap_layer.draw_circle(t[0], 14.0 + 26.0 * k, Color(1, 0.9, 0.3, 0.55 * (1.0 - k)))
		_tap_layer.draw_arc(t[0], 18.0 + 30.0 * k, 0, TAU, 40, Color(1, 1, 1, 0.9 * (1.0 - k)), 4.0)


## 자막. y = 상자 위쪽(기본 화면 아래쪽).
func _say(t: String, y := 1000.0) -> void:
	_caption.text = t
	_cap_box.visible = t != ""
	_cap_box.size = Vector2(680, 0)
	_cap_box.position = Vector2(20, y)


func _show_note(t: String, y := 300.0) -> void:
	_note.text = t
	_note_box.visible = t != ""
	_note_box.size = Vector2(640, 0)
	_note_box.position = Vector2(40, y)


func _tap(at: Vector2) -> void:
	_taps.append([at, 0.0])
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = at
		e.global_position = at
		Input.parse_input_event(e)


func _tap_ctl(c: Control) -> void:
	_tap(c.get_global_rect().get_center())


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _find(path: String, from: Node = null) -> Node:
	var n: Node = from if from != null else get_tree().root
	for c in n.get_children():
		if c.get_script() != null and c.get_script().resource_path == path:
			return c
	for c in n.get_children():
		var r := _find(path, c)
		if r != null:
			return r
	return null


func _own_all(level := 30, promo := 1) -> void:
	for h in GameData.heroes():
		Economy.heroes[str(h.id)] = 1
		Economy.hero_levels[str(h.id)] = level
		Economy.hero_promotions[str(h.id)] = promo


func _team(ids: Array) -> void:
	for id in ids:
		Economy.heroes[id] = 1
		Economy.hero_levels[id] = 30
		Economy.hero_promotions[id] = 1
	Economy.deploy = ids.duplicate()
	Economy.levels[GameData.KEEP] = 10
	Economy.levels[GameData.GATE] = 10


func _scroll_to(c: Control) -> void:
	var p := c.get_parent()
	while p != null and not (p is ScrollContainer):
		p = p.get_parent()
	if p != null:
		p.ensure_control_visible(c)


func _scroll_bottom(w: Node) -> void:
	await _frames(2)
	for c in w.find_children("*", "ScrollContainer", true, false):
		if c.is_visible_in_tree():
			c.scroll_vertical = 100000


func _heroes() -> Array:
	return get_tree().get_nodes_in_group("heroes").filter(func(h): return is_instance_valid(h) and h.is_alive())


func _cast_now(hs: Array) -> void:
	for h in hs:
		if "_skx" in h and h._skx != null:
			for k in h._skx._cd:
				h._skx._cd[k] = minf(float(h._skx._cd[k]), 0.0)


# ---------------------------------------------------------------- 2. 빠른 두 번 탭

func _run_double() -> void:
	var tabs = _find("res://scripts/tab_bar.gd")
	tabs.press("shop")
	var shop = tabs.windows.shop
	shop.open_tab("daily")
	await _wait(1.5)
	var id := "d_pouch_gold"
	var b: Button = shop.buttons["buy:" + id]
	_scroll_to(b)
	await _wait(0.6)
	_say("상점 [일일] — 골드 주머니 (다이아 40, 하루 3번)", 1040)
	await _wait(2.0)
	var d0 := Economy.diamonds
	_say("구매 버튼을 아주 빠르게 5번 연타합니다", 1040)
	await _wait(1.0)
	var at: Vector2 = shop.buttons["buy:" + id].get_global_rect().get_center()
	for i in 5:  # 0.1초 안의 연타(녹화는 실제보다 느려 한 프레임에 몰아 보낸다)
		_tap(at)
	await _wait(1.2)
	_say("5번 눌렀지만 1번만 구매 — 다이아 %s → %s (−%d)" % [UiKit.commas(d0), UiKit.commas(Economy.diamonds), d0 - Economy.diamonds], 1040)
	await _wait(3.5)
	var d1 := Economy.diamonds
	_say("0.5초 뒤 다시 한 번 누르면 정상적으로 한 번 더 삽니다", 1040)
	await _wait(1.0)
	_tap_ctl(shop.buttons["buy:" + id])
	await _wait(1.2)
	_say("다이아 %s → %s (−%d)\n상점·PVP 상점·길드 상점·길드 기부·파견 새로고침 5곳에 같은 보호 + 서버도 같은 요청을 한 번만 처리" % [UiKit.commas(d1), UiKit.commas(Economy.diamonds), d1 - Economy.diamonds], 1000)
	await _wait(4.5)


# ---------------------------------------------------------------- 3. 원거리 사거리 + 범위 ×1.3

func _setup_range() -> void:
	var keep := 10
	Economy.levels[GameData.KEEP] = keep
	Economy.levels[GameData.GATE] = keep
	var slots := GameData.hero_slots(keep)
	var melee := GameData.heroes().filter(func(h): return h.role == "melee").map(func(h): return str(h.id))
	var ranged := GameData.heroes().filter(func(h): return h.role == "ranged").map(func(h): return str(h.id))
	var team := []
	for i in slots:
		team.append(melee[i] if i % 8 < 4 else ranged[i])
	_team(team)
	Economy.soldiers = {"infantry:2": 48}
	Economy.soldier_deployed = {"infantry:2": 48}


func _run_range() -> void:
	GameState.auto_continue = false
	GameState.stage = 40
	GameState.start_stage()
	_say("스테이지 40 — 성문 앞 보병 싸움에 성벽 위 원거리 영웅이 닿는지", 1040)
	await _wait(5.0)
	var rings := {}
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.3, 0.9, 1.0, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	for h in _heroes():
		if h.role == "ranged" and h.has_method("is_on_wall") and h.is_on_wall():
			var r := float(h.def.range)
			var mi := MeshInstance3D.new()
			var tm := TorusMesh.new()
			tm.inner_radius = r - 0.3
			tm.outer_radius = r + 0.3
			tm.rings = 64
			mi.mesh = tm
			mi.material_override = mat
			mi.top_level = true
			_main.add_child(mi)
			rings[h] = mi
	var cam := get_viewport().get_camera_3d()
	cam.get_parent().pan_to(Vector3.ZERO, 0.6)
	create_tween().tween_property(cam, "size", cam.size * 1.7, 0.8)
	_say("파란 원 = 성벽 위 원거리 영웅의 사거리\n궁수 15m · 치유 14m · 마법 13m · 고르크 13m (전 12 · 10 · 9 · 6.5m)", 1000)
	var t := 0.0
	var cast_t := 0.0
	while t < 34.0 and GameState.mode == GameState.Mode.STAGE:
		for h in rings:
			if is_instance_valid(h):
				rings[h].global_position = Vector3(h.global_position.x, h.global_position.y + 0.1, h.global_position.z)
				rings[h].visible = h.is_alive()
			else:
				rings[h].visible = false
		if t > 18.0 and _caption.text.begins_with("파란"):
			_say("범위 스킬은 반경·길이가 약 1.3배로 넓어졌습니다 (스킬을 자주 쓰게 해 보여 줌)", 1040)
		if t > 18.0:
			cast_t -= get_process_delta_time()
			if cast_t <= 0.0:
				cast_t = 1.5
				_cast_now(_heroes())
		await get_tree().process_frame
		t += get_process_delta_time()


# ---------------------------------------------------------------- 4. 전투력

func _setup_power() -> void:
	_own_all(1, 0)


func _run_power() -> void:
	var lines := ["같은 등급 · 같은 레벨 · 같은 승급이면 전투력 차이 최대 10\n"]
	for lp in [[1, 0], [50, 1], [120, 3], [200, 5]]:
		var row := "Lv%d ★%d   " % [lp[0], lp[1]]
		var parts := []
		for g in ["R", "SR", "SSR", "UR"]:
			var lo := 1 << 30
			var hi := 0
			for h in GameData.heroes():
				if h.grade == g:
					var p := GameData.hero_power(h, lp[0], lp[1], {})
					lo = mini(lo, p)
					hi = maxi(hi, p)
			parts.append("%s %s~%s(%d)" % [g, UiKit.commas(lo), UiKit.commas(hi), hi - lo])
		lines.append(row + "\n   " + " · ".join(parts.slice(0, 2)) + "\n   " + " · ".join(parts.slice(2)))
	var tabs = _find("res://scripts/tab_bar.gd")
	tabs.press("hero")
	await _wait(1.5)
	_say("영웅 창 — 모든 영웅 Lv1 ★0 (전투력 순)", 1040)
	await _wait(3.5)
	_say("같은 등급끼리는 전투력이 거의 같고, 등급이 오를수록 크게 뜁니다", 1040)
	var hp = tabs.windows.hero
	for c in hp.find_children("*", "ScrollContainer", true, false):
		if c.is_visible_in_tree():
			var tw := create_tween()
			tw.tween_property(c, "scroll_vertical", 1400, 6.0)
			break
	await _wait(6.5)
	_say("")
	_show_note("\n".join(lines) + "\n\n(괄호 = 같은 등급 안 최대 차이 · 실제 전투 능력치는 그대로)", 260)
	await _wait(9.0)
	_show_note("")
	for lp in [[50, 1]]:
		for id in Economy.heroes:
			Economy.hero_levels[id] = lp[0]
			Economy.hero_promotions[id] = lp[1]
	Economy.roster_changed.emit()
	Economy.changed.emit()
	tabs.press("hero")
	await _wait(0.5)
	tabs.press("hero")
	await _wait(1.5)
	_say("모든 영웅 Lv50 ★1 로 바꾼 목록", 1040)
	await _wait(5.0)


# ---------------------------------------------------------------- 6. 파티 던전

func _setup_party() -> void:
	_own_all(8, 0)
	Economy.soldiers = {"infantry:3": 8, "archer:3": 8}


func _run_party() -> void:
	var tabs = _find("res://scripts/tab_bar.gd")
	tabs.press("dungeon")
	var panel = tabs.windows.dungeon
	panel.set_section("party")
	_say("던전 → [파티] 리치의 무덤 — 시험이라 AI 성주가 빈자리를 채웁니다", 990)
	await _wait(2.5)
	panel.party_tab._start("lich")
	while Party.state() != "confirm":
		await get_tree().process_frame
	await _wait(1.5)
	Party.accept(true)
	var b = null
	while b == null:
		await get_tree().process_frame
		for c in get_children():
			if c.get_script() == PartyBattle and not c.is_queued_for_deletion():
				b = c
	await _wait(0.5)
	_say("시작하자마자 내 영웅이 이미 선택돼 있습니다 (선택됨: %s) — 바로 바닥을 눌러 움직일 수 있어요" % ("예" if b.picker != null and b.picker.selected != null else "아니요"), 990)
	await _wait(4.0)
	var seen_ring := 0
	var t := 0.0
	var moved := false
	while not b.done and t < 70.0:
		if b.phase == b.Phase.FIGHT:
			Engine.time_scale = 1.5
		if not moved and t > 2.0 and b.picker != null and b.picker.selected != null:
			moved = true
			var cam := get_viewport().get_camera_3d()
			var me = b.picker.selected
			var p := cam.unproject_position(me.global_position) + Vector2(-120, 60)
			_tap(p)
			_say("(내 영웅 선택됨 → 바닥을 한 번 눌러 이동)", 990)
		if is_instance_valid(b.boss) and int(b.boss.casts.get("ring", 0)) > seen_ring:
			seen_ring = int(b.boss.casts.ring)
			_say("죽음의 고리 예고 — AI 영웅들도 사람처럼 0.3~0.9초 늦게 원 밖으로 피합니다 (20%는 못 보고 맞음)", 990)
		await get_tree().process_frame
		t += get_process_delta_time() / maxf(Engine.time_scale, 0.01)
	Engine.time_scale = 1.0
	_say("")
	await _wait(3.0)


# ---------------------------------------------------------------- 7. 설정 스킬 이름 띠

func _setup_settings() -> void:
	_team(["ignis", "valen", "nev", "arteon", "grom", "frieda", "kyle", "luna"])
	Economy.soldiers = {"infantry:2": 30}
	Economy.soldier_deployed = {"infantry:2": 30}


func _run_settings() -> void:
	Prefs.set_value("skill_banner", true)
	Prefs.set_value("skill_banner_size", "m")
	GameState.auto_continue = false
	GameState.stage = 12
	GameState.start_stage()
	_say("스테이지 시작 — 괴물이 성문에 닿을 때까지 기다립니다", 1040)
	await _wait(12.0)
	var cam := get_viewport().get_camera_3d()
	var focus: Vector3 = _heroes()[0].global_position
	var best := INF
	for h in _heroes():
		for m in get_tree().get_nodes_in_group("monsters"):
			if m.is_alive():
				var d: float = h.global_position.distance_to(m.global_position)
				if d < best:
					best = d
					focus = h.global_position
	cam.get_parent().pan_to(focus, 0.6)
	create_tween().tween_property(cam, "size", 28.0, 0.8)
	_focus = focus
	_say("전투 중 영웅 머리 위 스킬 이름 띠 — 보통 크기 (기본)", 1040)
	await _cast_for(5.0)
	var menu = _find("res://scripts/side_menu.gd")
	var sp = _find("res://scripts/settings_panel.gd")
	sp.open()
	await _wait(1.0)
	await _scroll_bottom(sp)
	await _wait(0.8)
	_say("설정 → 화면: [스킬 이름 표시] 켬/끔 · [스킬 이름 크기] 작게/보통/크게", 150)
	await _wait(3.0)
	_tap_ctl(sp.banner_size_buttons["l"])
	await _wait(1.2)
	_say("크기 [크게] 선택 (저장값: %s)" % Prefs.get_str("skill_banner_size", "m"), 150)
	await _wait(1.5)
	sp.close()
	_say("크게 — 띠와 글자·아이콘이 1.35배", 1040)
	await _cast_for(5.0)
	sp.open()
	await _wait(0.6)
	await _scroll_bottom(sp)
	await _wait(0.5)
	_tap_ctl(sp.banner_size_buttons["s"])
	_say("크기 [작게] 선택", 150)
	await _wait(1.0)
	sp.close()
	_say("작게 — 0.75배", 1040)
	await _cast_for(5.0)
	sp.open()
	await _wait(0.6)
	await _scroll_bottom(sp)
	await _wait(0.5)
	_tap_ctl(sp.banner_check)
	await _wait(1.0)
	_say("[스킬 이름 표시] 끔 (저장값: %s)" % ("켬" if Prefs.get_bool("skill_banner") else "끔"), 150)
	await _wait(1.2)
	sp.close()
	_say("끔 — 스킬은 그대로 쓰지만 머리 위 띠가 뜨지 않습니다 (SSR 컷인은 그대로)", 1040)
	await _cast_for(6.0)
	Prefs.set_value("skill_banner", true)
	Prefs.set_value("skill_banner_size", "m")
	var _u = menu


func _cast_for(sec: float) -> void:
	var t := 0.0
	var k := 0.0
	while t < sec:
		k -= get_process_delta_time()
		if k <= 0.0:
			k = 0.9
			var hs := _heroes()
			if _focus != Vector3.INF:
				hs = hs.filter(func(x): return x.global_position.distance_to(_focus) < 14.0)
			hs.shuffle()
			_cast_now(hs.slice(0, 3))
		await get_tree().process_frame
		t += get_process_delta_time()


# ---------------------------------------------------------------- 8. [건설] 띠

func _run_tray() -> void:
	var tabs = _find("res://scripts/tab_bar.gd")
	var bb = _find("res://scripts/build_button.gd")
	var list = _find("res://scripts/build_list_panel.gd")
	_say("성 화면 — 왼쪽 아래 [건설]", 1000)
	await _wait(2.0)
	_tap_ctl(bb.button)
	await _wait(1.8)
	_say("[건설] 띠가 펼쳐진 상태에서 아래 [영웅] 탭을 누르면…", 1000)
	await _wait(2.5)
	_tap_ctl(tabs.buttons.hero)
	await _wait(1.6)
	_say("띠가 접히고 영웅 창만 열립니다 (전에는 둘이 겹쳤음) — 띠 열림: %s" % ("예" if list.is_open() else "아니요"), 1000)
	await _wait(4.0)
	_say("창을 닫고 다시 [건설] → 이번엔 [병사] 탭", 1000)
	tabs.windows.hero.close()
	await _wait(1.0)
	_tap_ctl(bb.button)
	await _wait(2.0)
	_tap_ctl(tabs.buttons.soldier if tabs.buttons.has("soldier") else tabs.buttons.values()[2])
	await _wait(1.6)
	_say("어느 창이 열려도 띠가 접혀 겹치지 않습니다 — 띠 열림: %s" % ("예" if list.is_open() else "아니요"), 1000)
	await _wait(3.5)


# ---------------------------------------------------------------- 9. PVP

func _setup_pvp() -> void:
	_own_all(40, 2)
	Economy.soldiers = {"infantry:3": 12, "archer:3": 12}


func _run_pvp() -> void:
	var ended := [false]
	Pvp.result_ready.connect(func(_r): ended[0] = true)
	var tabs = _find("res://scripts/tab_bar.gd")
	tabs.press("dungeon")
	tabs.windows.dungeon.set_section("pvp")
	Pvp.fetch()
	await _wait(1.0)
	tabs.windows.dungeon.pvp.open_mode("duel")
	_say("던전 → [PVP] → 결투", 1000)
	await _wait(2.5)
	tabs.windows.dungeon.close()
	Pvp.start("duel", Pvp.default_team("duel"))
	var b = null
	while b == null:
		await get_tree().process_frame
		for c in get_children():
			if c.get_script() == PvpBattle and not c.is_queued_for_deletion():
				b = c
		if b == null:
			b = _find("res://scripts/pvp_battle.gd")
	_say("시작 거리가 넓어졌습니다 — 앞줄 사이 24m (전 18m)", 1000)
	await _wait(5.0)
	_say("영웅이 쓰러져도 처치·사망 알림 문구가 뜨지 않습니다 (2배속 녹화)", 1000)
	Engine.time_scale = 2.0
	var t := 0.0
	while not ended[0] and t < 120.0:
		await get_tree().process_frame
		t += get_process_delta_time() / 2.0
	Engine.time_scale = 1.0
	_say("결과는 한 번만 나옵니다 (KO 띠 → 결과 다시 뜨던 것 없앰)", 1000)
	await _wait(7.0)


# ---------------------------------------------------------------- 10. 전투 통계

func _setup_stats() -> void:
	_team(["lumina", "gaia", "ignis", "valen", "arteon", "grom", "kyle", "luna"])
	Economy.soldiers = {"infantry:2": 30}
	Economy.soldier_deployed = {"infantry:2": 30}


func _run_stats() -> void:
	var sb = _find("res://scripts/stats_button.gd")
	_say("방치 중(성 화면)에는 [통계] 버튼이 없습니다", 1000)
	await _wait(3.0)
	GameState.auto_continue = false
	GameState.stage = 20
	GameState.start_stage()
	await _wait(2.0)
	_say("스테이지가 시작되면 왼쪽 아래(배속 버튼 위)에 [통계]", 1000)
	await _wait(9.0)
	_tap_ctl(sb.button)
	await _wait(1.0)
	_say("영웅별 가한 피해 — 싸우는 동안 실시간으로 늘어납니다", 160)
	await _wait(6.0)
	_tap_ctl(sb.kind_buttons["taken"])
	_say("[받은 피해]", 160)
	await _wait(4.5)
	_tap_ctl(sb.kind_buttons["healed"])
	_say("[치유량] — 치유 영웅", 160)
	await _wait(4.5)
	_tap_ctl(sb.kind_buttons["dealt"])
	_say("다시 [가한 피해] — 숫자가 계속 오릅니다", 160)
	await _wait(5.0)


# ---------------------------------------------------------------- 11. 영웅 탭 판정

func _run_tap() -> void:
	var picker = _find("res://scripts/unit_picker.gd")
	var cam := get_viewport().get_camera_3d()
	var rig = cam.get_parent()
	var hs := _heroes().filter(func(h): return not (h.has_method("is_on_wall") and h.is_on_wall()))
	if hs.is_empty():
		hs = _heroes()
	var h = hs[0]
	_say("영웅 고르기 판정이 넓어졌습니다 — 몸(발~머리 세로줄)에서 48px 안이면 선택 (전 32px)", 1000)
	rig.pan_to(h.global_position, 0.8)
	var tw := create_tween()
	tw.tween_property(cam, "size", 16.0, 0.8)
	await _wait(3.0)
	# 몸 가운데에서 화면 방향 dir로 나가며 판정 거리가 want가 되는 점
	var spot := func(dir: Vector2, want: float) -> Vector2:
		var mid := (cam.unproject_position(h.global_position + Vector3(0, 0.1, 0)) + cam.unproject_position(h.global_position + Vector3(0, 1.8, 0))) / 2.0
		var p := mid
		for k in 400:
			p = mid + dir.normalized() * float(k)
			if picker.hero_tap_dist(h, p) >= want:
				break
		return p
	for c in [[Vector2(1, 0), 42.0, "몸 오른쪽 42px"], [Vector2(-1, -0.6), 40.0, "머리 왼쪽 40px"], [Vector2(1, 0.5), 44.0, "발 오른쪽 44px"], [Vector2(1, -0.2), 62.0, "몸 오른쪽 62px (판정 밖)"]]:
		var p: Vector2 = spot.call(c[0], c[1])
		_say("%s를 누르면… (몸까지 %.0fpx)" % [c[2], picker.hero_tap_dist(h, p)], 1000)
		await _wait(1.6)
		_tap(p)
		await _wait(1.0)
		_say("%s → 선택됨: %s" % [c[2], "예" if picker.selected == h else "아니요"], 1000)
		await _wait(2.4)
		if picker.selected != null:
			picker._select(null)
		await _wait(0.8)
	_say("이미 고른 영웅을 다시 누를 때는 12px 안이어야 풀립니다 (살짝 빗나가면 짧게 이동)", 1000)
	await _wait(3.5)


# ---------------------------------------------------------------- 12. 모집

func _run_gacha() -> void:
	var rp = _find("res://scripts/recruit_panel.gd")
	rp.open()
	rp.set_currency(GameData.GACHA_DIA)
	_say("다이아 모집 — 새 소환 연출: 별빛 터널 + 떨어지는 유성 + 빛의 틈", 1150)
	await _wait(1.5)
	_tap_ctl(rp.ten_button)
	await _wait(7.0)
	_say("결과 화면에서 [10회 더] — 연출 중에 연타하면 뽑지 않고 연출을 걷고 카드를 다 엽니다", 1130)
	await _wait(1.5)
	var d0 := Economy.diamonds
	var at: Vector2 = rp.again10_button.get_global_rect().get_center()
	for i in 5:  # 연출 중 연타(녹화는 실제보다 느려 한 프레임에 몰아 보낸다)
		_tap(at)
	await _wait(2.0)
	_say("[10회 더] 연타 → 10회 1번만 (다이아 −%s)" % UiKit.commas(d0 - Economy.diamonds), 1130)
	await _wait(3.5)
	_say("[연출 건너뛰기] 체크 → 소환 연출 없이 카드가 바로 펼쳐집니다", 1130)
	await _wait(1.0)
	_tap_ctl(rp.skip_box)
	await _wait(1.0)
	_tap_ctl(rp.again10_button)
	await _wait(3.0)
	_tap_ctl(rp.again10_button)
	await _wait(3.0)
	_tap_ctl(rp.skip_box)
	await _wait(0.6)
	_say("[반복 모집] 체크 → SSR 이상이 나오거나 재화가 떨어지거나 [■ 멈춤]까지 자동으로 계속", 1130)
	await _wait(1.0)
	_tap_ctl(rp.auto_box)
	await _wait(1.0)
	_say("체크하면 같은 10회 모집이 저절로 이어집니다 — [1회 더] 자리는 [■ 멈춤]", 1130)
	await _wait(14.0)
	if rp.auto_running():
		_say("[■ 멈춤]으로 멈춥니다", 1130)
		_tap_ctl(rp.again_button)
		await _wait(3.0)
	else:
		_say("SSR 이상이 나와 반복 모집이 멈췄습니다", 1130)
		await _wait(3.0)


# ---------------------------------------------------------------- 13. 겹침

func _setup_overlap() -> void:
	_own_all(10, 0)


func _run_overlap() -> void:
	var tabs = _find("res://scripts/tab_bar.gd")
	tabs.press("hero")
	var hp = tabs.windows.hero
	await _wait(1.5)
	_say("영웅 창 — [영웅]·[합성] 탭이 오른쪽 위 X(닫기)와 겹치지 않습니다", 1040)
	await _wait(3.5)
	_tap_ctl(hp.fuse_tab)
	await _wait(1.0)
	_say("[합성] 탭에서도 X가 가려지지 않습니다", 1040)
	await _wait(3.0)
	_tap_ctl(hp.heroes_tab)
	await _wait(0.8)
	hp.show_detail("arteon")
	await _wait(1.2)
	_say("영웅 상세 — 이름·등급·[배치] 줄이 맨 위 X 옆으로, 그림 카드는 그 아래부터", 1040)
	await _wait(4.5)
	hp.close()
	tabs.press("dungeon")
	var dp = tabs.windows.dungeon
	dp.set_section("party")
	await _wait(1.5)
	_say("파티 던전 — 잠긴 난이도 \"매우 어려움 (잠김)\" 글자가 버튼 밖으로 넘치지 않게 줄였습니다", 1040)
	await _wait(5.0)
