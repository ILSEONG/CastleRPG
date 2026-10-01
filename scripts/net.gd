extends Node
## 서버 접속(개정 9 온라인 모드). 오토로드 Net. API 주소가 비면 오프라인 모드 — 아무것도 하지 않는다.
## 주소: 프로젝트 설정 castle/api_base_url. 디버그 빌드에선 `-- --api=<url>`(네이티브)·`?api=<url>`(웹)이 앞선다.
## start(): 게스트 로그인 → /v1/gamedata(GameData.apply_remote) → /v1/player. 그 뒤 connected를 낸다(main이 월드를 만든다).
## 요청은 HTTPRequest 하나로 한 번에 하나(큐). 연결 실패·5xx·409는 2·4·8…초(최대 15초) 뒤 같은 요청을 다시 보내고,
## 401은 다시 로그인한 뒤 다시 보낸다. 그 밖의 4xx는 버린다. 토큰은 메모리에만 둔다.
## 응답의 server_now − 로컬 시각으로 Economy.clock_offset을 맞춘다. 처치 골드는 10초마다·스테이지 클리어 때 보낸다.

const GameData := preload("res://scripts/game_data.gd")

const RETRY_MAX_SEC := 15.0
const TIMEOUT_SEC := 10.0
const FLUSH_SEC := 10.0  # 처치 골드 보고 간격
const DEVICE_RE := "^[A-Za-z0-9-]{16,128}$"

signal connected     # 끊긴 상태(또는 첫 접속 전)에서 서버에 닿았다
signal disconnected  # 연결된 상태에서 요청이 실패했다

var api_base := ""  # ""이면 오프라인
var device_path := "user://device.json"  # 테스트는 start() 전에 임시 경로로 바꾼다
var device_id := ""
var token := ""  # 메모리에만
var up := false  # 지금 서버와 연결됨
var ready_once := false  # 첫 접속(gamedata + player)을 마쳤다
var gamedata_version := ""
var logins := 0  # 로그인 성공 횟수(테스트용)
var requested := {}  # 경로 → 큐에 넣은 횟수(테스트용)
var kill_seq_sent := 0  # 마지막으로 큐에 넣은 처치 묶음 번호

var _http: HTTPRequest
var _queue: Array = []  # {method, path, body, auth, done, fail}
var _busy := false
var _fails := 0
var _auth_retries := 0
var _flush_cd := FLUSH_SEC
var _refreshing := false
var _started := false


func _ready() -> void:
	api_base = resolve_api_base()
	_http = HTTPRequest.new()
	_http.timeout = TIMEOUT_SEC
	_http.request_completed.connect(_on_completed)
	add_child(_http)
	set_process(false)


func is_online() -> bool:
	return api_base != ""


## 접속 시작(온라인 모드에서 main이 부른다). 두 번째 호출은 무시.
func start() -> void:
	if _started or not is_online():
		return
	_started = true
	Economy.net = self
	Economy.save_path = ""  # 온라인은 서버가 저장한다
	GameState.stage_cleared.connect(_on_stage_cleared)
	connected.connect(flush_kills)  # 다시 연결되면 쌓아 둔 처치를 보낸다
	device_id = load_device_id(device_path)
	_queue.append(_login_item())
	send("GET", "/v1/gamedata", null, _on_gamedata, Callable(), false)
	send("GET", "/v1/player", null, _on_first_player)
	set_process(true)


## 요청을 큐 끝에 넣는다. done(data: Dictionary)은 2xx 응답, fail()은 서버가 거절(4xx)해 버렸을 때.
func send(method: String, path: String, body = null, done := Callable(), fail := Callable(), auth := true) -> void:
	requested[path] = int(requested.get(path, 0)) + 1
	_queue.append({"method": method, "path": path, "body": body, "auth": auth, "done": done, "fail": fail})
	_pump()


## /v1/player로 상태·시세를 다시 받는다(겹쳐 보내지 않는다).
func refresh() -> void:
	if _refreshing:
		return
	_refreshing = true
	send("GET", "/v1/player", null, _on_refreshed, _on_refresh_failed)


