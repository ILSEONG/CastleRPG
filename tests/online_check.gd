extends Node
## 헤드리스 온라인 통합 체크(개정 9 §7). dev/online-check.sh가 서버(메모리 PGlite, 테스트 훅, 포트 8790)를 띄우고 두 번 돌린다.
## 실행: ... res://tests/online_check.tscn -- --api=http://127.0.0.1:8790 --device=<임시 파일> --state=<임시 파일> --phase=1|2
## phase 1: 접속·월드·응답 처리 규칙(classify)·처치 골드·재로그인·4xx 버림·수집·판매·시세 갱신·끊김·스테이지 클리어·
##   끊긴 동안 쌓인 클리어 둘 중 두 번째 거부 → 다음 경계에서 서버 stage로·처치 묶음 나누기. 끝 상태를 --state 파일에 쓴다.
## phase 2: 같은 기기 id로 다시 접속해 골드·자원·스테이지가 그대로인지 본다. 웹 비영구 저장소 경고 띠와 띠 위치도 본다.
## 오토로드를 쓰므로 tests/run_tests.gd(-s)에서 preload 금지. user://save.json·device.json을 쓰지 않는다(온라인은 저장 안 함, 기기 id는 임시 파일).

const Balance := preload("res://scripts/balance.gd")
const GameData := preload("res://scripts/game_data.gd")
const PickerScript := preload("res://scripts/unit_picker.gd")
const SpawnerScript := preload("res://scripts/spawner.gd")
const BadgesScript := preload("res://scripts/badges.gd")
const HudScript := preload("res://scripts/hud.gd")
const MerchantPanelScript := preload("res://scripts/merchant_panel.gd")
const BuildingsScript := preload("res://scripts/buildings.gd")
const DEAD_API := "http://127.0.0.1:1"  # 아무도 듣지 않는 포트 — 끊김 흉내

