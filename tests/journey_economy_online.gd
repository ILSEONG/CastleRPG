extends Node
## 통합 테스트(경제·영웅, 2026-10-14): 로컬 서버(메모리 PGlite, ALLOW_TEST_HOOKS=1, tutorial_new_players=0)에 게스트로 접속해
## 모집·상점·결제 상품·영웅·장비·병사·주머니·오프라인 보상·상인 판매를 버튼이 부르는 같은 길(창의 버튼 pressed·Economy 함수)로 하나씩 해 보고,
## 동작마다 ① 누른 즉시 보이는 값(예측) ② 서버 응답 뒤 앱 값 ③ 새로 받은 GET /v1/player를 비교한다(다르면 FAIL).
## 실행: cd server && PGLITE_DIR=memory ALLOW_TEST_HOOKS=1 PORT=8801 node src/main.ts &
##   curl -XPOST localhost:8801/v1/test/config -H 'content-type: application/json' -d '{"key":"tutorial_new_players","value":"0"}'
##   xvfb-run -a godot --path . --resolution 720x1280 res://tests/journey_economy_online.tscn -- --api=http://127.0.0.1:8801 --device=/tmp/x/device.json --out=/tmp/econ.png
## 마지막 줄이 ECONOMY ONLINE PASSED(실패면 종료 코드 1).

const EconomyScript := preload("res://scripts/economy.gd")
const ShopItems := preload("res://scripts/shop_items.gd")
const IapItems := preload("res://scripts/iap_items.gd")
const GameData := preload("res://scripts/game_data.gd")
const ReleasePlatform := preload("res://scripts/release_platform.gd")
const AdPlayer := preload("res://scripts/ad_player.gd")

## 이 문구가 알림에 뜨면 서버가 거절해 되돌린 것(예측 ≠ 서버)
const FAIL_TEXTS := [EconomyScript.ROLLBACK_TEXT, EconomyScript.SHOP_FAIL_TEXT, EconomyScript.IAP_FAIL_TEXT, EconomyScript.GACHA_FAIL_TEXT,
	EconomyScript.LEVELUP_FAIL_TEXT, EconomyScript.PROMOTE_FAIL_TEXT, EconomyScript.DEPLOY_FAIL_TEXT, EconomyScript.POUCH_FAIL_TEXT,
	EconomyScript.MERGE_FAIL_TEXT, EconomyScript.SOLDIER_DEPLOY_FAIL_TEXT, EconomyScript.TRAIN_FAIL_TEXT, EconomyScript.GROWTH_FAIL_TEXT,
	EconomyScript.EQUIP_FAIL_TEXT]

var _main
var _shots: Array = []
var _fails := 0
var _notes: Array = []
var _kills := 0  # 비교 구간 동안 처치가 있었으면 골드는 그만큼 흔들린다
var _gacha_results: Array = []
var _gacha_got := false
var _leveled_to := 0
var _offline := {}


func _ready() -> void:
	Fever.save_path = ""
	Guild.save_path = ""
	get_window().size = Vector2i(360, 640)
	var device := Net.arg_value("device")
	_check(Net.is_online() and device != "", "online mode with --api and --device", Net.api_base)
	if _fails > 0:
		return _finish()
	Net.device_path = device
	Net.auth_path = device.get_base_dir().path_join("auth.json")
	DirAccess.remove_absolute(device)
	Net.set_auth("guest")
	_main = preload("res://scenes/main.tscn").instantiate()
	add_child(_main)
	_check(await _wait_until(func(): return Net.ready_once and _main.camera != null, 30.0), "world built after connecting", "")
	if _fails > 0:
		return _finish()
	Economy.notice.connect(func(s): _notes.append(s))
	Economy.killed.connect(func(_k): _kills += 1)
	Economy.gacha_done.connect(func(r):
		_gacha_results = r
		_gacha_got = true)
	Economy.gacha_leveled.connect(func(lv): _leveled_to = lv)
	Economy.offline_reported.connect(func(r): _offline = r.duplicate())
	_check(await _wait_until(func(): return Net.up, 15.0), "connected", "")
	await _frames(30)
	_stop_battle()
	await _wait_sec(2.0)
	await _settle()

	var only := Net.arg_value("only")  # 디버그: --only=heroes 처럼 한 묶음만(앞 묶음이 준비한 상태가 없으면 일부 체크는 실패한다)
	for sec in ["recruit_insufficient", "shop", "iap", "recruit", "heroes", "equipment", "soldiers", "pouches_offline_merchant"]:
		if only == "" or only == sec:
			await call("_" + sec)
	_sheet()
	_finish()


# --- 모집 ---

func _recruit_insufficient() -> void:
	print("== recruit: insufficient currency")
	var rp = _panel("recruit_panel.gd")
	rp.open()
	await _frames(5)
	_check(Economy.gold < Economy.gacha_cost("gold", 1) and rp.one_button.disabled, "gold [1회] is disabled with no gold", str([Economy.gold, rp.one_button.disabled]))
	var n0 := _notes.size()
	_check(not Economy.gacha(1, "gold") and _notes.slice(n0).has(EconomyScript.NO_GOLD_TEXT), "gold recruit with no gold: notice, nothing sent", str(_notes.slice(n0)))
	_check(not Economy.gacha(1, "diamond") and _notes.slice(n0).has(EconomyScript.NO_DIA_TEXT), "diamond recruit with no diamonds: notice", str(_notes.slice(n0)))
	_check(not Economy.gacha(1, "ticket") and _notes.slice(n0).has(EconomyScript.NO_TICKET_TEXT), "ticket recruit with no tickets: notice", str(_notes.slice(n0)))
	rp.set_currency("diamond")
	await _frames(3)
	rp.one_button.pressed.emit()
	await _frames(3)
	_check(rp.shop_ask.visible and not Economy._waiting.has("gacha"), "diamond [1회] with no diamonds opens the go-to-shop ask", "")
	await _snap()
	rp.shop_ask.visible = false
	rp.close()
	await _same_as_server("recruit refusals change nothing", ["gold", "diamonds", "tickets", "heroes", "gacha"])


