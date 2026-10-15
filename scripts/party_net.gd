extends Node
## 파티 퀘스트 실시간 연결(party_battle.gd 자식). 서버 server/src/party_live.ts 방(WebSocket)에 붙는다 — 공성전(war_net.gd)과 같은 방식.
## - 방장(먼저 들어온 성주): 이 기기가 전투를 판단하고 battle.SNAP_SEC마다 상태 한 장(snap)을 보낸다. 다른 성주의 명령(cmd)을 받아 그 영웅에 준다.
##   전투가 끝나면 end {win, elapsed} — 서버가 매치 결과로 남기고 모두에게 end를 돌려준다(방장도 받는다).
## - 참가자: 방장 상태를 따라 그리고(꼭두각시), 내 영웅 명령을 방장에게 보낸다. 방장이 나가면 이어받는다(host).
## - end를 받으면 각자 결과를 서버에 보낸다(Party.finish — 서버는 방장이 알린 결과를 쓴다).
## 연결이 안 되거나 끊기면 이 기기가 혼자 이어서 판단하고, 끝나면 바로 결과를 보낸다(solo).

const CONNECT_WAIT := 8.0
const PATH := "/v1/party/live"

var battle
var url := ""
var ws := WebSocketPeer.new()
var link := "connecting"  # connecting | open | solo
var ended := false
var _wait := CONNECT_WAIT


static func live_url(api_base: String, match_id: String, token: String) -> String:
	var base := api_base
	if base.begins_with("https://"):
		base = "wss://" + base.substr(8)
	elif base.begins_with("http://"):
		base = "ws://" + base.substr(7)
	return "%s%s?match=%s&token=%s" % [base, PATH, match_id.uri_encode(), token.uri_encode()]


func _ready() -> void:
	battle.command_sent.connect(_on_command)
	if url == "" or ws.connect_to_url(url) != OK:
		_go_solo()


func is_open() -> bool:
	return link == "open" and ws.get_ready_state() == WebSocketPeer.STATE_OPEN


func _process(delta: float) -> void:
	if link == "solo":
		return
	ws.poll()
	match ws.get_ready_state():
		WebSocketPeer.STATE_CONNECTING:
			_wait -= delta
			if _wait <= 0.0:
				ws.close()
				_go_solo()
		WebSocketPeer.STATE_OPEN:
			if link == "connecting":
				link = "open"
			while ws.get_available_packet_count() > 0:
				_on_message(ws.get_packet().get_string_from_utf8())
			if battle.role == "host" and not battle.done and battle.snapshot_due():
				_send({"t": "snap", "s": battle.snapshot()})
		WebSocketPeer.STATE_CLOSED:
			if not ended:
				_go_solo()


func _on_message(raw: String) -> void:
	var m = JSON.parse_string(raw)
	if not (m is Dictionary):
		return
	match str(m.get("t", "")):
		"hello":
			if m.get("snap") is Dictionary:
				battle.apply_snapshot(m.snap)
			battle.set_role("host" if m.get("host", false) else "puppet")
		"snap":
			if m.get("s") is Dictionary:
				battle.apply_snapshot(m.s)
		"cmd":
			if battle.role == "host":
				battle.apply_command(int(m.get("seat", -1)), int(m.get("uid", 0)), m.get("pos"))
		"host":
			if m.get("snap") is Dictionary:
				battle.apply_snapshot(m.snap)
			battle.set_role("host")
		"end":
			ended = true
			battle.end_from_room(bool(m.get("win", false)), float(m.get("elapsed", battle.clock)))


## 끊김·연결 실패: 이 기기가 혼자 판단한다(이미 방장이었으면 그대로).
func _go_solo() -> void:
	if link == "solo":
		return
	link = "solo"
	if not battle.done:
		battle.set_role("host")
	else:
		battle.report_result()  # 끝을 알린 뒤 end를 못 받고 끊겼다: 바로 보낸다


## 방장: 결과를 방에 알린다. 열려 있지 않으면 false(쓰는 쪽이 바로 Party.finish).
func send_end(win: bool, elapsed: float) -> bool:
	if not is_open():
		return false
	_send({"t": "end", "win": win, "elapsed": snappedf(elapsed, 0.01)})
	return true


func _on_command(uid: int, pos) -> void:
	_send({"t": "cmd", "uid": uid, "pos": pos})


func _exit_tree() -> void:
	ws.close()


func _send(msg: Dictionary) -> void:
	if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws.send_text(JSON.stringify(msg))
