extends RefCounted
## 분석 이벤트(2026-10-23, 이탈 기록). 서버 통계(운영 관리 [통계], server/src/retention.ts)와 별개로 플랫폼 분석 도구에도 남긴다.
##  앱인토스(웹): 래퍼 window.castleToss.log(이름, JSON) → 토스 SDK Analytics.log(앱인토스 콘솔에서 본다, apps-in-toss/src/main.ts).
##  Android: Firebase Analytics 플러그인(CastleAnalytics 싱글턴)이 있으면 logEvent(이름, Dictionary). 없으면(설정 파일 전) 아무것도 안 한다.
## 이벤트: guide_step {step(1부터), id} — 가이드 미션 보상을 받음, guide_done, purchase {product}.
## 실패해도 게임은 그대로(기록만 빠진다).


static func event(name: String, params := {}) -> void:
	if OS.has_feature("web"):
		var api = JavaScriptBridge.get_interface("castleToss")
		if api != null and api.log != null:
			api.log(name, JSON.stringify(params))
	elif Engine.has_singleton("CastleAnalytics"):
		Engine.get_singleton("CastleAnalytics").logEvent(name, params)
