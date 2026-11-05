extends Control
## 길드 문양 시안 한 장(개발용, 화면 필요): 모양 8 · 문양 20 · 색 조합 예시를 그려 PNG로 저장하고 끝난다.
## 실행: xvfb-run -a godot --path . --resolution 1200x1500 res://tests/emblem_sheet.tscn -- --out=/tmp/emblem_sheet.png

const E := preload("res://scripts/guild_emblem.gd")


func _ready() -> void:
	var bad := 0
	for i in E.SYMBOLS:
		for p in E.symbol_parts(i):
			if Geometry2D.triangulate_polygon(p.poly).is_empty():
				print("BAD symbol ", i, " ", p.poly)
				bad += 1
	for i in E.SHAPES:
		if Geometry2D.triangulate_polygon(E.shape_poly(i)).is_empty():
			print("BAD shape ", i)
			bad += 1
	print("bad polys: ", bad)
	queue_redraw()
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var out := "/tmp/emblem_sheet.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	get_viewport().get_texture().get_image().save_png(out)
	get_tree().quit()


func _draw() -> void:
	var w := get_viewport_rect().size.x
	draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), Color(0.93, 0.88, 0.76))
	var cell := w / 8.0
	# 1줄: 모양 8가지(같은 색·문양)
	for i in E.SHAPES:
		E.draw_parts(self, Vector2(cell * (i + 0.5), cell * 0.5), cell * 0.86, i, 0, E.BG[5], E.FG[0])
	# 2~4줄: 문양 20가지(조합 다양)
	var cols := [[0, 0], [5, 1], [2, 0], [6, 2], [11, 4], [3, 0], [1, 3], [7, 0], [9, 1], [4, 0]]
	for i in E.SYMBOLS:
		var r := 1 + i / 8
		var k := i % 8
		var cc: Array = cols[i % cols.size()]
		E.draw_parts(self, Vector2(cell * (k + 0.5), cell * (r + 0.5)), cell * 0.86, (i * 3) % E.SHAPES, i, E.BG[cc[0]], E.FG[cc[1]])
	# 5~6줄: 무작위 조합(추천·상대 길드가 받는 것)
	for k in 16:
		var v := E.from_seed(k * 7919 + 123457)
		E.draw(self, Vector2(cell * (k % 8 + 0.5), cell * (4 + k / 8 + 0.5)), cell * 0.86, v)
	# 마지막 줄: 작은 크기(목록·랭킹 48px)
	for k in 16:
		E.draw(self, Vector2(40 + k * 70, cell * 6 + 40), 48, E.from_seed(k * 104729 + 7))
