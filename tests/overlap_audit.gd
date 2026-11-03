extends Node
## 겹침 전수 점검(개발용, 2026-11-03 사용자 "버튼같은거 겹치는거 없나 전수조사해"): 실제 main 씬에서 모든 창(ui_windows 무리)과
## 그 탭(buttons["tab:…"], 영웅 창 탭, 던전 창 구역, 상점 탭)을 하나씩 열고, 눈에 보이는 버튼끼리·버튼과 글자(Label)가 겹치거나
## 화면(720×1280) 밖으로 나간 것을 출력한다(스크롤 영역에 잘려 안 보이는 부분은 뺀다). --dir이 있으면 화면마다 PNG도 남긴다.
## 실행: xvfb-run -a godot --path . --resolution 720x1280 --rendering-driver opengl3 res://tests/overlap_audit.tscn -- --dir=/tmp/overlap
## 끝에 "OVERLAP TOTAL n" — n = 문제 수(0이면 통과, 종료 코드도 0).

const HEROES := ["arteon", "ignis", "sylvana", "grom", "baldur", "lumina", "kyle", "nev", "luna", "valen"]
const MIN_PX := 3.0  # 이보다 얕게 닿는 것은 테두리 맞닿음으로 본다

var _main
var _dir := ""
var _issues := 0
var _seen := {}


var _done := false


func _ready() -> void:
	Fever.save_path = ""
	Guild.save_path = ""
	Pvp.save_path = ""
	_dir = Net.arg_value("dir")
	if _dir != "":
		DirAccess.make_dir_recursive_absolute(_dir)
	var online := Net.is_online() and Net.arg_value("device") != ""
	if online:  # 온라인(--api --device, 테스트 훅 서버): 내용이 찬 창(우편·랭킹·파견·길드·거래소 등)까지 본다
		Net.device_path = Net.arg_value("device")
		Net.auth_path = Net.device_path.get_base_dir().path_join("auth.json")
		DirAccess.remove_absolute(Net.device_path)
		Net.set_auth("guest")
	else:
		Economy.save_path = ""
		Tutorial.save_path = ""
		Economy.reset(Time.get_unix_time_from_system())
		Tutorial.state = "skipped"
		for id in HEROES:
			Economy.heroes[id] = 1
		Economy.diamonds = 500
		Economy.admin = true
	_main = preload("res://scenes/main.tscn").instantiate()
	add_child(_main)
	if online:
		var t0 := Time.get_ticks_msec()
		while not Net.ready_once and Time.get_ticks_msec() - t0 < 30000:
			await _frames(1)
		await _post("/v1/test/admin", {})
		await _post("/v1/test/stage", {"stage": 60})
		await _post("/v1/test/tut_step", {"step": 999})
		await _post("/v1/test/levels", {"levels": {"keep": 15, "barracks": 10, "lab": 5, "dispatch": 5, "tavern": 1}, "res": {"wood": 900000, "stone": 900000, "food": 900000}})
		await _post("/v1/test/grant_diamonds", {"amount": 99999})
		await _post("/v1/test/grant_gold", {"amount": 9999999})
		for h in HEROES + ["bron", "mira", "rian", "echo", "felix", "hans", "ella", "dorik", "nina", "jack"]:
			await _post("/v1/test/grant_hero", {"hero_id": h})
		await _post("/v1/guild/create", {"name": "겹침점검", "emblem": 0})
		Net.refresh()
	await _frames(120)
	await _check_screen("castle", get_tree().root)
	for w in get_tree().get_nodes_in_group("ui_windows"):
		var name_s: String = w.get_script().resource_path.get_file().get_basename()
		match name_s:
			"building_panel":
				w.open_building("keep")
			"offline_panel":
				w.show_report({"away_sec": 7380.0, "kills": 1234, "gold_tenths": 56780000})
			_:
				w.open()
		await _settle()
		if not w.visible:
			print("OVERLAP INFO ", name_s, " did not open")
			continue
		await _check_screen(name_s, w)
		var bs = w.get("buttons")
		if bs is Dictionary:
			for k in bs.keys():
				if str(k).begins_with("tab:") and bs[k] is Button and bs[k].is_visible_in_tree():
					bs[k].pressed.emit()
					await _settle()
					await _check_screen(name_s + "_" + str(k).substr(4), w)
		match name_s:
			"hero_panel":
				w.set_tab("fuse")
				await _settle()
				await _check_screen("hero_panel_fuse", w)
				w.set_tab("heroes")
				w.show_detail("arteon")
				await _settle()
				await _check_screen("hero_panel_detail", w)
			"dungeon_panel":
				for sec in ["pvp", "party"]:
					w.set_section(sec)
					await _settle()
					await _check_screen("dungeon_panel_" + sec, w)
				w.set_section("dungeon")
				w.open_form("gold")
				await _settle()
				await _check_screen("dungeon_panel_form", w)
			"shop_panel":
				for t in w.TABS:
					w.open_tab(t[0])
					await _settle()
					await _check_screen("shop_panel_" + t[0], w)
			"building_panel":
				for b in ["barracks", "lab", "tavern", "dispatch"]:
					w.open_building(b)
					await _settle()
					await _check_screen("building_panel_" + b, w)
		w.close()
		await _frames(3)
	GameState.start_stage()  # 전투 화면(HUD·스킬 버튼·배속·피버)
	await get_tree().create_timer(6.0).timeout
	await _check_screen("battle", get_tree().root)
	print("OVERLAP TOTAL ", _issues)
	get_tree().quit(0 if _issues == 0 else 1)


