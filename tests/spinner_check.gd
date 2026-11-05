extends Node
## 로딩 고리 체크(사용자 2026-11-05 "인게임 내에서 로딩이 걸리는 부분은 스피너처리를 해"):
## (1) Spinner.mark: 「불러오는 중」 글 왼쪽에 고리, 글이 바뀌면 숨는다 (2) 가운데 고리: 0.25초 넘게 기다릴 때만, 풀리면 숨는다,
## 던전 입장 대기(Economy._waiting "dungeon")도 띄운다 (3) 실제 창: 랭킹 창이 불러오는 중이면 고리가 보인다.
## 실행: xvfb-run -a godot --path . --resolution 720x1280 res://tests/spinner_check.tscn [-- --out=<png>]  (마지막 줄 SPINNER PASSED)

const Spinner := preload("res://scripts/spinner.gd")
const Busy := preload("res://scripts/busy_spinner.gd")

var _fails := 0


func _ready() -> void:
	var out := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	var layer := CanvasLayer.new()
	add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color(0.93, 0.89, 0.8)
	bg.size = Vector2(720, 1280)
	layer.add_child(bg)
	var l := Label.new()
	l.text = "불러오는 중…"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 26)
	l.add_theme_color_override("font_color", Color(0.35, 0.33, 0.3))
	l.position = Vector2(60, 300)
	l.size = Vector2(600, 40)
	layer.add_child(l)
	var s = Spinner.mark(l)
	await _frames(3)
	_check(s != null and s.visible and s.position.x + s.size.x <= (l.size.x - 200.0) / 2.0 + 30.0 and s.position.x > 0.0, "(1) a ring shows just left of the centred loading text", str(s.position if s else null))
	_check(Spinner.mark(l) == s, "(1) marking twice keeps one ring", "")
	var busy = Busy.new()
	add_child(busy)
	await _frames(2)
	_check(not busy.box.visible, "(2) no centre ring when nothing waits", "")
	Spinner.hold("t", true)
	await _frames(2)
	_check(not busy.box.visible, "(2) a short wait (<0.25 s) does not flash the ring", "")
	await get_tree().create_timer(0.35).timeout
	await _frames(2)
	_check(busy.box.visible and absf(busy.box.get_global_rect().get_center().x - 360.0) < 2.0, "(2) after 0.25 s the ring shows in the screen centre", str(busy.box.get_global_rect()))
	if out != "":
		get_viewport().get_texture().get_image().save_png(out)
	Spinner.hold("t", false)
	await _frames(2)
	_check(not busy.box.visible, "(2) released: the ring goes", "")
	l.text = "결과"
	await _frames(2)
	_check(not s.visible, "(1) the label's text changed: its ring hides", "")
	Economy._waiting["dungeon"] = true
	await get_tree().create_timer(0.35).timeout
	await _frames(2)
	_check(busy.box.visible, "(2) waiting for the dungeon start shows the centre ring", "")
	Economy._waiting.erase("dungeon")
	await _frames(2)
	_check(not busy.box.visible, "(2) dungeon answer: ring goes", "")
	print("SPINNER FAILED %d" % _fails if _fails > 0 else "SPINNER PASSED")
	get_tree().quit(1 if _fails > 0 else 0)


func _check(ok: bool, what: String, detail: String) -> void:
	if ok:
		print("PASS ", what)
	else:
		_fails += 1
		print("FAIL ", what, "  ", detail)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
