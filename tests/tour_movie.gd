extends Node
## 게임 전체 소개 영상(개발용, 2026-11-06): 로컬 테스트 서버(dev/tour/seed.py로 채운 AI 성주·길드·채팅·거래소)에 접속해
## 실제 main 씬을 띄우고 화면을 직접 눌러 가며 콘텐츠 하나씩 보여 준다. 자막 + 누른 자리 표시. 게임 코드·숫자는 건드리지 않는다.
## 실행(dev/tour/record.sh가 한다):
##   xvfb-run -n 91 -s "-screen 0 720x1280x24" godot --path . --resolution 720x1280 --write-movie x.avi --fixed-fps 30 \
##     res://tests/tour_movie.tscn -- --api=http://127.0.0.1:8790 --device=/tmp/tour/device.json --item=castle
## --item=dump: 창마다 보이는 버튼 글자를 찍고 PNG를 남긴다(스크립트 짤 때).

const UiKit := preload("res://scripts/ui_kit.gd")
const FONT := preload("res://assets/fonts/Pretendard-SemiBold.otf")
const UiWindow := preload("res://scripts/ui_window.gd")

var _main
var _item := "dump"
var _cap_box: PanelContainer
var _caption: Label
var _title_box: PanelContainer
var _title: Label
var _taps: Array = []  # [pos, age]
var _tap_layer: Control
var tabs
var menu
var _follow_fight := false
var _follow_t := 0.0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--item="):
			_item = a.substr(7)
	get_tree().create_timer(600.0, true, false, true).timeout.connect(func(): print("MOVIE timeout"); get_tree().quit())
	Fever.save_path = ""
	Guild.save_path = ""
	GuildWar.save_path = ""
	var device := Net.arg_value("device")
	if not Net.is_online() or device == "":
		push_error("tour needs --api and --device")
		get_tree().quit(1)
		return
	Net.device_path = device
	Net.auth_path = device.get_base_dir().path_join("auth.json")
	if not FileAccess.file_exists(Net.auth_path):
		Net.set_auth("guest")
	if _item == "guide":  # 테스트 장면은 가이드를 건너뛴다 — 새 성주 계정이라 서버 가이드 진행을 따르게 다시 켠다
		await get_tree().process_frame
		await get_tree().process_frame
		Tutorial.save_path = ""
		Tutorial.tours_on = true
		Tutorial.go_online()
	_main = preload("res://scenes/main.tscn").instantiate()
	add_child(_main)
	_build_overlay()
	await _until(func(): return Net.ready_once and _main.camera != null, 60.0)
	await _until(func(): return preload("res://scripts/preloader.gd").done, 90.0)
	await _wait(2.5)  # 불러오기 화면이 걷힐 때까지
	tabs = _find("res://scripts/tab_bar.gd")
	menu = _find("res://scripts/side_menu.gd")
	print("MOVIE start frame %d" % Engine.get_frames_drawn())
	if has_method("_run_" + _item):
		await call("_run_" + _item)
	else:
		push_error("unknown item " + _item)
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
	_cap_box = _box(Color(0.08, 0.06, 0.04, 0.8))
	_caption = _label(27, Color(1.0, 0.95, 0.78))
	_cap_box.add_child(_caption)
	layer.add_child(_cap_box)
	_cap_box.visible = false
	_title_box = _box(Color(0.10, 0.16, 0.30, 0.9))  # 네이비(로딩 화면과 같은 계열)
	_title = _label(34, Color(0.92, 0.95, 1.0))
	_title_box.add_child(_title)
	layer.add_child(_title_box)
	_title_box.visible = false


func _box(col: Color) -> PanelContainer:
	var b := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(14)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	b.add_theme_stylebox_override("panel", sb)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


