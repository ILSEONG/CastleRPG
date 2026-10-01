extends "res://scripts/ui_window.gd"
## [병사] 탭 시트(개정 13 §6·§7.1): 위 "배치 d / 인구 (인구)", 보유 병종·티어 행(티어 높은 순, 같은 티어는 자동 배치 순서 보병 → 기병 → 궁병) —
## 병종 그림(unit_icon: figure + 오른위 갈매기 티어)·"보병 T2"·보유 N·[−] d [+]([+]는 보유·인구 상한에서, [−]는 0에서 비활성).
## [자동 배치](Economy.auto_deploy — 적용 안 함)·[모두 해제]·[적용](편집이 지금 배치와 같으면 비활성) → Economy.set_soldier_deploy.
## 아래 병사 건물 생산 상태 3줄 "보병 막사 Lv 3 · 다음 2:41:10"(열려 있는 동안 매 프레임 글자만 고친다).
## 편집(work)은 열 때 지금 배치로 시작하고, 합성으로 보유가 줄면 보유로 자른다. 영웅 시트처럼 칩 줄 아래 ~ 탭 바 위를 채우고 뒤 입력을 막는다.
## unit_icon·figure는 건물 창(병사 건물 합성 칸)도 쓴다.

const GameData := preload("res://scripts/game_data.gd")
const EconomyScript := preload("res://scripts/economy.gd")
const Art := preload("res://scripts/art.gd")
const LowpolyBox := preload("res://scripts/lowpoly_box.gd")
const PortraitsScript := preload("res://scripts/portraits.gd")
const FONT := preload("res://assets/fonts/Pretendard-SemiBold.otf")

const EMPTY_TEXT := "보유한 병사가 없습니다"
const ROW_ICON_PX := 72.0
const CHEVRON := Color(1.0, 0.84, 0.3)  # hp_bars 갈매기와 같은 금색 + 진한 테두리
const CHEVRON_EDGE := Color(0.12, 0.10, 0.14)
const ALL := 1 << 30  # 인구 무제한(행 순서 = 자동 배치 순서)

var work := {}  # 편집 중인 배치 "병종:티어" → 수(> 0만)
var rows := {}  # 키 → {box, count, have, minus, plus}(표시 순서)
var summary_label: Label
var empty_label: Label
var auto_button: Button
var clear_button: Button
var apply_button: Button
var prod_labels := {}  # 병사 건물 id → 생산 상태 Label

var _rows_box: VBoxContainer


func _ready() -> void:
	_build_window(0, 10)
	dialog.get_parent().color = Color(0, 0, 0, 0)  # 시트가 화면을 채운다
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(_title("병사"))
	summary_label = _label("", 30)
	content.add_child(summary_label)
	empty_label = _label(EMPTY_TEXT, 26, HudScript.INK.lightened(0.3))
	content.add_child(empty_label)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	_rows_box = VBoxContainer.new()
	_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows_box.add_theme_constant_override("separation", 8)
	scroll.add_child(_rows_box)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)
	content.add_child(bar)
	auto_button = _button("자동 배치", UiKit.STEEL, 26)
	auto_button.pressed.connect(func(): _set_work(Economy.auto_deploy()))
	clear_button = _button("모두 해제", UiKit.STEEL, 26)
	clear_button.pressed.connect(func(): _set_work({}))
	apply_button = _button("적용")
	apply_button.pressed.connect(apply)
	for b in [auto_button, clear_button, apply_button]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.add_child(b)
	for s in GameData.soldiers():
		var l := _label("", 24, HudScript.INK, HORIZONTAL_ALIGNMENT_LEFT)
		content.add_child(l)
		prod_labels[s.building] = l
	_fit()
	Economy.soldiers_changed.connect(_refresh)
	Economy.changed.connect(_refresh)  # 인구(민가 레벨)


func _fit() -> void:
	_fit_sheet()


func _on_open() -> void:
	work = Economy.soldier_deploy()
	_refresh()


func _process(_delta: float) -> void:
	if visible:
		_tick_production()


## 행 key의 배치 수를 d만큼 — 0 아래, 보유 위, 인구 위([+]일 때)로는 가지 않는다(버튼 비활성과 같은 규칙).
func step(key: String, d: int) -> void:
	var n := int(work.get(key, 0)) + d
	if n < 0 or n > int(Economy.soldiers.get(key, 0)) or (d > 0 and _total(work) >= Economy.population()):
		return
	if n == 0:
		work.erase(key)
	else:
		work[key] = n
	_refresh()


func apply() -> void:
	if Economy.set_soldier_deploy(work):
		var later := "" if GameState.mode == GameState.Mode.IDLE else " — 다음 스테이지부터"
		Economy.notice.emit("병사 배치를 적용했습니다" + later)
	_refresh()


func _set_work(d: Dictionary) -> void:
	work = d.duplicate()
	_refresh()


static func _total(d: Dictionary) -> int:
	var n := 0
	for k in d:
		n += int(d[k])
	return n


func _refresh() -> void:
	if not visible:
		return
	var owned := Economy.soldier_counts()
	work = EconomyScript.trim_deploy(work, owned)  # 합성으로 줄었으면 보유로
	var keys := EconomyScript.auto_deploy_for(owned, ALL).keys()
	if keys != rows.keys():
		_rebuild_rows(keys)
	var pop := Economy.population()
	var total := _total(work)
	summary_label.text = "배치 %d / %d (인구)" % [total, pop]
	for k in rows:
		var n := int(work.get(k, 0))
		var r: Dictionary = rows[k]
		r.count.text = str(n)
		r.have.text = "보유 %d" % int(owned[k])
		r.minus.disabled = n == 0
		r.plus.disabled = n >= int(owned[k]) or total >= pop
	empty_label.visible = rows.is_empty()
	apply_button.disabled = work == Economy.soldier_deploy() or Economy.soldier_deploy_block(work) != ""
	clear_button.disabled = work.is_empty()
	auto_button.disabled = work == Economy.auto_deploy()
	_tick_production()


