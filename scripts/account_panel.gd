extends "res://scripts/ui_window.gd"
## 계정 창(HUD [계정], 온라인 모드만): 소셜 로그인(Google·카카오·네이버)으로 계정을 연동하거나 다른 기기의 계정으로 바꾼다.
## 흐름: [Google로 계속] → POST /v1/auth/link/start → 시스템 브라우저로 provider 로그인(OS.shell_open) → 앱으로 돌아올 때까지
## POLL_SEC마다 GET /v1/auth/link/poll. done이면 switched에 따라
##  - 연동(처음 보는 계정 → 지금 플레이어에 묶임): 알림 한 줄, 연동 상태만 새로 고침
##  - 전환(이미 다른 플레이어의 계정): 기기가 그 플레이어에 묶였다 — 방치면 곧바로, 스테이지 중이면 끝난 뒤 Net.restart()로
##    처음부터 다시 접속해 월드를 다시 만든다(지금 게스트 진행은 버려진다 — 서버 정책).
## 창을 닫아도 진행 중인 시도의 poll은 이어진다(브라우저에서 돌아오는 동안). 서버에 꺼진 provider 버튼은 비활성.

const PROVIDERS := [["google", "Google"], ["kakao", "카카오"], ["naver", "네이버"]]
const COLORS := {"google": Color("4285F4"), "kakao": Color("C9A400"), "naver": Color("03A94A")}
const DIALOG_W := 560
const POLL_SEC := 2.0
const POLL_MAX_SEC := 600.0  # 서버의 시도 유효 시간(NONCE_TTL)과 같다
const GUEST_TEXT := "게스트 계정 — 이 기기에만 묶여 있습니다"
const LINKED_PREFIX := "연동: "
const NOTE := "계정을 연동하면 다른 기기에서 이어 할 수 있습니다"
const WAIT_TEXT := "브라우저에서 로그인한 뒤 돌아와 주세요"
const DONE_TEXT := "연동했습니다"
const SWITCH_TEXT := "그 계정의 진행으로 바꿉니다"
const SWITCH_WAIT_TEXT := "스테이지가 끝나면 계정을 바꿉니다"
const FAIL_TEXT := {"denied": "로그인을 취소했습니다", "expired": "시간이 지났습니다. 다시 시도해 주세요", "provider": "로그인하지 못했습니다. 다시 시도해 주세요"}

var buttons := {}  # provider → Button
var status: Label
var wait_label: Label
var available: Array = []  # 서버가 켠 provider
var linked: Array = []  # 이 플레이어가 연동한 provider
var nonce := ""  # 진행 중인 로그인 시도("" = 없음)
var open_browser := true  # 테스트는 끈다(헤드리스에서 브라우저를 띄우지 않게)
var last_result := ""  # 마지막 poll 결과(done·error 코드, 테스트가 읽는다)
var switch_pending := false  # 전환이 정해졌고 스테이지가 끝나기를 기다린다

var _poll_left := 0.0
var _poll_out := false  # poll 응답을 기다리는 중
var _deadline_ms := 0


func _ready() -> void:
	_build_window(DIALOG_W)
	content.add_child(_title("계정"))
	status = _label(GUEST_TEXT, 24, Color(HudScript.INK, 0.8))
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(status)
	for p in PROVIDERS:
		var b := _button("%s로 계속" % p[1], COLORS[p[0]])
		b.pressed.connect(_begin.bind(p[0]))
		content.add_child(b)
		buttons[p[0]] = b
	wait_label = _label(WAIT_TEXT, 22, Color(HudScript.INK, 0.75))
	wait_label.visible = false
	content.add_child(wait_label)
	content.add_child(_label(NOTE, 22, HudScript.INK.lightened(0.3)))
	var close_button := _button("닫기", UiKit.STEEL)
	close_button.pressed.connect(close)
	content.add_child(close_button)
	GameState.mode_changed.connect(_on_mode_changed)
	set_process(false)
	_refresh()


