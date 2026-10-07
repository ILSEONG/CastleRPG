extends RefCounted
## 기기 설정(2026-10-06): 앱 로컬 user://settings.json 한 파일(Music.settings_path). 설정 창(settings_panel.gd)이 바꾸고 재시작해도 남는다.
## 여기 키: shake(화면 흔들림·히트스톱·SSR 줌, 기본 켬) · damage_numbers(떠오르는 피해 숫자, 기본 켬) · sfx(효과음, 기본 켬) · sfx_volume(효과음 크기 0..1, 기본 1).
## 파일은 오토로드 Music이 읽고 쓴다(배경음악 music·music_volume과 같은 파일) — 이 스크립트는 그 앞의 얇은 창구.


static func get_bool(key: String, default := true) -> bool:
	var m := _music()
	return bool(m.prefs.get(key, default)) if m != null else default


static func set_value(key: String, value) -> void:
	var m := _music()
	if m != null:
		m.prefs[key] = value
		m.save_settings()


## 오토로드 Music(이름으로 찾는다 — 오토로드 없이 도는 -s 단위 테스트에서도 컴파일되게). 없으면 null = 기본값.
static func _music() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("Music") if tree != null else null


static func get_float(key: String, default := 1.0) -> float:
	var m := _music()
	return float(m.prefs.get(key, default)) if m != null else default
