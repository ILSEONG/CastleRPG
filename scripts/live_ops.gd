extends Node
## 운영 도구(2026-10-12, 서버 server/src/live_ops.ts). 오토로드 LiveOps — 온라인 전용.
## - 공지사항: GET /v1/notices(로딩 일괄 조회 /v1/boot에도). 새 공지(지금 가장 큰 id > 기기에 저장한 notice_seen)가 있으면 성 화면이 뜬 뒤
##   공지 창(notice_panel.gd)을 한 번 띄운다. [공지] 메뉴에 빨간 점.
## - 우편함: GET /v1/mail(일괄 조회에도), [받기]·[모두 받기] → POST /v1/mail/claim {ids}. 누르면 곧바로 목록에서 빠지고 골드·자원·다이아·
##   모집권·주머니가 바로 오른다(Economy.predict_reward — 영웅·장비·열쇠는 응답 때). 거절되면 되돌리고 알린다. [우편] 메뉴에 빨간 점.
## - 쿠폰: POST /v1/coupon {code} → 결과를 done(ok, 글)로(설정 창 [쿠폰 입력] → coupon_panel.gd).
## - 점검·강제 업데이트: Net이 503 maintenance·426 update_required를 받으면 block()을 부른다 → 화면 전체를 덮는 안내(ops_overlay.gd).
##   점검은 서버가 다시 답하면(Net._on_completed ok) 걷힌다. 업데이트는 [업데이트](스토어 주소, 웹이면 새로 고침)만 남는다.
## 앱 버전(프로젝트 설정 application/config/version)은 Net이 모든 요청에 X-App-Version으로 보낸다.

const Prefs := preload("res://scripts/prefs.gd")
const OverlayScript := preload("res://scripts/ops_overlay.gd")
const GameData := preload("res://scripts/game_data.gd")
const UiKit := preload("res://scripts/ui_kit.gd")

signal changed  # 공지·우편 목록이 바뀌었다
signal block_changed  # 점검·업데이트 안내가 생기거나 걷혔다

const SEEN_KEY := "notice_seen"
const KEY_NAMES := {"gold": "골드 던전 열쇠", "equip": "장비 던전 열쇠", "ticket": "모집권 던전 열쇠"}
const MAIL_POLL_SEC := 300.0  # 창을 안 열어도 이만큼마다 우편을 다시 본다(관리자가 보낸 보상 빨간 점)
const COUPON_TEXT := {"unknown_coupon": "없는 쿠폰 번호입니다", "coupon_used": "이미 사용한 쿠폰입니다", "coupon_expired": "기간이 지난 쿠폰입니다",
	"coupon_used_up": "선착순 수량이 모두 소진된 쿠폰입니다", "coupon_not_started": "아직 사용할 수 없는 쿠폰입니다"}

var notices: Array = []  # [{id, title, body, kind, pinned, at}]
var mails: Array = []  # [{id, title, body, reward, at, expires}] — 받는 중인 것은 빠져 있다
var notices_loaded := false
var mail_loaded := false
var block := {}  # {} 또는 {kind: "maintenance"|"update", text, until, store_url}
var overlay  # ops_overlay.gd
var claiming := {}  # 받는 중 key → [우편들](거절되면 되돌린다)
var redeeming := false

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
		Economy.notice.emit("서버에 연결된 뒤 받을 수 있습니다")
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
	Economy.notice.emit(("우편을 받았습니다" if take.size() == 1 else "우편 %d개를 받았습니다" % take.size()) + ("" if text == "" else ": " + text))
	changed.emit()
	Net.send("POST", "/v1/mail/claim", {"ids": send_ids}, _on_claimed.bind(key), _on_claim_failed.bind(key), true, true)
	return true


func _on_claimed(d: Dictionary, key: String) -> void:
	claiming.erase(key)
	Economy.settle(key)
	Economy.apply_server(d)
	var r = d.get("reward")
	if r is Dictionary and r.get("items") is Array and not r.items.is_empty():
		Economy.notice.emit("장비 %d개가 보관함에 들어갔습니다" % r.items.size())
	changed.emit()


func _on_claim_failed(key: String) -> void:
	var back: Array = claiming.get(key, [])
	claiming.erase(key)
	Economy.unpredict(key)
	if Net.last_error == "claimed":
		Economy.notice.emit("이미 받았거나 기간이 지난 우편입니다")
	else:
		mails = back + mails  # 되돌린다
		mails.sort_custom(func(a, b): return float(a.get("at", 0)) > float(b.get("at", 0)))
		Economy.notice.emit("우편을 받지 못했습니다. 잠시 뒤 다시 시도해 주세요")
	Net.refresh()
	fetch_mail()
	changed.emit()


## 쿠폰 사용. done(ok: bool, text: String). 보냈으면 true.
func redeem(code: String, done: Callable) -> bool:
	var c := code.strip_edges().to_upper().replace("-", "").replace(" ", "")
	if c.length() < 4:
		done.call(false, "쿠폰 번호를 확인해 주세요")
		return false
	if not Net.up or redeeming:
		done.call(false, "서버에 연결된 뒤 사용할 수 있습니다")
		return false
	redeeming = true
	Net.send("POST", "/v1/coupon", {"code": c}, func(d: Dictionary):
		redeeming = false
		Economy.apply_server(d)
		var r = d.get("reward")
		var text := reward_text(r) if r is Dictionary else ""
		done.call(true, "쿠폰 보상을 받았습니다" + ("" if text == "" else ": " + text)),
		func():
			redeeming = false
			done.call(false, COUPON_TEXT.get(Net.last_error, "쿠폰을 사용하지 못했습니다. 잠시 뒤 다시 시도해 주세요")),
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
		parts.append("%s 영웅 %s" % [h.get("grade", ""), h.get("name", str(id))] + ("" if n == 1 else " %d장" % n))
	if r.get("equip") is Dictionary:
		parts.append("%s 장비 %d개" % [r.equip.get("grade", ""), int(r.equip.get("n", 1))])
	if r.get("equips") is Dictionary:
		for g in r.equips:
			parts.append("%s 장비 %d개" % [g, int(r.equips[g])])
	if r.get("items") is Array and not r.has("equip") and not r.has("equips"):
		parts.append("장비 %d개" % r.items.size())
	for k in [["gold", "골드"], ["diamonds", "다이아"], ["wood", "목재"], ["stone", "석재"], ["food", "식량"]]:
		if int(r.get(k[0], 0)) > 0:
			parts.append("%s %s" % [k[1], UiKit.commas(int(r[k[0]]))])
	if int(r.get("tickets", 0)) > 0:
		parts.append("다이아 모집권 %d장" % int(r.tickets))
	for t in KEY_NAMES:
		if int(r.get("keys_" + t, 0)) > 0:
			parts.append("%s %d개" % [KEY_NAMES[t], int(r["keys_" + t])])
	var pz := Economy.pouches_in(r)
	for id in Economy.pouch_ids():
		if pz.has(id):
			parts.append(Economy.pouch_name(id) + ("" if int(pz[id]) == 1 else " %d개" % int(pz[id])))
	return " + ".join(parts)



# --- 점검·업데이트(Net이 부른다) ---

## 서버가 점검(503 maintenance) 또는 업데이트 필요(426 update_required)라고 답했다.
func on_blocked(code: int, data: Dictionary) -> void:
	var b := {}
	if code == 426:
		b = {"kind": "update", "text": "새 버전이 나왔습니다. 업데이트 후 이용해 주세요.", "min_version": str(data.get("min_version", "")),
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