class ErrorCounter extends Logger:
	var count := 0
	var warnings: Array[String] = []  # 경고 문구(경고는 실패로 세지 않고, 특정 경고가 났는지·안 났는지 본다)
	func _log_error(_fn: String, _file: String, _line: int, code: String, why: String, _notify: bool, error_type: int, _bt: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			warnings.append(code + " " + why)
		else:
			count += 1

var _fails := 0
var _errors := ErrorCounter.new()
var _main
var _picker
var _spawner
var _badges
var _hud
var _panel
var _scenery
var _resp = null  # _request의 응답
var _resp_done := false


func _ready() -> void:
	OS.add_logger(_errors)
	Engine.max_fps = 60
	get_window().size = Vector2i(360, 640)  # 논리 화면 720×1280(input_check와 같다)
	var phase := Net.arg_value("phase")
	var device := Net.arg_value("device")
	var state_path := Net.arg_value("state")
	_check(Net.is_online() and device != "" and state_path != "" and phase in ["1", "2"], "online mode with --api, --device, --state, --phase",
		"api=%s device=%s state=%s phase=%s" % [Net.api_base, device, state_path, phase])
	if _fails == 0:
		Net.device_path = device  # start() 전에
		if phase == "1":
			await _phase1(state_path)
		else:
			await _phase2(state_path)
	if _errors.count > 0:
		print("ONLINE SCRIPT ERRORS %d" % _errors.count)
	_fails += _errors.count
	if _fails > 0:
		print("ONLINE FAILED %d" % _fails)
		get_tree().quit(1)
	else:
		print("ONLINE PHASE %s PASSED" % phase)
		get_tree().quit(0)


func _phase1(state_path: String) -> void:
	DirAccess.remove_absolute(Net.device_path)  # 새 기기
	GameState.stage = 9  # 접속하면 서버 값으로 바뀌어야 한다
	Economy.gold = 777
	if not await _start_world():
		return
	var grunt1 := GameData.kill_gold("grunt", 1)

	# (a) 접속 → 월드, 서버 상태
	_check(Net.logins == 1 and Net.gamedata_version != "" and GameData.errors == 0, "(a) one guest login, server gamedata applied",
		"logins=%d version=%s errors=%d" % [Net.logins, Net.gamedata_version, GameData.errors])
	_check(GameState.stage == 1 and Economy.server_stage == 1 and Economy.gold == 0 and Economy.server_gold == 0,
		"(a) GameState.stage and gold come from the server (new player: stage 1, gold 0)", "stage=%d server_stage=%d gold=%d" % [GameState.stage, Economy.server_stage, Economy.gold])
	_check(Net.device_id.length() == 32 and Net.device_id.is_valid_hex_number() and FileAccess.file_exists(Net.device_path),
		"(a) device id is 128-bit hex saved to the device file", "id=%s" % Net.device_id)
	_check(Economy.save_path == "" and absf(Economy.clock_offset) < 5.0 and Net.up and not _hud._banner.visible,
		"(a) online: no local save, clock offset synced, no disconnect banner", "save=%s offset=%.3f up=%s" % [Economy.save_path, Economy.clock_offset, Net.up])
	_check_classify()

	# (b) 처치 골드: 몬스터를 실제로 죽인다(스포너 경로) → 바로 표시, 10초 안에 /v1/kills로 서버 골드
	var kills0: int = Net.requested.get("/v1/kills", 0)
	_spawner._spawn({"kind": "grunt", "side": 0, "time": 0.0})
	_spawner._spawn({"kind": "epic_boss", "side": 1, "time": 0.0})
	await _frames(2)
	for m in get_tree().get_nodes_in_group("monsters"):
		m.take_damage(1e9)
	var expect := grunt1 + GameData.kill_gold("epic_boss", 1)
	_check(Economy.gold == expect and Economy.server_gold == 0 and Net.requested.get("/v1/kills", 0) == kills0,
		"(b) kills show at once as server gold + unsent estimate", "gold=%d server=%d expect=%d" % [Economy.gold, Economy.server_gold, expect])
	var flushed := await _wait_until(func(): return Economy.server_gold == expect, Net.FLUSH_SEC + 5.0)
	_check(flushed and Economy.gold == expect and Economy.kills_pending.is_empty() and Economy.kills_sent.is_empty() and Net.requested.get("/v1/kills", 0) == kills0 + 1,
		"(b) kill gold is reported within 10 s in one /v1/kills and the server gold rises by it",
		"server=%d gold=%d requests=%d" % [Economy.server_gold, Economy.gold, Net.requested.get("/v1/kills", 0) - kills0])
	_check(Net.kill_seq_sent == 1, "(b) first kill batch carries seq 1", "seq=%d" % Net.kill_seq_sent)

	# (c) 토큰이 틀리면(401) 다시 로그인하고 같은 요청이 통과한다
	Net.token = "not-a-token"
	var r := await _request("GET", "/v1/player")
	_check(not r.is_empty() and Net.logins == 2 and Net.token != "not-a-token" and Net.up, "(c) a 401 logs in again and the request goes through",
		"resp=%s logins=%d" % [not r.is_empty(), Net.logins])
	_check(r.get("player", {}).has("kill_seq") and Economy.kill_seq == 1, "(c) server kill_seq is taken from player responses",
		"has=%s kill_seq=%d" % [r.get("player", {}).has("kill_seq"), Economy.kill_seq])
	# 4xx(여기선 모르는 몬스터 400)는 그 요청만 한 번 버리고 경고 — 다시 보내지 않고 큐는 계속 간다
	var rejected0 := _warned("server rejected")
	var k400: int = Net.requested.get("/v1/kills", 0)
	r = await _request("POST", "/v1/kills", {"seq": Net.kill_seq_sent + 1, "stage": 1, "kills": {"ghost": 1}})
	var p400: int = Net.requested.get("/v1/player", 0)
	var r2 := await _request("GET", "/v1/player")
	_check(r.is_empty() and _warned("server rejected") == rejected0 + 1 and Net.requested.get("/v1/kills", 0) == k400 + 1 and Net.up
		and not r2.is_empty() and Net.requested.get("/v1/player", 0) == p400 + 1,
		"(c) a 400 is dropped once with a warning (no retry, no banner) and the next request goes through",
		"resp=%s warnings=%d up=%s" % [r, _warned("server rejected") - rejected0, Net.up])

	# (d) test/age 10분 → 말풍선(서버 last_collect + 보정 시각), 벌목장 탭 → 서버 수집량. 응답 전 재탭은 무시
	r = await _request("POST", "/v1/test/age", {"minutes": 10})
	var now := Economy.time_now()
	var ids: Array = _badges.badge_ids(now)
	ids.sort()
	_check(ids == ["farm", "lumber", "quarry"] and Economy.pending("lumber", now) == 100, "(d) badges and pending use server last_collect and the server clock",
		"ids=%s pending=%d" % [ids, Economy.pending("lumber", now)])
	var lp := _building_px("lumber")
	var hit: Dictionary = _picker._pick(lp, PickerScript.LAYER_TAP)
	_check(not hit.is_empty() and hit.collider.get_meta("building", "") == "lumber", "(d) precondition: lumber tap point hits the lumber body", "px=%s" % lp)
	var col0: int = Net.requested.get("/v1/collect", 0)
	_badges.last_pop = {}
	_picker._tap_object(lp)
	_picker._tap_object(lp)  # 응답 전 재탭
	_check(Net.requested.get("/v1/collect", 0) == col0 + 1 and Economy.res["wood"] == 0 and _badges.last_pop.is_empty(),
		"(d) a second tap before the reply is ignored; nothing changes until the reply", "collect requests=%d wood=%d" % [Net.requested.get("/v1/collect", 0) - col0, Economy.res["wood"]])
	await _wait_until(func(): return not _badges.last_pop.is_empty(), 10.0)
	_check(Economy.res["wood"] == 100 and _badges.last_pop.get("amount", 0) == 100 and _badges.last_pop.get("kind", "") == "wood",
		"(d) server collect: +100 wood from the reply, pop shows the reply amount", "wood=%d pop=%s" % [Economy.res["wood"], _badges.last_pop])

	# (e) 판매: 서버 시세로, 창과 상인 이름표도 서버 시세
	var rate := float(Economy.merchant.rate)
	var gold0: int = Economy.server_gold
	var gain := Economy.sell_value("wood", 100, rate)
	_panel.open()
	_check(_panel._rate_label.text == "현재 시세 ×%.1f" % rate, "(e) trade window shows the server merchant rate", "label=%s rate=%.1f" % [_panel._rate_label.text, rate])
	var sell0: int = Net.requested.get("/v1/sell", 0)
	_panel.sell_buttons["wood"].pressed.emit()
	_panel.sell_buttons["wood"].pressed.emit()  # 응답 전 재탭
	await _wait_until(func(): return Economy.res["wood"] == 0, 10.0)
	_check(Economy.res["wood"] == 0 and Economy.server_gold == gold0 + gain and Economy.gold == gold0 + gain and Net.requested.get("/v1/sell", 0) == sell0 + 1,
		"(e) one sell request: wood 0, server gold + floor(100 x price x server rate)", "gold=%d expect=%d requests=%d" % [Economy.server_gold, gold0 + gain, Net.requested.get("/v1/sell", 0) - sell0])
	_panel.close()
	await get_tree().create_timer(1.2).timeout
	_check(_scenery.merchant_label.text == "상인 ×%.1f" % rate, "(e) merchant name tag shows the server rate", "label=%s" % _scenery.merchant_label.text)

	# (f) next_change가 지나면 /v1/player로 시세를 한 번 갱신한다
	var p0: int = Net.requested.get("/v1/player", 0)
	Economy.merchant.next_change = Economy.time_now() - 1.0
	var refreshed := await _wait_until(func(): return float(Economy.merchant.next_change) > Economy.time_now(), 10.0)
	_check(refreshed and Net.requested.get("/v1/player", 0) == p0 + 1, "(f) after next_change the app refreshes /v1/player once",
		"refreshed=%s requests=%d" % [refreshed, Net.requested.get("/v1/player", 0) - p0])

	# (g) 끊김: 보고 중 서버가 사라짐 → 띠, 수집·판매 탭은 알림만. 다시 연결되면 같은 seq로 재전송 + 끊긴 동안의 처치도 보낸다
	r = await _request("POST", "/v1/test/age", {"minutes": 10})  # 끊긴 동안 수집할 거리
	var live := Net.api_base
	var gold1: int = Economy.server_gold
	kills0 = Net.requested.get("/v1/kills", 0)
	var seq0: int = Net.kill_seq_sent
	for i in 3:
		Economy.add_kill("grunt", 1)
	Net.api_base = DEAD_API
	Net.flush_kills()
	var down := await _wait_until(func(): return not Net.up, 20.0)
	_check(down and _hud._banner.visible and _hud._link_label.visible, "(g) a failed request shows the '서버 연결 중…' banner", "up=%s banner=%s" % [Net.up, _hud._banner.visible])
	await _frames(1)
	_check_band_layout("(g)")
	col0 = Net.requested.get("/v1/collect", 0)
	sell0 = Net.requested.get("/v1/sell", 0)
	_badges.last_pop = {}
	_picker._tap_object(lp)
	_check(Net.requested.get("/v1/collect", 0) == col0 and _hud._toast.visible and _hud._toast.text == "연결 대기 중" and Economy.res["wood"] == 0,
		"(g) lumber tap while disconnected only shows '연결 대기 중' (no request)", "requests=%d toast=%s '%s'" % [Net.requested.get("/v1/collect", 0) - col0, _hud._toast.visible, _hud._toast.text])
	Economy.sell_all(Economy.time_now())
	_check(Net.requested.get("/v1/sell", 0) == sell0, "(g) sell while disconnected sends nothing", "requests=%d" % [Net.requested.get("/v1/sell", 0) - sell0])
	for i in 2:
		Economy.add_kill("grunt", 1)  # 전투는 계속된다
	Net.flush_kills()
	_check(Economy.gold == gold1 + 5 * grunt1 and Net.requested.get("/v1/kills", 0) == kills0 + 1, "(g) kills keep counting while disconnected and are not sent",
		"gold=%d expect=%d requests=%d" % [Economy.gold, gold1 + 5 * grunt1, Net.requested.get("/v1/kills", 0) - kills0])
	Net.api_base = live
	var back := await _wait_until(func(): return Net.up, 40.0)
	_check(back and not _hud._banner.visible, "(g) the backoff retry reconnects and hides the banner", "up=%s banner=%s" % [Net.up, _hud._banner.visible])
	await _wait_until(func(): return Economy.kills_pending.is_empty() and Economy.kills_sent.is_empty(), 10.0)
	_check(Economy.server_gold == gold1 + 5 * grunt1 and Net.requested.get("/v1/kills", 0) == kills0 + 2 and Net.kill_seq_sent == seq0 + 2,
		"(g) the retried batch keeps its seq and the disconnected kills follow on reconnect",
		"server=%d expect=%d requests=%d seq=%d" % [Economy.server_gold, gold1 + 5 * grunt1, Net.requested.get("/v1/kills", 0) - kills0, Net.kill_seq_sent])
	_check(Economy.kill_seq == Net.kill_seq_sent, "(g) server kill_seq matches the last batch", "server=%d sent=%d" % [Economy.kill_seq, Net.kill_seq_sent])
	var g := Economy.server_gold
	r = await _request("POST", "/v1/kills", {"seq": Economy.kill_seq, "stage": 1, "kills": {"grunt": 5}})
	_check(int(r.get("gold_gained", -1)) == 0 and Economy.server_gold == g, "(g) a replayed seq adds no gold", "resp=%s" % [r.get("gold_gained")])
	_check(Economy.res["wood"] == 0, "(g) the disconnected tap did not collect later", "wood=%d" % Economy.res["wood"])
	_badges.last_pop = {}
	_picker._tap_object(lp)
	await _wait_until(func(): return not _badges.last_pop.is_empty(), 10.0)
	_check(Economy.res["wood"] == 100, "(g) after reconnecting the same tap collects", "wood=%d" % Economy.res["wood"])

	# (h) 스테이지 클리어: 쌓인 처치를 곧바로 보내고 /v1/stage/clear로 저장
	Net._flush_cd = Net.FLUSH_SEC  # 10초 보고가 끼어들지 않게
	var gold2: int = Economy.server_gold
	for i in 4:
		Economy.add_kill("grunt", 1)
	GameState.start_stage()
	GameState.stop_after_stage()  # 결과 뒤 대기 모드로(스포너는 멈춰 있다)
	GameState.on_all_monsters_dead()
	var saved := await _wait_until(func(): return Economy.server_stage == 2 and Economy.kills_pending.is_empty() and Economy.kills_sent.is_empty(), 10.0)
	var t_clear := Time.get_ticks_msec()  # 서버가 클리어 1을 반영한 뒤(last_stage_clear 이후)
	_check(saved and GameState.stage == 2 and Economy.server_gold == gold2 + 4 * grunt1, "(h) stage clear sends the kills at once and saves stage 2",
		"server_stage=%d stage=%d gold=%d expect=%d" % [Economy.server_stage, GameState.stage, Economy.server_gold, gold2 + 4 * grunt1])
	# 이미 반영된 클리어를 다시 보내면(응답 유실 뒤 재전송) cleared:false지만 서버 stage가 이미 2라 경고하지 않는다
	var refused0 := _warned("refused stage")
	Net._on_stage_cleared(1)
	var resent := await _wait_until(func(): return Net._clears_out == 0, 10.0)
	_check(resent and _warned("refused stage") == refused0 and Economy.server_stage == 2 and GameState.stage == 2,
		"(h) a resent clear the server already applied (cleared:false, server stage 2) gives no warning",
		"warnings=%d server_stage=%d stage=%d" % [_warned("refused stage") - refused0, Economy.server_stage, GameState.stage])

	# (i) 끊긴 동안 클리어 둘이 쌓인다 → 다시 연결되면 연달아 가고, 두 번째는 서버 최소 간격(waves × wave_size / kill_rate_cap)에 걸려
	#     cleared:false. 로컬 스테이지는 그 사이 바꾸지 않고 다음 경계(스테이지 시작의 refill)에서 서버 stage로 맞춘다.
	await _wait_until(func(): return GameState.mode == GameState.Mode.IDLE, 10.0)
	var clears0: int = Net.requested.get("/v1/stage/clear", 0)
	Net.api_base = DEAD_API
	_clear_now()  # 2 → 3
	var down2 := await _wait_until(func(): return not Net.up, 20.0)
	await _wait_until(func(): return GameState.mode == GameState.Mode.IDLE, 10.0)
	_clear_now()  # 3 → 4
	await _wait_until(func(): return GameState.mode == GameState.Mode.IDLE, 10.0)
	_check(down2 and GameState.stage == 4 and Economy.server_stage == 2 and Net._clears_out == 2 and Net.requested.get("/v1/stage/clear", 0) == clears0 + 2,
		"(i) two clears queue up while disconnected (local stage 4, server 2)", "down=%s stage=%d server=%d out=%d" % [down2, GameState.stage, Economy.server_stage, Net._clears_out])
	var row := GameData.stage(2)
	var min_ms := int((row.waves * row.wave_size / GameData.config_num("kill_rate_cap") + 1.0) * 1000.0)
	await _wait_until(func(): return Time.get_ticks_msec() - t_clear > min_ms, 20.0)  # 클리어 2는 최소 간격을 넘겨 닿게
	Net.api_base = live
	var answered := await _wait_until(func(): return Net.up and Net._clears_out == 0, 40.0)
	_check(answered and Economy.server_stage == 3 and _warned("refused stage") == refused0 + 1 and GameState.stage == 4 and GameState.mode == GameState.Mode.IDLE,
		"(i) on reconnect clear 2 is saved and clear 3 is refused as too soon (one warning); the local stage waits for the next boundary",
		"answered=%s server=%d warnings=%d stage=%d" % [answered, Economy.server_stage, _warned("refused stage") - refused0, GameState.stage])
	var gold3: int = Economy.server_gold
	var boss3 := GameData.kill_gold("epic_boss", 3)
	Economy.add_kill("epic_boss", 4)  # 로컬 스테이지 4에서 잡았다
	_check(boss3 != GameData.kill_gold("epic_boss", 4) and Economy.gold == gold3 + boss3, "(i) a kill above the server stage is estimated at the server stage",
		"gold=%d expect=%d" % [Economy.gold, gold3 + boss3])
	Net.flush_kills()
	await _wait_until(func(): return Economy.kills_pending.is_empty() and Economy.kills_sent.is_empty(), 10.0)
	_check(Economy.server_gold == gold3 + boss3 and Economy.gold == Economy.server_gold, "(i) the server pays it at the server stage, matching the estimate",
		"server=%d expect=%d" % [Economy.server_gold, gold3 + boss3])
	GameState.start_stage()  # 경계: refill → 서버 stage
	_check(GameState.stage == 3 and Economy.server_stage == 3 and GameState.mode == GameState.Mode.STAGE and _hud._stage_label.text == "스테이지 3",
		"(i) at the next stage start GameState.stage and the HUD follow the server stage 3", "stage=%d label=%s" % [GameState.stage, _hud._stage_label.text])
	GameState.damage_castle(1e9)  # 클리어 없이 끝낸다(패배 → 대기, 스테이지 유지)
	await _wait_until(func(): return GameState.mode == GameState.Mode.IDLE, 10.0)
	_check(GameState.stage == 3 and Economy.server_stage == 3 and Net._clears_out == 0, "(i) after the failed stage local and server stay at 3",
		"stage=%d server=%d" % [GameState.stage, Economy.server_stage])

	# (j) 종류별 처치 수가 서버 상한을 넘으면 묶음을 나눠 보낸다(한 묶음이면 400으로 통째로 버려진다)
	var kills1: int = Net.requested.get("/v1/kills", 0)
	var seq1: int = Net.kill_seq_sent
	rejected0 = _warned("server rejected")
	Economy.kills_pending = {3: {"grunt": Economy.MAX_KILL_COUNT + 1}}
	Net.flush_kills()
	var split := await _wait_until(func(): return Economy.kills_sent.is_empty(), 15.0)
	_check(split and Net.requested.get("/v1/kills", 0) == kills1 + 2 and Net.kill_seq_sent == seq1 + 2 and Economy.kill_seq == seq1 + 2 and _warned("server rejected") == rejected0,
		"(j) 10 001 kills of one kind go out as two accepted batches (seq +2, no 400)",
		"requests=%d seq=%d server_seq=%d rejected=%d" % [Net.requested.get("/v1/kills", 0) - kills1, Net.kill_seq_sent - seq1, Economy.kill_seq - seq1, _warned("server rejected") - rejected0])

	var f := FileAccess.open(state_path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"device_id": Net.device_id, "gold": Economy.server_gold, "res": Economy.res, "stage": Economy.server_stage}))
	f.close()


