extends Node
## 운영 도구(2026-10-12, 서버 server/src/live_ops.ts). 오토로드 LiveOps — 온라인 전용.
## - 공지사항: GET /v1/notices(로딩 일괄 조회 /v1/boot에도). 새 공지(지금 가장 큰 id > 기기에 저장한 notice_seen)가 있으면 성 화면이 뜬 뒤
##   공지 창(notice_panel.gd)을 한 번 띄운다. [공지] 메뉴에 빨간 점.
## - 우편함: GET /v1/mail(일괄 조회에도), [받기]·[모두 받기] → POST /v1/mail/claim {ids}. 누르면 곧바로 목록에서 빠지고 골드·자원·다이아·
##   모집권·주머니가 바로 오른다(Economy.predict_reward — 영웅·장비·열쇠는 응답 때). 거절되면 되돌리고 알린다. [우편] 메뉴에 빨간 점.
## - 쿠폰: POST /v1/coupon {code} → 결과를 done(ok, 글)로(설정 창 [쿠폰 입력] → coupon_panel.gd).
## - 점검·강제 업데이트: Net이 503 maintenance·426 update_required를 받으면 block()을 부른다 → 화면 전체를 덮는 안내(ops_overlay.gd).
##   점검은 서버가 다시 답하면(Net._on_completed ok) 걷힌다. 업데이트는 [업데이트](스토어 주소, 웹이면 새로 고침)만 남는다.
## - 고객 문의(2026-10-14, server/src/inquiry.ts): 설정 [문의하기] → 문의 창(inquiry_panel.gd). [보내기]를 누르면 곧바로 내 문의 목록 맨 위에
##   "답변 대기"로 들어가고 입력 칸이 비워진다(POST /v1/inquiry — 보낼 때마다 만든 key로 연타·재전송이 두 번 쌓이지 않는다).
##   거절되면 목록에서 빼고 쓴 글을 돌려준다(inquiry_failed). 답변은 우편([문의 답변])으로 오고, 문의 창 목록에도 보인다.
## 앱 버전(프로젝트 설정 application/config/version)은 Net이 모든 요청에 X-App-Version으로 보낸다.

const Lang := preload("res://scripts/lang.gd")

const ReleasePlatform := preload("res://scripts/release_platform.gd")
const Prefs := preload("res://scripts/prefs.gd")
const OverlayScript := preload("res://scripts/ops_overlay.gd")
const GameData := preload("res://scripts/game_data.gd")
const UiKit := preload("res://scripts/ui_kit.gd")

signal changed  # 공지·우편 목록이 바뀌었다
signal inquiry_failed(category: String, text: String)  # 문의를 못 보냈다(문의 창이 쓴 글을 되돌린다)
signal block_changed  # 점검·업데이트 안내가 생기거나 걷혔다

const SEEN_KEY := "notice_seen"
static var KEY_NAMES := {"gold": Lang.t("live_ops.key_names.gold"), "equip": Lang.t("live_ops.key_names.equip"), "ticket": Lang.t("live_ops.key_names.ticket")}
const MAIL_POLL_SEC := 300.0  # 창을 안 열어도 이만큼마다 우편을 다시 본다(관리자가 보낸 보상 빨간 점)
static var INQUIRY_TEXT := {"too_many_inquiries": Lang.t("live_ops.inquiry_text.too_many_inquiries")}
static var COUPON_TEXT := {"unknown_coupon": Lang.t("live_ops.coupon_text.unknown_coupon"), "coupon_used": Lang.t("live_ops.coupon_text.coupon_used"), "coupon_expired": Lang.t("live_ops.coupon_text.coupon_expired"),
	"coupon_used_up": Lang.t("live_ops.coupon_text.coupon_used_up"), "coupon_not_started": Lang.t("live_ops.coupon_text.coupon_not_started")}

var notices: Array = []  # [{id, title, body, kind, pinned, at}]
var mails: Array = []  # [{id, title, body, reward, at, expires}] — 받는 중인 것은 빠져 있다
var notices_loaded := false
var mail_loaded := false
var block := {}  # {} 또는 {kind: "maintenance"|"update", text, until, store_url}
var overlay  # ops_overlay.gd
var claiming := {}  # 받는 중 key → [우편들](거절되면 되돌린다)
var redeeming := false
var inquiries: Array = []  # 내 문의 [{id, category, body, status, answer, at, answered_at}] — 보내는 중인 것은 id < 0, pending
var inquiries_loaded := false

