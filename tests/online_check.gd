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
const RecruitPanelScript := preload("res://scripts/recruit_panel.gd")
const HeroPanelScript := preload("res://scripts/hero_panel.gd")
const TabBarScript := preload("res://scripts/tab_bar.gd")
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
var _recruit
var _hero_panel
var _tabs
var _resp = null  # _request의 응답
var _resp_done := false


func _ready() -> void:
	OS.add_logger(_errors)
	Engine.max_fps = 60
	Fever.save_path = ""  # 개정 14: 테스트는 user://local.json을 쓰지 않는다
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
	var grunt1 := GameData.kill_gold_tenths("grunt", 1)

	# (a) 접속 → 월드, 서버 상태
	_check(Net.logins == 1 and Net.gamedata_version != "" and GameData.errors == 0, "(a) one guest login, server gamedata applied",
		"logins=%d version=%s errors=%d" % [Net.logins, Net.gamedata_version, GameData.errors])
	_check(GameState.stage == 1 and Economy.server_stage == 1 and Economy.gold_tenths == 0 and Economy.server_gold_tenths == 0,
		"(a) GameState.stage and gold come from the server (new player: stage 1, gold 0)", "stage=%d server_stage=%d gold=%d" % [GameState.stage, Economy.server_stage, Economy.gold_tenths])
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
	var expect := grunt1 + GameData.kill_gold_tenths("epic_boss", 1)
	_check(Economy.gold_tenths == expect and Economy.server_gold_tenths == 0 and Net.requested.get("/v1/kills", 0) == kills0,
		"(b) kills show at once as server gold + unsent estimate", "gold=%d server=%d expect=%d" % [Economy.gold_tenths, Economy.server_gold_tenths, expect])
	var flushed := await _wait_until(func(): return Economy.server_gold_tenths == expect, Net.FLUSH_SEC + 5.0)
	_check(flushed and Economy.gold_tenths == expect and Economy.kills_pending.is_empty() and Economy.kills_sent.is_empty() and Net.requested.get("/v1/kills", 0) == kills0 + 1,
		"(b) kill gold is reported within 10 s in one /v1/kills and the server gold rises by it",
		"server=%d gold=%d requests=%d" % [Economy.server_gold_tenths, Economy.gold_tenths, Net.requested.get("/v1/kills", 0) - kills0])
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
	var rate := float(Economy.merchant.rates.wood)
	_check(Economy.merchant.rates.size() == 3 and Economy.merchant.rates.has("stone") and Economy.merchant.rates.has("food"), "(e) server merchant has rates for wood, stone and food", "rates=%s" % [Economy.merchant.rates])
	var gold0: int = Economy.server_gold_tenths
	var gain := Economy.sell_value("wood", 100, rate) * 10  # 판매 골드는 정수 → tenths는 × 10
	_panel.open()
	_check(_panel.rate_labels["wood"].text == "×%.1f" % rate and _panel.rate_labels["food"].text == "×%.1f" % float(Economy.merchant.rates.food), "(e) trade window rows show the server rate of each resource", "wood=%s food=%s" % [_panel.rate_labels["wood"].text, _panel.rate_labels["food"].text])
	var sell0: int = Net.requested.get("/v1/sell", 0)
	_panel.sell_buttons["wood"].pressed.emit()  # 수량 칸 펼침 → [최대] → [선택 판매]
	_panel.qty_max["wood"].pressed.emit()
	_panel.sell_selected_button.pressed.emit()
	_panel.sell_selected_button.pressed.emit()  # 응답 전 재탭
	await _wait_until(func(): return Economy.res["wood"] == 0, 10.0)
	_check(Economy.res["wood"] == 0 and Economy.server_gold_tenths == gold0 + gain and Economy.gold_tenths == gold0 + gain and Net.requested.get("/v1/sell", 0) == sell0 + 1,
		"(e) one sell request: wood 0, server gold + floor(100 x price x server rate)", "gold=%d expect=%d requests=%d" % [Economy.server_gold_tenths, gold0 + gain, Net.requested.get("/v1/sell", 0) - sell0])
	_panel.close()
	var wt = _main.get_children().filter(func(c): return c.get_script() == preload("res://scripts/world_tags.gd"))[0]
	_check(wt.text("merchant") == "상인" and _scenery.merchant_anchor.y > 2.0, "(e) merchant name tag is just the name (rates and countdown live in the trade window)", "label=%s" % wt.text("merchant"))

	await _sell_many_online_check()

	# (f) next_change가 지나면 /v1/player로 시세를 한 번 갱신한다
	var p0: int = Net.requested.get("/v1/player", 0)
	Economy.merchant.next_change = Economy.time_now() - 1.0
	var refreshed := await _wait_until(func(): return float(Economy.merchant.next_change) > Economy.time_now(), 10.0)
	_check(refreshed and Net.requested.get("/v1/player", 0) == p0 + 1, "(f) after next_change the app refreshes /v1/player once",
		"refreshed=%s requests=%d" % [refreshed, Net.requested.get("/v1/player", 0) - p0])

	# (g) 끊김: 보고 중 서버가 사라짐 → 띠, 수집·판매 탭은 알림만. 다시 연결되면 같은 seq로 재전송 + 끊긴 동안의 처치도 보낸다
	r = await _request("POST", "/v1/test/age", {"minutes": 10})  # 끊긴 동안 수집할 거리
	var live := Net.api_base
	var gold1: int = Economy.server_gold_tenths
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
	_check(Economy.gold_tenths == gold1 + 5 * grunt1 and Net.requested.get("/v1/kills", 0) == kills0 + 1, "(g) kills keep counting while disconnected and are not sent",
		"gold=%d expect=%d requests=%d" % [Economy.gold_tenths, gold1 + 5 * grunt1, Net.requested.get("/v1/kills", 0) - kills0])
	Net.api_base = live
	var back := await _wait_until(func(): return Net.up, 40.0)
	_check(back and not _hud._banner.visible, "(g) the backoff retry reconnects and hides the banner", "up=%s banner=%s" % [Net.up, _hud._banner.visible])
	await _wait_until(func(): return Economy.kills_pending.is_empty() and Economy.kills_sent.is_empty(), 10.0)
	_check(Economy.server_gold_tenths == gold1 + 5 * grunt1 and Net.requested.get("/v1/kills", 0) == kills0 + 2 and Net.kill_seq_sent == seq0 + 2,
		"(g) the retried batch keeps its seq and the disconnected kills follow on reconnect",
		"server=%d expect=%d requests=%d seq=%d" % [Economy.server_gold_tenths, gold1 + 5 * grunt1, Net.requested.get("/v1/kills", 0) - kills0, Net.kill_seq_sent])
	_check(Economy.kill_seq == Net.kill_seq_sent, "(g) server kill_seq matches the last batch", "server=%d sent=%d" % [Economy.kill_seq, Net.kill_seq_sent])
	var g := Economy.server_gold_tenths
	r = await _request("POST", "/v1/kills", {"seq": Economy.kill_seq, "stage": 1, "kills": {"grunt": 5}})
	_check(int(r.get("gold_gained_tenths", -1)) == 0 and Economy.server_gold_tenths == g, "(g) a replayed seq adds no gold", "resp=%s" % [r.get("gold_gained_tenths")])
	_check(Economy.res["wood"] == 0, "(g) the disconnected tap did not collect later", "wood=%d" % Economy.res["wood"])
	_badges.last_pop = {}
	_picker._tap_object(lp)
	await _wait_until(func(): return not _badges.last_pop.is_empty(), 10.0)
	_check(Economy.res["wood"] == 100, "(g) after reconnecting the same tap collects", "wood=%d" % Economy.res["wood"])

	# (h) 스테이지 클리어: 쌓인 처치를 곧바로 보내고 /v1/stage/clear로 저장
	Net._flush_cd = Net.FLUSH_SEC  # 10초 보고가 끼어들지 않게
	var gold2: int = Economy.server_gold_tenths
	for i in 4:
		Economy.add_kill("grunt", 1)
	GameState.start_stage()
	GameState.auto_continue = false  # 결과 뒤 대기 모드로(스포너는 멈춰 있다)
	GameState.on_all_monsters_dead()
	var saved := await _wait_until(func(): return Economy.server_stage == 2 and Economy.kills_pending.is_empty() and Economy.kills_sent.is_empty(), 10.0)
	var t_clear := Time.get_ticks_msec()  # 서버가 클리어 1을 반영한 뒤(last_stage_clear 이후)
	_check(saved and GameState.stage == 2 and Economy.server_gold_tenths == gold2 + 4 * grunt1, "(h) stage clear sends the kills at once and saves stage 2",
		"server_stage=%d stage=%d gold=%d expect=%d" % [Economy.server_stage, GameState.stage, Economy.server_gold_tenths, gold2 + 4 * grunt1])
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
	var gold3: int = Economy.server_gold_tenths
	var boss3 := GameData.kill_gold_tenths("epic_boss", 3)
	Economy.add_kill("epic_boss", 4)  # 로컬 스테이지 4에서 잡았다
	_check(boss3 != GameData.kill_gold_tenths("epic_boss", 4) and Economy.gold_tenths == gold3 + boss3, "(i) a kill above the server stage is estimated at the server stage",
		"gold=%d expect=%d" % [Economy.gold_tenths, gold3 + boss3])
	Net.flush_kills()
	await _wait_until(func(): return Economy.kills_pending.is_empty() and Economy.kills_sent.is_empty(), 10.0)
	_check(Economy.server_gold_tenths == gold3 + boss3 and Economy.gold_tenths == Economy.server_gold_tenths, "(i) the server pays it at the server stage, matching the estimate",
		"server=%d expect=%d" % [Economy.server_gold_tenths, gold3 + boss3])
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

	var copies_start := await _heroes_online()
	await _levelup_online()
	await _promote_online()

	await _growth_online(state_path)  # 개정 20: 골드를 쓴다 — 건물 단계 전에
	await _buildings_online(state_path)  # 자원이 바뀐다 — 끝 상태를 쓰기 전에
	await _soldiers_online(state_path)

	var f := FileAccess.open(state_path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"device_id": Net.device_id, "gold_tenths": Economy.server_gold_tenths, "res": Economy.res, "stage": Economy.server_stage,
		"heroes": Economy.heroes, "deploy": Economy.deploy, "copies_start": copies_start, "levels": Economy.hero_levels,
		"shards": Economy.hero_shards, "promotions": Economy.hero_promotions}))
	f.close()


