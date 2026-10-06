extends CanvasLayer
## 로그인 화면(온라인 모드, 저장한 로그인 방식이 없을 때 main이 띄운다). 방치형 게임 첫 화면처럼: 시작 그림(splash — 앱 아이콘 느낌의
## 주황 하늘·성·게임 이름 로고가 그림에 들어 있다) 위, 아래쪽 따뜻한 갈색 그라데이션 위에 제공자 버튼 셋 — [Google로 시작하기](흰 바탕·G 로고) [카카오로 시작하기](#FEE500·말풍선)
## [네이버로 시작하기](#03C75A·N) — 그 아래 [게스트로 시작하기] 글자 버튼, 맨 아래 약관 안내와 버전. 회원가입 없음: 처음 로그인하면 계정이 생긴다.
## 소셜 로그인: verifier(무작위 32바이트 hex)의 sha256을 challenge로 POST /v1/auth/oauth/start → 받은 주소를 시스템 브라우저로 열고
## (OS.shell_open), POLL_SEC마다 POST /v1/auth/oauth/poll {state, verifier}로 결과를 기다린다(앱으로 돌아오면 곧바로 받는다).
## 성공하면 Net.set_auth(제공자, 세션) 뒤 logged_in. 게스트는 Net.set_auth("guest") 뒤 logged_in. 기다리는 동안은 안내 창
## ([브라우저 다시 열기] [취소]), 실패는 버튼 아래 한 줄로 알린다. 기기 id를 함께 보내 그 기기의 게스트 진행을 소셜 계정에 잇는다(서버 규칙).

const UiKit := preload("res://scripts/ui_kit.gd")

signal logged_in

const SPLASH := preload("res://assets/ui/splash.png")
const POLL_SEC := 2.0
const BUTTON_W := 560.0
const BUTTON_H := 88.0
const TERMS := "로그인하면 이용약관 및 개인정보처리방침에 동의하게 됩니다."
const SHADE := Color(0.36, 0.17, 0.04)  # 아래 그라데이션(주황 하늘의 어두운 쪽)
## 제공자 → [버튼 글자, 바탕, 글자색, 테두리(없으면 투명)] — 각 사 로그인 버튼 지침의 색
const BRANDS := {
	"google": ["Google로 시작하기", Color("FFFFFF"), Color("1F1F1F"), Color("747775")],
	"kakao": ["카카오로 시작하기", Color("FEE500"), Color(0, 0, 0, 0.85), Color(0, 0, 0, 0)],
	"naver": ["네이버로 시작하기", Color("03C75A"), Color("FFFFFF"), Color(0, 0, 0, 0)],
}
## 실패 코드 → 안내
const ERRORS := {
	"provider_unavailable": "아직 준비 중인 로그인입니다",
	"login_denied": "로그인이 취소되었습니다",
	"login_failed": "로그인하지 못했습니다. 다시 시도해 주세요",
	"login_expired": "시간이 지났습니다. 다시 시도해 주세요",
	"net": "서버에 연결할 수 없습니다",
}

var buttons := {}  # 제공자 → Button
var guest_button: Button
var message_label: Label
var wait_panel: Control

var _http: HTTPRequest
var _provider := ""
var _verifier := ""
var _state := ""
var _url := ""
var _polling := false
var _poll_left := 0.0
var _done := Callable()  # 지금 요청의 응답 처리
var opener := func(url: String): OS.shell_open(url)  # 제공자 로그인 주소 열기(테스트는 바꾼다 — 브라우저를 띄우지 않게)


func _ready() -> void:
	layer = 5
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var bg := TextureRect.new()
	bg.texture = SPLASH
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var shade := TextureRect.new()  # 아래쪽을 어둡게 — 버튼·글자가 성·하늘 위에서도 또렷하게
	var grad := Gradient.new()
	grad.set_color(0, Color(SHADE, 0.0))
	grad.set_color(1, Color(SHADE, 0.8))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 4
	gt.height = 256
	shade.texture = gt
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.anchor_left = 0.0
	shade.anchor_right = 1.0
	shade.anchor_top = 0.5
	shade.anchor_bottom = 1.0
	root.add_child(shade)
	root.add_child(_button_block())
	var terms := _text(TERMS, 18, Color(1, 1, 1, 0.8))
	terms.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	terms.grow_horizontal = Control.GROW_DIRECTION_BOTH
	terms.offset_top = -64
	terms.offset_bottom = -36
	root.add_child(terms)
	var version := _text("v" + str(ProjectSettings.get_setting("application/config/version", "")), 16, Color(1, 1, 1, 0.6))
	version.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	version.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	version.grow_vertical = Control.GROW_DIRECTION_BEGIN
	version.offset_right = -16
	version.offset_bottom = -12
	root.add_child(version)
	wait_panel = _wait_block()
	root.add_child(wait_panel)
	_http = HTTPRequest.new()
	_http.timeout = 10.0
	_http.request_completed.connect(_on_http)
	add_child(_http)


