extends RefCounted
## 설정 창의 [알림] 칸(2026-10-12, 푸시 알림 Notify). settings_panel.gd가 add_to(창)로 붙이고 창을 열 때 refresh()를 부른다.
## 알림을 띄울 수 없는 빌드(웹·앱인토스·PC — Notify.supported() 거짓)에서는 칸을 만들지 않는다.

const ROWS := [
	["notify", "푸시 알림"],
	["notify_timer", "건설·훈련·연구 완료"],
	["notify_idle", "방치 보상 가득"],
	["notify_daily", "출석 알림"],
	["notify_war", "공성전 시작"],
	["notify_night", "야간 알림 (22시~8시)"],
]

var toggles := {}  # Prefs 키 → 체크 버튼
var section: Label


## 창(settings_panel.gd)의 content에 칸을 붙인다. 지원 안 하는 빌드면 null.
static func add_to(panel: Node) -> RefCounted:
	var notify := panel.get_node_or_null("/root/Notify")
	if notify == null or not notify.supported():
		return null
	var s := new()
	s.section = panel._section("알림")
	panel.content.add_child(s.section)
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
	section.text = "알림 (휴대폰 설정에서 꺼져 있어요)" if master_on and blocked else "알림"
