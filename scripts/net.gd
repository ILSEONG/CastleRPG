extends Node
## 서버 접속(개정 9 온라인 모드). 오토로드 Net. API 주소가 비면 오프라인 모드 — 아무것도 하지 않는다.
## 주소: 프로젝트 설정 castle/api_base_url. 디버그 빌드에선 `-- --api=<url>`(네이티브)·`?api=<url>`(웹)이 앞선다.
## start(): 게스트 로그인 → /v1/gamedata(GameData.apply_remote) → /v1/player. 그 뒤 connected를 낸다(main이 월드를 만든다).
## 첫 /v1/player가 틀렸거나 버려지면 백오프 뒤 다시 받는다.
## 요청은 HTTPRequest 하나로 한 번에 하나(큐). 응답 처리는 classify() 참고 — 끊김 띠는 연결 불가·시간 초과에만 뜨고,
## 서버가 답한 실패(5xx·409·4xx)는 횟수를 정해 다시 보내거나 버려 큐를 무한히 막지 않는다. 토큰은 메모리에만 둔다.
## 응답의 server_now − 로컬 시각으로 Economy.clock_offset을 맞춘다. 처치 골드는 10초마다·스테이지 클리어 때 보낸다.
## 서버 stage가 진실: 클리어가 거부되면(cleared:false) 다음 스테이지 경계(GameState.refill)에서 GameState.stage를 서버 값으로 맞춘다.

const GameData := preload("res://scripts/game_data.gd")

const RETRY_MAX_SEC := 15.0
const TIMEOUT_SEC := 10.0
const FLUSH_SEC := 10.0  # 처치 골드 보고 간격
const AUTH_MAX := 3  # 연속 401(다시 로그인해도 또 401) 허용 횟수. 넘으면 끊김 상태로 RETRY_MAX_SEC마다 다시 로그인
const SERVER_TRIES := 4  # 접속 뒤 5xx·408·429는 한 요청을 이만큼 다시 보내고 버린다
const DEVICE_RE := "^[A-Za-z0-9-]{16,128}$"
const STORAGE_TEXT := "브라우저 저장소가 꺼져 있어 진행이 저장되지 않을 수 있습니다"

signal connected     # 끊긴 상태(또는 첫 접속 전)에서 서버에 닿았다
signal disconnected  # 연결된 상태에서 요청이 서버에 닿지 못했다(연결 불가·시간 초과) 또는 연속 401

var api_base := ""  # ""이면 오프라인
var device_path := "user://device.json"  # 테스트는 start() 전에 임시 경로로 바꾼다
var device_id := ""
var token := ""  # 메모리에만
var up := false  # 지금 서버와 연결됨
var ready_once := false  # 첫 접속(gamedata + player)을 마쳤다
var storage_persistent := true  # user://가 남는가(웹 사생활 모드·IndexedDB 차단이면 false). 테스트는 start() 전에 바꾼다
var gamedata_version := ""
var logins := 0  # 로그인 성공 횟수(테스트용)
var requested := {}  # 경로 → 큐에 넣은 횟수(테스트용)
var kill_seq_sent := 0  # 마지막으로 큐에 넣은 처치 묶음 번호
var last_error := ""  # 마지막으로 버린 요청의 서버 오류 코드(fail 콜백이 읽는다. 답이 없었으면 "")

var _http: HTTPRequest
var _queue: Array = []  # {method, path, body, auth, done, fail, tries, conflicted}
var _busy := false
var _fails := 0  # 연속 연결 실패(백오프)
var _auth_retries := 0  # 연속 401. 인증 요청이 성공해야 0(로그인 성공만으로는 안 된다)
var _clears_out := 0  # 보냈고 답을 못 받은 스테이지 클리어
var _first_tries := 0
var _flush_cd := FLUSH_SEC
var _refreshing := false
var _started := false


func _ready() -> void:
	api_base = resolve_api_base()
	storage_persistent = OS.is_userfs_persistent()
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
	GameState.refilled.connect(_on_refilled)
	connected.connect(flush_kills)  # 다시 연결되면 쌓아 둔 처치를 보낸다
	if not storage_persistent:
		push_warning("user storage is not persistent: the device id (guest account key) may not survive this visit")
	device_id = load_device_id(device_path)
	_queue.append(_login_item())
	send("GET", "/v1/gamedata", null, _on_gamedata, Callable(), false)
	send("GET", "/v1/player", null, _on_first_player, _retry_first_player)
	set_process(true)


## 요청을 큐 끝에 넣는다. done(data: Dictionary)은 2xx 응답, fail()은 그 요청을 버렸을 때(4xx·재시도 소진).
## once: 다시 보내면 두 번 반영될 수 있는 요청(모집). 401(서버가 아무것도 안 함) 말고는 다시 보내지 않는다 — 연결 실패·
## 시간 초과·5xx·409면 버리고 fail, 대신 /v1/player를 큐 머리에 넣어 상태(이미 반영됐는지)를 새로 받는다.
func send(method: String, path: String, body = null, done := Callable(), fail := Callable(), auth := true, once := false) -> void:
	var it := _item(method, path, body, done, fail, auth)
	it.once = once
	_queue.append(it)
	_pump()


