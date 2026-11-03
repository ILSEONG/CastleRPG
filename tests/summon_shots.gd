extends Node
## 소환 연출 스틸(개발용): 등급마다 몇 순간을 찍어 한 장으로 붙인다.
##   xvfb-run -a godot --path . --resolution 720x1280 res://tests/summon_shots.tscn -- --out=/tmp/summon.png

const SummonStage := preload("res://scripts/summon_stage.gd")


func _ready() -> void:
	var out := "/tmp/summon.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	var st = SummonStage.new()
	add_child(st)
	await get_tree().process_frame
	var rows := []
	for g in ["R", "SR", "SSR", "UR"]:
		var row := []
		st.play(g, 10)
		var times := [0.18, 0.32, 0.46, 0.7, 0.97].map(func(x): return x * st._len)
		var last := 0.0
		for t in times:
			while st._t < t:
				await get_tree().process_frame
			var img := get_viewport().get_texture().get_image()
			img.resize(240, 427)
			row.append(img)
		rows.append(row)
		st.stop()
	var sheet := Image.create(240 * 5, 427 * 4, false, Image.FORMAT_RGBA8)
	for y in rows.size():
		for x in rows[y].size():
			var im: Image = rows[y][x]
			im.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(im, Rect2i(0, 0, 240, 427), Vector2i(x * 240, y * 427))
	sheet.save_jpg(out, 0.85)
	print("SUMMON SHOTS ", out)
	get_tree().quit()