func _rebuild_rows(keys: Array) -> void:
	for r in rows.values():
		_rows_box.remove_child(r.box)
		r.box.queue_free()
	rows.clear()
	for k in keys:
		var p := EconomyScript.parse_soldier_key(k)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.add_child(unit_icon(p[0], p[1], ROW_ICON_PX))
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.alignment = BoxContainer.ALIGNMENT_CENTER
		info.add_child(_label("%s T%d" % [GameData.soldier(p[0]).name, p[1]], 28, HudScript.INK, HORIZONTAL_ALIGNMENT_LEFT))
		var have := _label("", 22, HudScript.INK.lightened(0.3), HORIZONTAL_ALIGNMENT_LEFT)
		info.add_child(have)
		row.add_child(info)
		var minus := _step_button("−", k, -1)
		var count := _label("", 30)
		count.custom_minimum_size = Vector2(56, 0)
		count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var plus := _step_button("+", k, 1)
		for c in [minus, count, plus]:
			row.add_child(c)
		_rows_box.add_child(row)
		rows[k] = {"box": row, "count": count, "have": have, "minus": minus, "plus": plus}


func _step_button(text: String, key: String, d: int) -> Button:
	var b := _button(text, UiKit.STEEL, 32)
	b.custom_minimum_size = Vector2(64, 56)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(step.bind(key, d))
	return b


func _tick_production() -> void:
	var now := Economy.time_now()
	for b in prod_labels:
		prod_labels[b].text = production_line(b, now)


## "보병 막사 Lv 3 · 다음 2:41:10". 남은 0초는 "곧"(온라인은 서버가 만들 때까지 0에 머문다).
func production_line(building_id: String, now: float) -> String:
	var p := Economy.soldier_production(building_id, now)
	var left: float = p.next_in_sec
	return "%s Lv %d · 다음 %s" % [GameData.building_def(building_id).name, p.level, UiKit.clock(left) if left > 0.0 else "곧"]


# --- 병종 그림(시트 행·건물 창 합성 칸) ---

## 병종 그림 텍스처 = 병사 피규어(Portraits "soldier:<병종>" — 월드 병사와 같은 몸). 렌더 전에는 자리표시를 주고 렌더를 요청한다.
## 병사 행·칸은 모두 이것으로 그린다(렌더가 끝나면 portrait_ready에 칸을 다시 그린다 — unit_icon).
static func figure(type: String) -> Texture2D:
	return PortraitsScript.portrait("soldier:" + type)


## 병종 그림 칸(px × px, 입력 없음). tier > 0이면 오른위에 갈매기 tier개(월드 머리 위 티어 표시와 같은 모양).
static func unit_icon(type: String, tier: int, px: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(px, px)
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func(): _draw_unit(c, type, tier))
	if PortraitsScript.current != null:  # 피규어 렌더가 끝나면 다시 그린다(칸이 사라지면 연결도 같이 끊긴다 — 대상이 c)
		PortraitsScript.current.portrait_ready.connect(c.queue_redraw.unbind(1))
	return c


## 병종 색 8각 바탕 + 피규어(렌더 전에는 이름 첫 글자) + 갈매기.
static func _draw_unit(c: Control, type: String, tier: int) -> void:
	var r := Rect2(Vector2.ZERO, c.size)
	var oct := LowpolyBox.octagon(r.grow(-2.0), r.size.x * 0.22)
	c.draw_colored_polygon(oct, Color(Art.SOLDIERS.get(type, {}).get("color", UiKit.STEEL)).lightened(0.35))
	oct.append(oct[0])
	c.draw_polyline(oct, UiKit.OUTLINE, 2.0, true)
	var tex := figure(type)
	if PortraitsScript.has_portrait("soldier:" + type):
		c.draw_texture_rect(tex, r, false)
	else:
		var glyph := str(GameData.soldier(type).get("name", "?")).left(1)
		var fs := roundi(r.size.y * 0.5)
		var base := Vector2(0, r.size.y * 0.5 + fs * 0.36)
		c.draw_string_outline(FONT, base, glyph, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, fs, 6, Color(UiKit.INK, 0.85))
		c.draw_string(FONT, base, glyph, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, fs, Color.WHITE)
	var w := r.size.x * 0.26
	var h := w * 0.45
	for i in tier:  # 오른위부터 아래로
		var tip := Vector2(r.size.x - w / 2.0 - 2.0, 3.0 + h + i * (h + 2.0))
		c.draw_colored_polygon(chevron(tip + Vector2(0, 1.0), w + 2.0, h + 2.0, h * 0.55 + 2.0), CHEVRON_EDGE)
		c.draw_colored_polygon(chevron(tip, w, h, h * 0.55), CHEVRON)


## 각진 V 갈매기(아래 꼭짓점 tip, 폭 w, 높이 h, 팔 두께 t) — hp_bars.add_chevron과 같은 6점.
static func chevron(tip: Vector2, w: float, h: float, t: float) -> PackedVector2Array:
	var hw := w / 2.0
	return PackedVector2Array([tip, tip + Vector2(-hw, -h), tip + Vector2(-hw + t, -h), tip + Vector2(0, -t), tip + Vector2(hw - t, -h), tip + Vector2(hw, -h)])
