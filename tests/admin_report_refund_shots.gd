extends Node
## 관리자 [신고]·[환불] 탭(2026-11-06): 예시 응답으로 그리고 스크린숏(/mnt/project-files/security/). 서버 없이 화면만 본다.
## 실행: xvfb-run godot --path . res://tests/admin_report_refund_shots.tscn

const OUT := "/mnt/project-files/security/"


func _ready() -> void:
	var now := Economy.time_now()
	var p = preload("res://scripts/admin_panel.gd").new()
	add_child(p)
	p.open()
	p.tab = "report"
	p.reps = {"open": 2, "reports": [
		{"id": 2, "reporter_name": "용감한 성주12", "target": "11111111-2222-3333-4444-555555555555", "target_name": "날쌘 기사7", "target_code": "11111111",
			"message_id": 9, "channel": "all", "text": "***야 접어라", "raw": "씨발아 접어라", "status": "open", "at": now - 120, "target_open": 2, "muted": null,
			"context": [{"id": 8, "name": "용감한 성주12", "text": "보스 같이 잡아요", "raw": null}, {"id": 9, "name": "날쌘 기사7", "text": "***야 접어라", "raw": "씨발아 접어라"}]},
		{"id": 1, "reporter_name": "푸른 마법사3", "target": "11111111-2222-3333-4444-555555555555", "target_name": "날쌘 기사7", "target_code": "11111111",
			"message_id": 5, "channel": "guild", "text": "광고 사이트 가세요", "raw": null, "status": "open", "at": now - 3600, "target_open": 2, "muted": null, "context": []}],
		"mutes": [{"player": "99999999-2222-3333-4444-555555555555", "code": "99999999", "reason": "도배", "until": now + 86400, "at": now - 60}]}
	p.expanded_report = 2
	p._rebuild()
	await _shot("admin_report_tab.png")
	p.tab = "refund"
	p.refs = {"google_sync": true, "refunds": [
		{"order_id": "google:GPA.3381-1111", "product": "dia_3", "name": "다이아 16,500", "provider": "google", "krw": 12000, "at": now - 90000, "refunded_at": now - 600,
			"clawback": {"diamonds": 12000, "debt": 21000, "tickets": 0}, "code": "1A2B3C4D", "debt": 21000}],
		"orders": [{"order_id": "google:GPA.3381-2222", "product": "monthly", "name": "월정액", "provider": "google", "krw": 4900, "at": now - 5000, "code": "1A2B3C4D", "debt": 0},
		{"order_id": "toss:0192f0a1-aaaa-7bbb-8ccc-1234567890ab", "product": "pkg_daily", "name": "일일 패키지", "provider": "toss", "krw": 1200, "at": now - 9000, "code": "55AA66BB", "debt": 0}]}
	p._rebuild()
	await _shot("admin_refund_tab.png")
	print("ADMIN SHOTS OK")
	get_tree().quit()


func _shot(name: String) -> void:
	for i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(OUT)
	get_viewport().get_texture().get_image().save_png(OUT + name)
