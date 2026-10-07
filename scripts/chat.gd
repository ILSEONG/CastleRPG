extends Node
## 채팅(사용자 2026-10-07, 오토로드 Chat): 전체·길드 채널. 서버 GET/POST /v1/chat(server/src/chat.ts, 마이그레이션 032).
## 전달은 폴링: 채팅 창이 열려 있으면 OPEN_POLL_SEC마다, 닫혀 있으면 성 화면 채팅 줄(chat_bar.gd)의 마지막 줄을 위해 IDLE_POLL_SEC마다.
## 보내면 내 줄이 바로 보이고(대기 표시 없음) 서버가 받으면 서버 줄로 바뀐다. 서버가 거절하면 그 줄을 지우고 짧은 알림(notice)을 낸다.
## 오프라인(서버 없음)이면 아무것도 보내지 않는다.

signal changed  # 메시지 목록·길드 채널 유무가 바뀌었다
signal notice(text: String)  # 보내기가 거절됐다 등 짧은 알림

const MAX_LEN := 100  # 서버 MAX_LEN과 같다
const GAP_SEC := 2.0  # 서버 GAP_SEC과 같다(도배 제한)
const KEEP := 100  # 채널마다 들고 있는 메시지 수
const OPEN_POLL_SEC := 3.0
const IDLE_POLL_SEC := 20.0
const CHANNELS := ["all", "guild"]
const REFUSALS := {
	"too_fast": "조금 천천히 보내 주세요",
	"no_guild": "길드에 들어가야 길드 채팅을 쓸 수 있어요",
	"empty": "보낼 내용을 적어 주세요",
}

var messages := {"all": [], "guild": []}  # 채널 → [{id, name, text, at, me, local?}] (오래된 것부터)
var has_guild := false  # 서버가 길드 채널을 돌려줬다(길드원)
var guild_name := ""
var window_open := false  # 채팅 창이 열려 있다(자주 받는다)
var polls := 0  # 받은 횟수(테스트용)

var _cd := 0.0  # 다음 받기까지
var _polling := false
var _last_send_ms := -100000
var _local_seq := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func online() -> bool:
	return Net.is_online()


func _process(delta: float) -> void:
	if not online() or not Net.ready_once:
		return
	_cd -= delta / maxf(Engine.time_scale, 0.01)  # 실제 초(배속과 무관)
	if _cd <= 0.0:
		poll()


## 지금 받는다(창을 열 때 바로).
func poll() -> void:
	_cd = OPEN_POLL_SEC if window_open else IDLE_POLL_SEC
	if _polling or not online() or not Net.up:
		return
	_polling = true
	var path := "/v1/chat?all=%d&guild=%d" % [last_id("all"), last_id("guild")]
	Net.send("GET", path, null, _on_poll, func(): _polling = false)


func set_window_open(on: bool) -> void:
	window_open = on
	if on:
		poll()


func last_id(ch: String) -> int:
	var best := 0
	for m in messages[ch]:
		best = maxi(best, int(m.id))
	return best


func _on_poll(d: Dictionary) -> void:
	_polls_done()
	var g = d.get("guild")
	var was := has_guild
	has_guild = g is Array
	var gname := str(d.get("guild_name", ""))
	var refetch := false
	if not has_guild or gname != guild_name:  # 길드를 나갔거나 바꿨다 — 그 길드 줄은 버리고(바꿨으면) 처음부터 다시 받는다
		refetch = has_guild and last_id("guild") > 0
		messages.guild = []
	guild_name = gname
	var added := _merge("all", d.get("all", []))
	if has_guild and not refetch:
		added = _merge("guild", g) or added
	if refetch:
		_cd = 0.0
	if added or was != has_guild:
		changed.emit()


func _polls_done() -> void:
	_polling = false
	polls += 1


## 서버 줄을 더한다(같은 id는 한 번만, 내 대기 줄 앞에). 더했으면 true.
func _merge(ch: String, rows) -> bool:
	if not rows is Array or rows.is_empty():
		return false
	var have := {}
	for m in messages[ch]:
		have[int(m.id)] = true
	var server: Array = messages[ch].filter(func(m): return not m.get("local", false))
	var local: Array = messages[ch].filter(func(m): return m.get("local", false))
	var added := false
	for r in rows:
		if r is Dictionary and not have.has(int(r.get("id", 0))):
			server.append(_row(r))
			added = true
	server.sort_custom(func(a, b): return int(a.id) < int(b.id))
	messages[ch] = (server + local).slice(-KEEP)
	return added


func _row(r: Dictionary) -> Dictionary:
	return {"id": int(r.get("id", 0)), "name": str(r.get("name", "")), "text": str(r.get("text", "")), "at": float(r.get("at", 0)), "me": bool(r.get("me", false))}


## 가장 최근 줄(채팅 줄 표시용): {ch, name, text} 또는 {}.
func latest() -> Dictionary:
	var best := {}
	var best_at := -1.0
	for ch in CHANNELS:
		if ch == "guild" and not has_guild:
			continue
		var xs: Array = messages[ch]
		if xs.is_empty():
			continue
		var m: Dictionary = xs[-1]
		var at := float(m.get("at", 0)) if not m.get("local", false) else 1e12
		if at >= best_at:
			best_at = at
			best = {"ch": ch, "name": m.name, "text": m.text}
	return best


## 보낸다: 내 줄을 바로 보이고 서버에 보낸다. 바로 거절(빈 글·너무 빠름·오프라인)이면 false(입력은 그대로 둔다).
func send(ch: String, raw: String) -> bool:
	var text := clean(raw)
	if text == "":
		return false
	if not online():
		notice.emit("온라인에서만 채팅할 수 있어요")
		return false
	if ch == "guild" and not has_guild:
		notice.emit(REFUSALS.no_guild)
		return false
	if Time.get_ticks_msec() - _last_send_ms < int(GAP_SEC * 1000.0):
		notice.emit(REFUSALS.too_fast)
		return false
	_last_send_ms = Time.get_ticks_msec()
	_local_seq += 1
	var lid := -_local_seq
	var me_name := str(Economy.friends.get("name", "나"))
	messages[ch].append({"id": lid, "name": me_name, "text": text, "at": Time.get_unix_time_from_system(), "me": true, "local": true})
	changed.emit()
	Net.send("POST", "/v1/chat", {"channel": ch, "text": text}, func(d): _on_sent(ch, lid, d), func(): _on_refused(ch, lid))
	return true


func _on_sent(ch: String, lid: int, d: Dictionary) -> void:
	var xs: Array = messages[ch].filter(func(m): return int(m.id) != lid)
	messages[ch] = xs
	var msg = d.get("msg")
	if msg is Dictionary:
		_merge(ch, [msg])
	changed.emit()


func _on_refused(ch: String, lid: int) -> void:
	messages[ch] = messages[ch].filter(func(m): return int(m.id) != lid)
	changed.emit()
	notice.emit(REFUSALS.get(Net.last_error, "메시지를 보내지 못했어요"))


## 서버 clean과 같다: 줄바꿈·제어 문자 → 공백, 공백 하나로, 앞뒤 공백 지움, MAX_LEN 글자까지.
static func clean(raw: String) -> String:
	var out := ""
	var space := false
	for i in raw.length():
		var c := raw.unicode_at(i)
		if c < 32 or c == 127 or c == 0x2028 or c == 0x2029 or c == 32 or c == 0x3000 or c == 0xA0:
			space = true
			continue
		if space and out != "":
			out += " "
		space = false
		out += String.chr(c)
	return out.substr(0, MAX_LEN)
