extends Node
## 계정 연결(2026-10-12, Google Play 빌드): 지금 계정(게스트 포함)에 Google·카카오·네이버 로그인을 붙인다 — 진행은 그대로, 다음부터
## 그 로그인으로 어느 기기에서든 이 계정에 들어온다. 설정 창 [계정] 줄이 쓴다.
## 흐름: POST /v1/auth/link/start {provider, challenge}(로그인 필요) → 받은 주소를 브라우저로 → POLL_SEC마다 POST /v1/auth/oauth/poll
## {state, verifier}. 성공하면 서버가 준 자동 로그인 세션으로 바꿔 저장한다(Net.set_auth — 게스트였어도 이제 그 소셜 로그인).
## 실패: 409 already_linked(그 로그인이 이미 다른 계정 것 — 아무것도 옮기지 않는다)·provider_taken(이 계정에 같은 종류가 이미 있다).
## 연결된 목록: GET /v1/auth/links {links:[provider]}.

const Lang := preload("res://scripts/lang.gd")

signal changed  # links·pending·message가 바뀌었다

const POLL_SEC := 2.0
const WAIT_SEC := 600.0  # 서버의 진행 행 수명(10분)
const PROVIDERS := ["google", "kakao", "naver"]
static var NAMES := {"google": "Google", "kakao": Lang.t("account_link.names.kakao"), "naver": Lang.t("account_link.names.naver")}
static var ERRORS := {
	"already_linked": Lang.t("account_link.errors.already_linked"),
	"provider_taken": Lang.t("account_link.errors.provider_taken"),
	"provider_unavailable": Lang.t("account_link.errors.provider_unavailable"),
	"login_denied": Lang.t("account_link.errors.login_denied"),
	"login_expired": Lang.t("account_link.errors.login_expired"),
	"ip_mismatch": Lang.t("account_link.errors.ip_mismatch"),
	"net": Lang.t("account_link.errors.net"),
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
	_set_message(Lang.t("account_link.start") % NAMES.get(provider, provider))
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


## 브라우저에서 게임으로 돌아오면(로그인 완료 링크·직접 전환) 기다리지 않고 바로 결과를 묻는다.
func _notification(what: int) -> void:
	if _state != "" and (what == NOTIFICATION_APPLICATION_RESUMED or what == NOTIFICATION_APPLICATION_FOCUS_IN):
		_poll_left = 0.0


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
		_set_message(Lang.t("account_link.on_poll") % [NAMES.get(provider, provider), NAMES.get(provider, provider)])
		return
	_finish(str(data.get("error", "")) if data is Dictionary else "login_failed")


func _finish(error: String) -> void:
	pending = ""
	_state = ""
	_set_message(ERRORS.get(error, Lang.t("account_link.finish")))


func _set_message(text: String) -> void:
	message = text
	changed.emit()


static func _sha256_hex(text: String) -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(text.to_utf8_buffer())
	return h.finish().hex_encode()