## (w) 개정 15 서버 승급: test/shards로 한스 조각 30 → 상세 [승급] → /v1/hero/promote 한 번(응답 전 재탭 무시), 조각 −5·★1·최대 레벨 30·연출,
##     한 번 더 → 조각 −25·★2. (x) 승급은 다시 보내지 않는다: 서버가 사라진 채 → 버리고 알림, 다시 연결되면 상태만 받는다.
## (y) 서버가 거부(409 not_enough_shards)하면 알림 + 상태 새로 받기. phase 2가 재접속 승급·조각 복원과 그 능력치로 선 영웅을 본다.
func _promote_online() -> void:
	var id := "hans"
	var lv := Economy.level_of(id)
	await _request("POST", "/v1/test/shards", {"hero_id": id, "shards": 30})
	_check(Economy.shards_of(id) == 30 and Economy.promotion_of(id) == 0 and lv == 12, "(w) precondition: hans Lv 12, 30 shards from the server, promotion 0",
		"shards=%d promotion=%d level=%d" % [Economy.shards_of(id), Economy.promotion_of(id), lv])
	var p0: int = Net.requested.get("/v1/hero/promote", 0)
	_hero_panel.open()
	_hero_panel.show_detail(id)
	_check(_hero_panel._promo.line.text == "조각 30 / 5" and not _hero_panel.promote_button.disabled, "(w) [승급] shows 조각 30 / 5 and is on", _hero_panel._promo.line.text)
	_hero_panel.promote_button.pressed.emit()
	_hero_panel.promote_button.pressed.emit()  # 응답 전 재탭
	_check(_hero_panel.promote_button.disabled and Economy.promote_waiting() and Economy.promotion_of(id) == 0, "(w) while waiting for the reply [승급] is off and nothing changes yet", "")
	var done := await _wait_until(func(): return Economy.promotion_of(id) == 1 and not Economy.promote_waiting(), 15.0)
	_check(done and Net.requested.get("/v1/hero/promote", 0) == p0 + 1 and Economy.shards_of(id) == 25 and _hero_panel.promotions_shown == 1
		and _hero_panel.big_card.stars == 1 and _hero_panel.level_label.text == "Lv 12 / 30" and _hero_panel._promo.line.text == "조각 25 / 25",
		"(w) one /v1/hero/promote: shards 30 -> 25, ★1, max level 30, with the effect",
		"requests=%d shards=%d promotion=%d label=%s" % [Net.requested.get("/v1/hero/promote", 0) - p0, Economy.shards_of(id), Economy.promotion_of(id), _hero_panel.level_label.text])
	_hero_panel.promote_button.pressed.emit()
	done = await _wait_until(func(): return Economy.promotion_of(id) == 2 and not Economy.promote_waiting(), 15.0)
	_check(done and Net.requested.get("/v1/hero/promote", 0) == p0 + 2 and Economy.shards_of(id) == 0 and _hero_panel.promote_button.disabled
		and _hero_panel.promote_reason.text == "조각 부족" and _hero_panel.level_label.text == "Lv 12 / 40",
		"(w) again: 25 shards -> ★2 (Lv 12 / 40); [승급] off with 조각 부족", "shards=%d reason=%s" % [Economy.shards_of(id), _hero_panel.promote_reason.text])
	var live := Net.api_base
	var notices := []
	var on_notice := func(t): notices.append(t)
	Economy.notice.connect(on_notice)
	await _request("POST", "/v1/test/shards", {"hero_id": id, "shards": 50})
	var w0 := _warned("not resending")
	Net.api_base = DEAD_API
	var sent := Economy.promote(id)
	var dropped := await _wait_until(func(): return not Net.up and not Economy.promote_waiting(), 20.0)
	_check(sent and dropped and notices.has(Economy.PROMOTE_FAIL_TEXT) and _warned("not resending") == w0 + 1,
		"(x) a promotion that cannot reach the server is dropped with a notice, not queued again", "sent=%s dropped=%s notices=%s" % [sent, dropped, notices])
	Net.api_base = live
	var back := await _wait_until(func(): return Net.up, 40.0)
	await _wait_until(func(): return not Net._refreshing, 10.0)
	await _frames(3)
	_check(back and Net.requested.get("/v1/hero/promote", 0) == p0 + 3 and Economy.promotion_of(id) == 2 and Economy.shards_of(id) == 50,
		"(x) after reconnecting the state is refreshed and the promotion is not resent",
		"requests=%d promotion=%d shards=%d" % [Net.requested.get("/v1/hero/promote", 0) - p0, Economy.promotion_of(id), Economy.shards_of(id)])
	await _request("POST", "/v1/test/shards", {"hero_id": id, "shards": 10})
	Economy._promote_online(id)  # 화면이 막는 요청을 직접 보낸다 — 서버가 409 not_enough_shards
	await _wait_until(func(): return not Economy.promote_waiting(), 15.0)
	await _wait_until(func(): return not Net._refreshing, 10.0)
	_check(notices.has("조각 부족") and Economy.promotion_of(id) == 2 and Economy.shards_of(id) == 10 and Net.requested.get("/v1/hero/promote", 0) == p0 + 4 and Net.up,
		"(y) a refused promotion (409 not_enough_shards) shows a notice and refreshes the state", "notices=%s promotion=%d" % [notices, Economy.promotion_of(id)])
	Economy.notice.disconnect(on_notice)
	_hero_panel.close()