## 쌓인 처치를 스테이지마다 /v1/kills로 보낸다. 끊겼거나 앞 보고가 아직 응답 전이면 다음 기회에.
## 묶음마다 seq = 마지막 번호 + 1. 다시 보내기는 같은 본문(같은 seq)이라 서버가 두 번 반영하지 않는다.
func flush_kills() -> void:
	if not up or not Economy.kills_sent.is_empty() or Economy.kills_pending.is_empty():
		return
	var batch: Dictionary = Economy.take_kills()
	for s in batch:
		var stage: int = s
		kill_seq_sent = maxi(Economy.kill_seq, kill_seq_sent) + 1
		send("POST", "/v1/kills", {"seq": kill_seq_sent, "stage": stage, "kills": batch[s]}, _on_kills.bind(stage), _on_kills_dropped.bind(stage))


func _process(delta: float) -> void:
	if not ready_once:
		return
	_flush_cd -= delta
	if _flush_cd <= 0.0:
		_flush_cd = FLUSH_SEC
		flush_kills()
	if up and not _refreshing and Economy.time_now() >= float(Economy.merchant.get("next_change", INF)):
		refresh()  # 시세 시간 칸이 바뀌었다


## API 주소. 디버그 빌드만 실행 인자·URL로 바꿀 수 있다 — 출시 빌드에서 남의 서버로 기기 id(계정 열쇠)를 보내게 하는 링크를 막는다.
static func resolve_api_base() -> String:
	var url := arg_value("api") if OS.is_debug_build() else ""
	if url == "":
		url = str(ProjectSettings.get_setting("castle/api_base_url", ""))
	return url.strip_edges().trim_suffix("/")


## 값 있는 플래그. 네이티브는 유저 인자 `-- --name=값`, 웹은 URL `?name=값`(main의 플래그 읽기와 같은 방식).
static func arg_value(name: String) -> String:
	var prefix := "--%s=" % name
	for a in OS.get_cmdline_user_args():
		if a.begins_with(prefix):
			return a.substr(prefix.length())
	if OS.has_feature("web"):
		var v = JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('%s') || ''" % name)
		return "" if v == null else str(v)
	return ""


## 기기 id(게스트 계정 열쇠). 없거나 깨졌으면 무작위 128비트 hex를 만들어 저장한다.
static func load_device_id(path: String) -> String:
	if FileAccess.file_exists(path):
		var json := JSON.new()  # parse_string은 깨진 입력에 엔진 오류를 찍는다
		if json.parse(FileAccess.get_file_as_string(path)) == OK and json.data is Dictionary:
			var saved = json.data.get("device_id")
			if saved is String and RegEx.create_from_string(DEVICE_RE).search(saved) != null:
				return saved
		push_warning("device id file is corrupt; making a new one")
	var id := Crypto.new().generate_random_bytes(16).hex_encode()
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("device id save failed: %s" % error_string(FileAccess.get_open_error()))
	else:
		f.store_string(JSON.stringify({"device_id": id}))
		f.close()
	return id


# --- 큐 ---

func _login_item() -> Dictionary:
	requested["/v1/auth/guest"] = int(requested.get("/v1/auth/guest", 0)) + 1
	return {"method": "POST", "path": "/v1/auth/guest", "body": {"device_id": device_id}, "auth": false, "done": _on_login, "fail": Callable()}


func _pump() -> void:
	if _busy or _queue.is_empty():
		return
	_busy = true
	_send_head()


func _next() -> void:
	_busy = false
	_pump()


func _send_head() -> void:
	var it: Dictionary = _queue[0]
	var headers := PackedStringArray()
	var body := ""
	if it.body != null:
		headers.append("Content-Type: application/json")
		body = JSON.stringify(it.body)
	if it.auth:
		headers.append("Authorization: Bearer " + token)
	var method := HTTPClient.METHOD_POST if it.method == "POST" else HTTPClient.METHOD_GET
	if _http.request(api_base + it.path, headers, method, body) != OK:
		_on_completed(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray())


