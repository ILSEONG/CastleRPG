extends "res://scripts/ui_window.gd"
## 길드 문양 만들기 창(2026-11-05, 사용자 "길드 문양은 길드장이 만들 수 있게해, 배경 모양 + 가운데 문양 + 배경 색 + 가운데 문양 색 조합으로"):
## 라이즈 오브 킹덤즈 연맹 깃발 편집, 로드 모바일 길드 배지, 클래시 오브 클랜 배지 편집처럼 위에 큰 미리보기, 아래에 고르는 칸 탭 네 개
## (배경 모양 · 가운데 문양 · 배경 색 · 문양 색)와 [무작위] [취소] [저장]. 저장하면 on_save(값)을 부른다 — 창설 카드는 고른 값만 들고,
## 길드장 화면은 Guild.set_emblem으로 서버에 보낸다(서버가 길드장인지 다시 본다).

const Lang := preload("res://scripts/lang.gd")
const E := preload("res://scripts/guild_emblem.gd")

const TABS := ["shape", "symbol", "bg", "fg"]
const CELL := 100.0
const SWATCH := Vector2(90, 70)

var shape := 0
var symbol := 0
var bg := 0
var fg := 0
var tab := "shape"
var on_save := Callable()
var buttons := {}  # 테스트용: "tab:shape", "pick:3", "random", "save", "cancel"

var _preview: Control
var _tab_row: HBoxContainer
var _grid: GridContainer


func _ready() -> void:
	_build_window(660, 12)
	layer = 3  # 길드 창(2) 위
	content.add_child(_title(Lang.t("guild_emblem_editor.title")))
	_preview = Control.new()
	_preview.custom_minimum_size = Vector2(0, 220)
	_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview.draw.connect(func(): E.draw_parts(_preview, _preview.size / 2.0, 210.0, shape, symbol, E.BG[bg], E.FG[fg]))
	content.add_child(_preview)
	_tab_row = HBoxContainer.new()
	_tab_row.add_theme_constant_override("separation", 6)
	content.add_child(_tab_row)
	var holder := CenterContainer.new()
	holder.custom_minimum_size = Vector2(0, (CELL + 8) * 4)
	content.add_child(holder)
	_grid = GridContainer.new()
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 8)
	holder.add_child(_grid)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var rnd := _button(Lang.t("guild_emblem_editor.random"), UiKit.STEEL, 26)
	rnd.custom_minimum_size.x = 150
	rnd.pressed.connect(randomize_all)
	row.add_child(rnd)
	buttons["random"] = rnd
	var cancel := _button(Lang.t("guild_emblem_editor.cancel"), UiKit.STEEL, 26)
	cancel.custom_minimum_size.x = 150
	cancel.pressed.connect(close)
	row.add_child(cancel)
	buttons["cancel"] = cancel
	var save := _button(Lang.t("guild_emblem_editor.save"), UiKit.AMBER, 26)
	save.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save.pressed.connect(_save)
	row.add_child(save)
	buttons["save"] = save
	content.add_child(row)
	_rebuild()


## 값 v로 열고, 저장하면 done(새 값).
func edit(v: int, done: Callable) -> void:
	var d := E.decode(v)
	shape = int(d.shape)
	symbol = int(d.symbol)
	bg = int(d.bg)
	fg = int(d.fg)
	on_save = done
	tab = "shape"
	open()


func value() -> int:
	return E.encode(shape, symbol, bg, fg)


func _on_open() -> void:
	_rebuild()
	_fit()


func randomize_all() -> void:
	shape = randi() % E.SHAPES
	symbol = randi() % E.SYMBOLS
	bg = randi() % E.BG.size()
	fg = randi() % E.FG.size()
	if _too_close(bg, fg):
		fg = 0 if E.BG[bg].get_luminance() < 0.5 else 3
	_rebuild()


## 배경과 문양 색이 너무 비슷하면(무작위일 때만 피한다 — 직접 고르면 그대로 둔다).
static func _too_close(b: int, f: int) -> bool:
	var a: Color = E.BG[b]
	var c: Color = E.FG[f]
	return absf(a.get_luminance() - c.get_luminance()) < 0.18 and Vector3(a.r - c.r, a.g - c.g, a.b - c.b).length() < 0.45


func pick(i: int) -> void:
	match tab:
		"shape":
			shape = i
		"symbol":
			symbol = i
		"bg":
			bg = i
		_:
			fg = i
	_rebuild()


func set_tab(t: String) -> void:
	tab = t
	_rebuild()


func _save() -> void:
	var v := value()
	close()
	if on_save.is_valid():
		on_save.call(v)


func _rebuild() -> void:
	if _grid == null:
		return
	_preview.queue_redraw()
	for k in buttons.keys():
		if str(k).begins_with("tab:") or str(k).begins_with("pick:"):
			buttons.erase(k)
	for c in _tab_row.get_children():
		_tab_row.remove_child(c)
		c.queue_free()
	for t in TABS:
		var b := Button.new()
		b.text = Lang.t("guild_emblem_editor.tab_" + t)
		b.custom_minimum_size = Vector2(0, 54)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 22)
		UiKit.apply_button(b, UiKit.AMBER if t == tab else UiKit.STEEL, 10.0)
		b.pressed.connect(set_tab.bind(t))
		_tab_row.add_child(b)
		buttons["tab:" + t] = b
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	var n: int
	match tab:
		"shape":
			n = E.SHAPES
		"symbol":
			n = E.SYMBOLS
		"bg":
			n = E.BG.size()
		_:
			n = E.FG.size()
	var colors := tab == "bg" or tab == "fg"
	_grid.columns = 6 if colors else 5
	var cur: int = {"shape": shape, "symbol": symbol, "bg": bg, "fg": fg}[tab]
	for i in n:
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = SWATCH if colors else Vector2(CELL, CELL)
		UiKit.apply_button(b, UiKit.AMBER if i == cur else Color(1, 1, 1, 0.55), 10.0)
		var face := Control.new()
		face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		face.mouse_filter = Control.MOUSE_FILTER_IGNORE
		face.draw.connect(_draw_cell.bind(face, i))
		b.add_child(face)
		b.pressed.connect(pick.bind(i))
		_grid.add_child(b)
		buttons["pick:%d" % i] = b
	_fit()


func _draw_cell(face: Control, i: int) -> void:
	var c := face.size / 2.0
	match tab:
		"shape":
			E.draw_parts(face, c, CELL * 0.8, i, symbol, E.BG[bg], E.FG[fg])
		"symbol":
			E.draw_parts(face, c, CELL * 0.8, shape, i, E.BG[bg], E.FG[fg])
		"bg":
			_swatch(face, c, E.BG[i])
		_:
			_swatch(face, c, E.FG[i])


## 색 칸: 각진 육각 보석(왼쪽 위 밝게) — 외곽선 없이 아래 그림자만.
func _swatch(face: Control, c: Vector2, col: Color) -> void:
	var r := 26.0
	var pts := PackedVector2Array()
	var sh := PackedVector2Array()
	for k in 6:
		var a := k * TAU / 6.0
		pts.append(c + Vector2(cos(a), sin(a)) * r)
		sh.append(c + Vector2(0, 3) + Vector2(cos(a), sin(a)) * r)
	face.draw_colored_polygon(sh, Color(0, 0, 0, 0.25))
	face.draw_colored_polygon(pts, col)
	face.draw_colored_polygon(PackedVector2Array([c, pts[3], pts[4], pts[5]]), col.lightened(0.18))
	face.draw_colored_polygon(PackedVector2Array([c, pts[0], pts[1], pts[2]]), col.darkened(0.14))