## (n) 서버 레벨업(개정 11): 영웅 상세 [레벨업] → /v1/hero/levelup 한 번(응답 전 재탭은 무시), 서버 골드 −비용 × 10 tenths(식량은 그대로 — 개정 12),
##     레벨 +1과 연출. [×10]은 감당 가능한 횟수를 한 요청으로.
## (o) 레벨업은 다시 보내지 않는다: 서버가 사라진 채 → 버리고 알림, 다시 연결되면 상태만 받는다(두 번째 요청 없음).
## (q) 서버가 거부(409 max_level)하면 알림 + 상태 새로 받기. phase 2가 재접속 레벨 복원을 본다.
func _levelup_online() -> void:
	await _request("POST", "/v1/test/age", {"minutes": 720})
	await _request("POST", "/v1/collect", {"building": "farm"})
	await _request("POST", "/v1/collect", {"building": "lumber"})
	await _request("POST", "/v1/sell", {"res": "wood"})
	await _wait_until(func(): return Economy.kills_pending.is_empty() and Economy.kills_sent.is_empty(), 10.0)
	var id := "hans"
	var gold0: int = Economy.server_gold_tenths
	var food0: int = Economy.res["food"]
	var c1 := GameData.levelup_cost("R", 1)
	_check(Economy.level_of(id) == 1 and Economy.gold >= 1000 and food0 >= 1000 and Economy.gold_tenths == gold0, "(n) precondition: hans Lv 1, gold and food from the server",
		"level=%d gold=%d food=%d" % [Economy.level_of(id), Economy.gold, food0])
	var l0: int = Net.requested.get("/v1/hero/levelup", 0)
	_hero_panel.open()
	_hero_panel.show_detail(id)
	_hero_panel.level_button.pressed.emit()
	_hero_panel.level_button.pressed.emit()  # 응답 전 재탭
	_check(_hero_panel.level_button.disabled and Economy.level_of(id) == 1 and Economy.levelup_waiting(), "(n) while waiting for the reply [레벨업] is off and nothing changes yet", "")
	var done := await _wait_until(func(): return Economy.level_of(id) == 2 and not Economy.levelup_waiting(), 15.0)
	_check(done and Net.requested.get("/v1/hero/levelup", 0) == l0 + 1 and Economy.server_gold_tenths == gold0 - int(c1.gold) * 10 and Economy.res["food"] == food0
		and _hero_panel.celebrations == 1 and _hero_panel.level_label.text == "Lv 2 / 20",
		"(n) one /v1/hero/levelup: server gold -30 (300 tenths), food unchanged, Lv 2 with the success effect",
		"requests=%d gold=%d->%d food=%d->%d label=%s" % [Net.requested.get("/v1/hero/levelup", 0) - l0, gold0, Economy.server_gold_tenths, food0, Economy.res["food"], _hero_panel.level_label.text])
	var n := Economy.levelup_affordable(id, 10)
	var cn := GameData.levelup_cost("R", 2, n)
	var gold1: int = Economy.server_gold_tenths
	var food1: int = Economy.res["food"]
	_hero_panel.ten_button.pressed.emit()
	done = await _wait_until(func(): return Economy.level_of(id) == 2 + n and not Economy.levelup_waiting(), 15.0)
	_check(done and n == 10 and Net.requested.get("/v1/hero/levelup", 0) == l0 + 2 and Economy.server_gold_tenths == gold1 - int(cn.gold) * 10 and Economy.res["food"] == food1,
		"(n) [×10] sends one request for the affordable count (10) and the server takes the summed cost",
		"n=%d level=%d gold=%d->%d" % [n, Economy.level_of(id), gold1, Economy.server_gold_tenths])

	var live := Net.api_base
	var notices := []
	var on_notice := func(t): notices.append(t)
	Economy.notice.connect(on_notice)
	var lv := Economy.level_of(id)
	var gold2: int = Economy.server_gold_tenths
	var w0 := _warned("not resending")
	Net.api_base = DEAD_API
	var sent := Economy.level_up(id, 1)
	var dropped := await _wait_until(func(): return not Net.up and not Economy.levelup_waiting(), 20.0)
	_check(sent and dropped and notices.has(Economy.LEVELUP_FAIL_TEXT) and _warned("not resending") == w0 + 1,
		"(o) a level-up that cannot reach the server is dropped with a notice, not queued again", "sent=%s dropped=%s notices=%s" % [sent, dropped, notices])
	Net.api_base = live
	var back := await _wait_until(func(): return Net.up, 40.0)
	await _wait_until(func(): return not Net._refreshing, 10.0)
	await _frames(3)
	_check(back and Net.requested.get("/v1/hero/levelup", 0) == l0 + 3 and Economy.level_of(id) == lv and Economy.server_gold_tenths == gold2,
		"(o) after reconnecting the state is refreshed and the level-up is not resent",
		"requests=%d level=%d gold=%d" % [Net.requested.get("/v1/hero/levelup", 0) - l0, Economy.level_of(id), Economy.server_gold_tenths])
	Economy._levelup_online(id, 50)  # 화면이 막는 요청을 직접 보낸다 — 서버가 409 max_level
	await _wait_until(func(): return not Economy.levelup_waiting(), 15.0)
	await _wait_until(func(): return not Net._refreshing, 10.0)
	_check(notices.has("최대 레벨입니다") and Economy.level_of(id) == lv and Net.requested.get("/v1/hero/levelup", 0) == l0 + 4 and Net.up,
		"(q) a refused level-up (409 max_level) shows a notice and refreshes the state", "notices=%s level=%d" % [notices, Economy.level_of(id)])
	Economy.notice.disconnect(on_notice)
	_hero_panel.close()