var _poll := MAIL_POLL_SEC
var _seq := 0


func _ready() -> void:
	Net.booted.connect(_on_booted)
	overlay = OverlayScript.new()
	add_child(overlay)


static func app_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", ""))


func _process(delta: float) -> void:
	if not Net.ready_once or not Net.up:
		return
	_poll -= delta / maxf(Engine.time_scale, 0.01)
	if _poll <= 0.0:
		_poll = MAIL_POLL_SEC
		fetch_mail()


func _on_booted(d: Dictionary) -> void:
	if d.get("notices") is Dictionary:
		_on_notices(d.notices)
	if d.get("mail") is Dictionary:
		_on_mail(d.mail)


func fetch_notices() -> void:
	if Net.is_online() and Net.up:
		Net.send("GET", "/v1/notices", null, _on_notices, Callable(), false)


func fetch_mail() -> void:
	if Net.is_online() and Net.up:
		_poll = MAIL_POLL_SEC
		Net.send("GET", "/v1/mail", null, _on_mail)


func _on_notices(d: Dictionary) -> void:
	if d.get("notices") is Array:
		notices = d.notices.filter(func(n): return n is Dictionary)
		notices_loaded = true
		changed.emit()


func _on_mail(d: Dictionary) -> void:
	if not d.get("mails") is Array:
		return
	var busy := {}
	for k in claiming:
		for m in claiming[k]:
			busy[int(m.id)] = true
	mails = d.mails.filter(func(m): return m is Dictionary and not busy.has(int(m.get("id", 0))))
	mail_loaded = true
	changed.emit()


## 가장 새 공지 id(없으면 0).
func latest_notice() -> int:
	var best := 0
	for n in notices:
		best = maxi(best, int(n.get("id", 0)))
	return best


## 아직 안 본 공지가 있다(빨간 점·성 화면에서 자동으로 띄우기).
func has_unseen() -> bool:
	return latest_notice() > int(Prefs.get_float(SEEN_KEY, 0.0))


func mark_seen() -> void:
	if has_unseen():
		Prefs.set_value(SEEN_KEY, latest_notice())
		changed.emit()


## 받을 우편 수(빨간 점).
func mail_count() -> int:
	return mails.size()


## 우편 받기(ids가 비면 전부). 곧바로 목록에서 빼고 보상을 보인다. 보냈으면 true.
func claim(ids: Array = []) -> bool:
	if not Net.up:
		Economy.notice.emit(Lang.t("live_ops.claim"))
		return false
	var take := mails.filter(func(m): return ids.is_empty() or ids.has(int(m.id)))
	if take.is_empty():
		return false
	_seq += 1
	var key := "mail:%d" % _seq
	claiming[key] = take
	var send_ids: Array = take.map(func(m): return int(m.id))
	mails = mails.filter(func(m): return not send_ids.has(int(m.id)))
	Economy.predict_reward(key, sum_rewards(take))
	var text := reward_text(sum_rewards(take))
	Economy.notice.emit((Lang.t("live_ops.claim_2") if take.size() == 1 else Lang.t("live_ops.claim_3") % take.size()) + ("" if text == "" else ": " + text))
	changed.emit()
	Net.send("POST", "/v1/mail/claim", {"ids": send_ids}, _on_claimed.bind(key), _on_claim_failed.bind(key), true, true)
	return true


func _on_claimed(d: Dictionary, key: String) -> void:
	claiming.erase(key)
	Economy.settle(key)
	Economy.apply_server(d)
	var r = d.get("reward")
	if r is Dictionary and r.get("items") is Array and not r.items.is_empty():
		Economy.notice.emit(Lang.t("live_ops.on_claimed") % r.items.size())
	changed.emit()