func _phase2(state_path: String) -> void:
	var json := JSON.new()
	_check(json.parse(FileAccess.get_file_as_string(state_path)) == OK and json.data is Dictionary, "(p2) phase 1 state file", state_path)
	if _fails > 0:
		return
	var saved: Dictionary = json.data
	GameState.stage = 9
	Economy.gold = 777
	Net.storage_persistent = false  # 웹 비영구 저장소 흉내(네이티브는 늘 영구)
	if not await _start_world():
		return
	_check(Net.device_id == saved.device_id and Net.logins == 1, "(p2) same device id from the device file", "id=%s saved=%s" % [Net.device_id, saved.device_id])
	var res_ok := true
	for r in GameData.resources():
		res_ok = res_ok and Economy.res[r.id] == int(saved.res[r.id])
	_check(Economy.gold == int(saved.gold) and Economy.server_gold == int(saved.gold) and res_ok and GameState.stage == int(saved.stage) and GameState.stage == 3,
		"(p2) second run restores gold, resources and stage", "gold=%d res=%s stage=%d saved=%s" % [Economy.gold, Economy.res, GameState.stage, saved])
	await _frames(2)
	_check(Net.up and _hud._banner.visible and _hud._storage_label.visible and not _hud._link_label.visible and _hud._storage_label.text == Net.STORAGE_TEXT
		and _warned("not persistent") == 1, "(p2) non-persistent storage: one warning log and a one-line notice in the band, the game goes on",
		"banner=%s storage=%s link=%s warnings=%d" % [_hud._banner.visible, _hud._storage_label.visible, _hud._link_label.visible, _warned("not persistent")])
	_hud._link_label.visible = true  # 가장 큰 띠(끊김 + 저장소 두 줄)로 위치를 본다
	await _frames(2)
	_check_band_layout("(p2)")