func _recruit() -> void:
	print("== recruit: gold / diamond / ticket")
	await _post("/v1/test/grant_gold", {"amount": 3000000})
	await _post("/v1/test/grant_diamonds", {"amount": 20000})
	var rp = _panel("recruit_panel.gd")
	rp.auto_delay = 999.0
	rp.open()
	rp.set_currency("gold")
	await _frames(5)
	# 골드 1회 — 창 버튼
	var cost1 := Economy.gacha_cost("gold", 1)
	var before := _cli()
	_gacha_got = false
	rp.one_button.pressed.emit()
	var pred := _cli()
	_check(pred.gold == before.gold - cost1 * 10, "gold 1x: gold is taken at once", str([before.gold, pred.gold, cost1]))
	rp.one_button.pressed.emit()  # 응답 전 재탭은 무시
	_check(await _wait_until(func(): return _gacha_got, 15.0) and _gacha_results.size() == 1, "gold 1x: one result", str(_gacha_results))
	await _settle()
	_check(rp.is_showing_results() and rp.cards.size() == 1, "gold 1x: the result window opens with 1 card", str(rp.cards.size()))
	await _snap()
	_check(_gacha_pulls_after(before, 1), "gold 1x: double tap pulled once (gold_pulls +1)", str([before.gacha, Economy.gacha_gold_pulls]))
	await _same_as_server("gold 1x", ["gold", "diamonds", "heroes", "gacha"], pred, ["gold"])
	_check_shards_invariant("gold 1x")
	rp._on_confirm()
	await _frames(3)
	# 골드 10회 × 4 → 골드 모집 Lv 2(40회)
	_leveled_to = 0
	for i in 4:
		var c10 := Economy.gacha_cost("gold", 10)
		before = _cli()
		_gacha_got = false
		rp.ten_button.pressed.emit()
		pred = _cli()
		_check(pred.gold == before.gold - c10 * 10, "gold 10x #%d: gold -%d at once" % [i + 1, c10], str([before.gold, pred.gold]))
		_check(await _wait_until(func(): return _gacha_got, 15.0) and _gacha_results.size() == 10, "gold 10x #%d: ten results" % (i + 1), str(_gacha_results.size()))
		await _settle()
		_check(rp.cards.size() == 10, "gold 10x #%d: 10 cards shown" % (i + 1), str(rp.cards.size()))
		await _same_as_server("gold 10x #%d" % (i + 1), ["gold", "heroes", "gacha"], pred, ["gold"])
		rp._on_confirm()
		await _frames(3)
	await _snap()
	_check(Economy.gacha_gold_level == 2 and Economy.gacha_gold_pulls == 1 and _leveled_to == 2, "41 gold pulls → gold recruit Lv 2 (1 into it)",
		str([Economy.gacha_gold_level, Economy.gacha_gold_pulls, _leveled_to]))
	_check(_notes.any(func(s): return str(s).begins_with("골드 모집 Lv 2")), "level-up notice shown", str(_notes.slice(-6)))
	_check(Economy.gacha_cost("gold", 1) > cost1, "Lv 2 gold cost is higher", str([cost1, Economy.gacha_cost("gold", 1)]))
	_check_shards_invariant("gold pulls")
	# 모집권(상점 주간 모집권 10장 묶음 + 일일 할인 1장으로 받았다)
	_check(Economy.dia_tickets >= 11, "tickets owned from the shop", str(Economy.dia_tickets))
	await _frames(3)
	rp.set_currency("diamond")
	await _frames(3)
	_check(rp.pull_currency(1) == "ticket" and rp.one_button.text.contains("모집권"), "with tickets the diamond buttons become ticket buttons", rp.one_button.text)
	var ticket_pulls := [10]
	for i in Economy.dia_tickets - 10:
		ticket_pulls.append(1)
	for n in ticket_pulls:
		before = _cli()
		_gacha_got = false
		(rp.one_button if n == 1 else rp.ten_button).pressed.emit()
		pred = _cli()
		_check(pred.tickets == before.tickets - n and pred.diamonds == before.diamonds, "ticket %dx: -%d tickets, diamonds kept" % [n, n], str([before.tickets, pred.tickets]))
		_check(await _wait_until(func(): return _gacha_got, 15.0) and _gacha_results.size() == n, "ticket %dx: %d results" % [n, n], str(_gacha_results.size()))
		await _settle()
		var pity := int(before.gacha[2])
		for r in _gacha_results:
			pity = 0 if r.grade in ["SSR", "UR"] else pity + 1
		_check(Economy.gacha_dia_pity == pity, "ticket %dx: shares the diamond pity" % n, str([Economy.gacha_dia_pity, pity]))
		await _same_as_server("ticket %dx" % n, ["gold", "diamonds", "tickets", "heroes", "gacha"], pred, ["tickets", "diamonds"])
		rp._on_confirm()
		await _frames(3)
	# 다이아 1회·10회 — 천장(모집권을 다 쓴 뒤라 다이아 버튼)
	_check(Economy.dia_tickets == 0 and rp.pull_currency(1) == "diamond", "tickets used up: buttons back to diamonds", str(Economy.dia_tickets))
	for n in [1, 10]:
		var cd := Economy.gacha_cost("diamond", n)
		before = _cli()
		_gacha_got = false
		(rp.one_button if n == 1 else rp.ten_button).pressed.emit()
		pred = _cli()
		_check(pred.diamonds == before.diamonds - cd, "diamond %dx: -%d diamonds at once" % [n, cd], str([before.diamonds, pred.diamonds]))
		_check(await _wait_until(func(): return _gacha_got, 15.0) and _gacha_results.size() == n, "diamond %dx: %d results" % [n, n], str(_gacha_results.size()))
		await _settle()
		_check(_gacha_results.filter(func(r): return r.grade != "R").size() >= (1 if n == 10 else 0), "diamond %dx: SR+ guarantee" % n, str(_gacha_results.map(func(r): return r.grade)))
		var pity := int(before.gacha[2])
		for r in _gacha_results:
			pity = 0 if r.grade == "SSR" else pity + 1
		_check(Economy.gacha_dia_pity == pity, "diamond %dx: pity counter follows the results" % n, str([before.gacha[2], Economy.gacha_dia_pity, pity]))
		await _same_as_server("diamond %dx" % n, ["gold", "diamonds", "heroes", "gacha"], pred, ["diamonds"])
		rp._on_confirm()
		await _frames(3)
	_check(rp.pity_label.text.begins_with("SSR 확정까지 %d회" % maxi(1, int(GameData.config_num("gacha_dia_pity")) - Economy.gacha_dia_pity)), "pity label", rp.pity_label.text)
	_check_shards_invariant("all pulls")
	var dups := 0
	for id in Economy.heroes:
		dups += int(Economy.heroes[id]) - 1
	_check(dups > 0, "duplicates were turned into shards", str(Economy.hero_shards))
	rp.close()
	_no_rollback("recruit")


func _gacha_pulls_after(before: Dictionary, n: int) -> bool:
	return Economy.gacha_gold_pulls == int(before.gacha[1]) + n and Economy.gacha_gold_level == int(before.gacha[0])


## 승급 전에는 조각 = copies − 1(중복 1장 = 조각 1)
func _check_shards_invariant(what: String) -> void:
	var bad := []
	for id in Economy.heroes:
		if Economy.promotion_of(id) == 0 and Economy.shards_of(id) != int(Economy.heroes[id]) - 1:
			bad.append([id, Economy.heroes[id], Economy.shards_of(id)])
	_check(bad.is_empty(), what + ": shards = copies − 1", str(bad))


# --- 상점 ---