func _on_claim_failed(key: String) -> void:
	var back: Array = claiming.get(key, [])
	claiming.erase(key)
	Economy.unpredict(key)
	if Net.last_error == "claimed":
		Economy.notice.emit(Lang.t("live_ops.on_claim_failed"))
	else:
		mails = back + mails  # 되돌린다
		mails.sort_custom(func(a, b): return float(a.get("at", 0)) > float(b.get("at", 0)))
		Economy.notice.emit(Lang.t("live_ops.on_claim_failed_2"))
	Net.refresh()
	fetch_mail()
	changed.emit()


## 쿠폰 사용. done(ok: bool, text: String). 보냈으면 true.
func redeem(code: String, done: Callable) -> bool:
	var c := code.strip_edges().to_upper().replace("-", "").replace(" ", "")
	if c.length() < 4:
		done.call(false, Lang.t("live_ops.redeem"))
		return false
	if not Net.up or redeeming:
		done.call(false, Lang.t("live_ops.redeem_2"))
		return false
	redeeming = true
	Net.send("POST", "/v1/coupon", {"code": c}, func(d: Dictionary):
		redeeming = false
		Economy.apply_server(d)
		var r = d.get("reward")
		var text := reward_text(r) if r is Dictionary else ""
		done.call(true, Lang.t("live_ops.redeem_3") + ("" if text == "" else ": " + text)),
		func():
			redeeming = false
			done.call(false, COUPON_TEXT.get(Net.last_error, Lang.t("live_ops.redeem_4"))),
		true, true)
	return true


## 우편 보상 여러 개를 하나로(숫자 키는 더한다, 영웅·장비는 개수). 응답 전 표시용.
static func sum_rewards(list: Array) -> Dictionary:
	var out := {}
	for m in list:
		var r = m.get("reward") if m is Dictionary else null
		if not r is Dictionary:
			continue
		for k in r:
			if k == "hero":
				var heroes: Dictionary = out.get("heroes", {})
				heroes[str(r.hero)] = int(heroes.get(str(r.hero), 0)) + int(r.get("hero_n", 1))
				out["heroes"] = heroes
			elif k == "equip" and r.equip is Dictionary:
				var eq: Dictionary = out.get("equips", {})
				eq[str(r.equip.get("grade", ""))] = int(eq.get(str(r.equip.get("grade", "")), 0)) + int(r.equip.get("n", 1))
				out["equips"] = eq
			elif k != "hero_n" and (r[k] is int or r[k] is float):
				out[k] = int(out.get(k, 0)) + int(r[k])
	return out



## 보상 풀어 쓰기("골드 5,000 + 다이아 300 + SSR 장비 2개 …"). 우편(hero·hero_n·equip{grade,n})·합친 것(heroes·equips)·
## 서버 응답 got(heroes·items) 모두 읽는다.
static func reward_text(r: Dictionary) -> String:
	var parts: Array = []
	var heroes: Dictionary = r.get("heroes", {}) if r.get("heroes") is Dictionary else {}
	if r.has("hero"):
		heroes = {str(r.hero): int(r.get("hero_n", 1))}
	for id in heroes:
		var h: Dictionary = GameData.hero(str(id))
		var n := int(heroes[id])
		parts.append(Lang.t("live_ops.reward_text") % [h.get("grade", ""), h.get("name", str(id))] + ("" if n == 1 else Lang.t("live_ops.reward_text_2") % n))
	if r.get("equip") is Dictionary:
		parts.append(Lang.t("live_ops.reward_text_3") % [r.equip.get("grade", ""), int(r.equip.get("n", 1))])
	if r.get("equips") is Dictionary:
		for g in r.equips:
			parts.append(Lang.t("live_ops.reward_text_3") % [g, int(r.equips[g])])
	if r.get("items") is Array and not r.has("equip") and not r.has("equips"):
		parts.append(Lang.t("live_ops.reward_text_4") % r.items.size())
	for k in [["gold", Lang.t("live_ops.reward_text_5")], ["diamonds", Lang.t("live_ops.reward_text_6")], ["wood", Lang.t("live_ops.reward_text_7")], ["stone", Lang.t("live_ops.reward_text_8")], ["food", Lang.t("live_ops.reward_text_9")]]:
		if int(r.get(k[0], 0)) > 0:
			parts.append("%s %s" % [k[1], UiKit.commas(int(r[k[0]]))])
	if int(r.get("tickets", 0)) > 0:
		parts.append(Lang.t("live_ops.reward_text_10") % int(r.tickets))
	for t in KEY_NAMES:
		if int(r.get("keys_" + t, 0)) > 0:
			parts.append(Lang.t("live_ops.reward_text_11") % [KEY_NAMES[t], int(r["keys_" + t])])
	var pz := Economy.pouches_in(r)
	for id in Economy.pouch_ids():
		if pz.has(id):
			parts.append(Economy.pouch_name(id) + ("" if int(pz[id]) == 1 else Lang.t("live_ops.reward_text_12") % int(pz[id])))
	parts.append_array(Economy.speedup_reward_parts(r))  # 2026-10-13 가속 아이템·일꾼 고용권
	return " + ".join(parts)



