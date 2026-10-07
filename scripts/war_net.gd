extends Node
## 공성 전투 실시간 연결(온라인). war_battle.gd 자식으로 붙는다. 서버 server/src/war_live.ts 방(WebSocket)에 붙어:
## - 방장(먼저 들어온 사람): 이 기기가 전투를 판단하고 battle.SNAP_SEC마다 상태 한 장(snap)을, CKPT_SEC마다 성 상태(ckpt)를 보낸다.
##   다른 길드원의 이동 명령(cmd)을 받아 그 영웅에 준다. 전투가 끝나면 end(최종 성 상태 — 서버가 저장하고 모두에게 end).
## - 참가자: 방장 상태를 따라 그리고(꼭두각시), 내 영웅 이동 명령을 방장에게 보낸다. 방장이 나가면 이어받는다(host).
## - 새 길드원이 들어오면 서버가 roster(그 분대)를 보낸다 — 모두 분대를 더한다. 길드장이 [전투 시작]을 누르면 서버가 start를 보낸다(배치 끝).
## 연결이 안 되거나 끊기면 이 기기가 혼자 이어서 판단하고, 끝나면 REST(/v1/guild/war/finish)로 결과를 보낸다.

const CKPT_SEC := 10.0
const CONNECT_WAIT := 8.0

var battle
var url := ""
var ws := WebSocketPeer.new()
var link := "connecting"  # connecting | open | solo
var ended := false

var _ckpt := CKPT_SEC
var _wait := CONNECT_WAIT
var _sent_end := false


## api(https://…) + 경로 → wss://…?battle=&token=
static func live_url(api_base: String, path: String, battle_id: String, token: String) -> String:
	var base := api_base
	if base.begins_with("https://"):
		base = "wss://" + base.substr(8)
	elif base.begins_with("http://"):
		base = "ws://" + base.substr(7)
	return "%s%s?battle=%s&token=%s" % [base, path, battle_id.uri_encode(), token.uri_encode()]


func _ready() -> void:
	battle.command_sent.connect(_on_command)
	battle.finished.connect(_on_finished)
	ws.inbound_buffer_size = 1 << 20
	ws.outbound_buffer_size = 1 << 20
	if url == "" or ws.connect_to_url(url) != OK:
		_go_solo()
	else:
		_status("실시간 연결 중…")


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
			if battle.role == "host" and not battle.done:
				if battle.snapshot_due():
					_send({"t": "snap", "s": battle.snapshot()})
				_ckpt -= delta
				if _ckpt <= 0.0:
					_ckpt = CKPT_SEC
					_send({"t": "ckpt", "state": battle.state_now()})
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
			if m.get("host", false):
				battle.set_role("host")
			_status("")
		"snap":
			if m.get("s") is Dictionary:
				battle.apply_snapshot(m.s)
		"cmd":
			if battle.role == "host":
				battle.apply_command(str(m.get("from", "")), int(m.get("uid", 0)), m.get("pos"))
		"host":
			if m.get("snap") is Dictionary:
				battle.apply_snapshot(m.snap)
			battle.set_role("host")
		"start":  # 서버: [전투 시작]이 눌렸다(배치 끝)
			battle.begin_fight()
		"roster":
			if m.get("squad") is Dictionary:
				battle.add_squad(m.squad)
		"end":
			ended = true
			if not battle.done:
				battle.end_from_host()
			GuildWar.fetch()


## 끊김·연결 실패: 이 기기가 혼자 판단한다(이미 방장이었으면 그대로).
func _go_solo() -> void:
	if link == "solo":
		return
	link = "solo"
	if not battle.done and battle.role == "puppet":
		battle.set_role("host")
	_status("실시간 연결이 끊겨 혼자 진행합니다")


func _on_command(uid: int, pos) -> void:
	_send({"t": "cmd", "uid": uid, "pos": pos})


func _on_finished(result: Dictionary) -> void:
	if battle.role == "puppet" or _sent_end:
		return
	_sent_end = true
	if link == "open" and ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_send({"t": "end", "state": result})
	else:
		GuildWar.finish(result)


func _exit_tree() -> void:
	if link == "open" and battle.role == "host" and not battle.done:
		_send({"t": "ckpt", "state": battle.state_now()})  # 나가도 지금까지 깎은 성은 남는다(다른 길드원이 이어받는다)
	ws.close()


func _send(msg: Dictionary) -> void:
	if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws.send_text(JSON.stringify(msg))


func _status(text: String) -> void:
	if battle.hud != null:
		battle.hud.set_status(text)