func _shop() -> void:
	print("== shop")
	var sp = _panel("shop_panel.gd")
	sp.open_tab("daily")
	await _frames(5)
	await _snap()
	# 무료 선물(다이아 50 + 골드 주머니)
	await _shop_buy(sp, "d_free")
	_check(Economy.shop_left("d_free") == 0 and sp.buttons["buy:d_free"].disabled, "free gift sold out after one", "")
	# 다이아가 모자란 상품: 알림만
	var n0 := _notes.size()
	_check(Economy.shop_block("d_ticket") == "diamonds", "240-diamond ticket is blocked with 50 diamonds", Economy.shop_block("d_ticket"))
	sp.buttons["buy:d_ticket"].pressed.emit()
	_check(_notes.slice(n0).has("다이아가 부족합니다") and Economy.shop_left("d_ticket") == 1, "short of diamonds: notice, nothing bought", str(_notes.slice(n0)))
	await _same_as_server("shop refusal", ["diamonds", "shop", "tickets"])
	await _post("/v1/test/grant_diamonds", {"amount": 10000})
	await _frames(3)
	# 일일 한도 3: 골드 주머니 ×3 → 매진 → 4번째 거절
	for i in 3:
		await _shop_buy(sp, "d_pouch_gold")
	_check(Economy.shop_left("d_pouch_gold") == 0 and Economy.shop_block("d_pouch_gold") == "sold_out" and sp.buttons["buy:d_pouch_gold"].disabled,
		"daily limit 3: sold out after three", str(Economy.shop_left("d_pouch_gold")))
	var dia := Economy.diamonds
	_check(not Economy.buy_shop("d_pouch_gold") and Economy.diamonds == dia, "4th buy is refused in the app", "")
	var r := await _post_raw("/v1/shop/buy", {"id": "d_pouch_gold", "n": 3})
	_check(not r[0] and r[1] == "sold_out", "server refuses the 4th: 409 sold_out", str(r))
	r = await _post_raw("/v1/shop/buy", {"id": "d_res", "n": 1})
	_check(not r[0] and r[1] == "stale", "server refuses a stale count: 409 stale", str(r))
	# 할인 모집권·자원 꾸러미·던전 입장권·가속(건설·연구)
	for id in ["d_ticket", "d_res", "d_key_gold", "d_sp_build", "d_sp_research"]:
		await _shop_buy(sp, id)
	# 주간: 무료 선물·모집권 10장·범용 가속 8시간
	sp._pick("weekly")
	await _frames(3)
	for id in ["w_free", "w_tickets", "w_sp_any"]:
		await _shop_buy(sp, id)
	_check(Economy.shop_left("w_tickets") == 0 and sp.buttons["buy:w_tickets"].disabled, "weekly limit 1: sold out", "")
	await _snap()
	# 광고 탭: 광고 없이는 안 산다, 중간에 닫으면 보상 없음, 끝까지 보면 받는다
	sp._pick("ad")
	await _frames(3)
	_check(not Economy.buy_shop("a_dia"), "ad item needs a watched ad", "")
	r = await _post_raw("/v1/shop/buy", {"id": "a_dia", "n": 0})
	_check(not r[0] and r[1] == "ad_required", "server: 409 ad_required without the ad", str(r))
	dia = Economy.diamonds
	sp.buttons["buy:a_dia"].pressed.emit()
	await _frames(3)
	_check(sp.ad_player.visible, "the ad screen opens", "")
	await _snap()
	sp.ad_player.close_button.pressed.emit()
	await _wait_sec(AdPlayer.SECONDS + 0.5)
	_check(Economy.diamonds == dia and Economy.shop_left("a_dia") == 5, "closing the ad early gives nothing", str([dia, Economy.diamonds]))
	var before := _cli()
	sp.buttons["buy:a_dia"].pressed.emit()
	_check(await _wait_until(func(): return Economy.shop_left("a_dia") == 4, AdPlayer.SECONDS + 3.0), "watching the ad to the end buys it", "")
	var pred := _cli()
	_check(pred.diamonds == before.diamonds + 100, "ad diamonds +100 at once", str([before.diamonds, pred.diamonds]))
	await _settle()
	await _same_as_server("ad a_dia", ["diamonds", "shop"], pred, ["diamonds", "shop"])
	AdPlayer.instant = true
	await _shop_buy(sp, "a_sp_any")
	AdPlayer.instant = false
	sp.close()
	_no_rollback("shop")


## 창 버튼으로 하나 사고 예측 = 서버 = 앱인지 본다.
func _shop_buy(sp, id: String) -> void:
	var x := ShopItems.find(id)
	var before := _cli()
	var left := Economy.shop_left(id)
	var key := "buy:" + id
	_check(sp.buttons.has(key) and not sp.buttons[key].disabled, "shop %s: button ready" % id, str(sp.buttons.keys()))
	if not sp.buttons.has(key):
		return
	sp.buttons[key].pressed.emit()
	var pred := _cli()
	var dia_cost := int(x.price) if x.currency == "diamonds" else 0
	_check(Economy.shop_left(id) == left - 1 and pred.diamonds == before.diamonds - dia_cost + int(x.give.get("diamonds", 0))
		and pred.tickets == before.tickets + int(x.give.get("tickets", 0)), "shop %s: shown at once (left %d → %d)" % [id, left, left - 1], str([before.diamonds, pred.diamonds, Economy.shop_left(id)]))
	await _settle()
	await _same_as_server("shop " + id, ["gold", "diamonds", "tickets", "res", "pouches", "speedups", "shop", "keys"], pred,
		["diamonds", "tickets", "res", "pouches", "speedups", "shop", "keys"])
	await _frames(2)


# --- 결제 상품 ---