func _on_completed(result: int, code: int, _headers: PackedStringArray, raw: PackedByteArray) -> void:
	if _queue.is_empty():
		return
	var it: Dictionary = _queue[0]
	var data = null
	var json := JSON.new()
	if raw.size() > 0 and json.parse(raw.get_string_from_utf8()) == OK:
		data = json.data
	var answered := result == HTTPRequest.RESULT_SUCCESS
	if answered and code >= 200 and code < 300 and data is Dictionary:
		_queue.pop_front()
		_fails = 0
		_auth_retries = 0
		if data.has("server_now"):
			Economy.clock_offset = float(data.server_now) - Time.get_unix_time_from_system()
		if it.done.is_valid():
			it.done.call(data)
		_mark_up()
		_next()
	elif answered and code == 401 and it.auth and _auth_retries < 2:
		_auth_retries += 1  # 토큰 만료·위조·없는 플레이어: 다시 로그인하고 같은 요청을 다시
		token = ""
		_queue.push_front(_login_item())
		_next()
	elif answered and code >= 400 and code < 500 and code not in [401, 408, 409, 429]:
		_queue.pop_front()  # 잘못된 요청: 다시 보내도 같다
		push_error("server rejected %s %s: %d %s" % [it.method, it.path, code, str(data)])
		if it.fail.is_valid():
			it.fail.call()
		_mark_up()
		_next()
	else:
		_fails += 1  # 연결 실패·시간 초과·5xx·409: 같은 요청을 잠시 뒤 다시
		_auth_retries = 0
		if up:
			up = false
			disconnected.emit()
		get_tree().create_timer(minf(pow(2.0, _fails), RETRY_MAX_SEC)).timeout.connect(_send_head)


func _mark_up() -> void:
	if ready_once and not up:
		up = true
		connected.emit()


# --- 응답 ---

func _on_login(data: Dictionary) -> void:
	token = str(data.get("token", ""))
	logins += 1


func _on_gamedata(data: Dictionary) -> void:
	gamedata_version = str(data.get("version", ""))
	if not GameData.apply_remote(data):
		push_error("server gamedata rejected (%d errors); keeping the built-in tables" % GameData.errors)


## 첫 player 응답: 상태와 스테이지·성 레벨을 서버 값으로 두고 HP를 새 표로 채운다. 그 다음 connected(_mark_up).
func _on_first_player(data: Dictionary) -> void:
	if not Economy.apply_server(data):
		return
	var p: Dictionary = data.player
	GameState.stage = int(p.stage)
	GameState.keep_level = int(p.get("keep_level", 1))
	GameState.gate_level = int(p.get("gate_level", 1))
	GameState.refill()
	ready_once = true


func _on_refreshed(data: Dictionary) -> void:
	_refreshing = false
	Economy.apply_server(data)


func _on_refresh_failed() -> void:
	_refreshing = false


func _on_kills(data: Dictionary, stage: int) -> void:
	Economy.kills_done(stage)
	Economy.apply_server(data)


func _on_kills_dropped(stage: int) -> void:
	Economy.kills_done(stage)
	Economy.changed.emit()


## 스테이지 클리어: 쌓인 처치를 먼저 보내고 클리어를 저장한다(끊겼어도 큐에 넣어 다시 연결되면 간다).
func _on_stage_cleared(stage: int) -> void:
	flush_kills()
	send("POST", "/v1/stage/clear", {"stage": stage}, _on_stage_saved)


## 너무 빠른 클리어는 서버가 cleared: false(상태 그대로)로 답한다 — 상태만 반영하고 다시 보내지 않는다.
func _on_stage_saved(data: Dictionary) -> void:
	if data.get("cleared", true) == false:
		push_warning("server refused stage clear; server stage stays %s" % str(data.get("player", {}).get("stage")))
	Economy.apply_server(data)