func _process(delta: float) -> void:
	if not _polling:
		return
	_poll_left -= delta
	if _poll_left <= 0.0 and not _done.is_valid():
		_poll_left = POLL_SEC
		_request("/v1/auth/oauth/poll", {"state": _state, "verifier": _verifier}, _on_poll)


## 게스트로 시작: 기기 id 계정(지금까지와 같다).
func press_guest() -> void:
	if _polling:
		return
	Net.set_auth("guest")
	logged_in.emit()


## 소셜 로그인 시작(Google·카카오·네이버).
func press_provider(provider: String) -> void:
	if _polling or _provider != "":
		return
	_provider = provider
	_message("")
	_verifier = Crypto.new().generate_random_bytes(32).hex_encode()
	_request("/v1/auth/oauth/start", {"provider": provider, "challenge": sha256_hex(_verifier), "device_id": Net.ensure_device_id()}, _on_started)


## 기다리기를 그만둔다(서버의 진행 행은 10분 뒤 버려진다).
func cancel() -> void:
	_polling = false
	_provider = ""
	_state = ""
	wait_panel.visible = false


static func sha256_hex(text: String) -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(text.to_utf8_buffer())
	return h.finish().hex_encode()


func _on_started(code: int, data) -> void:
	if code != 200 or not (data is Dictionary) or not (data.get("url") is String) or not (data.get("state") is String):
		_fail(_code_of(code, data))
		return
	_state = data.state
	_url = data.url
	_polling = true
	_poll_left = POLL_SEC
	wait_panel.visible = true
	opener.call(_url)


func _on_poll(code: int, data) -> void:
	if not _polling:
		return
	if code == 202 or code == 0:  # 아직(브라우저에서 로그인 중) 또는 잠깐 끊김 — 계속 기다린다
		return
	if code == 200 and data is Dictionary and data.get("session") is String and data.get("token") is String:
		_polling = false
		Net.set_auth(_provider, data.session)
		Net.token = data.token
		logged_in.emit()
		return
	_fail(_code_of(code, data))


func _fail(code: String) -> void:
	cancel()
	_message(ERRORS.get(code, ERRORS.login_failed))


static func _code_of(code: int, data) -> String:
	if code == 0:
		return "net"
	return str(data.get("error", "")) if data is Dictionary else ""