func _iap() -> void:
	print("== iap")
	var sp = _panel("shop_panel.gd")
	sp.open_tab("diamond")
	await _frames(5)
	var before := _cli()
	var n0 := _notes.size()
	_check(sp.buttons.has("iap:dia_1"), "diamond tab lists ₩ buttons", str(sp.buttons.keys()))
	sp.buttons["iap:dia_1"].pressed.emit()
	await _frames(3)
	_check(_notes.slice(n0).has(ReleasePlatform.iap_off_text()), "payments off: the right notice", str(_notes.slice(n0)))
	_check(not Economy.iap_enabled, "server says payments are off", "")
	await _same_as_server("iap while payments are off", ["diamonds", "iap"])
	_check(_cli().diamonds == before.diamonds, "nothing granted while payments are off", "")
	sp.open_tab("package")
	await _frames(3)
	n0 = _notes.size()
	sp.buttons["iap:monthly"].pressed.emit()
	_check(_notes.slice(n0).has(ReleasePlatform.iap_off_text()), "monthly card while off: notice", str(_notes.slice(n0)))
	await _snap()
	# 시험 결제(서버 provider "test", ALLOW_TEST_HOOKS만)
	var seq := [0]
	StorePay.fake_store = func(id):
		seq[0] += 1
		return "econ-%s-%d-%d" % [id, Time.get_ticks_msec(), seq[0]]
	for id in ["dia_1", "dia_1", "monthly", "pass_growth", "no_ads"]:
		before = _cli()
		var first := Economy.iap_first_bonus(id)
		StorePay._opening_until = 0.0
		_check(Economy.iap_buy(id), "test purchase %s: payment opened" % id, "")
		_check(await _wait_until(func(): return StorePay._sent.is_empty(), 15.0), "test purchase %s: answered" % id, "")
		await _settle()
		var p := IapItems.find(id)
		var want := int(p.give.get("diamonds", 0))
		if p.kind == "diamond":
			want = want * 2 if first else want + int(p.bonus)
		_check(_cli().diamonds == before.diamonds + want, "purchase %s: +%d diamonds" % [id, want], str([before.diamonds, _cli().diamonds]))
		await _same_as_server("purchase " + id, ["diamonds", "tickets", "speedups", "iap"])
	_check(Economy.has_pass("pass_growth") and Economy.ad_free() and Economy.monthly_left("monthly") == 30, "owns the growth pass, ad removal and 30 days of monthly",
		str([Economy.has_pass("pass_growth"), Economy.ad_free(), Economy.monthly_left("monthly")]))
	# 같은 영수증을 다시 보내면 두 번 지급하지 않는다
	before = _cli()
	var tok := "econ-replay-%d" % Time.get_ticks_msec()
	StorePay._send("dia_2", "test", tok)
	await _wait_until(func(): return StorePay._sent.is_empty(), 15.0)
	await _settle()
	var mid := _cli()
	StorePay._send("dia_2", "test", tok)
	await _wait_until(func(): return StorePay._sent.is_empty(), 15.0)
	await _wait_sec(1.0)
	await _settle()
	_check(mid.diamonds == before.diamonds + 16000 and _cli().diamonds == mid.diamonds, "same receipt twice → granted once", str([before.diamonds, mid.diamonds, _cli().diamonds]))
	StorePay.fake_store = Callable()
	# 월정액 오늘 보상
	sp.open_tab("package")
	await _frames(5)
	_check(sp.buttons.has("monthly:monthly"), "[오늘 받기] shows for the owned monthly card", str(sp.buttons.keys()))
	before = _cli()
	sp.buttons["monthly:monthly"].pressed.emit()
	var pred := _cli()
	_check(pred.diamonds == before.diamonds + 500 and int(pred.speedups.get("build_60", 0)) == int(before.speedups.get("build_60", 0)) + 1,
		"monthly claim: reward shown at once", str([before.diamonds, pred.diamonds]))
	await _settle()
	await _same_as_server("claim monthly", ["diamonds", "speedups", "iap"], pred, ["diamonds", "speedups", "iap"])
	_check(not Economy.claim_monthly("monthly") and not Economy.can_claim_monthly("monthly"), "second monthly claim today is refused", "")
	var r := await _post_raw("/v1/iap/monthly/claim", {"product": "monthly"})
	_check(not r[0] and r[1] == "claimed", "server: 409 claimed", str(r))
	r = await _post_raw("/v1/iap/monthly/claim", {"product": "monthly_plus"})
	_check(not r[0] and r[1] == "inactive", "server: 409 inactive for a card not owned", str(r))
	# 성장 패스: 라운드 10을 깨야 단계 0
	_check(not Economy.can_claim_growth(0, "free", 0), "growth tier 0 locked before round 10", "")
	r = await _post_raw("/v1/iap/growth/claim", {"tier": 0, "track": "free"})
	_check(not r[0] and r[1] == "not_ready", "server: growth 409 not_ready before round 10", str(r))
	await _post("/v1/test/stage", {"stage": 12})
	await _frames(5)
	sp._pick("pass")
	await _frames(5)
	await _snap()
	for track in ["free", "paid"]:
		var k: String = "growth:0:" + track
		_check(sp.buttons.has(k), "pass tab: [받기] for tier 0 %s" % track, str(sp.buttons.keys()))
		if not sp.buttons.has(k):
			continue
		before = _cli()
		sp.buttons[k].pressed.emit()
		pred = _cli()
		var rw: Dictionary = IapItems.GROWTH[0][track]
		_check(pred.diamonds == before.diamonds + int(rw.get("diamonds", 0)), "growth %s: reward shown at once" % track, str([before.diamonds, pred.diamonds]))
		await _settle()
		await _same_as_server("claim growth 0 " + track, ["diamonds", "tickets", "speedups", "iap"], pred, ["diamonds", "tickets", "speedups", "iap"])
		await _frames(3)
	_check(not Economy.claim_growth(0, "paid", 11), "growth tier 0 paid can't be claimed twice", "")
	_check(not Economy.can_claim_growth(1, "free", 11), "growth tier 1 still locked (round 25)", "")
	# 광고 제거: 광고 상품을 광고 없이 바로
	sp._pick("ad")
	await _frames(3)
	before = _cli()
	sp.buttons["buy:a_ticket"].pressed.emit()
	await _frames(2)
	_check(not sp.ad_player.visible and _cli().tickets == before.tickets + 1, "ad-free: the ad item is given without the ad", str([before.tickets, _cli().tickets]))
	await _settle()
	await _same_as_server("ad-free a_ticket", ["tickets", "shop"])
	sp.close()
	_no_rollback("iap")


# --- 영웅 ---

func _heroes() -> void:
	print("== heroes")
	var hp = _panel("hero_panel.gd")
	hp.open()
	await _frames(5)
	await _snap()
	var id := "hans"  # R 영웅
	hp.show_detail(id)
	await _frames(3)
	# 레벨업 1
	var before := _cli()
	var c1 := int(GameData.levelup_cost("R", Economy.level_of(id), 1).gold)
	hp.level_button.pressed.emit()
	var pred := _cli()
	_check(pred.heroes[id][1] == before.heroes[id][1] + 1 and pred.gold == before.gold - c1 * 10, "level up 1: shown at once (-%d gold)" % c1, str([before.heroes[id], pred.heroes[id]]))
	await _settle()
	await _same_as_server("level up 1", ["gold", "heroes"], pred, ["gold", "heroes"])
	# [×10]
	before = _cli()
	var n := Economy.levelup_affordable(id, 10)
	var c10 := int(GameData.levelup_cost("R", Economy.level_of(id), n).gold)
	hp.ten_button.pressed.emit()
	pred = _cli()
	_check(n == 10 and pred.heroes[id][1] == before.heroes[id][1] + n and pred.gold == before.gold - c10 * 10, "level up ×10: +%d levels at once" % n, str([n, before.heroes[id], pred.heroes[id]]))
	await _settle()
	await _same_as_server("level up ×10", ["gold", "heroes"], pred, ["gold", "heroes"])
	# 최대 레벨(승급 0 = 20)까지, 넘으면 막힌다
	var cap := GameData.max_level(0)
	while Economy.level_of(id) < cap:
		Economy.level_up(id, mini(10, cap - Economy.level_of(id)))
		await _settle()
	_check(Economy.level_of(id) == cap, "levelled to the cap %d" % cap, str(Economy.level_of(id)))
	var n0 := _notes.size()
	_check(not Economy.level_up(id, 1) and _notes.slice(n0).has("최대 레벨"), "above the cap: refused with notice", str(_notes.slice(n0)))
	var r := await _post_raw("/v1/hero/levelup", {"hero_id": id, "count": 1})
	_check(not r[0] and r[1] == "max_level", "server: 409 max_level", str(r))
	await _same_as_server("level cap", ["gold", "heroes"])
	# 승급(조각 5 → ★1, 최대 레벨 오름)
	var cost := Economy.promote_cost(id)
	await _post("/v1/test/shards", {"hero_id": id, "shards": cost})
	await _frames(3)
	before = _cli()
	hp.promote_button.pressed.emit()
	pred = _cli()
	_check(pred.heroes[id][3] == 1 and pred.heroes[id][2] == 0, "promote: ★1 and shards spent at once", str(pred.heroes[id]))
	await _settle()
	await _same_as_server("promote", ["heroes"], pred, ["heroes"])
	_check(GameData.max_level(1) > cap and Economy.levelup_block(id, 1) == "", "★1 raises the level cap", str(GameData.max_level(1)))
	n0 = _notes.size()
	_check(not Economy.promote(id) and _notes.slice(n0).has(EconomyScript.PROMOTE_TEXT.not_enough_shards), "promote without shards: notice", str(_notes.slice(n0)))
	r = await _post_raw("/v1/hero/promote", {"hero_id": id})
	_check(not r[0] and r[1] == "not_enough_shards", "server: 409 not_enough_shards", str(r))
	# 일괄 승급
	await _post("/v1/test/shards", {"hero_id": "ella", "shards": 30})
	await _post("/v1/test/shards", {"hero_id": "dorik", "shards": 7})
	await _frames(3)
	hp._show_list()
	await _frames(3)
	var plan := Economy.promote_all_plan()
	_check(plan.any(func(x): return x.hero_id == "ella" and x.to == 2 and x.shards == 30) and plan.any(func(x): return x.hero_id == "dorik" and x.to == 1 and x.shards == 5),
		"promote-all plan: ella ★2 (30), dorik ★1 (5)", str(plan))
	hp.ask_promote_all()
	await _frames(3)
	_check(hp.promote_all_confirm.visible, "promote-all confirm window", "")
	await _snap()
	before = _cli()
	hp._on_promote_all_confirm(true)
	pred = _cli()
	_check(pred.heroes.ella[3] == 2 and pred.heroes.dorik[3] == 1 and pred.heroes.dorik[2] == 2, "promote-all shown at once", str([pred.heroes.ella, pred.heroes.dorik]))
	hp._on_promote_all_confirm(true)  # 빠른 두 번째 [승급]: 두 번 빼지 않는다
	await _settle()
	await _same_as_server("promote all", ["heroes"], pred, ["heroes"])
	# 성장(공용 업그레이드) 1·10
	for cnt in [1, 10]:
		before = _cli()
		var gc := Economy.upgrade_total_cost("atk", cnt)
		_check(Economy.growth_up("atk", cnt), "growth atk ×%d sent" % cnt, Economy.growth_block("atk", cnt))
		pred = _cli()
		_check(int(pred.upgrades.get("atk", 0)) == int(before.upgrades.get("atk", 0)) + cnt and pred.gold == before.gold - gc * 10, "growth ×%d shown at once" % cnt, str(pred.upgrades))
		await _settle()
		await _same_as_server("growth atk ×%d" % cnt, ["gold", "upgrades"], pred, ["gold", "upgrades"])
	# 배치: [자동 배치] → [적용], 새로 받아도 그대로
	hp._show_list()
	await _frames(3)
	hp.auto_deploy()
	var want: Array = hp.work.duplicate()
	_check(want.size() == GameState.hero_count() and not want.has(null), "auto deploy fills %d slots" % want.size(), str(want))
	hp.apply_button.pressed.emit()
	_check(Economy.deploy == want, "apply: deploy shown at once", str(Economy.deploy))
	await _settle()
	await _same_as_server("auto deploy", ["deploy"])
	var swap := want.duplicate()
	swap.reverse()
	Economy.set_deploy(swap)
	await _settle()
	await _same_as_server("set_deploy (reversed)", ["deploy"])
	Net.refresh()
	await _wait_sec(1.0)
	await _settle()
	_check(Economy.deploy == swap, "deploy kept after a fresh /v1/player", str([Economy.deploy, swap]))
	var bad := swap.duplicate()
	bad[0] = bad[1]
	r = await _post_raw("/v1/deploy", {"deploy": bad})
	_check(not r[0] and r[1] == "bad_deploy", "server refuses a duplicate deploy", str(r))
	hp.close()
	_no_rollback("heroes")


