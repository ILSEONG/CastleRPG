extends RefCounted
## 출시 플랫폼(2026-10-07). 빌드마다 하나:
## - google_play: 안드로이드 APK. 로그인 화면 = Google·카카오·네이버 + 게스트. 결제는 Google Play 결제(연결 전).
## - apps_in_toss: 토스 앱 안 미니앱(웹 묶음, apps-in-toss/). 로그인 화면 없음 — 토스 게임 로그인(getUserKeyForGame hash)으로 바로 시작
##   (앱인토스 게임 출시 가이드: 사용자 식별키로 식별, 진입하자마자 로그인 시트를 띄우지 않는다). 결제는 토스 인앱 결제(연결 전).
## 값: 프로젝트 설정 castle/platform. 앱인토스 내보내기 프리셋(피처 태그 apps_in_toss)이 castle/platform.apps_in_toss로 덮어쓴다.

const GOOGLE_PLAY := "google_play"
const APPS_IN_TOSS := "apps_in_toss"

static var override := ""  # 테스트가 바꾼다


static func current() -> String:
	if override != "":
		return override
	return APPS_IN_TOSS if str(ProjectSettings.get_setting_with_override("castle/platform")) == APPS_IN_TOSS else GOOGLE_PLAY


static func is_toss() -> bool:
	return current() == APPS_IN_TOSS


## 이 빌드 로그인 화면의 소셜 버튼(앱인토스는 화면 없이 토스 로그인).
static func login_providers() -> Array:
	return [] if is_toss() else ["google", "kakao", "naver"]


## 결제 상품을 눌렀는데 아직 결제가 연결되지 않았을 때의 안내.
static func iap_off_text() -> String:
	return "결제는 토스 출시 후 열려요" if is_toss() else "결제는 Google Play 출시 후 열려요"


## 웹 주소의 쿼리 문자열(eval 없이 — 앱인토스 보안 기준). 웹이 아니면 "".
static func web_query() -> String:
	if not OS.has_feature("web"):
		return ""
	var loc = JavaScriptBridge.get_interface("location")
	return "" if loc == null else str(loc.search)