## POST 하나(로그인 화면 전용 — Net 큐와 따로). done(code: int, data) — 연결 실패면 code 0.
func _request(path: String, body: Dictionary, done: Callable) -> void:
	_done = done
	var err := _http.request(Net.api_base + path, PackedStringArray(["Content-Type: application/json"]), HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		_done = Callable()
		done.call(0, null)


func _on_http(result: int, code: int, _headers: PackedStringArray, raw: PackedByteArray) -> void:
	var done := _done
	_done = Callable()
	if not done.is_valid():
		return
	var json := JSON.new()
	var data = json.data if raw.size() > 0 and json.parse(raw.get_string_from_utf8()) == OK else null
	done.call(code if result == HTTPRequest.RESULT_SUCCESS else 0, data)


func _message(text: String) -> void:
	message_label.text = text
	message_label.visible = text != ""


# --- 모양 ---

func _button_block() -> Control:
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	box.offset_bottom = -110
	box.add_theme_constant_override("separation", 16)
	for p in ["google", "kakao", "naver"]:
		var b := _brand_button(p)
		b.pressed.connect(press_provider.bind(p))
		buttons[p] = b
		box.add_child(b)
	guest_button = Button.new()
	guest_button.text = "게스트로 시작하기"
	guest_button.flat = true
	guest_button.custom_minimum_size = Vector2(0, 56)
	guest_button.add_theme_font_size_override("font_size", 24)
	for st in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		guest_button.add_theme_color_override(st, Color(1, 1, 1, 0.92))
	guest_button.focus_mode = Control.FOCUS_NONE
	guest_button.pressed.connect(press_guest)
	guest_button.draw.connect(func():  # 밑줄
		var w := guest_button.get_theme_font("font").get_string_size(guest_button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
		var y := guest_button.size.y / 2.0 + 15.0
		guest_button.draw_line(Vector2((guest_button.size.x - w) / 2.0, y), Vector2((guest_button.size.x + w) / 2.0, y), Color(1, 1, 1, 0.75), 2.0))
	box.add_child(guest_button)
	message_label = _text("", 22, Color(1.0, 0.86, 0.5))
	message_label.visible = false
	box.add_child(message_label)
	return box


## 제공자 버튼: 둥근 사각(각 사 색) + 왼쪽 로고 + 가운데 글자. 누르면 살짝 어두워진다.
func _brand_button(provider: String) -> Button:
	var spec: Array = BRANDS[provider]
	var b := Button.new()
	b.custom_minimum_size = Vector2(BUTTON_W, BUTTON_H)
	b.focus_mode = Control.FOCUS_NONE
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = spec[1].darkened(0.12) if st == "pressed" else spec[1]
		sb.set_corner_radius_all(14)
		sb.border_color = spec[3]
		sb.set_border_width_all(2 if spec[3].a > 0.0 else 0)
		sb.shadow_color = Color(0, 0, 0, 0.25)
		sb.shadow_size = 0 if st == "pressed" else 4
		sb.shadow_offset = Vector2(0, 3)
		b.add_theme_stylebox_override(st, sb)
	var label := _text(spec[0], 30, spec[2])
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(label)
	var logo := Control.new()
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	logo.position = Vector2(34, (BUTTON_H - 44.0) / 2.0)
	logo.size = Vector2(44, 44)
	logo.draw.connect(draw_logo.bind(logo, provider))
	b.add_child(logo)
	return b


## 로고(44×44 칸): Google 네 색 G, 카카오 검은 말풍선, 네이버 흰 N.
static func draw_logo(c: Control, provider: String) -> void:
	var s := c.size
	var o := s / 2.0
	match provider:
		"google":
			var r := s.x * 0.36
			var w := s.x * 0.17
			# 각도: 0 = 오른쪽, 시계 방향(화면 y 아래). 오른쪽 위가 열린 G
			c.draw_arc(o, r, deg_to_rad(-140.0), deg_to_rad(-38.0), 24, Color("EA4335"), w, true)  # 빨강(위)
			c.draw_arc(o, r, deg_to_rad(140.0), deg_to_rad(220.0), 20, Color("FBBC05"), w, true)  # 노랑(왼쪽)
			c.draw_arc(o, r, deg_to_rad(35.0), deg_to_rad(140.0), 24, Color("34A853"), w, true)  # 초록(아래)
			c.draw_arc(o, r, deg_to_rad(0.0), deg_to_rad(35.0), 10, Color("4285F4"), w, true)  # 파랑(오른쪽)
			c.draw_rect(Rect2(o.x - 0.5, o.y - w / 2.0, r + w / 2.0 + 0.5, w), Color("4285F4"))  # 가로 막대
		"kakao":
			var pts := PackedVector2Array()
			for i in 40:
				var a := TAU * i / 40.0
				pts.append(o + Vector2(cos(a) * s.x * 0.44, sin(a) * s.y * 0.36 - s.y * 0.05))
			c.draw_colored_polygon(pts, Color(0, 0, 0, 0.9))
			c.draw_colored_polygon(PackedVector2Array([o + Vector2(-s.x * 0.22, s.y * 0.18), o + Vector2(-s.x * 0.04, s.y * 0.24),
				o + Vector2(-s.x * 0.28, s.y * 0.42)]), Color(0, 0, 0, 0.9))  # 꼬리
		"naver":
			var x0 := o.x - s.x * 0.3
			var x1 := o.x + s.x * 0.3
			var y0 := o.y - s.y * 0.3
			var y1 := o.y + s.y * 0.3
			var bw := s.x * 0.2
			c.draw_colored_polygon(PackedVector2Array([Vector2(x0, y0), Vector2(x0 + bw, y0), Vector2(x1 - bw, y1 - s.y * 0.2), Vector2(x1 - bw, y0),
				Vector2(x1, y0), Vector2(x1, y1), Vector2(x1 - bw, y1), Vector2(x0 + bw, y0 + s.y * 0.2), Vector2(x0 + bw, y1), Vector2(x0, y1)]), Color.WHITE)


func _wait_block() -> Control:
	var back := ColorRect.new()
	back.color = Color(0, 0, 0, 0.55)
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_STOP
	back.visible = false
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(560, 0)
	panel.add_theme_stylebox_override("panel", UiKit.panel(UiKit.CREAM_DIALOG, 18.0, 28))
	back.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	panel.add_child(box)
	box.add_child(_text("브라우저에서 로그인해 주세요", 32, UiKit.INK))
	var hint := _text("로그인을 마치고 게임으로 돌아오면 자동으로 시작합니다", 22, UiKit.INK.lightened(0.3))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var again := Button.new()
	again.text = "브라우저 다시 열기"
	again.custom_minimum_size = Vector2(0, 64)
	again.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	again.add_theme_font_size_override("font_size", 24)
	UiKit.apply_button(again, Color(0.98, 0.70, 0.20), 12.0)
	again.pressed.connect(func(): opener.call(_url))
	row.add_child(again)
	var stop := Button.new()
	stop.text = "취소"
	stop.custom_minimum_size = Vector2(150, 64)
	stop.add_theme_font_size_override("font_size", 24)
	UiKit.apply_button(stop, UiKit.STEEL, 12.0)
	stop.pressed.connect(cancel)
	row.add_child(stop)
	box.add_child(row)
	return back


func _text(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l