# --- 장비 ---

func _equipment() -> void:
	print("== equipment")
	await _post("/v1/test/grant_items", {"grades": ["R", "SR", "SSR", "SR", "R", "SSR", "SR", "R", "SSR", "SR", "R", "SR"]})
	await _frames(3)
	_check(Economy.bag.size() == 12, "12 items in the bag", str(Economy.bag.size()))
	await _same_as_server("grant items", ["items", "equipment"])
	var hp = _panel("hero_panel.gd")
	var bag = hp.bag
	var id := "hans"
	hp.open()
	hp.show_detail(id)
	await _frames(3)
	# 무기 아닌 장비 하나를 그 칸 고르기로 장착
	var it: Dictionary = {}
	for x in Economy.bag:
		if x.slot != "weapon":
			it = x
			break
	hp.press_equip(it.slot)
	await _frames(3)
	_check(bag.visible and bag.mode == "pick", "equip slot opens the picker", "")
	await _snap()
	var before := _cli()
	bag.equip(int(it.id))
	var pred := _cli()
	_check(int(pred.equipment.get(id, {}).get(it.slot, 0)) == int(it.id), "equip shown at once", str(pred.equipment))
	await _settle()
	await _same_as_server("equip", ["equipment", "items"], pred, ["equipment"])
	# 해제
	hp.press_equip(it.slot)
	await _frames(3)
	bag.unequip()
	pred = _cli()
	_check(not pred.equipment.get(id, {}).has(it.slot), "unequip shown at once", str(pred.equipment))
	await _settle()
	await _same_as_server("unequip", ["equipment", "items"], pred, ["equipment"])
	# 자동착용
	var plan := Economy.auto_equip_plan(id)
	_check(not plan.is_empty(), "auto-equip has a plan", "")
	hp.auto_equip()
	pred = _cli()
	_check(pred.equipment.get(id, {}).size() == plan.size(), "auto-equip shown at once (%d slots)" % plan.size(), str(pred.equipment))
	await _settle()
	await _same_as_server("auto equip", ["equipment", "items"], pred, ["equipment"])
	_check(Economy.auto_equip_plan(id).is_empty(), "nothing better left after auto-equip", "")
	# 판매: 장착 중은 안 팔린다, 나머지는 값만큼 골드
	var worn := int(Economy.equipment[id].values()[0])
	var n0 := _notes.size()
	_check(Economy.sell_items([worn]) == 0 and _notes.slice(n0).has(EconomyScript.EQUIP_TEXT.equipped), "selling a worn item: notice", str(_notes.slice(n0)))
	var r := await _post_raw("/v1/items/sell", {"item_ids": [worn]})
	_check(not r[0] and r[1] == "equipped", "server: 409 equipped", str(r))
	bag.open_bag()
	await _frames(3)
	var free: Array = Economy.bag.filter(func(x): return Economy.item_owner(int(x.id)) == "").map(func(x): return int(x.id))
	var value := 0
	for x in free.slice(0, 3):
		bag.toggle(x)
		value += GameData.item_sell_value(Economy.item(x))
	await _snap()
	before = _cli()
	bag.sell_button.pressed.emit()
	pred = _cli()
	_check(pred.gold == before.gold + value * 10 and pred.items.size() == before.items.size() - 3, "sell 3: +%d gold and items gone at once" % value, str([before.gold, pred.gold, pred.items.size()]))
	await _settle()
	await _same_as_server("sell items", ["gold", "items", "equipment"], pred, ["gold", "items"])
	bag.close()
	hp.close()
	# 보관함 가득: 상한까지 채우면 장비 던전이 막힌다
	var cap := int(GameData.config_num("equip_bag_cap"))
	while Economy.bag.size() + int(GameData.config_num("equip_drop_count")) <= cap:
		var k := mini(50, cap - Economy.bag.size())
		var gr := []
		for i in k:
			gr.append("R")
		await _post("/v1/test/grant_items", {"grades": gr})
		await _frames(2)
	_check(Economy.bag_full(), "bag full at %d / %d" % [Economy.bag.size(), cap], "")
	var party := Economy.default_party("equip")
	_check(Economy.dungeon_block("equip", 1, party) == "bag_full", "equipment dungeon blocked: bag_full", Economy.dungeon_block("equip", 1, party))
	n0 = _notes.size()
	_check(not Economy.start_dungeon("equip", 1, party) and _notes.slice(n0).has(EconomyScript.DUNGEON_TEXT.bag_full), "start: notice 보관함이 가득 찼습니다", str(_notes.slice(n0)))
	r = await _post_raw("/v1/dungeon/start", {"type": "equip", "level": 1, "party": party})
	_check(not r[0] and r[1] == "bag_full", "server: 409 bag_full", str(r))
	# 한 번에 많이 팔아 비운다
	free = Economy.bag.filter(func(x): return Economy.item_owner(int(x.id)) == "").map(func(x): return int(x.id))
	before = _cli()
	Economy.sell_items(free)
	pred = _cli()
	await _settle()
	_check(not Economy.bag_full() and Economy.bag.size() == before.items.size() - free.size(), "selling %d items frees the bag" % free.size(), str(Economy.bag.size()))
	await _same_as_server("sell many", ["gold", "items", "equipment"], pred, ["gold", "items"])
	_no_rollback("equipment")


