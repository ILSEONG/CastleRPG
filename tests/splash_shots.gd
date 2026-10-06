extends Node
## 시작 화면 스냅샷(개발용): 로딩 화면(preloader — 서버 연결·불러오기)과 로그인 화면을 찍어 한 장으로 붙인다(부트 스플래시는 splash.png 그대로).
## 화면이 필요하다(헤드리스 불가). 실행: xvfb-run -a godot --path . --resolution 720x1600 res://tests/splash_shots.tscn -- --out=/tmp/splash.png

const PreloaderScript := preload("res://scripts/preloader.gd")
const LoginScreenScript := preload("res://scripts/login_screen.gd")

var _shots: Array = []


func _ready() -> void:
	var load_screen = PreloaderScript.new()
	load_screen.connecting = true
	add_child(load_screen)
	await _frames(5)
	load_screen.label.text = PreloaderScript.LOAD_TEXT
	load_screen.bar.value = 55.0
	await _snap()
	load_screen.set_process(false)
	load_screen.queue_free()
	var login = LoginScreenScript.new()
	add_child(login)
	await _snap()
	var w := 0
	for s in _shots:
		w += s.get_width()
	var sheet := Image.create(w + 24 * (_shots.size() - 1), _shots[0].get_height(), false, Image.FORMAT_RGB8)
	sheet.fill(Color.WHITE)
	var x := 0
	for s in _shots:
		sheet.blit_rect(s, Rect2i(Vector2i.ZERO, s.get_size()), Vector2i(x, 0))
		x += s.get_width() + 24
	var out := "/tmp/splash_shots.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
	sheet.save_png(out)
	print("saved ", out)
	get_tree().quit()


func _snap() -> void:
	await _frames(20)
	var img := get_viewport().get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	_shots.append(img)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