## main을 띄워 접속을 기다린다. 월드가 생기면 스포너를 멈추고 몬스터를 치운다.
func _start_world() -> bool:
	_main = preload("res://scenes/main.tscn").instantiate()
	add_child(_main)
	var built := await _wait_until(func(): return _main.camera != null, 30.0)
	_check(built, "(a) world is built after connecting (login, gamedata, player)", "ready=%s up=%s" % [Net.ready_once, Net.up])
	if not built:
		return false
	await _frames(3)
	for c in _main.get_children():
		var s = c.get_script()
		if s == PickerScript:
			_picker = c
		elif s == SpawnerScript:
			_spawner = c
		elif s == BadgesScript:
			_badges = c
		elif s == HudScript:
			_hud = c
		elif s == MerchantPanelScript:
			_panel = c
		elif s == BuildingsScript:
			_scenery = c
	_spawner.set_process(false)
	for m in get_tree().get_nodes_in_group("monsters"):
		m.queue_free()
	return true


## 테스트가 직접 보내는 요청(Net 큐를 지난다). 플레이어 응답이면 Economy에 반영한다.
func _request(method: String, path: String, body = null) -> Dictionary:
	_resp = null
	_resp_done = false
	Net.send(method, path, body, _on_resp, _on_resp_fail)
	await _wait_until(func(): return _resp_done, 30.0)
	return _resp if _resp is Dictionary else {}