## (k) 서버 모집 1회: 판매로 골드를 모아 주점 창에서 [1회 모집] → 요청 한 번, 서버 골드 3000 tenths↓, 영웅 +1, 결과 카드.
## (l) 모집은 다시 보내지 않는다: 서버가 사라진 채 모집 → 버리고 알림, 다시 연결되면 /v1/player로 상태를 받는다(두 번째 모집 요청 없음).
## (m) 배치: 영웅 창 [적용] → /v1/deploy → 서버 배치, 방치 모드라 곧바로 영웅이 바뀐다. phase 2가 재접속 복원을 본다.
## 모집 전 copies 합(새 플레이어 = 시작 영웅 수)을 돌려준다 — phase 2는 그 합 + 1(뽑은 한 장, 새 영웅이든 중복이든)을 본다.
func _heroes_online() -> int:
	await _request("POST", "/v1/test/age", {"minutes": 720})
	await _request("POST", "/v1/collect", {"building": "lumber"})
	await _request("POST", "/v1/sell", {"res": "all"})
	await _wait_until(func(): return Economy.kills_pending.is_empty() and Economy.kills_sent.is_empty(), 10.0)
	var gold0: int = Economy.server_gold_tenths
	_check(Economy.gold >= 300 and Economy.gold_tenths == gold0, "(k) precondition: at least 300 server gold from selling", "gold=%d" % Economy.gold)
	var copies0 := _copies()
	_check(copies0 == GameData.config_list("starter_heroes").size(), "(k) precondition: a new player owns the starters once each", "copies=%d heroes=%s" % [copies0, Economy.heroes])
	var g0: int = Net.requested.get("/v1/gacha", 0)
	_recruit.open()
	_recruit.one_button.pressed.emit()
	_recruit.one_button.pressed.emit()  # 응답 전 재탭
	_check(_recruit.one_button.disabled and Economy.gold_tenths == gold0, "(k) while waiting for the reply the buttons are off and nothing changes yet", "")
	var shown := await _wait_until(func(): return _recruit.is_showing_results(), 15.0)
	var got: String = _recruit.cards[0].hero_id if shown and _recruit.cards.size() == 1 else ""
	_check(shown and Net.requested.get("/v1/gacha", 0) == g0 + 1 and Economy.server_gold_tenths == gold0 - 3000 and Economy.gold_tenths == gold0 - 3000
		and _copies() == copies0 + 1 and got != "" and int(Economy.heroes.get(got, 0)) >= 1,
		"(k) one /v1/gacha: server gold -300 (3000 tenths), one more hero, one result card",
		"requests=%d gold=%d->%d copies=%d->%d card=%s" % [Net.requested.get("/v1/gacha", 0) - g0, gold0, Economy.server_gold_tenths, copies0, _copies(), got])
	_recruit.close()

	var live := Net.api_base
	var notices := []
	var on_notice := func(t): notices.append(t)
	Economy.notice.connect(on_notice)
	var gold1: int = Economy.server_gold_tenths
	var copies1 := _copies()
	Net.api_base = DEAD_API
	var sent := Economy.gacha(1)
	var dropped := await _wait_until(func(): return not Net.up and not Economy._waiting.has("gacha"), 20.0)
	_check(sent and dropped and notices.has(Economy.GACHA_FAIL_TEXT) and _warned("not resending") == 1, "(l) a gacha that cannot reach the server is dropped with a notice, not queued again",
		"sent=%s dropped=%s notices=%s" % [sent, dropped, notices])
	Net.api_base = live
	var back := await _wait_until(func(): return Net.up, 40.0)
	await _frames(3)
	_check(back and Net.requested.get("/v1/gacha", 0) == g0 + 2 and Economy.server_gold_tenths == gold1 and _copies() == copies1,
		"(l) after reconnecting the state is refreshed and the gacha is not resent", "requests=%d gold=%d copies=%d" % [Net.requested.get("/v1/gacha", 0) - g0, Economy.server_gold_tenths, _copies()])
	Economy.notice.disconnect(on_notice)

	var starters := ["hans", "ella", "dorik", "nina"]
	var want: Array = ([got] + starters.filter(func(id): return id != got)).slice(0, 4)
	var d0: int = Net.requested.get("/v1/deploy", 0)
	_hero_panel.open()
	_hero_panel.work = want.duplicate()
	_hero_panel.apply()
	var saved := await _wait_until(func(): return Economy._pending_deploy == null, 10.0)
	var r := await _request("GET", "/v1/player")
	await _frames(3)
	var ids := get_tree().get_nodes_in_group("heroes").filter(func(h): return h.is_alive())
	ids.sort_custom(func(a, b): return a.index < b.index)
	ids = ids.map(func(h): return h.def.id)
	_check(saved and Net.requested.get("/v1/deploy", 0) == d0 + 1 and r.get("player", {}).get("deploy") == want and Economy.deploy == want and GameState.deploy() == want
		and GameState.mode == GameState.Mode.IDLE and ids == want,
		"(m) [적용] sends one /v1/deploy; the server keeps it and the idle heroes switch at once", "want=%s server=%s ids=%s" % [want, r.get("player", {}).get("deploy"), ids])
	_hero_panel.close()
	return copies0


func _copies() -> int:
	var n := 0
	for id in Economy.heroes:
		n += int(Economy.heroes[id])
	return n


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
	_check(Economy.gold_tenths == int(saved.gold_tenths) and Economy.server_gold_tenths == int(saved.gold_tenths) and res_ok and GameState.stage == int(saved.stage) and GameState.stage == 3,
		"(p2) second run restores gold, resources and stage", "gold=%d res=%s stage=%d saved=%s" % [Economy.gold_tenths, Economy.res, GameState.stage, saved])
	# 서버 모집은 암호학적 난수라 새 영웅인지 중복인지 정해져 있지 않다 — 보유 수(id 개수)가 아니라 phase 1 끝 보유와 같은지,
	# copies 합이 모집 전 합 + 1(한 장)인지 본다.
	var heroes_ok: bool = saved.get("heroes") is Dictionary and saved.heroes.size() == Economy.heroes.size()
	var saved_sum := 0
	if heroes_ok:
		for id in saved.heroes:
			heroes_ok = heroes_ok and int(Economy.heroes.get(id, 0)) == int(saved.heroes[id])
			saved_sum += int(saved.heroes[id])
	var start := int(saved.get("copies_start", -1))
	_check(heroes_ok and start == GameData.config_list("starter_heroes").size() and saved_sum == start + 1 and _copies() == start + 1,
		"(p2) reconnecting restores the owned heroes exactly: copies sum = starters + the one server pull",
		"heroes=%s saved=%s start=%d sum=%d" % [Economy.heroes, saved.get("heroes"), start, _copies()])
	var spawned := get_tree().get_nodes_in_group("heroes").filter(func(h): return h.is_alive())
	spawned.sort_custom(func(a, b): return a.index < b.index)
	_check(Economy.deploy == saved.deploy and GameState.deploy() == saved.deploy and spawned.map(func(h): return h.def.id) == saved.deploy,
		"(p2) reconnecting restores the deploy, and the world spawns that deploy",
		"deploy=%s saved=%s" % [Economy.deploy, saved.get("deploy")])
	var levels_ok: bool = saved.get("levels") is Dictionary and Economy.level_of("hans") == 12
	if levels_ok:
		for id in saved.levels:
			levels_ok = levels_ok and Economy.level_of(id) == int(saved.levels[id])
	var stats_ok := true
	for h in spawned:
		stats_ok = stats_ok and is_equal_approx(h.hp_max, GameData.hero_stats(h.def, Economy.level_of(h.def.id), Economy.promotion_of(h.def.id)).hp)
	_check(levels_ok and stats_ok, "(p2) reconnecting restores hero levels (hans Lv 12) and the spawned heroes use them",
		"levels=%s saved=%s" % [Economy.hero_levels, saved.get("levels")])
	var promo_ok: bool = saved.get("promotions") is Dictionary and saved.get("shards") is Dictionary and Economy.promotion_of("hans") == 2 and Economy.shards_of("hans") == 10
	if promo_ok:
		for id in saved.promotions:
			promo_ok = promo_ok and Economy.promotion_of(id) == int(saved.promotions[id]) and Economy.shards_of(id) == int(saved.shards.get(id, 0))
	var hans_node = spawned.filter(func(h): return h.def.id == "hans")
	_check(promo_ok and hans_node.size() == 1 and is_equal_approx(hans_node[0].hp_max, GameData.hero_stats(GameData.hero("hans"), 12, 0).hp * 2.25),
		"(p2) reconnecting restores promotions and shards (hans ★2, 10 shards); the spawned hans has HP x1.5^2",
		"promotions=%s shards=%s saved=%s" % [Economy.hero_promotions, Economy.hero_shards, saved.get("promotions")])
	await _frames(2)
	_check(Net.up and _hud._banner.visible and _hud._storage_label.visible and not _hud._link_label.visible and _hud._storage_label.text == Net.STORAGE_TEXT
		and _warned("not persistent") == 1, "(p2) non-persistent storage: one warning log and a one-line notice in the band, the game goes on",
		"banner=%s storage=%s link=%s warnings=%d" % [_hud._banner.visible, _hud._storage_label.visible, _hud._link_label.visible, _warned("not persistent")])
	_hud._link_label.visible = true  # 가장 큰 띠(끊김 + 저장소 두 줄)로 위치를 본다
	await _frames(2)
	_check_band_layout("(p2)")
	_buildings_restored(state_path)
	_soldiers_restored(state_path)
	_growth_restored(state_path)


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
		elif s == RecruitPanelScript:
			_recruit = c
		elif s == HeroPanelScript:
			_hero_panel = c
		elif s == TabBarScript:
			_tabs = c
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


