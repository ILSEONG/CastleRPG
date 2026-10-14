extends RefCounted
## 설정 창의 [알림] 칸(2026-10-12, 푸시 알림 Notify). settings_panel.gd가 add_to(창)로 붙이고 창을 열 때 refresh()를 부른다.
## 알림을 띄울 수 없는 빌드(웹·앱인토스·PC — Notify.supported() 거짓)에서는 칸을 만들지 않는다.

const Lang := preload("res://scripts/lang.gd")

static var ROWS := [
	["notify", Lang.t("notify_settings.rows")],
	["notify_timer", Lang.t("notify_settings.rows_2")],
	["notify_idle", Lang.t("notify_settings.rows_3")],
	["notify_daily", Lang.t("notify_settings.rows_4")],
	["notify_war", Lang.t("notify_settings.rows_5")],
	["notify_night", Lang.t("notify_settings.rows_6")],
]

var toggles := {}  # Prefs 키 → 체크 버튼
var section: Label


## 창(settings_panel.gd)의 content에 칸을 붙인다. 지원 안 하는 빌드면 null.
static func add_to(panel: Node) -> RefCounted:
	var notify := panel.get_node_or_null("/root/Notify")
	if notify == null or not notify.supported():
		return null
	var s := new()
	s.section = panel._section(Lang.t("notify_settings.add_to"))
	panel.body.add_child(s.section)
	for r in ROWS:
		var key: String = r[0]
		s.toggles[key] = panel._toggle_row(r[1], func(on: bool):
			notify.set_enabled(key, on)
			s.refresh())
	notify.resumed.connect(s.refresh)
	s.refresh()
	return s


## 지금 값으로 다시 보인다. 전체를 끄면 나머지는 눌리지 않는다. 기기에서 알림이 막혀 있으면 칸 이름에 적는다.
func refresh() -> void:
	var notify = Engine.get_main_loop().root.get_node_or_null("/root/Notify")
	if notify == null:
		return
	var master_on: bool = notify.enabled("notify")
	for key in toggles:
		var b: Button = toggles[key]
		b.set_block_signals(true)
		b.button_pressed = notify.enabled(key)
		b.set_block_signals(false)
		b.disabled = key != "notify" and not master_on
		b.modulate.a = 0.45 if b.disabled else 1.0
		b.queue_redraw()
		for k in b.get_children():
			if k is Control:
				k.queue_redraw()
	var blocked: bool = notify.plugin != null and not notify.plugin.has_permission()
	section.text = Lang.t("notify_settings.refresh") if master_on and blocked else Lang.t("notify_settings.refresh_2")