func _on_resp(d: Dictionary) -> void:
	if d.has("player"):
		Economy.apply_server(d)
	_resp = d
	_resp_done = true


func _on_resp_fail() -> void:
	_resp_done = true


func _wait_until(cond: Callable, timeout_sec: float) -> bool:
	var end := Time.get_ticks_msec() + int(timeout_sec * 1000.0)
	while not cond.call():
		if Time.get_ticks_msec() > end:
			return false
		await get_tree().process_frame
	return true


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
		await get_tree().process_frame


## 건물 부지 중심 약간 위(탭 판정체 안)의 화면 좌표.
func _building_px(id: String) -> Vector2:
	var b := Balance.building(id)
	return _main.camera.unproject_position(Vector3((b.cell.x + b.size.x / 2.0) * Balance.TILE, 1.0, (b.cell.y + b.size.y / 2.0) * Balance.TILE))


## 응답 처리 규칙 표(Net.classify): 띠는 연결 실패에만, 401은 연속 AUTH_MAX번까지 다시 로그인 후 끊김, 409는 상태 갱신 후 한 번 더,
## 5xx·408·429·형이 틀린 2xx는 SERVER_TRIES번까지, 그 밖의 4xx는 버린다.
func _check_classify() -> void:
	var ok := HTTPRequest.RESULT_SUCCESS
	var cases := [  # [result, code, data, auth, auth_retries, tries, conflicted, 기대]
		[HTTPRequest.RESULT_CANT_CONNECT, 0, null, true, 0, 0, false, "net"],
		[HTTPRequest.RESULT_TIMEOUT, 0, null, true, 0, 0, false, "net"],
		[ok, 200, {}, true, 0, 0, false, "ok"],
		[ok, 200, null, true, 0, 0, false, "retry"],
		[ok, 401, {}, true, 0, 0, false, "relogin"],
		[ok, 401, {}, true, Net.AUTH_MAX - 1, 0, false, "relogin"],
		[ok, 401, {}, true, Net.AUTH_MAX, 0, false, "auth_down"],
		[ok, 401, {}, false, 0, 0, false, "drop"],
		[ok, 409, {}, true, 0, 0, false, "refresh"],
		[ok, 409, {}, true, 0, 0, true, "drop"],
		[ok, 500, {}, true, 0, 0, false, "retry"],
		[ok, 503, {}, true, 0, Net.SERVER_TRIES - 1, false, "retry"],
		[ok, 500, {}, true, 0, Net.SERVER_TRIES, false, "drop"],
		[ok, 429, {}, true, 0, 0, false, "retry"],
		[ok, 400, {}, true, 0, 0, false, "drop"],
		[ok, 404, {}, true, 0, 0, false, "drop"],
		[ok, 413, {}, true, 0, 0, false, "drop"],
	]
	var bad := []
	for c in cases:
		var got: String = Net.classify(c[0], c[1], c[2], c[3], c[4], c[5], c[6])
		if got != c[7]:
			bad.append("%s -> %s (want %s)" % [c.slice(0, 7), got, c[7]])
	_check(bad.is_empty(), "(a) response policy: network failure -> banner + retry, 401 -> relogin x%d then down, 409 -> refresh + one retry, 5xx/408/429 -> %d retries, other 4xx dropped" % [Net.AUTH_MAX, Net.SERVER_TRIES], str(bad))
	_check(Net.backoff(1) == 2.0 and Net.backoff(3) == 8.0 and Net.backoff(10) == Net.RETRY_MAX_SEC, "(a) backoff 2, 4, 8 ... capped at 15 s", "")