## 띠가 상단 자원 칩·큰 버튼·하단 탭 바·알림 자리를 가리지 않는다(층만 다른 CanvasLayer라 화면 좌표가 같다).
func _check_band_layout(tag: String) -> void:
	var band: Rect2 = _hud._banner.get_global_rect()
	var chips: Rect2 = _hud._chip_row.get_global_rect()
	var button: Rect2 = _hud._button.get_global_rect()
	var toast: Rect2 = _hud._toast.get_global_rect()
	var bar: Rect2 = _tabs._bar.get_global_rect()
	_check(band.size.y > 0.0 and not band.intersects(chips) and not band.intersects(button) and not band.intersects(toast) and not band.intersects(bar),
		"%s the band covers neither the resource chips, the big button, the tab bar nor the toast spot" % tag,
		"band=%s chips=%s button=%s bar=%s toast=%s" % [band, chips, button, bar, toast])


## 대기 → 스테이지 → 전멸(클리어) → 결과 뒤 대기(연속 진행 끔). 스포너는 멈춰 있다.
func _clear_now() -> void:
	GameState.start_stage()
	GameState.auto_continue = false
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


## (r) 개정 12 서버 건물: 성채 업그레이드 → 요청 한 번(응답 전 재탭 무시), 서버 자원 −비용, 일꾼·build_started → test/build_now →
##     서버의 게으른 완료 → 성채 Lv 2(building_done)·성 HP 1200. (s) 재전송 금지: 서버가 사라진 채 → 버리고 알림, 다시 연결돼도 두 번째 요청
##     없음. (t) 서버 거부(409 prereq) → 알림. (u) 벌목장: 시작할 때 서버가 자동 수집. 마지막으로 성문 건설을 걸어 둔 채 끝 상태를
##     <state>.buildings에 쓴다 — phase 2가 재접속 복원(레벨·일꾼·인구·성/성문 HP)을 본다.
func _buildings_online(state_path: String) -> void:
	await _request("POST", "/v1/test/age", {"minutes": 720})
	for b in ["lumber", "quarry", "farm"]:
		await _request("POST", "/v1/collect", {"building": b})
	var started := []
	var done := []
	var notices := []
	var on_start := func(id, f): started.append([id, f])
	var on_done := func(id, l): done.append([id, l])
	var on_notice := func(t): notices.append(t)
	Economy.build_started.connect(on_start)
	Economy.building_done.connect(on_done)
	Economy.notice.connect(on_notice)
	var res0: Dictionary = Economy.res.duplicate()
	var cost := Economy.upgrade_cost("keep")
	var p0 := await _request("GET", "/v1/player")
	_check(Economy.building_level("keep") == 1 and Economy.build.is_empty() and Economy.upgrade_block("keep", Economy.time_now()) == "" and Economy.population() == 6
		and p0.get("player", {}).get("population") == 6 and p0.get("player", {}).get("buildings", {}).size() == 11,
		"(r) precondition: all 11 buildings from the server at Lv 1, builder idle, population 6", "keep=%d build=%s" % [Economy.building_level("keep"), Economy.build])
	var u0: int = Net.requested.get("/v1/building/upgrade", 0)
	var sent := Economy.upgrade("keep", Economy.time_now())
	var again := Economy.upgrade("keep", Economy.time_now())  # 응답 전 재탭
	_check(sent and not again and Economy.upgrade_block("keep", Economy.time_now()) == "waiting" and Net.requested.get("/v1/building/upgrade", 0) == u0 + 1 and Economy.res == res0,
		"(r) one upgrade request; a second tap before the reply is ignored and nothing changes yet", "requests=%d" % [Net.requested.get("/v1/building/upgrade", 0) - u0])
	await _wait_until(func(): return not Economy.build.is_empty() and not Economy._waiting.has("build"), 15.0)
	var fin := float(Economy.build.get("finish", 0.0))
	var paid := true
	for r in cost:
		paid = paid and Economy.res[r] == int(res0[r]) - int(cost[r])
	_check(Economy.build.get("id") == "keep" and paid and started == [["keep", fin]] and absf(fin - (Economy.time_now() + 60.0)) < 10.0 and Economy.upgrade_block("barracks", Economy.time_now()) == "keep_cap",
		"(r) the server takes 300/300/200 and starts the builder (finish = server time + 60 s), build_started", "build=%s res=%s started=%s" % [Economy.build, Economy.res, started])
	Economy.finish_build_now()  # POST /v1/test/build_now — 응답(플레이어 읽기)이 게으른 완료를 한다
	await _wait_until(func(): return Economy.building_level("keep") == 2, 15.0)
	await _frames(2)
	_check(Economy.building_level("keep") == 2 and Economy.build.is_empty() and done == [["keep", 2]] and GameState.castle_hp_max == 1200.0 and GameState.hero_count() == 4,
		"(r) build_now -> the server completes it: keep Lv 2, building_done, castle HP 1200", "keep=%d done=%s castle=%.0f" % [Economy.building_level("keep"), done, GameState.castle_hp_max])
	# (s) 재전송 금지
	var live := Net.api_base
	var w0 := _warned("not resending")
	Net.api_base = DEAD_API
	var sent2 := Economy.upgrade("barracks", Economy.time_now())
	var dropped := await _wait_until(func(): return not Net.up and not Economy._waiting.has("build"), 20.0)
	_check(sent2 and dropped and notices.has(Economy.BUILD_FAIL_TEXT) and _warned("not resending") == w0 + 1,
		"(s) an upgrade that cannot reach the server is dropped with a notice, not queued again", "sent=%s dropped=%s notices=%s" % [sent2, dropped, notices])
	Net.api_base = live
	var back := await _wait_until(func(): return Net.up, 40.0)
	await _wait_until(func(): return not Net._refreshing, 10.0)
	await _frames(3)
	_check(back and Net.requested.get("/v1/building/upgrade", 0) == u0 + 2 and Economy.build.is_empty() and Economy.building_level("barracks") == 1,
		"(s) after reconnecting the state is refreshed and the upgrade is not resent", "requests=%d build=%s" % [Net.requested.get("/v1/building/upgrade", 0) - u0, Economy.build])
	# (t) 서버 거부: 성채 3은 성문·막사 ≥ 2가 선행 — 화면이 막는 요청을 직접 보낸다
	Economy._upgrade_online("keep")
	await _wait_until(func(): return not Economy._waiting.has("build"), 15.0)
	await _wait_until(func(): return not Net._refreshing, 10.0)
	_check(notices.has(Economy.BLOCK_TEXT.prereq) and Economy.build.is_empty() and Net.up, "(t) a refused upgrade (409 prereq) shows the reason and changes nothing", "notices=%s" % [notices])
	# (u) 벌목장: 서버가 시작할 때 자동 수집(10분 = 100)하고 그 목재까지 비용에 쓴다. 먼저 비워 두고(남은 초 0) 10분 앞당긴다
	await _request("POST", "/v1/collect", {"building": "lumber"})
	await _request("POST", "/v1/test/age", {"minutes": 10})
	var wood0: int = Economy.res["wood"]
	var lc := Economy.upgrade_cost("lumber")
	Economy.upgrade("lumber", Economy.time_now())
	await _wait_until(func(): return Economy.build.get("id") == "lumber", 15.0)
	_check(Economy.res["wood"] == wood0 + 100 - int(lc.wood), "(u) a resource building upgrade collects first on the server (+100 wood) and then pays", "wood=%d -> %d" % [wood0, Economy.res["wood"]])
	Economy.finish_build_now()
	await _wait_until(func(): return Economy.building_level("lumber") == 2, 15.0)
	# 성문 건설을 걸어 둔 채로 끝낸다(45초)
	Economy.upgrade("gate", Economy.time_now())
	await _wait_until(func(): return Economy.build.get("id") == "gate", 15.0)
	_check(Economy.building_level("lumber") == 2 and Economy.build.get("id") == "gate" and done.size() == 2, "(u) lumber Lv 2 done; the gate is left building for phase 2",
		"lumber=%d build=%s done=%s" % [Economy.building_level("lumber"), Economy.build, done])
	Economy.build_started.disconnect(on_start)
	Economy.building_done.disconnect(on_done)
	Economy.notice.disconnect(on_notice)
	var f := FileAccess.open(state_path + ".buildings", FileAccess.WRITE)
	f.store_string(JSON.stringify({"levels": Economy.levels, "build": Economy.build}))
	f.close()


