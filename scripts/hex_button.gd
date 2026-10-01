extends Button
## 로우폴리 6각 버튼(HUD [영웅], 스펙 §5): 등급 보석과 같은 부채꼴 면 6개 + 진한 외곽선 + 외곽선 글자.
## 눌리면 어둡게·글자 2px 아래, 6각 안만 누를 수 있다.

const UiKit := preload("res://scripts/ui_kit.gd")
const FONT := preload("res://assets/fonts/Pretendard-SemiBold.otf")

var label := ""
var color := UiKit.STEEL
var font_size := 26


func _init() -> void:
	flat = true
	focus_mode = Control.FOCUS_NONE


func _radius() -> float:
	return minf(size.x, size.y) / 2.0 - 3.0


func _has_point(point: Vector2) -> bool:
	return point.distance_to(size / 2.0) <= _radius()


func _draw() -> void:
	var mode := get_draw_mode()
	var down := mode == DRAW_PRESSED or mode == DRAW_HOVER_PRESSED
	var c := color.darkened(0.15) if down else (color.lightened(0.1) if mode == DRAW_HOVER else color)
	var shift := Vector2(0, UiKit.PRESS_SHIFT if down else 0.0)
	UiKit.draw_gem(self, size / 2.0 + shift * 0.5, _radius(), c, 6)
	var y := size.y / 2.0 + font_size * 0.35 + shift.y
	draw_string_outline(FONT, Vector2(0, y), label, HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, 6, Color(UiKit.INK, 0.85))
	draw_string(FONT, Vector2(0, y), label, HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, Color.WHITE)