# --- 점검·업데이트(Net이 부른다) ---

## 서버가 점검(503 maintenance) 또는 업데이트 필요(426 update_required)라고 답했다.
func on_blocked(code: int, data: Dictionary) -> void:
	var b := {}
	if code == 426:
		b = {"kind": "update", "text": Lang.t("live_ops.on_blocked.text"), "min_version": str(data.get("min_version", "")),
			"store_url": str(data.get("store_url", ""))}
	else:
		var until = data.get("until")
		b = {"kind": "maintenance", "text": str(data.get("message", "")), "until": float(until) if until is float or until is int else 0.0}
	if b != block:
		block = b
		block_changed.emit()


## 서버가 다시 정상으로 답했다 — 점검 안내를 걷는다(업데이트 안내는 남는다: 앱을 바꿔야 한다).
func on_ok() -> void:
	if not block.is_empty() and block.get("kind") == "maintenance":
		block = {}
		block_changed.emit()


func is_blocked() -> bool:
	return not block.is_empty()


# --- 고객 문의 ---

func fetch_inquiries() -> void:
	if Net.is_online() and Net.up:
		Net.send("GET", "/v1/inquiry", null, func(d: Dictionary):
			if d.get("inquiries") is Array:
				var pending := inquiries.filter(func(q): return q.get("pending", false))
				inquiries = pending + d.inquiries.filter(func(q): return q is Dictionary)
				inquiries_loaded = true
				changed.emit())


## 앱이 문의에 붙이는 플레이어 정보(친구 코드는 서버가 안다).
static func inquiry_info() -> Dictionary:
	return {"name": str(Economy.friends.get("name", "")), "login": Net.auth_mode, "version": app_version(),
		"platform": ReleasePlatform.current(), "device": ("%s %s" % [OS.get_name(), OS.get_model_name()]).strip_edges()}


## 문의 보내기. 곧바로 목록 맨 위에 넣는다. 보냈으면 true(글이 비었거나 서버가 없으면 false — 알림을 띄운다).
func send_inquiry(category: String, text: String) -> bool:
	var t := text.strip_edges()
	if t == "":
		Economy.notice.emit(Lang.t("live_ops.send_inquiry"))
		return false
	if not Net.up:
		Economy.notice.emit(Lang.t("live_ops.send_inquiry_2"))
		return false
	_seq += 1
	var key := "q%d-%d-%d" % [int(Time.get_unix_time_from_system()), _seq, randi() % 100000]
	var q := {"id": -_seq, "key": key, "category": category, "body": t, "status": "open", "answer": "", "at": Economy.time_now(), "pending": true}
	inquiries.push_front(q)
	Economy.notice.emit(Lang.t("live_ops.send_inquiry_3"))
	changed.emit()
	Net.send("POST", "/v1/inquiry", {"key": key, "category": category, "body": t, "info": inquiry_info()}, func(d: Dictionary):
		var i := inquiries.find(q)
		if d.get("inquiry") is Dictionary:
			if i >= 0:
				inquiries[i] = d.inquiry
		elif i >= 0:
			inquiries.remove_at(i)
		changed.emit(),
		func():
			inquiries.erase(q)
			Economy.notice.emit(INQUIRY_TEXT.get(Net.last_error, Lang.t("live_ops.send_inquiry_4")))
			inquiry_failed.emit(category, t)
			changed.emit(),
		true, true)
	return true
