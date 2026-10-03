extends "res://scripts/ui_window.gd"
## 방치 보상 개요 창: 앱을 껐다(백그라운드에서) 돌아오면 떠나 있던 시간·그동안 처치한 적·얻은 골드를 보여 준다(Economy.offline_reported).
## 앱을 끈 동안의 처치 골드는 offline_gold_mult(0.5)배, 최대 accum_cap_min분까지만 쌓인다(Economy.offline_reward). [확인] 또는 배경 탭으로 닫는다.
## 창을 만들기 전에 정산이 끝났으면(온라인 응답이 먼저 옴) 만들 때 Economy.offline_report로 곧바로 연다.

const GameData := preload("res://scripts/game_data.gd")
const IconsScript := preload("res://scripts/icons.gd")

const DIALOG_W := 560.0
const TITLE := "방치 보상"

var away_label: Label
var kills_label: Label
var gold_label: Label
var note_label: Label
var ok_button: Button


func _ready() -> void:
	_build_window(DIALOG_W, 16)
	content.add_child(_title(TITLE))
	away_label = _label("", 28)
	content.add_child(away_label)
	kills_label = _label("", 28)
	content.add_child(kills_label)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	var coin = IconsScript.new()
	coin.custom_minimum_size = Vector2(40, 40)
	coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(coin)
	gold_label = _label("", 38, HudScript.INK)
	row.add_child(gold_label)
	content.add_child(row)
	note_label = _label("", 20, HudScript.INK.lightened(0.3))
	note_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(note_label)
	ok_button = _button("확인")
	ok_button.pressed.connect(close)
	content.add_child(ok_button)
	Economy.offline_reported.connect(show_report)
	if not Economy.offline_report.is_empty():
		show_report(Economy.offline_report)


## 정산 r = {away_sec, kills, gold_tenths}를 보여 주며 연다(보여 준 정산은 Economy에서 비운다).
func show_report(r: Dictionary) -> void:
	Economy.offline_report = {}
	var away := float(r.get("away_sec", 0.0))
	var cap := GameData.config_num("accum_cap_min") * 60.0
	away_label.text = "방치 시간  " + away_text(away)
	kills_label.text = "처치한 적  %s마리" % UiKit.commas(int(r.get("kills", 0)))
	gold_label.text = "+%s 골드" % UiKit.commas(int(r.get("gold_tenths", 0)) / 10)
	var pct := roundi(GameData.config_num("offline_gold_mult") * 100.0)
	note_label.text = "앱을 끈 동안 처치 골드는 %d%%만 쌓입니다 (최대 %s)" % [pct, away_text(cap)]
	if away > cap:
		note_label.text += "\n최대 시간까지만 적립되었습니다"
	_fit()
	open()


## 떠나 있던 시간: "3일 4시간", "3시간 12분", "12분"(1분 미만은 "1분 미만").
static func away_text(sec: float) -> String:
	var m := floori(maxf(0.0, sec) / 60.0)
	if m < 1:
		return "1분 미만"
	if m < 60:
		return "%d분" % m
	var h := m / 60
	if h < 24:
		return "%d시간 %d분" % [h, m % 60] if m % 60 > 0 else "%d시간" % h
	return "%d일 %d시간" % [h / 24, h % 24] if h % 24 > 0 else "%d일" % (h / 24)