## /v1/player로 상태·시세를 다시 받는다(겹쳐 보내지 않는다).
func refresh() -> void:
	if _refreshing:
		return
	_refreshing = true
	send("GET", "/v1/player", null, _on_refreshed, _on_refresh_failed)


## 쌓인 처치를 스테이지마다 /v1/kills로 보낸다. 끊겼거나 앞 보고가 아직 응답 전이면 다음 기회에.
## 종류별 수가 서버 상한을 넘으면 여러 묶음으로 나눈다. 묶음마다 seq = 마지막 번호 + 1.
## 다시 보내기는 같은 본문(같은 seq)이라 서버가 두 번 반영하지 않는다.
func flush_kills() -> void:
	if not up or not Economy.kills_sent.is_empty() or Economy.kills_pending.is_empty():
		return
	var batch: Dictionary = Economy.take_kills()
	for s in batch.keys():
		var stage: int = s
		for part in Economy.split_kills(batch[s]):
			kill_seq_sent = maxi(Economy.kill_seq, kill_seq_sent) + 1
			send("POST", "/v1/kills", {"seq": kill_seq_sent, "stage": stage, "kills": part}, _on_kills.bind(stage, part), _on_kills_dropped.bind(stage, part))


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


const DURABLE_PATHS := ["/v1/kills", "/v1/stage/clear"]  # 5xx에도 버리지 않는 요청(멱등)


## 응답 하나를 어떻게 처리할지(순수 함수 — online_check가 표로 확인한다).
##  net: 연결 불가·시간 초과 — 끊김 띠, 같은 요청을 백오프로 계속 다시
##  ok: 반영
##  relogin: 401 — 다시 로그인하고 같은 요청(첫 401은 곧바로, 연속 401은 백오프)
##  auth_down: 연속 401이 AUTH_MAX번 — 끊김 상태, RETRY_MAX_SEC 뒤 다시 로그인
##  refresh: 첫 409(경합) — /v1/player로 상태를 받고 같은 요청을 한 번 더
##  retry: 5xx·408·429·형이 틀린 2xx — 띠 없이 백오프로 다시, tries가 SERVER_TRIES면 drop
##  drop: 그 밖의 4xx(400·404·413…)·두 번째 409 — 그 요청을 버리고 경고
static func classify(result: int, code: int, data, auth: bool, auth_retries: int, tries: int, conflicted: bool) -> String:
	if result != HTTPRequest.RESULT_SUCCESS:
		return "net"
	if code >= 200 and code < 300 and data is Dictionary:
		return "ok"
	if code == 401 and auth:
		return "relogin" if auth_retries < AUTH_MAX else "auth_down"
	if code == 409:
		return "drop" if conflicted else "refresh"
	if code >= 500 or code < 400 or code == 408 or code == 429:
		return "retry" if tries < SERVER_TRIES else "drop"
	return "drop"


static func backoff(n: int) -> float:
	return minf(pow(2.0, n), RETRY_MAX_SEC)


# --- 큐 ---

func _item(method: String, path: String, body, done: Callable, fail: Callable, auth: bool) -> Dictionary:
	requested[path] = int(requested.get(path, 0)) + 1
	return {"method": method, "path": path, "body": body, "auth": auth, "done": done, "fail": fail, "tries": 0, "conflicted": false}


func _login_item() -> Dictionary:
	return _item("POST", "/v1/auth/guest", {"device_id": device_id}, _on_login, Callable(), false)


func _pump() -> void:
	if _busy or _queue.is_empty():
		return
	_busy = true
	_send_head()


func _next() -> void:
	_busy = false
	_pump()


## 머리 요청을 sec초 뒤 다시 보낸다(그동안 _busy라 다른 요청은 기다린다).
func _retry_in(sec: float) -> void:
	get_tree().create_timer(sec).timeout.connect(_send_head)


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
	# 첫 접속 전, 그리고 처치·스테이지 클리어(seq·stage로 서버가 중복을 막는다 — 다시 보내도 안전, 버리면 진행을 잃는다)는
	# 5xx도 버리지 않고 계속 다시 보낸다
	var keep_trying: bool = not ready_once or it.path in DURABLE_PATHS
	var step := classify(result, code, data, it.auth, _auth_retries, 0 if keep_trying else it.tries, it.conflicted)
	if step != "net":
		_fails = 0
	if it.get("once", false) and step in ["net", "retry", "refresh"]:
		_drop_once(it, step, code, data)
		return
	match step:
		"ok":
			_queue.pop_front()
			if it.auth:
				_auth_retries = 0
			if data.has("server_now"):
				Economy.clock_offset = float(data.server_now) - Time.get_unix_time_from_system()
			if it.done.is_valid():
				it.done.call(data)
			_mark_up()
			_next()
		"relogin", "auth_down":
			_auth_retries += 1  # 토큰 만료·위조·없는 플레이어: 다시 로그인하고 같은 요청을 다시
			token = ""
			_queue.push_front(_login_item())
			if step == "auth_down":
				push_warning("server keeps answering 401 after logging in again; retrying in %d s" % RETRY_MAX_SEC)
				_go_down()
				_retry_in(RETRY_MAX_SEC)
			elif _auth_retries == 1:
				_next()
			else:
				_retry_in(backoff(_auth_retries - 1))
		"refresh":
			it.conflicted = true  # 경합: 상태를 새로 받고 같은 요청을 한 번만 더
			_queue.push_front(_item("GET", "/v1/player", null, _on_state, Callable(), true))
			_mark_up()
			_next()
		"retry":
			it.tries += 1
			_mark_up()  # 서버는 닿는다 — 띠 없음
			_retry_in(backoff(it.tries))
		"drop":
			_queue.pop_front()
			push_warning("server rejected %s %s: %d %s; dropping it" % [it.method, it.path, code, str(data)])
			last_error = str(data.get("error", "")) if data is Dictionary else ""
			if it.fail.is_valid():
				it.fail.call()
			_mark_up()
			_next()
		"net":
			_fails += 1
			_go_down()
			_retry_in(backoff(_fails))


