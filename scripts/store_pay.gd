extends Node
## 실결제(2026-10-12, 오토로드 StorePay). 결제 상품 버튼(Economy.iap_buy)이 부른다.
## - Google Play(APK): 안드로이드 플러그인 CastleBilling(addons/castle_billing, Play Billing 8) — purchase(상품 id, account_tag)로 결제 창.
##   결제되면 purchase_token(상품, 토큰, 상태) → 서버 POST /v1/iap/purchase {product, provider:"google", token}. 서버가 Google에 확인하고
##   지급한 뒤 consume한다(앱은 acknowledge·consume하지 않는다).
## - 토스 인앱 결제(앱인토스 .ait): 래퍼 window.castleToss.buy(sku, onGrant, onDone) — 결제가 끝나면 onGrant(주문 번호) → 같은 서버 요청
##   (provider "toss", token = 주문 번호) → 결과를 castleToss.granted(주문, 지급됨?)로 토스에 알린다.
## - 못 받은 결제 되찾기(restore_once — 첫 /v1/player에서 결제가 열려 있으면 한 번): Google은 consume 안 된 구매(queryPurchases),
##   토스는 지급 대기 주문(pendingOrders)을 다시 서버에 보낸다. 서버는 같은 주문을 두 번 지급하지 않는다(이미 받았으면 {already}).
## - 서버가 아직 확인 중(202 pending)이면 알리고, 다음 접속 때 다시 보낸다. 한도에 걸려 지급하지 못한 Google 결제는 consume되지 않아
##   Google이 3일 뒤 자동 환불한다.
## 결제가 안 열린 경우(서버에 그 플랫폼 결제 키가 없음·플러그인 없음): 알림만(ReleasePlatform.iap_off_text).
## 실결제는 결제 창이 곧바로 뜨는 것 말고는 미리 반영하지 않는다(진짜 돈 — 서버 확인 뒤에 지급).

const ReleasePlatform := preload("res://scripts/release_platform.gd")
const PLUGIN := "CastleBilling"
const DONE_TEXT := "결제가 완료되어 지급했습니다"
const PENDING_TEXT := "결제를 확인하고 있습니다. 확인되면 다음 접속 때 지급됩니다"
const FAIL_TEXT := "결제를 확인하지 못했습니다. 지급되지 않은 결제는 자동으로 환불됩니다"
const OPEN_FAIL_TEXT := "결제 창을 열지 못했습니다. 잠시 뒤 다시 시도해 주세요"
const UNSUPPORTED_TEXT := "토스 앱을 최신 버전으로 업데이트해 주세요"
const PURCHASED := 1  # Google Purchase.PurchaseState
const PENDING := 2
const USER_CANCELED := 1  # Google BillingResponseCode

var fake_store := Callable()  # 테스트: func(상품 id) -> 토큰. 있으면 provider "test"(테스트 훅 서버만 받는다)
var _billing: Object = null  # Google 플러그인
var _restored := false
var _querying := false  # 되찾기(queryPurchases) 결과를 받는 중 — 결제 창 결과와 같은 신호로 온다, 알림 없이
var _sent := {}  # 서버에 보내는 중인 토큰(같은 결제를 겹쳐 보내지 않게)
var _quiet := {}  # 되찾기로 보낸 토큰 — 실패 알림을 띄우지 않는다
var _js_cbs := []  # JavaScriptBridge 콜백이 불리기 전에 사라지지 않게


## 이 빌드의 결제 제공자.
func provider() -> String:
	if fake_store.is_valid():
		return "test"
	return "toss" if ReleasePlatform.is_toss() else "google"


## 지금 결제 창을 열 수 있나(서버가 그 플랫폼 결제를 켰고, 앱에 결제 연결이 있다).
func ready_to_buy() -> bool:
	if fake_store.is_valid():
		return true
	if not Economy.iap_enabled or not provider() in Economy.iap_providers:
		return false
	return _toss() != null if provider() == "toss" else _google() != null


## 결제 상품 사기. 결제 창을 열었으면 true.
func buy(id: String) -> bool:
	if not ready_to_buy():
		Economy.notice.emit(ReleasePlatform.iap_off_text())
		return false
	if not Net.up:
		Economy.notice.emit(Economy.WAIT_TEXT)
		return false
	match provider():
		"test":
			_send(id, "test", str(fake_store.call(id)))
		"google":
			_google().purchase(id, Economy.account_tag)
		"toss":
			_toss_buy(id)
	return true


## 못 받은 결제를 한 번 되찾는다(Economy가 결제가 열린 첫 상태에서 부른다).
func restore_once() -> void:
	if _restored or not ready_to_buy() or fake_store.is_valid():
		return
	_restored = true
	if provider() == "google":
		_querying = true
		_google().queryPurchases()
	else:
		var cb := JavaScriptBridge.create_callback(_on_toss_pending)
		_js_cbs.append(cb)
		_toss().pendingOrders(cb)