## (p2) 재접속하면 건물 레벨·진행 중 일꾼(끝나는 시각이 지났으면 서버가 완료한 레벨)·인구·성/성문 HP가 그대로다.
func _buildings_restored(state_path: String) -> void:
	var json := JSON.new()
	var ok := json.parse(FileAccess.get_file_as_string(state_path + ".buildings")) == OK and json.data is Dictionary
	_check(ok, "(p2) phase 1 buildings state file", state_path)
	if not ok:
		return
	var saved: Dictionary = json.data
	var fin := float(saved.build.finish)
	var gate_done: bool = Economy.build.is_empty()  # 끝나는 시각이 지나 서버가 완료했다(시각 검사는 아래)
	var levels_ok := true
	for id in saved.levels:
		var want := int(saved.levels[id]) + (1 if gate_done and id == "gate" else 0)
		levels_ok = levels_ok and Economy.building_level(id) == want
	var build_ok: bool = Economy.time_now() >= fin - 1.0 if gate_done else (Economy.build.get("id") == "gate" and absf(float(Economy.build.finish) - fin) < 0.01)
	_check(levels_ok and build_ok and Economy.building_level("keep") == 2 and Economy.building_level("lumber") == 2 and Economy.population() == 6
		and GameState.castle_hp_max == 1200.0 and GameState.gate_hp_max == 400.0 * Economy.building_level("gate"),
		"(p2) reconnecting restores every building level and the builder (gate %s), population, castle/gate HP" % ["done by the server" if gate_done else "still building"],
		"levels=%s build=%s saved=%s" % [Economy.levels, Economy.build, saved])