## 띠가 상단 자원 칩·아래 버튼·알림 자리를 가리지 않는다(층만 다른 CanvasLayer라 화면 좌표가 같다).
func _check_band_layout(tag: String) -> void:
	var band: Rect2 = _hud._banner.get_global_rect()
	var chips: Rect2 = _hud._chip_row.get_global_rect()
	var button: Rect2 = _hud._button.get_global_rect()
	var toast: Rect2 = _hud._toast.get_global_rect()
	_check(band.size.y > 0.0 and not band.intersects(chips) and not band.intersects(button) and not band.intersects(toast),
		"%s the band covers neither the resource chips, the bottom button nor the toast spot" % tag, "band=%s chips=%s button=%s toast=%s" % [band, chips, button, toast])


## 대기 → 스테이지 → 전멸(클리어) → 결과 뒤 대기(중지 예약). 스포너는 멈춰 있다.
func _clear_now() -> void:
	GameState.start_stage()
	GameState.stop_after_stage()
	GameState.on_all_monsters_dead()


## text가 든 경고 수.
func _warned(text: String) -> int:
	return _errors.warnings.filter(func(w): return w.contains(text)).size()


func _check(cond: bool, what: String, detail: String) -> void:
	if cond:
		print("ONLINE PASS: " + what)
	else:
		_fails += 1
		print("ONLINE FAIL: %s (%s)" % [what, detail])