func _on_open() -> void:
	Net.send("GET", "/v1/auth/links", null, _on_links)
	_fit()


func _on_links(d: Dictionary) -> void:
	available = d.get("available", []) if d.get("available") is Array else []
	linked = d.get("linked", []) if d.get("linked") is Array else []
	_refresh()


func _refresh() -> void:
	var names := []
	for p in PROVIDERS:
		var b: Button = buttons[p[0]]
		var on: bool = p[0] in linked
		b.text = "%s 연동됨" % p[1] if on else "%s로 계속" % p[1]
		b.disabled = nonce != "" or switch_pending or p[0] not in available
		if on:
			names.append(p[1])
	status.text = GUEST_TEXT if names.is_empty() else LINKED_PREFIX + ", ".join(names)
	wait_label.visible = nonce != ""


## provider 로그인을 시작한다: 시도를 만들고 브라우저를 연 뒤 poll을 돈다.
func _begin(provider: String) -> void:
	if nonce != "" or switch_pending:
		return
	Net.send("POST", "/v1/auth/link/start", {"provider": provider, "device_id": Net.device_id}, _on_started, _on_start_failed)


func _on_started(d: Dictionary) -> void:
	var url := str(d.get("url", ""))
	nonce = str(d.get("nonce", ""))
	if nonce == "" or url == "":
		push_warning("bad link start response: %s" % str(d))
		nonce = ""
		return
	_poll_left = POLL_SEC
	_poll_out = false
	_deadline_ms = Time.get_ticks_msec() + int(POLL_MAX_SEC * 1000.0)
	set_process(true)
	_refresh()
	if open_browser:
		OS.shell_open(url)


func _on_start_failed() -> void:
	Economy.notice.emit(FAIL_TEXT.provider if Net.last_error != "provider_unavailable" else "이 서버에서 쓸 수 없는 로그인입니다")


func _process(delta: float) -> void:
	if nonce == "":
		set_process(false)
		return
	if Time.get_ticks_msec() > _deadline_ms:
		_finish("expired")
		return
	_poll_left -= delta
	if _poll_left <= 0.0 and not _poll_out:
		_poll_left = POLL_SEC
		_poll_out = true
		Net.send("GET", "/v1/auth/link/poll?nonce=" + nonce, null, _on_poll, _on_poll_failed)


func _on_poll(d: Dictionary) -> void:
	_poll_out = false
	match str(d.get("status", "")):
		"pending":
			pass
		"done":
			_finish("done")
			if d.get("switched", false) == true:
				_switch()
			else:
				Economy.notice.emit(DONE_TEXT)
				if visible:
					Net.send("GET", "/v1/auth/links", null, _on_links)
		_:
			_finish(str(d.get("error", "provider")))


## poll을 서버가 거부했다(404: 모르는·사라진 시도) — 끝낸다.
func _on_poll_failed() -> void:
	_poll_out = false
	_finish("provider")


func _finish(result: String) -> void:
	nonce = ""
	last_result = result
	set_process(false)
	if FAIL_TEXT.has(result):
		Economy.notice.emit(FAIL_TEXT[result])
	_refresh()


## 다른 플레이어의 계정이었다: 방치면 곧바로 다시 접속, 스테이지 중이면 끝난 뒤(이번 스테이지의 처치·클리어는 지금 플레이어 것).
func _switch() -> void:
	close()
	if GameState.mode == GameState.Mode.IDLE:
		Economy.notice.emit(SWITCH_TEXT)
		Net.restart()
	else:
		switch_pending = true
		Economy.notice.emit(SWITCH_WAIT_TEXT)
		_refresh()


func _on_mode_changed(mode: int) -> void:
	if switch_pending and mode == GameState.Mode.IDLE:
		switch_pending = false
		Economy.notice.emit(SWITCH_TEXT)
		Net.restart()