## (v) 개정 16 서버 훈련: 막사 6·궁병 훈련소 5 훈련 → 서버가 비용을 빼고 대기열(응답 training)을 준다 — 요청 한 번(응답 전 재탭 무시).
##     시간이 흘러도(test/age) 수령 전엔 보유 그대로, 수령 전 수령은 409. 시간 당기기(finish_training_now = test/age) → 완료 → 수령(보유 +n,
##     알림 "보병 +6"), 다시 수령은 409 empty(알림 없음). 취소: 기병 훈련 → [취소] → 비용 50% 환불. 재전송 금지: 서버가 사라진 채 시작 →
##     버리고 알림, 다시 연결돼도 두 번째 요청 없음. 합성(개정 13): 요청 한 번 → 1티어 −5·2티어 +1, 재전송 금지, 409 max_tier 알림.
##     배치: 서버 저장·월드에 선다, 인구 초과 400. 끝에 기병 1마리 훈련을 걸어 둔 채 <state>.soldiers에 쓴다 — phase 2가 재접속 복원을 본다.
func _soldiers_online(state_path: String) -> void:
	var notices := []
	var on_notice := func(t): notices.append(t)
	Economy.notice.connect(on_notice)
	await _request("POST", "/v1/test/age", {"minutes": 720})  # 훈련 비용
	for b in ["lumber", "quarry", "farm"]:
		await _request("POST", "/v1/collect", {"building": b})
	var c0 := Economy.soldier_counts()
	var res0: Dictionary = Economy.res.duplicate()
	var t0: int = Net.requested.get("/v1/soldiers/train", 0)
	var sent := Economy.start_training("barracks", 6)
	var again := Economy.start_training("barracks", 6)  # 응답 전 재탭
	_check(sent and not again and Economy.train_block("barracks", 6) == "waiting" and Net.requested.get("/v1/soldiers/train", 0) == t0 + 1 and Economy.res == res0,
		"(v) one training request; a second tap before the reply is ignored and nothing changes yet", "requests=%d" % [Net.requested.get("/v1/soldiers/train", 0) - t0])
	await _wait_until(func(): return Economy.training("barracks").count == 6 and not Economy.training_waiting("barracks", "train"), 15.0)
	Economy.start_training("archery", 5)
	await _wait_until(func(): return Economy.training("archery").count == 5, 15.0)
	var q := Economy.training("barracks")
	_check(q.count == 6 and not q.ready and absf(q.finish - (Economy.time_now() + 6 * 10800.0)) < 30.0 and Economy.res.food == res0.food - 180 - 125
		and Economy.res.wood == res0.wood - 120 - 150 and Economy.soldier_counts() == c0,
		"(v) the server takes the cost at once (6 infantry 180 food / 120 wood, 5 archers 125 / 150) and queues them (finish = server time + n x 3 h)",
		"q=%s res=%s -> %s" % [q, res0, Economy.res])
	await _request("POST", "/v1/test/age", {"minutes": 60})
	var r0 := _warned("server rejected")
	await _request("POST", "/v1/soldiers/collect", {"building": "barracks"})
	_check(Economy.soldier_counts() == c0 and not Economy.training("barracks").ready and not Economy.collect_training("barracks") and _warned("server rejected") == r0 + 1,
		"(v) time passing adds no soldiers; collecting before the finish is refused (409 not_ready)", "soldiers=%s" % [Economy.soldier_counts()])
	Economy.finish_training_now("barracks")  # POST /v1/test/age(남은 분) — 궁병(더 짧다)도 끝난다
	await _wait_until(func(): return Economy.training("barracks").ready and Economy.training("archery").ready, 15.0)
	var c0_inf := int(c0.get("infantry:1", 0))
	var collected := Economy.collect_training("barracks") and Economy.collect_training("archery")
	await _wait_until(func(): return Economy.train_queues.is_empty() and not Economy.training_waiting("archery", "collect"), 15.0)
	_check(collected and int(Economy.soldiers.get("infantry:1", 0)) == c0_inf + 6 and int(Economy.soldiers.get("archer:1", 0)) == int(c0.get("archer:1", 0)) + 5
		and notices.has("보병 +6") and notices.has("궁병 +5"), "(v) pulled forward and collected: 보병 +6, 궁병 +5 from the server, notices '보병 +6'",
		"soldiers=%s notices=%s" % [Economy.soldiers, notices])
	var n0 := notices.size()
	Economy._train_online("collect", "barracks", {"building": "barracks"}, false)  # 응답을 잃은 수령의 재전송 흉내 — 409 empty
	await _wait_until(func(): return not Economy.training_waiting("barracks", "collect"), 15.0)
	await _wait_until(func(): return not Net._refreshing, 10.0)
	_check(int(Economy.soldiers.get("infantry:1", 0)) == c0_inf + 6 and notices.size() == n0, "(v) a repeated collect (409 empty) adds nothing and shows no notice", "notices=%s" % [notices.slice(n0)])
	# 취소: 기병 2마리(식량 80·석재 40) → 절반 환불
	var res1: Dictionary = Economy.res.duplicate()
	Economy.start_training("stable", 2)
	await _wait_until(func(): return Economy.training("stable").count == 2, 15.0)
	var c1: int = Net.requested.get("/v1/soldiers/cancel", 0)
	var canceled := Economy.cancel_training("stable")
	await _wait_until(func(): return Economy.training("stable").count == 0 and not Economy.training_waiting("stable", "cancel"), 15.0)
	_check(canceled and Net.requested.get("/v1/soldiers/cancel", 0) == c1 + 1 and Economy.res.food == res1.food - 40 and Economy.res.stone == res1.stone - 20
		and notices.has(Economy.CANCEL_TEXT), "(v) [취소] on the server refunds half (2 cavalry: 80 / 40 -> back 40 / 20) and empties the queue", "res=%s -> %s" % [res1, Economy.res])
	# 재전송 금지(시작)
	var live := Net.api_base
	var w0 := _warned("not resending")
	var t1: int = Net.requested.get("/v1/soldiers/train", 0)
	Net.api_base = DEAD_API
	var sent2 := Economy.start_training("archery", 1)
	var dropped := await _wait_until(func(): return not Net.up and not Economy.training_waiting("archery", "train"), 20.0)
	_check(sent2 and dropped and notices.has(Economy.TRAIN_FAIL_TEXT) and _warned("not resending") == w0 + 1,
		"(v) a training start that cannot reach the server is dropped with a notice, not queued again", "sent=%s dropped=%s" % [sent2, dropped])
	Net.api_base = live
	var back := await _wait_until(func(): return Net.up, 40.0)
	await _wait_until(func(): return not Net._refreshing, 10.0)
	await _frames(3)
	_check(back and Net.requested.get("/v1/soldiers/train", 0) == t1 + 1 and Economy.training("archery").count == 0,
		"(v) after reconnecting the training start is not resent (the archery queue stays empty)", "requests=%d" % [Net.requested.get("/v1/soldiers/train", 0) - t1])
	# 합성: 한 번만 보낸다(응답 전 재탭은 무시)
	var m0: int = Net.requested.get("/v1/soldiers/merge", 0)
	var inf1 := int(Economy.soldiers.get("infantry:1", 0))
	var inf2 := int(Economy.soldiers.get("infantry:2", 0))
	var msent := Economy.merge_soldiers("infantry", 1)
	var magain := Economy.merge_soldiers("infantry", 1)
	_check(msent and not magain and Economy.merge_block("infantry", 1) == "waiting" and Net.requested.get("/v1/soldiers/merge", 0) == m0 + 1,
		"(v) one merge request; a second tap before the reply is ignored", "requests=%d" % [Net.requested.get("/v1/soldiers/merge", 0) - m0])
	await _wait_until(func(): return not Economy._waiting.has("merge"), 15.0)
	_check(int(Economy.soldiers.get("infantry:1", 0)) == inf1 - 5 and int(Economy.soldiers.get("infantry:2", 0)) == inf2 + 1,
		"(v) the server merges 5 tier-1 infantry into 1 tier-2", "infantry:1 %d -> %d, infantry:2 %d -> %d" % [inf1, Economy.soldiers.get("infantry:1", 0), inf2, Economy.soldiers.get("infantry:2", 0)])
	# 재전송 금지(합성)
	w0 = _warned("not resending")
	var arc1 := int(Economy.soldiers.get("archer:1", 0))
	Net.api_base = DEAD_API
	var msent2 := Economy.merge_soldiers("archer", 1)
	dropped = await _wait_until(func(): return not Net.up and not Economy._waiting.has("merge"), 20.0)
	_check(msent2 and dropped and notices.has(Economy.MERGE_FAIL_TEXT) and _warned("not resending") == w0 + 1,
		"(v) a merge that cannot reach the server is dropped with a notice, not queued again", "sent=%s dropped=%s notices=%s" % [msent2, dropped, notices])
	Net.api_base = live
	back = await _wait_until(func(): return Net.up, 40.0)
	await _wait_until(func(): return not Net._refreshing, 10.0)
	await _frames(3)
	_check(back and Net.requested.get("/v1/soldiers/merge", 0) == m0 + 2 and int(Economy.soldiers.get("archer:1", 0)) == arc1,
		"(v) after reconnecting the merge is not resent (the archers are unchanged)", "requests=%d archers %d -> %s" % [Net.requested.get("/v1/soldiers/merge", 0) - m0, arc1, Economy.soldiers.get("archer:1")])
	# 서버 거부: 최대 티어 — 화면이 막는 요청을 직접 보낸다
	Economy._merge_online("cavalry", 5)
	await _wait_until(func(): return not Economy._waiting.has("merge"), 15.0)
	await _wait_until(func(): return not Net._refreshing, 10.0)
	_check(notices.has(Economy.SOLDIER_TEXT.max_tier) and Net.up, "(v) a refused merge (409 max_tier) shows the reason", "notices=%s" % [notices])
	# 배치: 서버 저장 → 월드에 선다. 인구(6)를 넘는 배치는 400
	var d := {"infantry:2": 1, "archer:1": 5}
	var d0: int = Net.requested.get("/v1/soldiers/deploy", 0)
	var ok := Economy.set_soldier_deploy(d)
	await _wait_until(func(): return Economy._pending_soldier_deploy == null, 15.0)
	var p := await _request("GET", "/v1/player")
	var server_d = p.get("player", {}).get("soldier_deploy", {})
	var stored: bool = server_d is Dictionary and server_d.size() == 2 and d.keys().all(func(k): return int(server_d.get(k, -1)) == d[k])
	await _frames(2)
	_check(ok and Net.requested.get("/v1/soldiers/deploy", 0) == d0 + 1 and stored and Economy.soldier_deploy() == d and _main.soldiers.size() == 6 and GameState.mode == GameState.Mode.IDLE,
		"(v) the soldier deploy is saved on the server and the six soldiers stand in front of the keep", "server=%s app=%s spawned=%d" % [server_d, Economy.soldier_deploy(), _main.soldiers.size()])
	r0 = _warned("server rejected")
	await _request("POST", "/v1/soldiers/deploy", {"deploy": {"archer:1": 5, "infantry:1": 1, "infantry:2": 1}})
	_check(_warned("server rejected") == r0 + 1 and Economy.soldier_deploy() == d, "(v) a deploy above the population is refused (400)", "warnings=%d" % [_warned("server rejected") - r0])
	# phase 2가 볼 대기열: 기병 1마리(3시간)
	Economy.start_training("stable", 1)
	await _wait_until(func(): return Economy.training("stable").count == 1 and not Economy.training_waiting("stable", "train"), 15.0)
	Economy.notice.disconnect(on_notice)
	var f := FileAccess.open(state_path + ".soldiers", FileAccess.WRITE)
	f.store_string(JSON.stringify({"soldiers": Economy.soldiers, "deploy": Economy.soldier_deployed, "training": Economy.train_queues}))
	f.close()