# --- 병사 ---

func _soldiers() -> void:
	print("== soldiers")
	await _post("/v1/test/levels", {"levels": {"houses": 5}, "res": {"wood": 5000000, "stone": 5000000, "food": 5000000}})
	await _frames(5)
	var b := "barracks"
	var k := EconomyScript.soldier_key("infantry", Economy.train_tier(b))
	# 훈련 → 수령 ×5
	for i in 5:
		var before := _cli()
		_check(Economy.start_training(b, 1), "train #%d sent" % (i + 1), Economy.train_block(b, 1))
		var pred := _cli()
		var cost := Economy.train_cost_now("infantry", 1, Economy.train_tier(b))
		_check(pred.training.has(b) and int(pred.res.food) == int(before.res.food) - int(cost.get("food", 0)), "train #%d: queue and cost shown at once" % (i + 1), str([pred.training, cost]))
		await _settle()
		await _same_as_server("train #%d" % (i + 1), ["res", "training", "soldiers"], pred, ["res"])
		var n0 := _notes.size()
		_check(not Economy.start_training(b, 1) and _notes.slice(n0).has(EconomyScript.TRAIN_TEXT.training), "train while training: notice", str(_notes.slice(n0)))
		Economy.finish_training_now(b)
		_check(await _wait_until(func(): return Economy.training(b).ready, 10.0), "training finished (test hook)", str(Economy.training(b)))
		await _settle()
		before = _cli()
		_check(Economy.collect_training(b), "collect #%d sent" % (i + 1), "")
		pred = _cli()
		_check(int(pred.soldiers.get(k, 0)) == int(before.soldiers.get(k, 0)) + 1 and not pred.training.has(b), "collect #%d shown at once" % (i + 1), str(pred.soldiers))
		await _settle()
		await _same_as_server("collect #%d" % (i + 1), ["soldiers", "training", "res"], pred, ["soldiers", "training"])
	# 훈련 취소: 50% 환불
	var before := _cli()
	Economy.start_training(b, 1)
	await _settle()
	var mid := _cli()
	var cost := Economy.train_cost_now("infantry", 1, Economy.train_tier(b))
	Economy.cancel_training(b)
	var pred := _cli()
	var ok := true
	for r in cost:
		ok = ok and int(pred.res[r]) == int(mid.res[r]) + int(cost[r]) / 2
	_check(ok and not pred.training.has(b), "cancel: 50% refund shown at once", str([mid.res, pred.res, cost]))
	await _settle()
	await _same_as_server("cancel training", ["res", "training", "soldiers"], pred, ["res", "training"])
	_check(_notes.has(EconomyScript.CANCEL_TEXT), "cancel notice", "")
	var r := await _post_raw("/v1/soldiers/cancel", {"building": b})
	_check(not r[0] and r[1] == "empty", "server: cancel with nothing → 409 empty", str(r))
	# 배치(병사 창): 자동 배치 → 적용
	var sp = _panel("soldier_panel.gd")
	sp.open()
	await _frames(3)
	sp.auto_button.pressed.emit()
	await _frames(2)
	_check(int(sp.work.get(k, 0)) == mini(5, Economy.population()), "soldier auto deploy: %d" % mini(5, Economy.population()), str(sp.work))
	sp.apply_button.pressed.emit()
	pred = _cli()
	_check(pred.soldier_deploy == sp.work, "soldier deploy shown at once", str(pred.soldier_deploy))
	await _settle()
	await _same_as_server("soldier deploy", ["soldiers", "soldier_deploy"], pred, ["soldier_deploy"])
	await _snap()
	# 합성 5 → 1(배치는 보유로 잘린다)
	var up := EconomyScript.soldier_key("infantry", Economy.train_tier(b) + 1)
	before = _cli()
	sp.merge(k)
	pred = _cli()
	_check(int(pred.soldiers.get(k, 0)) == int(before.soldiers.get(k, 0)) - 5 and int(pred.soldiers.get(up, 0)) == 1 and int(pred.soldier_deploy.get(k, 0)) == 0,
		"merge 5→1 shown at once, deploy trimmed", str([pred.soldiers, pred.soldier_deploy]))
	await _settle()
	await _same_as_server("merge soldiers", ["soldiers", "soldier_deploy"], pred, ["soldiers", "soldier_deploy"])
	var n0 := _notes.size()
	_check(not Economy.merge_soldiers("infantry", Economy.train_tier(b)) and _notes.slice(n0).has(EconomyScript.SOLDIER_TEXT.not_enough), "merge without 5: notice", str(_notes.slice(n0)))
	r = await _post_raw("/v1/soldiers/merge", {"type": "infantry", "tier": Economy.train_tier(b)})
	_check(not r[0] and r[1] == "not_enough", "server: merge 409 not_enough", str(r))
	# 직접 배치(set_soldier_deploy)·인구 초과
	Economy.set_soldier_deploy({up: 1})
	await _settle()
	await _same_as_server("set_soldier_deploy", ["soldier_deploy"])
	n0 = _notes.size()
	_check(not Economy.set_soldier_deploy({up: 2}) and _notes.slice(n0).has(EconomyScript.SOLDIER_TEXT.not_owned), "deploying more than owned: notice", str(_notes.slice(n0)))
	sp.close()
	_no_rollback("soldiers")


# --- 주머니·오프라인 보상·상인 ---

