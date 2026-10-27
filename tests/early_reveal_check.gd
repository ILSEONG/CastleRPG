extends Node
## 초반 단순화(사용자 2026-10-23 "처음 몇 시간 동안 보이는 재화·버튼을 줄이고"): 새 게임으로 main을 띄워
## 가이드 중 숨긴 화면 요소가 그 미션에서 하나씩 나타나는지, 나타날 때 「새 기능」 띠가 뜨는지 본다.
## 1) 새 게임: 골드·다이아 칩, [진행], 가이드 카드만. 목재·석재·식량 칩, 하단 탭, [건설], 상인, [연속 진행], FEVER, 채팅 줄은 없고 [메뉴]는 설정·공지·우편만.
## 2) 1-1 클리어 → [보상 받기]: [영웅]·[상점] 탭과 "새 기능: 영웅 · 상점" 띠.
## 3) 「벌목장 건설」 미션: [건설] 버튼·목재 칩. 4) 「상인과 거래」: 상인. 5) 가이드를 끝내면(또는 건너뛰면) 전부 보인다.
## 실행: xvfb-run -a godot --path . --resolution 720x1280 res://tests/early_reveal_check.tscn  (마지막 줄 EARLY REVEAL PASSED)
##   -- --out=<png 경로>: 단계마다 찍은 화면을 한 장으로 붙여 저장한다

const PreloaderScript := preload("res://scripts/preloader.gd")
const GuideTour := preload("res://scripts/guide_tour.gd")

var _fails := 0
var _shots: Array = []
var _hud
var _tabs
var _menu
var _build
var _scenery
var _banner


func _ready() -> void:
	Economy.save_path = ""
	Fever.save_path = ""
	Guild.save_path = ""
	GuildWar.save_path = ""
	Party.save_path = ""
	await _frames(2)
	Tutorial.save_path = ""
	Economy.reset(Time.get_unix_time_from_system())
	Fever.auto_next = false
	Tutorial.begin(true)
	Tutorial.tours_on = false
	PreloaderScript.done = true
	add_child(preload("res://scenes/main.tscn").instantiate())
	await _frames(40)
	var root := get_tree().root
	_hud = GuideTour.find_script_node(root, "res://scripts/hud.gd")
	_tabs = GuideTour.find_script_node(root, "res://scripts/tab_bar.gd")
	_menu = GuideTour.find_script_node(root, "res://scripts/side_menu.gd")
	_build = GuideTour.find_script_node(root, "res://scripts/build_button.gd")
	_scenery = GuideTour.find_script_node(root, "res://scripts/buildings.gd")
	_banner = GuideTour.find_script_node(root, "res://scripts/reveal_banner.gd")
	_check(_hud != null and _tabs != null and _menu != null and _build != null and _scenery != null and _banner != null, "main has the HUD, tabs, menu, [건설], scenery and the banner", "")
	if _fails > 0:
		return _finish()
	# 1) 새 게임
	_menu.set_open(true)
	await _frames(20)
	_check(_chip("gold") and _chip("diamond") and not _chip("wood") and not _chip("stone") and not _chip("food"), "new game: only the gold and diamond chips", _chips_text())
	_check(not _tabs._bar.visible and _tabs.buttons.values().all(func(b): return not b.visible), "new game: no bottom tabs", _tabs_text())
	_check(not _build.button.visible and not _scenery.merchant_shown() and not _hud._auto.visible and not _hud._fever.visible, "new game: no [건설], merchant, [연속 진행] or FEVER",
		"build=%s merchant=%s auto=%s fever=%s" % [_build.button.visible, _scenery.merchant_shown(), _hud._auto.visible, _hud._fever.visible])
	_check(_menu_ids() == ["settings", "notice", "mail"], "new game: the menu has settings, notice and mail only", str(_menu_ids()))
	await _snap("새 게임 첫 화면")
	_menu.set_open(false)
	# 2) 1-1 클리어 → 보상
	GameState.stage = 2
	Tutorial.note_stage(2)
	Tutorial.check()
	await _frames(5)
	_check(Tutorial.complete() and Tutorial.claim(), "1-1 cleared: [보상 받기]", "step=%d" % Tutorial.step)
	await _frames(20)
	_check(_tabs._bar.visible and _tabs.buttons.hero.visible and _tabs.buttons.shop.visible and not _tabs.buttons.growth.visible, "after 1-1: [영웅]·[상점] tabs appear", _tabs_text())
	_check(_banner.band.visible and _banner.label.text == "새 기능: 영웅 · 상점", "after 1-1: one \"새 기능\" band names both", "%s %s" % [_banner.band.visible, _banner.label.text])
	await _snap("1-1 보상 뒤")
	# 3) 벌목장 미션
	await _frames(int(60 * (_banner.HOLD_SEC + _banner.FADE_SEC)) + 10)
	Tutorial.step = Tutorial.mission_index("build_lumber")
	Tutorial.changed.emit()
	await _frames(20)
	_check(_build.button.visible and _chip("wood") and not _chip("stone"), "lumber mission: [건설] and the wood chip appear", _chips_text())
	_check(_banner.band.visible and _banner.label.text.contains("건설") and not _banner.label.text.contains("목재"), "lumber mission: the band names [건설] (chips appear quietly)", _banner.label.text)
	_check(_hud._auto.visible and Tutorial.ui_shown("hud:speed") and _tabs.buttons.growth.visible, "earlier missions' [연속 진행], speed and [성장] stay shown", _tabs_text())
	await _snap("벌목장 미션")
	# 4) 상인
	Tutorial.step = Tutorial.mission_index("sell")
	Tutorial.changed.emit()
	await _frames(20)
	_check(_scenery.merchant_shown() and _chip("stone") and _chip("food"), "merchant mission: the merchant shows (stone/food chips by now)", _chips_text())
	# 5) 가이드 끝: 전부
	Tutorial.state = "done"
	Tutorial.changed.emit()
	_menu.set_open(true)
	await _frames(20)
	_check(_chip("wood") and _chip("stone") and _chip("food") and _tabs.buttons.values().all(func(b): return b.visible) and _menu_ids().size() == 10 and _build.button.visible,
		"guide done: every chip, tab and menu item shows", "%s / %s / %s" % [_chips_text(), _tabs_text(), _menu_ids()])
	await _snap("가이드를 끝낸 뒤")
	_menu.set_open(false)
	_finish()