## (e2) 선택 판매: 열린 두 칸을 요청 한 번으로 판다(응답 전 재탭은 무시). 서버 시세·골드와 일치.
func _sell_many_online_check() -> void:
	await _request("POST", "/v1/test/age", {"minutes": 7})
	await _request("POST", "/v1/collect", {"building": "lumber"})
	await _request("POST", "/v1/collect", {"building": "quarry"})
	var w: int = Economy.res["wood"]
	var s: int = Economy.res["stone"]
	var gold0: int = Economy.server_gold_tenths
	var gain := (Economy.sell_value("wood", w, float(Economy.merchant.rates.wood)) + Economy.sell_value("stone", s, float(Economy.merchant.rates.stone))) * 10
	var sell0: int = Net.requested.get("/v1/sell", 0)
	_panel.open()
	for id in ["wood", "stone"]:
		_panel.sell_buttons[id].pressed.emit()
		_panel.qty_max[id].pressed.emit()
	_panel.sell_selected_button.pressed.emit()
	_panel.sell_selected_button.pressed.emit()  # 재탭(수량은 0이라 보내지 않는다)
	await _wait_until(func(): return Economy.res["wood"] == 0 and Economy.res["stone"] == 0, 10.0)
	_check(w > 0 and s > 0 and Economy.server_gold_tenths == gold0 + gain and Net.requested.get("/v1/sell", 0) == sell0 + 1,
		"(e2) [sell selected] online: one items request sells both boxes at the server rates", "gold=%d expect=%d requests=%d" % [Economy.server_gold_tenths, gold0 + gain, Net.requested.get("/v1/sell", 0) - sell0])
	_panel.close()


## (p2) 재접속하면 병사 보유·배치·훈련 대기열(개정 16)이 그대로이고 월드에 그 병사들이 선다.
func _soldiers_restored(state_path: String) -> void:
	var json := JSON.new()
	var ok := json.parse(FileAccess.get_file_as_string(state_path + ".soldiers")) == OK and json.data is Dictionary
	_check(ok, "(p2) phase 1 soldiers state file", state_path)
	if not ok:
		return
	var saved: Dictionary = json.data
	var same: bool = Economy.soldiers.size() == saved.soldiers.size() and Economy.soldier_deployed.size() == saved.deploy.size()
	for k in saved.soldiers:
		same = same and int(Economy.soldiers.get(k, 0)) == int(saved.soldiers[k])
	for k in saved.deploy:
		same = same and int(Economy.soldier_deployed.get(k, 0)) == int(saved.deploy[k])
	_check(same and _main.soldiers.size() == 6, "(p2) reconnecting restores the soldiers and their deploy, and the world spawns them",
		"soldiers=%s deploy=%s saved=%s spawned=%d" % [Economy.soldiers, Economy.soldier_deployed, saved, _main.soldiers.size()])
	var tq: Dictionary = saved.get("training", {})
	var q := Economy.training("stable")
	_check(tq.keys() == ["stable"] and Economy.train_queues.keys() == ["stable"] and q.count == int(tq.stable.count) and absf(q.finish - float(tq.stable.finish)) < 0.01 and not q.ready,
		"(p2) reconnecting restores the training queue (stable: 1 cavalry, same finish)", "queues=%s saved=%s" % [Economy.train_queues, tq])


## (z) 개정 20 서버 성장 강화: 골드를 만든 뒤 atk ×3 → /v1/upgrade 한 번(응답 전 재탭 무시, 재전송 없음), 서버 골드 −합계 × 10 tenths, Lv 3.
##     crit_dmg 한 번 더, 서버 거부(409 max_level)는 알림만. 끝 상태를 <state>.growth에 써서 phase 2가 재접속 복원을 본다.
func _growth_online(state_path: String) -> void:
	var notices := []
	var on_notice := func(t): notices.append(t)
	Economy.notice.connect(on_notice)
	await _request("POST", "/v1/test/age", {"minutes": 720})
	await _request("POST", "/v1/collect", {"building": "lumber"})
	await _request("POST", "/v1/sell", {"res": "wood"})
	await _wait_until(func(): return Economy.kills_pending.is_empty() and Economy.kills_sent.is_empty(), 10.0)
	var gold0: int = Economy.server_gold_tenths
	var cost3 := Economy.upgrade_total_cost("atk", 3)
	var u0: int = Net.requested.get("/v1/upgrade", 0)
	_check(Economy.upgrades.is_empty() and Economy.gold_tenths == gold0 and Economy.gold >= cost3 + 1000, "(z) precondition: no upgrades, gold from the server covers atk x3 and one more",
		"upgrades=%s gold=%d cost=%d" % [Economy.upgrades, Economy.gold, cost3])
	var sent := Economy.growth_up("atk", 3)
	var again := Economy.growth_up("atk", 1)  # 응답 전 재탭
	_check(sent and not again and Economy.upgrades_waiting() and Economy.upgrade_level("atk") == 0 and Net.requested.get("/v1/upgrade", 0) == u0 + 1,
		"(z) one /v1/upgrade request; a second tap before the reply is ignored and nothing changes yet", "requests=%d" % [Net.requested.get("/v1/upgrade", 0) - u0])
	var done := await _wait_until(func(): return Economy.upgrade_level("atk") == 3 and not Economy.upgrades_waiting(), 15.0)
	_check(done and Net.requested.get("/v1/upgrade", 0) == u0 + 1 and Economy.server_gold_tenths == gold0 - cost3 * 10 and Economy.upgrades == {"atk": 3} \
		and is_equal_approx(Economy.upgrade_bonus().atk_pct, 0.015), "(z) the server took the summed gold (x 10 tenths) and set atk Lv 3 (+1.5%)",
		"requests=%d gold=%d->%d upgrades=%s" % [Net.requested.get("/v1/upgrade", 0) - u0, gold0, Economy.server_gold_tenths, Economy.upgrades])
	var gold1: int = Economy.server_gold_tenths
	var cc := Economy.upgrade_total_cost("crit_dmg", 1)
	Economy.growth_up("crit_dmg", 1)
	await _wait_until(func(): return Economy.upgrade_level("crit_dmg") == 1 and not Economy.upgrades_waiting(), 15.0)
	_check(Economy.upgrades == {"atk": 3, "crit_dmg": 1} and Economy.server_gold_tenths == gold1 - cc * 10 and Net.requested.get("/v1/upgrade", 0) == u0 + 2,
		"(z) a second upgrade (crit_dmg Lv 1) is charged on its own cost", "gold=%d upgrades=%s" % [Economy.server_gold_tenths, Economy.upgrades])
	Economy._growth_online("mspd", 100)  # 화면이 막는 요청을 직접 보낸다 — 서버가 409 max_level
	await _wait_until(func(): return not Economy.upgrades_waiting(), 15.0)
	_check(notices.has("최대 레벨입니다") and Economy.upgrades == {"atk": 3, "crit_dmg": 1} and Economy.server_gold_tenths == gold1 - cc * 10 and Net.up,
		"(z) the server refuses 409 max_level: a notice, nothing charged", "notices=%s gold=%d" % [notices, Economy.server_gold_tenths])
	Economy.notice.disconnect(on_notice)
	var f := FileAccess.open(state_path + ".growth", FileAccess.WRITE)
	f.store_string(JSON.stringify({"upgrades": Economy.upgrades}))
	f.close()


## (p2) 재접속하면 성장 레벨이 그대로다.
func _growth_restored(state_path: String) -> void:
	var json := JSON.new()
	var ok := json.parse(FileAccess.get_file_as_string(state_path + ".growth")) == OK and json.data is Dictionary
	_check(ok, "(p2) phase 1 growth state file", state_path)
	if not ok:
		return
	var saved: Dictionary = json.data.upgrades
	var same: bool = saved.size() == 2 and Economy.upgrades.size() == saved.size()
	for k in saved:
		same = same and Economy.upgrade_level(k) == int(saved[k])
	_check(same and Economy.upgrade_level("atk") == 3 and Economy.upgrade_level("crit_dmg") == 1, "(p2) reconnecting restores the growth levels (atk 3, crit_dmg 1)",
		"upgrades=%s saved=%s" % [Economy.upgrades, saved])
