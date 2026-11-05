extends Control
## 티어 문양 확인(개발용): 위 줄 = PVP 화면 배지(PvpView.draw_badge), 아래 = 그림 문양(TierEmblem.draw). 화면이 필요하다.
## 실행: xvfb-run -a godot --path . --resolution 720x1280 res://tests/tier_emblem_shots.tscn -- --out=/tmp/tiers.png

const PvpRules := preload("res://scripts/pvp_rules.gd")
const PvpView := preload("res://scripts/pvp_view.gd")
const TierEmblem := preload("res://scripts/tier_emblem.gd")
const UiKit := preload("res://scripts/ui_kit.gd")
const HudScript := preload("res://scripts/hud.gd")


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = UiKit.CREAM
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	for i in PvpRules.TIERS.size():
		var id: String = PvpRules.TIERS[i][0]
		var old := Control.new()
		old.position = Vector2(8 + i * 101, 16)
		old.size = Vector2(96, 112)
		old.draw.connect(func(): PvpView.draw_badge(old, id))
		add_child(old)
		var nw := Control.new()
		nw.position = Vector2((i % 3) * 240 + 30 + (240 if i == 6 else 0), 130 + (i / 3) * 300)
		nw.size = Vector2(180, 330)
		nw.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		nw.draw.connect(func():
			TierEmblem.draw(nw, id, Vector2(90, 130), 130.0)
			var font := ThemeDB.fallback_font
			var name: String = PvpRules.TIERS[i][1]
			var tw := font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
			nw.draw_string(font, Vector2(90 - tw / 2.0, 260), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, HudScript.INK))
		add_child(nw)
	for k in 10:
		await get_tree().process_frame
	var out := "/tmp/tiers.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	get_viewport().get_texture().get_image().save_png(out)
	print("saved ", out)
	get_tree().quit()