func _pouches_offline_merchant() -> void:
	print("== pouches / offline / merchant")
	var pp = _panel("pouch_panel.gd")
	pp.open()
	await _frames(5)
	await _snap()
	var id := "gold_60"
	if Economy.pouch_count(id) < 4:  # --only로 이 묶음만 돌릴 때
		await _post("/v1/test/grant_diamonds", {"amount": 1000})
		for sid in ["d_free", "d_pouch_gold", "d_pouch_gold", "d_pouch_gold"]:
			Economy.buy_shop(sid)
			await _settle()
		pp._rebuild()
		await _frames(3)
	var have := Economy.pouch_count(id)
	_check(have >= 4, "gold pouches from the shop: %d" % have, str(Economy.pouches))
	var one := Economy.pouch_value(id, GameState.stage)
	var before := _cli()
	pp.buttons["open:" + id].pressed.emit()
	var pred := _cli()
	_check(pred.gold == before.gold + int(one.gold_tenths) and int(pred.pouches.get(id, 0)) == have - 1, "open 1 pouch shown at once (+%d tenths)" % int(one.gold_tenths), str([before.gold, pred.gold]))
	await _settle()
	await _same_as_server("open pouch", ["gold", "pouches", "res"], pred, ["gold", "pouches"])
	await _frames(3)
	have = Economy.pouch_count(id)
	before = _cli()
	pp.buttons["all:" + id].pressed.emit()
	pred = _cli()
	_check(pred.gold == before.gold + int(one.gold_tenths) * have and not pred.pouches.has(id), "open all (%d) shown at once" % have, str([before.gold, pred.gold, pred.pouches]))
	await _settle()
	await _same_as_server("open all pouches", ["gold", "pouches", "res"], pred, ["gold", "pouches"])
	var rid := "res_60"
	if Economy.pouch_count(rid) == 0:
		Economy.buy_shop("d_pouch_res")
		await _settle()
	before = _cli()
	var rv := Economy.pouch_value(rid, GameState.stage)
	Economy.open_pouch(rid, 1, GameState.stage)
	pred = _cli()
	_check(int(pred.res.wood) == int(before.res.wood) + int(rv.res.get("wood", 0)), "resource pouch shown at once", str([rv, before.res, pred.res]))
	await _settle()
	await _same_as_server("open res pouch", ["gold", "pouches", "res"], pred, ["pouches", "res"])
	pp.close()
	# 오프라인 보상: 지난 활동을 2시간 앞당기고 정산
	await _post("/v1/test/away", {"minutes": 120})
	before = _cli()
	var off = _panel("offline_panel.gd")
	_offline = {}
	Economy.claim_offline(GameState.stage)
	_check(await _wait_until(func(): return off.visible, 10.0), "offline reward window opens", "")
	await _settle()
	var after := _cli()
	var shown := int(off.gold_label.text.replace("+", "").replace(" 골드", "").replace(",", ""))
	_check(float(_offline.get("away_sec", 0.0)) >= 7200.0 and float(_offline.get("away_sec", 0.0)) < 7300.0, "offline away ≈ 2 h", str(_offline))
	var expect: Dictionary = EconomyScript.offline_reward(float(_offline.get("away_sec", 0.0)), Economy.server_stage, Economy.kill_tenths(EconomyScript.OFFLINE_KIND, Economy.server_stage))
	_check(after.gold - before.gold == int(expect.tenths) and shown == int(expect.tenths) / 10, "offline gold = app formula (%d tenths)" % int(expect.tenths),
		str([after.gold - before.gold, expect, off.gold_label.text, off.kills_label.text]))
	await _snap()
	await _same_as_server("offline reward", ["gold"])
	off.ok_button.pressed.emit()
	Economy.claim_offline(GameState.stage)  # 곧바로 다시: 두 번 받지 않는다
	await _wait_sec(1.0)
	await _settle()
	_check(not off.visible and _cli().gold == after.gold, "claiming again right away gives nothing", str([after.gold, _cli().gold]))
	# 상인: 수량 판매(선택 판매)·전부 판매
	await _post("/v1/test/levels", {"res": {"wood": 20000, "stone": 15000, "food": 12000}})
	await _frames(3)
	var mp = _panel("merchant_panel.gd")
	mp.open()
	await _frames(5)
	mp._toggle_qty("wood")
	mp._toggle_qty("stone")
	mp.qty_inputs["wood"].set_value(5000)
	mp.qty_inputs["stone"].set_value(3000)
	await _frames(2)
	var now := Economy.time_now()
	var g := Economy.sell_gold("wood", 5000, Economy.current_rate("wood", now)) + Economy.sell_gold("stone", 3000, Economy.current_rate("stone", now))
	await _snap()
	before = _cli()
	mp.sell_selected_button.pressed.emit()
	pred = _cli()
	_check(pred.gold == before.gold + g * 10 and int(pred.res.wood) == 15000 and int(pred.res.stone) == 12000, "sell selected shown at once (+%d gold)" % g, str([before.gold, pred.gold, pred.res]))
	await _settle()
	await _same_as_server("merchant sell selected", ["gold", "res"], pred, ["gold", "res"])
	now = Economy.time_now()
	g = 0
	for r in ["wood", "stone", "food"]:
		g += Economy.sell_gold(r, int(Economy.res[r]), Economy.current_rate(r, now))
	before = _cli()
	mp.sell_all_button.pressed.emit()
	pred = _cli()
	_check(pred.gold == before.gold + g * 10 and int(pred.res.wood) == 0 and int(pred.res.food) == 0, "sell all shown at once (+%d gold)" % g, str([before.gold, pred.gold]))
	mp.sell_all_button.pressed.emit()  # 응답 전 재탭은 무시
	await _settle()
	await _same_as_server("merchant sell all", ["gold", "res"], pred, ["gold", "res"])
	Economy.sell("wood", Economy.time_now(), 10)  # 0개 판매: 아무 일 없음
	await _settle()
	await _same_as_server("selling with nothing", ["gold", "res"])
	mp.close()
	_no_rollback("pouch/offline/merchant")


# --- 비교 ---

## 앱 상태를 서버 모양으로(비교용). 숫자는 정수로.
func _cli() -> Dictionary:
	var h := {}
	for id in Economy.heroes:
		h[id] = [int(Economy.heroes[id]), Economy.level_of(id), Economy.shards_of(id), Economy.promotion_of(id)]
	var tr := {}
	for b in Economy.train_queues:
		var q: Dictionary = Economy.train_queues[b]
		tr[b] = [int(q.count), int(q.get("tier", 1))]
	var keys := {}
	for t in GameData.DUNGEON_TYPES:
		keys[t] = int(Economy.dungeon_state(t).keys)
	return _norm({"gold": Economy.gold_tenths, "diamonds": Economy.diamonds, "tickets": Economy.dia_tickets,
		"gacha": [Economy.gacha_gold_level, Economy.gacha_gold_pulls, Economy.gacha_dia_pity], "heroes": h, "deploy": Economy.deploy,
		"res": Economy.res, "pouches": Economy.pouches, "speedups": Economy.speedups, "soldiers": Economy.soldiers,
		"soldier_deploy": Economy.soldier_deployed, "training": tr, "items": Economy.bag.map(func(x): return int(x.id)),
		"equipment": Economy.equipment, "upgrades": Economy.upgrades, "keys": keys,
		"shop": ShopItems.ITEMS.map(func(x): return Economy.shop_left(x.id)), "iap": _iap_norm(Economy.iap_view())})


func _srv(p: Dictionary) -> Dictionary:
	var h := {}
	for id in p.get("heroes", {}):
		var v: Dictionary = p.heroes[id]
		h[id] = [v.copies, v.level, v.shards, v.promotion]
	var tr := {}
	for b in p.get("training", {}):
		var q = p.training[b]
		if q is Dictionary:
			tr[b] = [q.count, q.get("tier", 1)]
	var keys := {}
	for t in GameData.DUNGEON_TYPES:
		keys[t] = int(p.get("dungeons", {}).get(t, {}).get("keys", 0))
	var sh: Dictionary = p.get("shop", {})
	var shop := ShopItems.ITEMS.map(func(x): return maxi(0, int(x.limit) - int(sh.get("w" if x.tab == "weekly" else "d", {}).get(x.id, 0))))
	var g: Dictionary = p.get("gacha", {})
	var pz := {}
	for k in p.get("pouches", {}):
		if int(p.pouches[k]) > 0:
			pz[k] = p.pouches[k]
	var sz := {}
	for k in p.get("speedups", {}):
		if int(p.speedups[k]) > 0:
			sz[k] = p.speedups[k]
	return _norm({"gold": p.get("gold_tenths"), "diamonds": p.get("diamonds"), "tickets": p.get("dia_tickets"),
		"gacha": [g.get("gold_level"), g.get("gold_pulls"), g.get("dia_pity")], "heroes": h, "deploy": p.get("deploy"),
		"res": p.get("res"), "pouches": pz, "speedups": sz, "soldiers": p.get("soldiers"), "soldier_deploy": p.get("soldier_deploy"),
		"training": tr, "items": p.get("items", []).map(func(x): return int(x.id)), "equipment": p.get("equipment"), "upgrades": p.get("upgrades"),
		"keys": keys, "shop": shop, "iap": _iap_norm(p.get("iap", {}))})


