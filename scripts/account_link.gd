extends Node
## 계정 연결(2026-10-12, Google Play 빌드): 지금 계정(게스트 포함)에 Google·카카오·네이버 로그인을 붙인다 — 진행은 그대로, 다음부터
## 그 로그인으로 어느 기기에서든 이 계정에 들어온다. 설정 창 [계정] 줄이 쓴다.
## 흐름: POST /v1/auth/link/start {provider, challenge}(로그인 필요) → 받은 주소를 브라우저로 → POLL_SEC마다 POST /v1/auth/oauth/poll
## {state, verifier}. 성공하면 서버가 준 자동 로그인 세션으로 바꿔 저장한다(Net.set_auth — 게스트였어도 이제 그 소셜 로그인).
## 실패: 409 already_linked(그 로그인이 이미 다른 계정 것 — 아무것도 옮기지 않는다)·provider_taken(이 계정에 같은 종류가 이미 있다).
## 연결된 목록: GET /v1/auth/links {links:[provider]}.

signal changed  # links·pending·message가 바뀌었다

const POLL_SEC := 2.0
const WAIT_SEC := 600.0  # 서버의 진행 행 수명(10분)
const PROVIDERS := ["google", "kakao", "naver"]
const NAMES := {"google": "Google", "kakao": "카카오", "naver": "네이버"}
const ERRORS := {
	"already_linked": "그 계정은 이미 다른 게임 계정에 연결되어 있습니다. 연결하지 않았습니다",
	"provider_taken": "이 계정에는 이미 같은 종류의 로그인이 연결되어 있습니다",
	"provider_unavailable": "아직 준비 중인 로그인입니다",
	"login_denied": "연결을 취소했습니다",
	"login_expired": "시간이 초과되었습니다. 다시 눌러 주세요",
	"net": "서버에 연결할 수 없습니다",
}

var links: Array = []  # 이 계정에 연결된 로그인
var pending := ""  # 브라우저에서 연결 중인 로그인
var message := ""
var opener := func(url: String): OS.shell_open(url)  # 테스트는 바꾼다(브라우저를 띄우지 않게)

var _state := ""
var _verifier := ""
var _poll_left := 0.0
var _wait_left := 0.0
var _http: HTTPRequest
var _busy := false


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 10.0
	add_child(_http)
	_http.request_completed.connect(_on_poll)


func load_links() -> void:
	if not Net.is_online():
		return
	Net.send("GET", "/v1/auth/links", null, func(d: Dictionary):
		links = d.get("links", []) if d.get("links") is Array else []
		changed.emit())


func is_linked(provider: String) -> bool:
	return provider in links or Net.auth_mode == provider


## 연결 시작: 바로 브라우저를 연다(서버 응답이 오면). 이미 연결된 것·진행 중이면 무시.
func start(provider: String) -> void:
	if pending != "" or is_linked(provider) or not Net.is_online():
		return
	pending = provider
	_verifier = Crypto.new().generate_random_bytes(32).hex_encode()
	_set_message("브라우저에서 %s 로그인을 마치면 바로 연결됩니다" % NAMES.get(provider, provider))
	Net.send("POST", "/v1/auth/link/start", {"provider": provider, "challenge": _sha256_hex(_verifier)}, _on_started, func(): _finish(Net.last_error))


func cancel() -> void:
	pending = ""
	_state = ""
	changed.emit()


func _on_started(d: Dictionary) -> void:
	if pending == "" or not (d.get("url") is String) or not (d.get("state") is String):
		_finish("login_failed")
		return
	_state = d.state
	_poll_left = POLL_SEC
	_wait_left = WAIT_SEC
	opener.call(d.url)


func _process(delta: float) -> void:
	if pending == "" or _state == "":
		return
	_wait_left -= delta
	if _wait_left <= 0.0:
		_finish("login_expired")
		return
	_poll_left -= delta
	if _poll_left > 0.0 or _busy:
		return
	_poll_left = POLL_SEC
	_busy = true
	if _http.request(Net.api_base + "/v1/auth/oauth/poll", PackedStringArray(["Content-Type: application/json"]), HTTPClient.METHOD_POST,
			JSON.stringify({"state": _state, "verifier": _verifier})) != OK:
		_busy = false


func _on_poll(result: int, code: int, _headers: PackedStringArray, raw: PackedByteArray) -> void:
	_busy = false
	if pending == "" or _state == "":
		return
	if result != HTTPRequest.RESULT_SUCCESS or code == 202 or code >= 500:
		return  # 아직(브라우저에서 로그인 중)·잠깐 끊김 — 계속 기다린다
	var json := JSON.new()
	var data = json.data if raw.size() > 0 and json.parse(raw.get_string_from_utf8()) == OK else null
	if code == 200 and data is Dictionary and data.get("session") is String and data.get("token") is String:
		var provider := pending
		Net.set_auth(provider, data.session)  # 이제 이 소셜 로그인으로 자동 로그인(진행은 같은 계정)
		Net.token = data.token
		if not provider in links:
			links.append(provider)
		pending = ""
		_state = ""
		_set_message("%s 계정과 연결했습니다. 다른 기기에서도 %s로 이어서 할 수 있습니다" % [NAMES.get(provider, provider), NAMES.get(provider, provider)])
		return
	_finish(str(data.get("error", "")) if data is Dictionary else "login_failed")


func _finish(error: String) -> void:
	pending = ""
	_state = ""
	_set_message(ERRORS.get(error, "연결하지 못했습니다. 다시 시도해 주세요"))


func _set_message(text: String) -> void:
	message = text
	changed.emit()


static func _sha256_hex(text: String) -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(text.to_utf8_buffer())
	return h.finish().hex_encode()