func _finish() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out=") and not _shots.is_empty():
			_sheet(a.substr(6))
	print("EARLY REVEAL %s" % ("PASSED" if _fails == 0 else "FAILED %d" % _fails))
	get_tree().quit(0 if _fails == 0 else 1)


func _chip(kind: String) -> bool:
	return _hud._chips[kind].get_parent().get_parent().visible


func _chips_text() -> String:
	return str(["gold", "wood", "stone", "food", "diamond"].filter(func(k): return _chip(k)))


func _tabs_text() -> String:
	return str(_tabs.buttons.keys().filter(func(k): return _tabs.buttons[k].visible))


func _menu_ids() -> Array:
	return _menu.buttons.keys().filter(func(k): return _menu.buttons[k].visible)


func _snap(_title: String) -> void:
	await _frames(4)
	_shots.append(get_viewport().get_texture().get_image())


func _sheet(path: String) -> void:
	var w: int = _shots[0].get_width() / 2
	var h: int = _shots[0].get_height() / 2
	var out := Image.create(w * _shots.size(), h, false, Image.FORMAT_RGBA8)
	for i in _shots.size():
		var im: Image = _shots[i]
		im.convert(Image.FORMAT_RGBA8)
		im.resize(w, h, Image.INTERPOLATE_LANCZOS)
		out.blit_rect(im, Rect2i(0, 0, w, h), Vector2i(i * w, 0))
	out.save_png(path)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _check(ok: bool, what: String, detail: String) -> void:
	print(("PASS " if ok else "FAIL ") + what + ("" if ok else "  " + detail))
	if not ok:
		_fails += 1