func _iap_norm(s: Dictionary) -> Dictionary:
	var m := {}
	var mon = s.get("monthly", {})
	if mon is Dictionary:
		for id in mon:
			m[id] = [mon[id].get("until"), mon[id].get("claimed")]
	var gp = s.get("gp", {})
	var passes: Array = s.get("passes", []) if s.get("passes") is Array else []
	passes = passes.duplicate()
	passes.sort()
	return {"passes": passes, "free": _sorted(gp.get("free", []) if gp is Dictionary else []), "paid": _sorted(gp.get("paid", []) if gp is Dictionary else []),
		"monthly": m, "first": _sorted(s.get("first", []) if s.get("first") is Array else [])}


static func _sorted(a: Array) -> Array:
	var out := a.map(func(x): return int(x) if (x is float or x is int) else x)
	out.sort()
	return out


## 숫자(정수 값의 float) → int, 사전은 그대로 재귀.
static func _norm(v):
	if v is float and v == floorf(v):
		return int(v)
	if v is Dictionary:
		var out := {}
		for k in v:
			out[str(k)] = _norm(v[k])
		return out
	if v is Array:
		return v.map(func(x): return _norm(x))
	return v


static func _js(v) -> String:
	return JSON.stringify(v, "", true)


## 지금 앱 상태(after)·누른 즉시 예측(pred의 pred_keys)이 새로 받은 서버 상태와 같은지.
func _same_as_server(what: String, keys: Array, pred := {}, pred_keys: Array = []) -> void:
	var k0 := _kills
	var p := await _get_player()
	_check(not p.is_empty(), what + ": GET /v1/player", "")
	if p.is_empty():
		return
	var srv := _srv(p)
	var cli := _cli()
	var diff := []
	for k in keys:
		if k == "gold" and _kills != k0:
			continue
		if _js(cli.get(k)) != _js(srv.get(k)):
			diff.append("%s app=%s server=%s" % [k, _js(cli.get(k)), _js(srv.get(k))])
	_check(diff.is_empty(), what + ": app = server " + str(keys), "; ".join(diff))
	if pred.is_empty():
		return
	diff = []
	for k in pred_keys:
		if k == "gold" and _kills != k0:
			continue
		if _js(pred.get(k)) != _js(srv.get(k)):
			diff.append("%s predicted=%s server=%s" % [k, _js(pred.get(k)), _js(srv.get(k))])
	_check(diff.is_empty(), what + ": prediction = server " + str(pred_keys), "; ".join(diff))


func _no_rollback(what: String) -> void:
	var bad := _notes.filter(func(s): return s in FAIL_TEXTS)
	_check(bad.is_empty(), what + ": no rollback notice", str(bad))


## 응답 대기·즉시 반영·보낼 요청이 모두 끝날 때까지.
func _settle() -> void:
	var ok := await _wait_until(_quiet, 20.0)
	if not ok:
		_check(false, "settle", str([Economy._hold, Economy._predicts.keys(), Economy._waiting.keys(), Net._queue.size()]))
	await _frames(3)


func _quiet() -> bool:
	return Economy._hold == 0 and Economy._predicts.is_empty() and Economy._waiting.is_empty() and Economy._key_predicts.is_empty() \
		and Economy._equip_predicts.is_empty() and Net._queue.is_empty() and not Net._busy


func _get_player() -> Dictionary:
	var box := [null]
	Net.send("GET", "/v1/player", null, func(d): box[0] = d, func(): box[0] = {})
	await _wait_until(func(): return box[0] != null, 15.0)
	return box[0].get("player", {}) if box[0] is Dictionary else {}


## 테스트 훅·응답을 앱에 반영.
func _post(path: String, body) -> void:
	var done := [false]
	Net.send("POST", path, body, func(d):
		if d is Dictionary and d.has("player"):
			Economy.apply_server(d)
		done[0] = true, func(): done[0] = true)
	await _wait_until(func(): return done[0], 15.0)
	await _frames(2)


## 서버에 직접(앱 상태는 건드리지 않는다): [성공?, 오류 코드].
func _post_raw(path: String, body) -> Array:
	var box := [null]
	Net.send("POST", path, body, func(_d): box[0] = [true, ""], func(): box[0] = [false, Net.last_error], true, true)
	await _wait_until(func(): return box[0] != null, 15.0)
	if box[0][0]:
		Net.refresh()
		await _wait_sec(0.5)
	return box[0] if box[0] != null else [false, "timeout"]


## 비교를 흔들지 않게 성 전투(몬스터 생성·황금 고블린)를 멈춘다.
func _stop_battle() -> void:
	for c in _main.get_children():
		var s = c.get_script()
		if s != null and (s.resource_path.ends_with("spawner.gd") or s.resource_path.ends_with("goblin_director.gd")):
			c.queue_free()


func _panel(file: String):
	for c in _main.get_children():
		var s = c.get_script()
		if s != null and s.resource_path.ends_with("/" + file):
			return c
	return null


func _finish() -> void:
	if _fails > 0:
		print("ECONOMY ONLINE FAILED %d" % _fails)
		get_tree().quit(1)
	else:
		print("ECONOMY ONLINE PASSED")
		get_tree().quit(0)


func _check(ok: bool, what: String, detail: String) -> void:
	print(("PASS " if ok else "FAIL ") + what + ("" if ok else "  " + detail))
	if not ok:
		_fails += 1


func _sheet() -> void:
	var out := "/tmp/journey_economy_online.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	if _shots.is_empty() or _shots[0] == null:
		return
	var w: int = _shots[0].get_width() / 2
	var h: int = _shots[0].get_height() / 2
	var sheet := Image.create(w * mini(_shots.size(), 8), h * ceili(_shots.size() / 8.0), false, Image.FORMAT_RGB8)
	for i in _shots.size():
		var img: Image = _shots[i]
		img.convert(Image.FORMAT_RGB8)
		img.save_png(out.get_basename() + "_%d.png" % (i + 1))
		img.resize(w, h, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(img, Rect2i(0, 0, w, h), Vector2i(w * (i % 8), h * (i / 8)))
	sheet.save_png(out)


func _snap() -> void:
	await _frames(8)
	_shots.append(get_viewport().get_texture().get_image())


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _wait_sec(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _wait_until(cond: Callable, timeout_sec: float) -> bool:
	var end := Time.get_ticks_msec() + int(timeout_sec * 1000.0)
	while not cond.call():
		if Time.get_ticks_msec() > end:
			return false
		await get_tree().process_frame
	return true
