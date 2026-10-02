extends "res://scripts/ui_window.gd"
## 다이아 상점 창(개정 23 §2, 모집 창 [다이아 상점]으로 연다): 상품 카드 4개(크기별 보석 더미·다이아 수·가격) + [구매]는 비활성 "준비 중",
## 안내 "결제 기능은 출시 전에 연결됩니다". 실결제(Google Play / App Store)는 범위 밖 — 개발은 테스트 훅·?econ-demo로 다이아를 받는다.
## 모집 창(층 2) 위에 뜬다(층 3).

const IconsScript := preload("res://scripts/icons.gd")

const DIALOG_W := 640
const PRODUCTS := [{"diamonds": 300, "price": 1200}, {"diamonds": 1000, "price": 3900}, {"diamonds": 3000, "price": 11000}, {"diamonds": 6500, "price": 22000}]
const SOON_TEXT := "준비 중"
const NOTE_TEXT := "결제 기능은 출시 전에 연결됩니다"
const PILE := [Vector2(0, 0), Vector2(-26, 14), Vector2(26, 14), Vector2(0, 26), Vector2(-14, -18), Vector2(14, -18)]  # 보석 더미 자리(가운데 기준)
var buy_buttons: Array = []
var note: Label


func _ready() -> void:
	_build_window(DIALOG_W)
	layer = 3  # 모집 창 위
	content.add_child(_title("다이아 상점"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	content.add_child(grid)
	for i in PRODUCTS.size():
		grid.add_child(_card(PRODUCTS[i], i + 2))  # 상품이 클수록 보석이 많다(2..5개)
	note = _label(NOTE_TEXT, 22, Color(HudScript.INK, 0.75))
	content.add_child(note)
	var close_button := _button("닫기", UiKit.STEEL)
	close_button.pressed.connect(close)
	content.add_child(close_button)


func _card(p: Dictionary, gems: int) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(290, 0)
	card.add_theme_stylebox_override("panel", UiKit.panel(UiKit.CREAM, 12.0, 12))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	card.add_child(box)
	var pile := Control.new()
	pile.custom_minimum_size = Vector2(0, 96)
	pile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pile.draw.connect(func():
		var c := pile.size / 2.0
		for j in range(gems - 1, -1, -1):  # 뒤에서 앞으로(가운데 보석이 맨 앞)
			IconsScript.draw_icon(pile, "diamond", c + PILE[j], 44.0 - j * 2.0))
	box.add_child(pile)
	box.add_child(_label("다이아 %s" % UiKit.commas(p.diamonds), 30))
	box.add_child(_label("%s원" % UiKit.commas(p.price), 24, Color(HudScript.INK, 0.8)))
	var buy := _button(SOON_TEXT, HudScript.ACCENT, 24)
	buy.disabled = true
	box.add_child(buy)
	buy_buttons.append(buy)
	return card


func _on_open() -> void:
	_fit()