## once 요청이 다시 보내야 할 결과(연결 실패·시간 초과·5xx·409)를 받았다: 버리고 fail, 상태를 새로 받는 /v1/player를 머리에 둔다.
## 연결 실패면 끊김 상태로 그 /v1/player를 백오프로 다시 보낸다(다시 연결되면 이미 반영됐는지 상태로 보인다).
func _drop_once(it: Dictionary, step: String, code: int, data) -> void:
	_queue.pop_front()
	push_warning("%s %s failed (%s, %d); not resending it" % [it.method, it.path, step, code])
	last_error = str(data.get("error", "")) if data is Dictionary else ""
	_queue.push_front(_item("GET", "/v1/player", null, _on_state, Callable(), true))
	if it.fail.is_valid():
		it.fail.call()
	if step == "net":
		_fails += 1
		_go_down()
		_retry_in(backoff(_fails))
	else:
		_mark_up()
		_next()


func _mark_up() -> void:
	if ready_once and not up:
		up = true
		connected.emit()


func _go_down() -> void:
	if up:
		up = false
		disconnected.emit()


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
		_retry_first_player()
		return
	var p: Dictionary = data.player
	GameState.stage = int(p.stage)
	GameState.keep_level = int(p.get("keep_level", 1))
	GameState.gate_level = int(p.get("gate_level", 1))
	GameState.refill()
	ready_once = true


## 첫 /v1/player가 틀렸거나 버려졌다: 백오프 뒤 다시 받는다(접속 화면에서 멈추지 않게).
func _retry_first_player() -> void:
	_first_tries += 1
	get_tree().create_timer(backoff(_first_tries)).timeout.connect(send.bind("GET", "/v1/player", null, _on_first_player, _retry_first_player))


func _on_refreshed(data: Dictionary) -> void:
	_refreshing = false
	Economy.apply_server(data)


func _on_refresh_failed() -> void:
	_refreshing = false


func _on_state(data: Dictionary) -> void:
	Economy.apply_server(data)


func _on_kills(data: Dictionary, stage: int, part: Dictionary) -> void:
	Economy.kills_done(stage, part)
	Economy.apply_server(data)


func _on_kills_dropped(stage: int, part: Dictionary) -> void:
	Economy.kills_done(stage, part)
	Economy.changed.emit()


## 스테이지 클리어: 쌓인 처치를 먼저 보내고 클리어를 저장한다(끊겼어도 큐에 넣어 다시 연결되면 간다).
func _on_stage_cleared(stage: int) -> void:
	flush_kills()
	_clears_out += 1
	send("POST", "/v1/stage/clear", {"stage": stage}, _on_stage_saved.bind(stage), _on_clear_dropped)


## cleared:false(너무 빠름·중복·앞지름)는 다시 보내지 않는다. 서버 stage가 이미 stage+1 이상이면 앞서 보낸 같은 클리어가
## 반영된 것(응답 유실 뒤 재전송)이라 경고하지 않는다. 로컬 스테이지는 _on_refilled가 다음 경계에서 맞춘다.
func _on_stage_saved(data: Dictionary, stage: int) -> void:
	_clears_out -= 1
	Economy.apply_server(data)
	if data.get("cleared", true) == false and Economy.server_stage <= stage:
		push_warning("server refused stage %d clear; server stage stays %d" % [stage, Economy.server_stage])


func _on_clear_dropped() -> void:
	_clears_out -= 1


## 스테이지 경계(refill: 결과가 끝나 대기·카운트다운으로 갈 때, 스테이지 시작). 보낸 클리어가 다 답을 받았는데
## 로컬 스테이지가 서버와 다르면(거부·버림) 서버 stage로 맞춘다. 스테이지 도중에는 바꾸지 않는다.
func _on_refilled() -> void:
	if ready_once and _clears_out == 0 and GameState.stage != Economy.server_stage:
		push_warning("local stage %d -> server stage %d" % [GameState.stage, Economy.server_stage])
		GameState.stage = Economy.server_stage
