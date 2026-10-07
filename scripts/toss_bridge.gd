extends Node
## 토스 게임 로그인 다리(앱인토스 빌드). 웹 래퍼(apps-in-toss/src/main.ts)가 window.castleToss.getUserKey(cb)를 두고,
## 그 안에서 SDK getUserKeyForGame()을 불러 cb(hash 또는 실패 코드)를 부른다. 실패 코드: "UNSUPPORTED"(토스 앱이 오래됨),
## "INVALID_CATEGORY"(게임 카테고리가 아닌 미니앱), "ERROR", "NO_BRIDGE"(래퍼 밖 — 일반 브라우저).
## 디버그 빌드는 래퍼 밖에서도 시험할 수 있게 ?toss_hash=값(웹)·-- --toss_hash=값(네이티브), 없으면 기기 id로 만든 값을 쓴다.

const ReleasePlatform := preload("res://scripts/release_platform.gd")

signal _answered(result: String)

const HASH_RE := "^[A-Za-z0-9+/=_.:-]{8,512}$"

var _cb: JavaScriptObject  # 콜백이 불리기 전에 사라지지 않게 잡아 둔다


## hash를 받는다(실패면 위 실패 코드). await로 부른다.
func user_key() -> String:
	var api = JavaScriptBridge.get_interface("castleToss") if OS.has_feature("web") else null
	if api == null:
		return _debug_key() if OS.is_debug_build() else "NO_BRIDGE"
	_cb = JavaScriptBridge.create_callback(func(args: Array): _answered.emit(str(args[0]) if args.size() > 0 and args[0] != null else "ERROR"))
	api.getUserKey(_cb)
	var r: String = await _answered
	_cb = null
	if OS.is_debug_build() and not is_hash(r):
		return _debug_key()  # 디버그: 토스 밖 브라우저(SDK가 실패)에서도 시험한다
	return r


static func is_hash(s: String) -> bool:
	return RegEx.create_from_string(HASH_RE).search(s) != null


func _debug_key() -> String:
	var v := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--toss_hash="):
			v = a.substr(12)
	if v == "" and OS.has_feature("web"):
		var q := ReleasePlatform.web_query()
		var i := q.find("toss_hash=")
		if i >= 0:
			v = q.substr(i + 10).get_slice("&", 0)
	return v if v != "" else "dev-" + Net.ensure_device_id()