func _label(px: int, col: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", FONT)
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", col)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(640, 0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _process(delta: float) -> void:
	var real := delta / maxf(Engine.time_scale, 0.01)
	for t in _taps:
		t[1] += real
	_taps = _taps.filter(func(t): return t[1] < 0.7)
	if _tap_layer != null:
		_tap_layer.queue_redraw()
	if _follow_fight:
		_follow_t -= real
		if _follow_t <= 0.0:
			_follow_t = 2.5
			var ms := get_tree().get_nodes_in_group("monsters").filter(func(m): return is_instance_valid(m) and m is Node3D and m.is_inside_tree())
			if not ms.is_empty():
				var best := Vector3.ZERO
				var best_n := 0
				for a in ms:  # 몬스터가 가장 많이 모인 곳(12m 안 수)
					var pa: Vector3 = (a as Node3D).global_position
					var n := 0
					for b in ms:
						if pa.distance_to((b as Node3D).global_position) < 12.0:
							n += 1
					if n > best_n:
						best_n = n
						best = pa
				print("TOUR follow ", best, " n=", best_n, " of ", ms.size())
				_cam().pan_to(Vector3(best.x, 0, best.z) * 0.85, 1.5)  # 무리 조금 안쪽(성벽 위 영웅도 보이게)


func _draw_taps() -> void:
	for t in _taps:
		var k: float = t[1] / 0.7
		_tap_layer.draw_circle(t[0], 14.0 + 26.0 * k, Color(1, 0.9, 0.3, 0.55 * (1.0 - k)))
		_tap_layer.draw_arc(t[0], 18.0 + 30.0 * k, 0, TAU, 40, Color(1, 1, 1, 0.9 * (1.0 - k)), 4.0)


## 자막(아래). y = 상자 위쪽.
func _say(t: String, y := 1010.0) -> void:
	_caption.text = t
	_cap_box.visible = t != ""
	_cap_box.size = Vector2(680, 0)
	_cap_box.position = Vector2(20, y)


## 콘텐츠 제목(위). 빈 글이면 숨긴다.
func _head(t: String, y := 150.0) -> void:
	_title.text = t
	_title_box.visible = t != ""
	_title_box.size = Vector2(680, 0)
	_title_box.position = Vector2(20, y)


## 콘텐츠 첫 화면: 제목을 크게 잠깐.
func _intro(t: String, sub := "") -> void:
	_head(t, 520)
	_say(sub, 620)
	await _wait(2.2)
	_head("")
	_say("")


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
	if c != null:
		_tap(c.get_global_rect().get_center())


## 보이는 버튼 중 글자(버튼 글 또는 안의 Label)가 text를 담은 첫 버튼을 누른다. 못 찾으면 false.
func _tap_text(text: String, from: Node = null) -> bool:
	var b := _btn(text, from)
	if b == null:
		print("TOUR no button: ", text)
		return false
	_tap_ctl(b)
	return true


func _btn(text: String, from: Node = null) -> Control:
	var root: Node = from if from != null else get_tree().root
	for c in root.find_children("*", "BaseButton", true, false):
		if not c.is_visible_in_tree() or not _on_screen(c):
			continue
		if _text_of(c).contains(text):
			return c
	return null


func _on_screen(c: Control) -> bool:
	var r := c.get_global_rect()
	return r.size.x > 4 and r.size.y > 4 and get_viewport().get_visible_rect().intersects(r)


func _text_of(c: Node) -> String:
	var s := ""
	if c is Button:
		s += (c as Button).text
	for l in c.find_children("*", "Label", true, false):
		s += " " + (l as Label).text
	return s


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _until(f: Callable, sec: float) -> bool:
	var t := 0.0
	while t < sec:
		if f.call():
			return true
		await get_tree().process_frame
		t += get_process_delta_time()
	return false


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


func _close_all() -> void:
	for x in get_tree().get_nodes_in_group(UiWindow.GROUP):
		if x.is_open():
			x.close()


## 창 안 스크롤을 천천히 내렸다 올린다(목록이 길면 끝까지 보여 준다).
func _scroll_tour(w: Node, sec := 3.0) -> void:
	var sc: ScrollContainer = null
	for c in w.find_children("*", "ScrollContainer", true, false):
		if c.is_visible_in_tree() and c.get_v_scroll_bar().max_value > c.size.y + 40:
			sc = c
			break
	if sc == null:
		await _wait(sec * 0.5)
		return
	var end := int(sc.get_v_scroll_bar().max_value - sc.size.y)
	var tw := create_tween()
	tw.tween_property(sc, "scroll_vertical", end, sec)
	await tw.finished
	await _wait(0.6)
	tw = create_tween()
	tw.tween_property(sc, "scroll_vertical", 0, sec * 0.5)
	await tw.finished


# ---------------------------------------------------------------- dump

func _shot(name: String) -> void:
	await _frames(8)
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("user://tour_dump")
	get_viewport().get_texture().get_image().save_png("user://tour_dump/%s.png" % name)
	var names := []
	for c in get_tree().root.find_children("*", "BaseButton", true, false):
		if c.is_visible_in_tree() and _on_screen(c):
			names.append(_text_of(c).strip_edges().replace("\n", "/"))
	print("DUMP ", name, " :: ", " | ".join(names))


func _run_dump() -> void:
	await _shot("castle")
	for id in ["growth", "hero", "soldier", "dungeon", "recruit", "shop"]:
		tabs.press(id)
		await _wait(2.0)
		await _shot("tab_" + id)
	_close_all()
	for id in ["settings", "notice", "mail", "bag", "mission", "ranking", "friend", "event", "exchange", "guild"]:
		_close_all()
		menu.pick(id)
		await _wait(2.5)
		await _shot("menu_" + id)
	_close_all()


func _req(path: String, body := {}) -> void:
	var done := [false]
	Net.send("POST", path, body, func(d):
		if d is Dictionary and d.has("version"):
			Economy.apply_server(d)
		if d is Dictionary and d.get("party") is Dictionary:
			Party._take(d)
		done[0] = true, func(): done[0] = true)
	await _until(func(): return done[0], 10.0)


func _cam():
	return _find("res://scripts/camera_rig.gd")


## 하단 탭 버튼을 눌러 창을 연다(누른 자리 표시).
func _tab(id: String) -> void:
	_tap_ctl(tabs.buttons[id])
	await _wait(1.6)


## 오른쪽 아래 [메뉴] → 항목.
func _menu(id: String) -> void:
	_close_all()
	await _wait(0.4)
	_tap_ctl(menu.toggle)
	await _wait(0.9)
	if menu.buttons.has(id) and menu.buttons[id].visible:
		_tap_ctl(menu.buttons[id])
	else:
		menu.pick(id)
	await _wait(1.8)


## 창 안 버튼을 글자로 누르고 잠깐 보여 준다.
func _press(text: String, sec := 2.0, from: Node = null) -> bool:
	var ok := _tap_text(text, from)
	await _wait(sec)
	return ok


# ================================================================ 콘텐츠

func _run_castle() -> void:
	await _intro("내 성", "방치형 디펜스 — 성을 키우고 영웅과 병사로 몰려오는 적을 막습니다")
	var rig = _cam()
	_say("위: 골드 · 목재 · 석재 · 식량 · 다이아\n가운데: 성채와 건물, 성벽 위 영웅, 성문 앞 병사")
	await _wait(4.0)
	rig.zoom_by(1.35)
	await _wait(1.0)
	_say("화면을 끌어 돌려 보고 두 손가락으로 확대·축소합니다")
	for i in 60:
		rig.rotate_yaw(1.5)
		await get_tree().process_frame
	await _wait(1.5)
	rig.zoom_by(0.65)
	await _wait(1.5)
	_say("건물을 누르면 건물 창 — 레벨업 · 생산 · 훈련 · 연구")
	_main._tutorial_goto("building:keep")
	await _wait(3.5)
	_close_all()
	_main._tutorial_goto("building:lumber")
	_say("목재소 · 채석장 · 농장은 시간이 지나면 자원이 쌓입니다")
	await _wait(3.5)
	_close_all()
	_say("왼쪽 아래 [건설] — 원하는 자리에 건물을 자유롭게 짓고 옮깁니다")
	var bb = _find("res://scripts/build_button.gd")
	if bb != null and bb.get("button") != null:
		_tap_ctl(bb.button)
	else:
		_find("res://scripts/build_list_panel.gd").open()
	await _wait(4.0)
	_close_tray()
	await _wait(0.6)
	_say("성 안을 돌아다니는 상인 — 남는 자원을 골드로 팝니다")
	_main._tutorial_goto("merchant")
	await _wait(3.5)
	_close_all()
	_say("오른쪽 아래 [메뉴]: 설정 · 공지 · 우편 · 가방 · 미션 · 랭킹 · 친구 · 이벤트 · 거래소 · 길드")
	_tap_ctl(menu.toggle)
	await _wait(4.0)
	_tap_ctl(menu.toggle)
	_say("")
	await _wait(1.0)


func _run_buildings() -> void:
	await _intro("건물 · 연구 · 파견", "라이즈 오브 킹덤즈처럼 성채 레벨이 다른 건물의 상한을 엽니다")
	_main._tutorial_goto("building:keep")
	_say("성채 — 성채 레벨이 오르면 새 건물과 영웅 자리가 열립니다")
	await _wait(3.0)
	await _scroll_tour(_find("res://scripts/building_panel.gd"), 2.5)
	_close_all()
	_main._tutorial_goto("building:barracks")
	_say("막사 · 궁수대 · 마구간 — 보병 · 궁병 · 기병을 훈련합니다")
	await _wait(3.5)
	await _press("훈련", 2.5)
	_close_all()
	_main._tutorial_goto("building:lab")
	_say("연구소 — 공격 · 방어 · 생산 연구로 모든 영웅·병사가 강해집니다")
	await _wait(2.5)
	_find("res://scripts/building_panel.gd").open_research()
	await _wait(3.0)
	var rp = _find("res://scripts/research_panel.gd")
	await _scroll_tour(rp, 2.5)
	_close_all()
	_main._tutorial_goto("building:dispatch")
	_say("파견소 — 쉬는 영웅을 의뢰에 보내 자원과 장비를 받아 옵니다")
	await _wait(2.5)
	_find("res://scripts/building_panel.gd").open_dispatch()
	await _wait(3.5)
	await _scroll_tour(_find("res://scripts/dispatch_panel.gd"), 2.0)
	_close_all()
	_main._tutorial_goto("building:forge")
	_say("대장간 · 창고 · 금광 · 망루 · 길드 회관 · 주점")
	await _wait(3.0)
	_close_all()
	_main._tutorial_goto("building:watchtower")
	await _wait(2.5)
	_close_all()
	_say("")


func _run_battle() -> void:
	await _intro("스테이지 전투", "메이플 키우기처럼 라운드를 밀고 70초마다 보스가 나옵니다")
	_say("[▶ 진행] — 다음 스테이지 도전")
	await _wait(1.0)
	if not _tap_text("진행"):
		_find("res://scripts/hud.gd").request_stage()
	await _wait(4.0)
	var rig = _cam()
	_follow_fight = true  # 몬스터가 가장 많이 몰린 곳으로 카메라를 천천히 옮긴다
	_say("적이 성문으로 몰려옵니다 — 성문 앞 병사와 성벽 위 원거리 영웅이 막습니다")
	await _wait(8.0)
	_say("왼쪽 아래 배속 x1 → x1.5 → x2")
	var sp = _find("res://scripts/speed_button.gd")
	if sp != null and sp.button != null and sp.button.is_visible_in_tree():
		_tap_ctl(sp.button)
		await _wait(0.8)
		_tap_ctl(sp.button)
	await _wait(6.0)
	_say("아래 영웅 초상화 위 스킬 — [스킬 AUTO]를 끄면 직접 눌러 씁니다")
	await _wait(8.0)
	_say("[통계] — 영웅마다 가한 피해 · 받은 피해 · 치유량")
	var st = _find("res://scripts/stats_button.gd")
	if st != null:
		st.open()
	await _wait(4.5)
	st.close()
	await _wait(0.3)

	_say("위 성문 체력(북·동·남·서)이 바닥나기 전에 적을 막아 라운드를 넘깁니다")
	await _wait(14.0)
	_say("")
	await _wait(6.0)
	_follow_fight = false
	if sp != null:
		sp.set_level(1.0)


func _run_growth() -> void:
	await _intro("성장", "골드로 공격 · 체력 · 공격 속도 등 모든 영웅·병사 공통 능력을 올립니다")
	await _tab("growth")
	_say("[강화]는 누르고 있으면 빠르게 연속 강화, [×10]은 10번 한 번에")
	await _wait(2.0)
	for i in 3:
		await _press("강화", 1.0)
	await _press("×10", 2.5)
	_say("")
	await _wait(1.5)
	_close_all()


func _run_hero() -> void:
	await _intro("영웅", "42명 영웅 — R · SR · SSR · UR, 별 ★0~★5")
	await _tab("hero")
	var hp = tabs.windows.hero
	_say("보유 영웅(전투력 순) — 위쪽 칸이 출전 중인 영웅")
	await _scroll_tour(hp, 3.0)
	var ids: Array = hp.owned_sorted()
	_say("영웅을 누르면 상세 — 능력치 · 스킬 3개 · 장비 6칸")
	await _wait(1.0)
	hp.show_detail(str(ids[0]))
	await _wait(4.0)
	_say("[레벨업] 골드 · [승급] 조각으로 별을 올립니다 (별마다 레벨 상한 +50)")
	await _press("레벨업", 2.5)
	_say("장비 — [자동 장착]으로 가장 좋은 장비를 한 번에")
	await _scroll_tour(hp, 2.0)
	hp.auto_equip()
	await _wait(2.5)
	_say("좌우로 넘겨 다른 영웅 보기")
	for i in 3:
		hp.step(1)
		await _wait(1.6)
	hp._show_list()
	await _wait(1.0)
	_say("[합성] — 같은 등급 영웅을 모아 윗 등급 영웅으로")
	await _press("합성", 3.5)
	_say("")
	_close_all()
	await _wait(1.0)


func _run_soldier() -> void:
	await _intro("병사", "보병 · 궁병 · 기병, T1~T5 티어")
	await _tab("soldier")
	_say("보유 병사와 배치 — 인구 안에서 [+][−]로 성문 앞에 세울 병사를 고릅니다")
	await _wait(3.0)
	await _press("자동 배치", 2.0)
	await _press("적용", 2.0)
	_say("[합성] 같은 티어 5마리 → 윗 티어 1마리")
	await _wait(2.5)
	_close_all()
	_main._tutorial_goto("building:barracks")
	_say("막사에서 병사를 훈련합니다 — 시간이 지나면 성문 앞으로")
	await _wait(4.0)
	_close_all()
	_say("")


func _run_recruit() -> void:
	await _intro("영웅 모집", "골드 모집과 다이아 모집 — 10회 모집은 SR 이상 1명 보장")
	await _tab("recruit")
	var rp = tabs.windows.recruit
	_say("골드 모집 — 모집할수록 레벨이 올라 SSR 확률이 오릅니다")
	await _wait(3.0)
	await _press("확률 정보", 3.5)
	await _scroll_tour(rp.odds, 2.0)
	if rp.odds.has_method("close"):
		rp.odds.close()
	else:
		rp.odds.visible = false
	await _wait(0.8)
	_say("다이아 모집 — SSR 5% · SR 30% · R 65% · UR 0.5%")
	await _press("다이아 모집", 2.0)
	_say("10회 모집 — 별빛 터널과 유성이 떨어지는 소환 연출")
	_tap_ctl(rp.ten_button)
	await _wait(9.0)
	_say("카드를 눌러 하나씩 뒤집거나 한 번에 모두 엽니다")
	await _wait(5.0)
	_say("[반복 모집] · [연출 건너뛰기]")
	await _wait(3.0)
	_close_all()
	_say("")


func _run_shop() -> void:
	await _intro("상점", "월정액 · 패키지 · 성장 패스 · 광고 보상 · 일일 · 주간 · PVP · 다이아")
	await _tab("shop")
	var w = tabs.windows.shop
	for t in [["패키지", "월정액과 패키지"], ["패스", "성장 패스 — 스테이지를 깰수록 보상"], ["광고", "광고 보고 무료 보상"], ["일일", "매일 바뀌는 일일 상품"],
			["주간", "주간 상품"], ["PVP", "PVP 점수로 사는 PVP 상점"], ["다이아", "다이아 충전"]]:
		_say(t[1])
		_tap_text(t[0], w)
		await _wait(1.6)
		await _scroll_tour(w, 2.0)
	_close_all()
	_say("")


func _run_dungeon() -> void:
	await _intro("던전", "골드 던전 · 장비 던전 · 모집권 던전 — 매일 열쇠로 도전")
	await _tab("dungeon")
	var w = tabs.windows.dungeon
	_say("카드마다 열쇠 수 · 단계 · 보상, ◀ ▶로 단계를 고릅니다")
	await _scroll_tour(w, 3.0)
	_say("[도전] → 출전 편성 — 영웅을 눌러 넣고 빼거나 [자동 편성]")
	await _press("도전", 3.0, w)
	_say("[출전]")
	await _press("출전", 2.0, w)
	_say("골드 던전 — 제한 시간 안에 몰려오는 적을 쓰러뜨려 골드를 모읍니다")
	await _wait(18.0)
	_say("")
	await _until(func(): return GameState.mode == GameState.Mode.IDLE, 40.0)
	await _wait(3.0)


func _run_pvp() -> void:
	await _intro("PVP", "결투(1:1 팀) · 총력전 — 시즌 점수와 PVP 상점")
	await _tab("dungeon")
	var w = tabs.windows.dungeon
	await _press("PVP", 2.5, w)
	Pvp.fetch()
	_say("모드 카드 — 결투 · 총력전")
	await _wait(2.0)
	w.pvp.open_mode("duel")
	_say("결투 — 내 점수 · 순위 · 상대 고르기 · 수비 팀")
	await _wait(3.0)
	await _scroll_tour(w, 2.0)
	var ended := [false]
	Pvp.result_ready.connect(func(_r): ended[0] = true)
	_say("[도전]")
	if not await _press("도전", 2.0, w):
		_close_all()
		Pvp.start("duel", Pvp.default_team("duel"))
	await _wait(3.0)
	_say("상대 성주의 영웅과 실시간 자동 전투 (2배속)")
	Engine.time_scale = 2.0
	var t := 0.0
	while not ended[0] and t < 60.0:
		await get_tree().process_frame
		t += get_process_delta_time() / 2.0
	Engine.time_scale = 1.0
	_say("결과 — 점수 변화")
	await _wait(5.0)
	_say("")


func _run_party() -> void:
	await _intro("파티 던전", "리치의 무덤 · 거미 여왕 — 다른 성주와 4인 파티")
	await _tab("dungeon")
	var w = tabs.windows.dungeon
	await _press("파티", 2.5, w)
	_say("보스마다 난이도 · 출전 영웅 고르기 · 친구 초대 · 파티 코드")
	await _scroll_tour(w, 2.5)
	_say("[파티 찾기] — 비슷한 성주를 찾아 자동으로 묶습니다")
	w.party_tab._start("lich")
	await _wait(2.0)
	await _req("/v1/test/party_bots_now", {})
	await _until(func(): return Party.state() == "confirm", 15.0)
	await _wait(1.5)
	Party.accept(true)
	await _until(func(): return _find("res://scripts/party_battle.gd") != null, 20.0)
	var b = _find("res://scripts/party_battle.gd")
	_say("내 영웅을 눌러 고르고 바닥을 눌러 움직입니다 — 보스 패턴을 피하세요")
	var t := 0.0
	Engine.time_scale = 1.5
	while b != null and is_instance_valid(b) and not b.done and t < 50.0:
		await get_tree().process_frame
		t += get_process_delta_time() / 1.5
		if t > 20.0 and t < 21.0:
			_say("보스의 장판 공격 · 졸개 소환 — 4명이 함께 막습니다")
	Engine.time_scale = 1.0
	await _wait(5.0)
	_say("")


func _run_guild() -> void:
	await _intro("길드", "출석 · 기부 · 길드 보스 · 길드전(공성전) · 길드 상점")
	await _menu("guild")
	var w = menu.windows.guild
	_say("길드 홈 — 길드 버프 · 공지 · 출석 · 출석 상자 · 기부")
	await _wait(2.0)
	await _press("출석하기", 2.0, w)
	await _scroll_tour(w, 3.0)
	_say("길드 보스 — 하루 2번, 길드원 피해를 모아 보상")
	await _press("보스", 3.5, w)
	_say("길드전(공성전) — 매주 다른 길드의 성을 공격하고 성문을 지킵니다")
	await _press("길드전", 3.5, w)
	await _scroll_tour(w, 2.0)
	_say("길드 상점 — 길드 코인으로 구매")
	await _press("상점", 2.0, w)
	await _scroll_tour(w, 2.0)
	_say("길드원 — 역할 · 전투력 · 마지막 접속")
	await _press("길드원", 3.0, w)
	_close_all()
	_say("")


func _run_missions() -> void:
	await _intro("미션 · 출석 이벤트", "일일 · 주간 · 반복 미션과 28일 출석")
	await _menu("mission")
	var w = menu.windows.mission
	_say("일일 미션 — 완료하면 [받기], [이동]은 그 화면으로 바로")
	await _wait(2.0)
	await _press("모두 받기", 2.5, w)
	await _scroll_tour(w, 2.0)
	_say("주간 미션")
	await _press("주간", 2.5, w)
	_say("반복 미션 — 끝없이 이어지는 목표")
	await _press("반복", 2.5, w)
	_say("")
	await _menu("event")
	_say("28일 출석 이벤트 — 매일 접속하면 다이아 · 열쇠 · 장비 · UR 영웅")
	await _wait(2.0)
	await _press("보상 받기", 3.0, menu.windows.event)
	_close_all()
	_say("")


func _run_bag() -> void:
	await _intro("가방 · 우편 · 공지", "방치 주머니와 운영자 우편, 공지사항")
	await _menu("notice")
	_say("공지사항 — 점검 · 이벤트 · 안내")
	await _wait(3.5)
	await _menu("mail")
	_say("우편함 — 운영자 선물 · 친구 다이아 선물 · 점검 보상")
	await _wait(2.5)
	await _press("모두 받기", 3.0, menu.windows.mail)
	await _menu("bag")
	_say("가방 — 방치 주머니를 열면 그 시간만큼의 골드 · 자원을 바로")
	await _wait(2.5)
	var w = menu.windows.bag
	var b := _btn("열기", w)
	if b != null:
		_tap_ctl(b)
	await _wait(3.0)
	_close_all()
	_say("")


func _run_social() -> void:
	await _intro("친구 · 랭킹 · 채팅", "다른 성주와 함께 — 친구 영웅 빌리기 · 다이아 선물")
	await _menu("friend")
	var w = menu.windows.friend
	_say("친구 목록 — 받은 신청 [수락], 친구에게 다이아 100개 선물")
	await _wait(2.5)
	await _press("수락", 2.0, w)
	await _press("모두 보내기", 2.5, w)
	await _scroll_tour(w, 2.0)
	_say("친구 추가 — 추천 성주 · 친구 코드로 찾기")
	await _press("친구 추가", 3.0, w)
	await _menu("ranking")
	w = menu.windows.ranking
	_say("랭킹 — 스테이지 · 전투력 · 길드")
	await _wait(2.5)
	await _press("전투력", 2.5, w)
	await _press("길드", 2.5, w)
	_close_all()
	_say("채팅 — 아래 채팅 줄을 누르면 전체 · 길드 채팅")
	var bar = _find("res://scripts/chat_bar.gd")
	var cp = _find("res://scripts/chat_panel.gd")
	cp.open()
	await _wait(3.5)
	await _press("길드", 3.0, cp)
	_close_all()
	_say("")


func _run_exchange() -> void:
	await _intro("거래소", "성주끼리 장비를 사고팝니다")
	await _menu("exchange")
	var w = menu.windows.exchange
	_say("구매 — 부위 · 등급 · 가격순으로 찾기")
	await _wait(3.0)
	await _scroll_tour(w, 2.0)
	_say("판매 등록 — 보관함 장비를 골드로 올립니다")
	await _press("판매 등록", 3.0, w)
	_say("내 판매 — 팔린 대금 받기")
	await _press("내 판매", 2.5, w)
	_close_all()
	_say("")


func _run_settings() -> void:
	await _intro("설정", "소리 · 그래픽 · 계정 · 쿠폰 · 문의")
	await _menu("settings")
	var w = menu.windows.settings
	_say("배경음악 · 효과음 · 그래픽 품질 · 프레임 · 절전 모드 · 화면 흔들림")
	await _wait(2.5)
	await _scroll_tour(w, 4.0)
	_say("닉네임 변경 · 친구 코드 · 계정 연결 · 쿠폰 · 문의하기")
	var sc: ScrollContainer = null
	for c in w.find_children("*", "ScrollContainer", true, false):
		if c.is_visible_in_tree():
			sc = c
			break
	if sc != null:
		sc.scroll_vertical = 100000
	await _wait(3.0)
	w.open_inquiry()
	_say("문의하기 — 앱 안에서 바로 문의, 답변도 앱으로")
	await _wait(3.0)
	_close_all()
	_say("")


func _run_admin() -> void:
	await _intro("운영 관리", "관리자 전용 — 점검 · 공지 · 우편 · 쿠폰 · 문의 · 신고 · 환불 · 통계")
	var ap = _find("res://scripts/admin_panel.gd")
	ap.open()
	await _wait(2.5)
	for t in ["상태", "공지", "우편", "쿠폰", "문의", "신고", "환불", "통계"]:
		_say("[%s]" % t)
		_tap_text(t, ap)
		await _wait(2.2)
	_close_all()
	_say("")


func _run_guide() -> void:
	await _intro("가이드 퀘스트", "처음 시작한 성주를 한 단계씩 이끄는 메이플 키우기식 가이드 (265개)")
	var card = _find("res://scripts/tutorial_card.gd")
	_say("아래 가이드 카드 — 지금 할 일과 보상, 화살표가 누를 곳을 가리킵니다", 120)
	await _wait(4.0)
	for st in [0, 3, 6, 10, 16, 24, 40, 70]:
		if st > 0:
			await _req("/v1/test/tut_step", {"step": st})
			await _wait(1.5)
		var m: Dictionary = Tutorial.mission()
		_say("가이드 %d — %s" % [st + 1, str(m.get("title", m.get("text", "")))] if not m.is_empty() else "", 120)
		await _wait(1.5)
		if card != null and card.action_button != null and card.action_button.is_visible_in_tree():
			_tap_ctl(card.action_button)
		await _wait(3.5)
		_close_all()
		_close_tray()
		await _wait(0.5)
	_say("")
	await _wait(1.5)


func _close_tray() -> void:
	var bl = _find("res://scripts/build_list_panel.gd")
	if bl != null and bl.is_open() and bl.has_method("close"):
		bl.close()
