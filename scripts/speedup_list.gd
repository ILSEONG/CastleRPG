extends VBoxContainer
## 가속 아이템 목록(2026-10-13 라오킹식 건설): 건물 창(건설 중)·연구 창(연구 중)이 [가속]을 누르면 펼친다.
## 그 타이머에 쓸 수 있는 보유 아이템(짧은 것부터, 전용 → 범용)마다 한 줄: "건설 가속 1시간 ×3" [1개] [n개](남은 시간을 채우는 수, 2개 이상일 때만).
## 규칙·상태는 Economy 가속 API(speedups_for·speedup_name·use_speedup)다. 보유·타이머가 바뀌면 부르는 쪽이 refresh한다.

const Lang := preload("res://scripts/lang.gd")

const EconomyScript := preload("res://scripts/economy.gd")
const HudScript := preload("res://scripts/hud.gd")
const UiKit := preload("res://scripts/ui_kit.gd")

static var EMPTY_TEXT := Lang.t("speedup_list.empty_text")

var target := "build"  # build | research
var building := ""  # 건설: 그 건물(""이면 1번 일꾼)
signal used  # 아이템을 썼다(타이머가 끝나면 창 배치가 바뀐다 — 창이 누름 보호를 다시 건다)

var _key := ""  # 마지막으로 그린 내용(보유·남은 시간 분) — 같으면 다시 만들지 않는다


func _ready() -> void:
	add_theme_constant_override("separation", 6)


## 타이머 남은 초(그 대상)
func left_sec(now: float) -> float:
	return Economy.research_left(now) if target == "research" else Economy.build_left(now, building)


func refresh() -> void:
	var now := Economy.time_now()
	var left := left_sec(now)
	var ids := Economy.speedups_for(target)
	var key := "%s|%s|%d|%s|%s" % [target, building, ceili(left / 60.0), ",".join(ids.map(func(i): return "%s:%d" % [i, Economy.speedup_count(i)])),
		Economy.speedup_waiting()]  # 응답이 오면(보유 수가 그대로여도) 꺼 둔 버튼을 다시 켠다
	if key == _key:
		return
	_key = key
	for c in get_children():
		remove_child(c)  # 같은 프레임의 두 번째 누름이 지울 버튼에 닿지 않게
		c.queue_free()
	if ids.is_empty():
		add_child(_label(EMPTY_TEXT, 22, HudScript.INK.lightened(0.3)))
		return
	for id in ids:
		var sp := EconomyScript.speedup_parse(id)
		var have := Economy.speedup_count(id)
		var need := mini(have, maxi(1, ceili(left / (float(sp.min) * 60.0))))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var l := _label("%s ×%d" % [EconomyScript.speedup_name(id), have], 24, HudScript.INK, HORIZONTAL_ALIGNMENT_LEFT)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		row.add_child(_use_button(id, 1, Lang.t("speedup_list.refresh")))
		if need > 1:
			row.add_child(_use_button(id, need, Lang.t("speedup_list.refresh_2") % need))
		add_child(row)


func _use_button(id: String, n: int, text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(108, 52)
	b.add_theme_font_size_override("font_size", 26)
	UiKit.apply_button(b, UiKit.AMBER, 12.0)
	b.disabled = Economy.speedup_waiting()
	b.pressed.connect(func():
		if Economy.use_speedup(id, n, target, building):
			_key = ""
			refresh()
			used.emit())
	return b


func _label(text: String, font_size: int, color: Color, align: int = HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l