func _post(path: String, body) -> void:
	_done = false
	Net.send("POST", path, body, func(d):
		if d is Dictionary and d.has("player"):
			Economy.apply_server(d)
		_done = true, func(): _done = true)
	var t0 := Time.get_ticks_msec()
	while not _done and Time.get_ticks_msec() - t0 < 10000:
		await _frames(1)
	if not _done:
		print("OVERLAP INFO no answer ", path)


func _settle() -> void:
	await get_tree().create_timer(0.5).timeout
	await _frames(2)


## 한 화면: 보이는 버튼·글자 사각형(잘린 만큼 줄여서)을 모아 겹침·화면 밖을 센다.
func _check_screen(name_s: String, root: Node) -> void:
	if _dir != "":
		var img := get_viewport().get_texture().get_image()
		img.convert(Image.FORMAT_RGB8)
		img.save_png("%s/%s.png" % [_dir, name_s])
	var vs := get_viewport().get_visible_rect()
	var items := []  # [control, rect, kind]
	for c in root.find_children("*", "Control", true, false):
		if not c.is_visible_in_tree() or c.modulate.a < 0.05:
			continue
		var kind := ""
		if c is BaseButton:
			kind = "button"
		elif c is Label and c.text.strip_edges() != "" and not _under_button(c):
			kind = "label"
		else:
			continue
		var r := _visible_rect(c)
		if kind == "label":
			r = r.intersection(_text_rect(c))
		if r.size.x < 2.0 or r.size.y < 2.0:
			continue
		if c is Button and c.text != "" and not c.clip_text:
			var f: Font = c.get_theme_font("font")
			var fs: int = c.get_theme_font_size("font_size")
			var widest := 0.0
			for line in c.text.split("\n"):
				widest = maxf(widest, f.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
			if widest > c.size.x - 4.0:
				_report(name_s, "text-wider-than-button", c, null, c.get_global_rect())
		items.append([c, r, kind])
		if not vs.grow(1.0).encloses(r):
			_report(name_s, "off-screen", c, null, r)
	for i in items.size():
		for j in range(i + 1, items.size()):
			var a = items[i]
			var b = items[j]
			if a[2] == "label" and b[2] == "label":
				continue
			if a[0].is_ancestor_of(b[0]) or b[0].is_ancestor_of(a[0]):
				continue
			var x: Rect2 = a[1].intersection(b[1])
			if x.size.x > MIN_PX and x.size.y > MIN_PX:
				_report(name_s, "overlap", a[0], b[0], x)


## 줄바꿈 없는 글자는 글자가 실제로 그려지는 폭만(정렬 반영). 줄바꿈 글자는 사각형 전체.
func _text_rect(l: Label) -> Rect2:
	var r := l.get_global_rect()
	if l.autowrap_mode != TextServer.AUTOWRAP_OFF:
		return r
	var f: Font = l.get_theme_font("font")
	var fs: int = l.get_theme_font_size("font_size")
	var w := 0.0
	for line in l.text.split("\n"):
		w = maxf(w, f.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	w = minf(w, r.size.x) if l.clip_text else w
	var x := r.position.x
	match l.horizontal_alignment:
		HORIZONTAL_ALIGNMENT_CENTER:
			x += (r.size.x - w) / 2.0
		HORIZONTAL_ALIGNMENT_RIGHT:
			x += r.size.x - w
	return Rect2(x, r.position.y, w, r.size.y)


func _under_button(c: Node) -> bool:
	var p := c.get_parent()
	while p != null:
		if p is BaseButton:
			return true
		p = p.get_parent()
	return false


## 조상 중 clip_contents(스크롤 등)에 잘린 뒤 보이는 사각형.
func _visible_rect(c: Control) -> Rect2:
	var r := c.get_global_rect()
	var p := c.get_parent()
	while p != null:
		if p is Control and (p.clip_contents or p is ScrollContainer):
			r = r.intersection(p.get_global_rect())
			if r.size == Vector2.ZERO:
				return r
		p = p.get_parent()
	return r


func _desc(c) -> String:
	if c == null:
		return ""
	var t := ""
	if c is Button or c is Label:
		t = str(c.text).replace("\n", " ").left(24)
	return "%s[%s '%s']" % [c.get_class(), c.name, t]


func _report(name_s: String, what: String, a, b, r: Rect2) -> void:
	var key := "%s|%s|%s|%s" % [name_s.get_slice("_", 0), what, _desc(a), _desc(b)]
	if _seen.has(key):
		return
	_seen[key] = true
	_issues += 1
	print("OVERLAP %s %s %s %s at %s" % [name_s, what, _desc(a), _desc(b), r])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
