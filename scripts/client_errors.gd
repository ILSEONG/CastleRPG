extends Node
## 앱 오류 보고(오토로드 ClientErrors, 2026-10-30 사용자 "1~4번 다 해줘"의 1번): GDScript·엔진 오류를 모아 서버 POST /v1/client/errors로 보낸다.
## 서버가 오류 모음(Sentry)으로 넘긴다(server/src/sentry.ts — SENTRY_DSN이 없으면 받기만 한다).
## 게임 요청 줄(Net)과 따로 자기 HTTPRequest로 보낸다(오류 보고가 게임 요청을 막지 않게). 실패하면 버린다.
## 같은 오류는 한 번만, 한 번 켤 때 SESSION_MAX개까지, SEND_SEC마다 모아서. 경고는 보내지 않는다. 오프라인이면 아무것도 안 한다.

const PATH := "/v1/client/errors"
const SESSION_MAX := 20
const SEND_SEC := 10.0
const BATCH := 10  # 서버 CLIENT_ERRORS_MAX와 같다


## 엔진이 오류를 찍을 때마다 부른다(다른 스레드에서도 온다 — 잠그고 쌓기만 한다).
class Catcher extends Logger:
	var mutex := Mutex.new()
	var pending: Array = []
	var seen := {}
	var total := 0

	func _log_error(fn: String, file: String, line: int, code: String, why: String, _editor_notify: bool, error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		var msg := why if why != "" else code
		var key := "%s:%d %s" % [file, line, msg]
		var stack := ""
		for bt in script_backtraces:
			for i in bt.get_frame_count():
				stack += "[%d] %s (%s:%d)\n" % [i, bt.get_frame_function(i), bt.get_frame_file(i), bt.get_frame_line(i)]
		if stack == "":
			stack = "[0] %s (%s:%d)" % [fn, file, line]
		mutex.lock()
		if not seen.has(key) and total < SESSION_MAX:
			seen[key] = true
			total += 1
			pending.append({"type": "ScriptError" if error_type == ERROR_TYPE_SCRIPT else "EngineError", "message": msg.substr(0, 1000), "stack": stack.substr(0, 4000)})
		mutex.unlock()

	func take() -> Array:
		mutex.lock()
		var out := pending.slice(0, BATCH)
		pending = pending.slice(BATCH)
		mutex.unlock()
		return out


var catcher := Catcher.new()
var sent := 0  # 보낸 오류 수(테스트용)
var _http := HTTPRequest.new()
var _busy := false
var _cd := SEND_SEC


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	OS.add_logger(catcher)
	_http.timeout = 15.0
	add_child(_http)
	_http.request_completed.connect(func(_r, _c, _h, _b): _busy = false)


func _exit_tree() -> void:
	OS.remove_logger(catcher)


func _process(delta: float) -> void:
	_cd -= delta / maxf(Engine.time_scale, 0.01)
	if _cd > 0.0:
		return
	_cd = SEND_SEC
	flush()


## 쌓인 오류를 지금 보낸다.
func flush() -> void:
	if _busy or Net.api_base == "":
		return
	var errors := catcher.take()
	if errors.is_empty():
		return
	var headers := PackedStringArray(["Content-Type: application/json"])
	if Net.token != "":
		headers.append("Authorization: Bearer " + Net.token)
	var body := {"version": LiveOps.app_version(), "os": OS.get_name(), "store": str(ProjectSettings.get_setting("castle/platform", "")), "errors": errors}
	if _http.request(Net.api_base + PATH, headers, HTTPClient.METHOD_POST, JSON.stringify(body)) == OK:
		_busy = true
		sent += errors.size()