## 영수증(토큰·주문 번호)을 서버에 보낸다. answer(지급됨?)는 토스가 쓴다.
func _send(product: String, prov: String, token: String, quiet := false, answer := Callable()) -> void:
	if token == "" or _sent.has(token):
		return
	_sent[token] = true
	if quiet:
		_quiet[token] = true
	Net.send("POST", "/v1/iap/purchase", {"product": product, "provider": prov, "token": token},
		func(d: Dictionary): _on_sent(d, token, answer), func(): _on_send_failed(token, answer))


func _on_sent(d: Dictionary, token: String, answer: Callable) -> void:
	var quiet: bool = _quiet.has(token)
	_sent.erase(token)
	_quiet.erase(token)
	if d.get("pending") == true:
		if not quiet:
			Economy.notice.emit(PENDING_TEXT)
		if answer.is_valid():
			answer.call(false)
		return
	if d.get("already") == true:
		Net.refresh()  # 이미 받은 주문(되찾기) — 상태만 새로
	else:
		Economy.apply_server(d)
		Economy.shop_changed.emit()
		Economy.dungeons_changed.emit()
		Economy.notice.emit(DONE_TEXT)
	if answer.is_valid():
		answer.call(true)


func _on_send_failed(token: String, answer: Callable) -> void:
	if not _quiet.has(token):
		Economy.notice.emit(FAIL_TEXT)
	_sent.erase(token)
	_quiet.erase(token)
	if answer.is_valid():
		answer.call(false)


# --- Google Play(안드로이드 플러그인) ---

func _google() -> Object:
	if _billing == null and Engine.has_singleton(PLUGIN):
		_billing = Engine.get_singleton(PLUGIN)
		_billing.connect("purchase_token", _on_google_token)
		_billing.connect("purchase_error", _on_google_error)
		_billing.connect("purchases_queried", func(_n: int): _querying = false)
		_billing.startConnection()
	return _billing


func _on_google_token(product: String, token: String, state: int) -> void:
	if state == PURCHASED:
		_send(product, "google", token, _querying)
	elif state == PENDING and not _querying:
		Economy.notice.emit(PENDING_TEXT)


func _on_google_error(code: int, message: String) -> void:
	if code == USER_CANCELED:
		return
	push_warning("billing error %d: %s" % [code, message])
	Economy.notice.emit(OPEN_FAIL_TEXT)


# --- 토스 인앱 결제(웹 래퍼) ---

func _toss() -> Object:
	if not OS.has_feature("web"):
		return null
	var api = JavaScriptBridge.get_interface("castleToss")
	return api if api != null and api.buy != null else null


## 우리 상품 id → 토스 콘솔 sku(서버 view.iap_skus.toss, 없으면 같은 id).
func _toss_sku(id: String) -> String:
	var m = Economy.iap_skus.get("toss", {})
	return str(m.get(id, id)) if m is Dictionary else id


func _toss_product(sku: String) -> String:
	var m = Economy.iap_skus.get("toss", {})
	if m is Dictionary:
		for id in m:
			if str(m[id]) == sku:
				return str(id)
	return sku


func _toss_buy(id: String) -> void:
	var api := _toss()
	var on_grant := JavaScriptBridge.create_callback(func(args: Array):
		var order := str(args[0]) if args.size() > 0 else ""
		_send(id, "toss", order, false, func(ok: bool): api.granted(order, ok)))
	var on_done := JavaScriptBridge.create_callback(func(args: Array):
		var kind := str(args[0]) if args.size() > 0 else ""
		var detail := str(args[1]) if args.size() > 1 else ""
		if kind == "error":
			if detail == "UNSUPPORTED":
				Economy.notice.emit(UNSUPPORTED_TEXT)
			elif not detail.to_upper().contains("CANCEL"):
				push_warning("toss iap error: " + detail)
				Economy.notice.emit(OPEN_FAIL_TEXT))
	_js_cbs = [on_grant, on_done]  # 이전 결제의 콜백은 끝났다
	api.buy(_toss_sku(id), on_grant, on_done)


func _on_toss_pending(args: Array) -> void:
	var list = JSON.parse_string(str(args[0])) if args.size() > 0 else null
	if not list is Array:
		return
	var api := _toss()
	for o in list:
		if o is Dictionary and str(o.get("orderId", "")) != "":
			var order := str(o.orderId)
			_send(_toss_product(str(o.get("sku", ""))), "toss", order, true, func(ok: bool):
				if ok:
					api.completeGrant(order))
